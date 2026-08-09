# Instalasi Promtail di Server Lain

Panduan memasang **Promtail** di server aplikasi agar log-nya dikirim ke Loki
di server monitoring. Dua opsi: **systemd** (rekomendasi untuk bare-metal) atau
**Docker**.

> Rilis Loki terbaru (v3.7+) **tidak lagi menyertakan** binary Promtail. Versi
> terakhir yang menyediakan binary standalone: **v3.6.11** (dipakai di panduan ini).
> Loki di sisi server tidak peduli versi Promtail yang mengirim.

Prasyarat:
- Port `3100` server monitoring bisa diakses dari server ini (cek firewall).
- Kredensial Loki (`LOKI_USER` / `LOKI_PASSWORD`) — sama dengan `.env` di server monitoring.

---

## Opsi A — systemd (rekomendasi)

Contoh ini dijalankan sebagai **root** (hilangkan `sudo` jika sudah root).

### 1. Download binary
```bash
cd /tmp
curl -L -o promtail.zip "https://github.com/grafana/loki/releases/download/v3.6.11/promtail-linux-amd64.zip"
apt-get install -y unzip            # kalau belum ada
unzip -o promtail.zip
mv promtail-linux-amd64 /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail
promtail --version
```

### 2. Folder + config
```bash
mkdir -p /etc/promtail /var/lib/promtail
```
Buat `/etc/promtail/promtail-config.yaml`, ganti semua placeholder `<...>`:
```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://<MONITORING_HOST>:3100/loki/api/v1/push
    basic_auth:                 # WAJIB — Loki pakai Basic Auth
      username: <LOKI_USER>
      password: <LOKI_PASSWORD>

scrape_configs:
  # Log aplikasi (web/service)
  - job_name: <APP_NAME>-app
    static_configs:
      - targets: [localhost]
        labels:
          job: <APP_NAME>-app
          host: <SERVER_NAME>
          __path__: <APP_DIR>/logs/app-*.log
    pipeline_stages:
      - json: { expressions: { time: time, level: level, service: service, event: event } }
      - timestamp: { source: time, format: RFC3339Nano }
      - labels: { level:, service: }

  # Log cron / scheduled jobs
  - job_name: <APP_NAME>-cron
    static_configs:
      - targets: [localhost]
        labels:
          job: <APP_NAME>-cron
          host: <SERVER_NAME>
          __path__: <APP_DIR>/logs/cron/*.log
    pipeline_stages:
      - json: { expressions: { time: time, level: level, task: task, event: event } }
      - timestamp: { source: time, format: RFC3339Nano }
      - labels: { level:, task: }
```

Placeholder:
| Placeholder | Isi |
| --- | --- |
| `<MONITORING_HOST>` | host/IP server monitoring (tempat Loki + loki-auth) |
| `<LOKI_USER>` / `<LOKI_PASSWORD>` | kredensial, sama dengan `.env` server monitoring |
| `<APP_NAME>` | nama app → jadi Loki job label (mis. `myapp`) |
| `<SERVER_NAME>` | nama server ini → label `host` |
| `<APP_DIR>` | path absolut deploy app (mis. `/root/myapp`) |

> Kalau log app **bukan** JSON, hapus seluruh blok `pipeline_stages`.

### 3. systemd unit
```bash
cat > /etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail log shipper -> Loki
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
# Ganti ke pemilik file log, atau biarkan root agar bisa baca semua log
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### 4. Aktifkan & jalankan
```bash
systemctl daemon-reload
systemctl enable --now promtail
systemctl status promtail
```

### 5. Verifikasi
```bash
journalctl -u promtail -f
```
Pastikan **tidak ada** `401`/`403` (auth) dan **tidak ada** `permission denied`.
Lalu dari server monitoring:
```bash
source /home/fajar/server-monitor/.env
curl -s -u "$LOKI_USER:$LOKI_PASSWORD" 'http://localhost:3100/loki/api/v1/label/job/values'; echo
```
Harus muncul job `<APP_NAME>-app` / `<APP_NAME>-cron`.

---

## Opsi B — Docker

Kalau server punya Docker:
```yaml
services:
  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: always
    volumes:
      - ./promtail-config.yaml:/etc/promtail/config.yml
      - /var/lib/promtail:/var/lib/promtail
      - <APP_DIR>/logs:<APP_DIR>/logs:ro   # mount folder log app (read-only)
    command: -config.file=/etc/promtail/config.yml
```
```bash
docker compose up -d
```
Isi `promtail-config.yaml` sama dengan Opsi A. (Image `grafana/promtail:latest`
masih tersedia walau binary standalone sudah tidak dirilis.)

---

## Troubleshooting

| Gejala | Penyebab & solusi |
| --- | --- |
| `401 Unauthorized` | `basic_auth` kosong/salah — samakan dengan `.env` server monitoring |
| `403 Forbidden` (`<html>`) | `.htpasswd` di server monitoring belum ter-generate — regenerate & restart `loki-auth` |
| `permission denied` baca log | `User=` bukan pemilik log → set ke pemilik, atau `chmod -R o+rX <APP_DIR>/logs` |
| `connection refused` | Port `3100` server monitoring diblokir firewall / URL salah |
| `too old` (400) | Promtail baca file log lama (>7 hari) — ditolak Loki, wajar |
| Job tidak muncul di Loki | Cek `journalctl -u promtail -f`, pastikan `__path__` cocok dengan file log yang ada |

Referensi template: [`docs/promtail-config.example.yaml`](promtail-config.example.yaml).
