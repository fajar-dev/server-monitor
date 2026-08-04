# server-monitor

Stack observability (metrik + log) berbasis Docker Compose, di-deploy di **server khusus monitoring** (terpisah dari server aplikasi). Server-server lain (app server) memasang agent ringan yang mengirim metrik & log ke server ini.

## Arsitektur

```
 Server Monitoring (stack ini)                    Server Aplikasi (agent, lihat examples/)
┌─────────────────────────────────────┐          ┌───────────────────────────┐
│  ┌──────────┐      ┌────────────┐   │  metrik  │  cAdvisor + node-exporter │
│  │  Grafana │◀────▶│ Prometheus │◀──┼──────────┼── (scrape via IP:port)    │
│  └──────────┘      └────────────┘   │          └───────────────────────────┘
│       ▲             ┌────────────┐  │          ┌───────────────────────────┐
│       └─────────────│    Loki    │◀─┼── log ───┼──  Promtail (push)        │
│                      └────────────┘  │          └───────────────────────────┘
│       ┌────────────┐ ┌────────────┐  │
│       │  Promtail  │ │  cAdvisor  │  │  (memantau container di server
│       │ (self logs)│ │(self stats)│  │   monitoring ini sendiri)
│       └────────────┘ └────────────┘  │
└─────────────────────────────────────┘
```

- **Prometheus** — menarik (pull/scrape) metrik dari cAdvisor & node-exporter, baik yang lokal maupun dari server aplikasi lain.
- **Loki** — menerima (push) log dari Promtail, baik yang lokal maupun dari server aplikasi lain.
- **Grafana** — dashboard visualisasi, sumber data Prometheus & Loki.
- **cAdvisor** (di stack ini) — memantau container yang berjalan di server monitoring itu sendiri (self-monitoring).
- **Promtail** (di stack ini) — mengirim log container di server monitoring itu sendiri ke Loki.

Untuk server aplikasi yang ingin dipantau, pasang agent (cAdvisor + node-exporter + Promtail) di server tersebut — lihat [`examples/promtail-config.example.yaml`](examples/promtail-config.example.yaml) dan bagian [Menambahkan server baru](#menambahkan-server-baru-untuk-dipantau) di bawah.

## Struktur direktori

```
server-monitor/
├── docker-compose.yml
├── .env.example                     # template kredensial (LOKI_USER/LOKI_PASSWORD)
├── config/
│   ├── prometheus.yml               # target scrape Prometheus (lokal + remote)
│   ├── loki-config.yml              # storage & schema Loki
│   ├── loki-auth.conf               # nginx Basic Auth di depan Loki
│   ├── loki.htpasswd                # kredensial ter-hash (di-generate, gitignored)
│   └── promtail-config.yml          # log lokal di server monitoring ini
├── grafana/provisioning/
│   ├── datasources/datasources.yaml # auto-provision Prometheus & Loki
│   └── alerting/                    # contact point, policy, rule alert 5xx → Google Chat
├── dashboards/                      # JSON dashboard (import via Grafana)
├── examples/
│   └── promtail-config.example.yaml # template Promtail (app + cron, dgn auth)
└── README.md
```

## Services & Port (server monitoring)

| Service    | Image                    | Port host | Kegunaan                                                        |
| ---------- | ------------------------ | --------- | --------------------------------------------------------------- |
| cadvisor   | gcr.io/cadvisor/cadvisor | 8080      | Metrik container di server monitoring ini sendiri               |
| prometheus | prom/prometheus          | 9090      | Query metrik (PromQL), scrape semua target                      |
| grafana    | grafana/grafana          | 3030      | Dashboard                                                       |
| loki       | grafana/loki             | —         | Internal only; menyimpan log (diakses via loki-auth / internal) |
| loki-auth  | nginx:alpine             | 3100      | Basic Auth proxy di depan Loki untuk client eksternal           |
| promtail   | grafana/promtail         | 9080      | Kirim log container lokal ke Loki                               |

## Prasyarat

1. **Docker** & **Docker Compose** sudah terpasang.
2. Salin `.env.example` → `.env`, isi kredensial Loki, lalu generate file htpasswd-nya:
   ```bash
   cp .env.example .env
   # edit .env — set LOKI_USER, LOKI_PASSWORD, dan GCHAT_WEBHOOK_URL
   source .env
   docker run --rm httpd:2.4-alpine htpasswd -nbB "$LOKI_USER" "$LOKI_PASSWORD" > config/loki.htpasswd
   ```
   Ulangi perintah `htpasswd` ini setiap kali mengganti password, lalu `docker compose restart loki-auth`.
   `GCHAT_WEBHOOK_URL` dipakai untuk alerting 5xx (lihat bagian [Alerting](#alerting-5xx--google-chat)).
3. Port berikut harus bisa diakses dari server-server yang ingin dipantau (idealnya lewat **private network/VPN**, bukan internet publik):
   - `9090` — kalau ingin Prometheus (di server ini) menarik metrik dari agent
   - `3100` — supaya Promtail di server lain bisa push log ke Loki di sini

   🔐 **Autentikasi Loki**: port `3100` tidak langsung ke Loki, melainkan lewat proxy **`loki-auth`** (nginx) yang menerapkan HTTP Basic Auth dari `LOKI_USER`/`LOKI_PASSWORD` di `.env`. Setiap Promtail dari server lain wajib mengirim kredensial yang sama (`basic_auth` di config-nya — lihat [`examples/promtail-config.example.yaml`](examples/promtail-config.example.yaml)). Grafana & Promtail lokal mengakses Loki langsung di dalam network (`loki:3100`) tanpa auth. **Tetap disarankan** membatasi port `3100` & `9090` lewat firewall untuk lapisan pertahanan tambahan.

Stack ini **tidak lagi bergantung pada Docker network eksternal** — semua service memakai network internal (`monitoring`) yang dibuat otomatis oleh compose file ini, karena server aplikasi yang dipantau tidak berada di host Docker yang sama.

## Instalasi & Menjalankan

```bash
docker compose up -d
```

Cek status semua container:

```bash
docker compose ps
```

Lihat log salah satu service (mis. saat troubleshooting):

```bash
docker compose logs -f prometheus
```

Menghentikan stack:

```bash
docker compose down
```

## Akses

| Tool       | URL                           | Keterangan                                                     |
| ---------- | ----------------------------- | -------------------------------------------------------------- |
| Grafana    | `http://<ip-monitoring>:3030` | Login default `admin` / `admin` (ganti saat login pertama)     |
| Prometheus | `http://<ip-monitoring>:9090` | Query PromQL & cek status target scrape (**Status → Targets**) |
| cAdvisor   | `http://<ip-monitoring>:8080` | Metrik container di server monitoring sendiri                  |
| Loki       | `http://<ip-monitoring>:3100` | API, biasanya diakses lewat Grafana, bukan langsung            |

### Data source di Grafana

Data source **Prometheus** & **Loki** sudah **di-provisioning otomatis** dari
[`grafana/provisioning/datasources/`](grafana/provisioning/datasources/datasources.yaml)
(uid `prometheus` & `loki`) — tidak perlu tambah manual. Kalau sebelumnya sudah menambah
manual dengan nama sama, hapus yang manual agar tidak dobel.

Import dashboard dari folder [`dashboards/`](dashboards/) (**Dashboards → Import → Upload JSON**),
atau dashboard komunitas seperti cAdvisor ([`14282`](https://grafana.com/grafana/dashboards/14282))
/ Node Exporter ([`1860`](https://grafana.com/grafana/dashboards/1860)).

## Alerting 5xx → Google Chat

Grafana otomatis memuat alert dari [`grafana/provisioning/alerting/`](grafana/provisioning/alerting/):
kalau ada log `status >= 500` dari job Loki `*-app` (mis. `kawan-nusa-be-app`, `simas-be-app`)
dalam 5 menit terakhir, alert **HTTP 5xx Errors** fire dan dikirim ke Google Chat.

Cara pakai:
1. Buat webhook di space Google Chat: **Space → Apps & integrations → Webhooks → Add webhook**, salin URL-nya.
2. Isi `GCHAT_WEBHOOK_URL` di `.env` dengan URL tersebut, lalu `docker compose up -d grafana`.
3. Cek di Grafana → **Alerting → Alert rules** (rule *HTTP 5xx Errors*) & **Contact points** (*google-chat* → tombol **Test**).

Detail perilaku:
- Dievaluasi tiap **1 menit**, `for: 0m` → fire dalam ≤1 menit sejak 5xx muncul.
- Satu alert **per job** (label `job`), jadi tahu app mana yang error.
- Bergantung pada log terstruktur (`status` di JSON) yang dikirim Promtail dari job `*-app`.
- Ubah ambang/rentang di [`grafana/provisioning/alerting/rules.yaml`](grafana/provisioning/alerting/rules.yaml).

## Menambahkan server baru untuk dipantau

Setiap server aplikasi yang ingin dipantau memasang **agent** (bukan stack lengkap ini), lalu mengarah ke server monitoring ini.

### Log (push ke Loki)

1. Salin [`examples/promtail-config.example.yaml`](examples/promtail-config.example.yaml) ke server target, ganti semua placeholder `<...>` (host monitoring, kredensial Loki, nama app/server, path log).
2. Jalankan Promtail di server target (binary langsung, atau lewat PM2 — lihat komentar di file example).
3. Log **otomatis muncul** di Loki begitu Promtail jalan (push-based) — tidak perlu konfigurasi tambahan di sisi server monitoring.

### Metrik (scrape oleh Prometheus)

1. Pasang exporter di server target — mis. `cadvisor` (metrik container) dan/atau `node-exporter` (metrik host) — dan pastikan port-nya bisa diakses dari server monitoring.
2. Di server monitoring, daftarkan target baru di [`config/prometheus.yml`](config/prometheus.yml) dengan `IP:port` server target, lalu restart Prometheus:
   ```bash
   docker compose restart prometheus
   ```

### Verifikasi di Grafana
- Metrik: Explore → Prometheus → `up{...}`
- Log: Explore → Loki → `{host="<SERVER_NAME>"}`

## Catatan penting

- **Data Prometheus & Loki persisten** lewat named volume (`prometheus-data`, `loki-data`), tidak hilang saat container restart/reboot.
- **Grafana data persisten** melalui named volume `grafana-data`.
- **Tidak ada dependensi network eksternal** — stack ini pakai network internal sendiri (`monitoring`), aman dijalankan di server manapun tanpa perlu network Docker dari stack lain.
- Semua service diset `restart: always`, otomatis jalan kembali setelah server reboot (selama Docker daemon juga auto-start).
- Amankan port `3100` (Loki) dan `9090` (Prometheus) dari akses publik — lihat bagian Prasyarat.
