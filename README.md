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

Untuk server aplikasi yang ingin dipantau, pasang agent (cAdvisor + node-exporter + Promtail) di server tersebut — lihat [`examples/remote-agent-compose.yml`](examples/remote-agent-compose.yml) dan bagian [Menambahkan server baru](#menambahkan-server-baru-untuk-dipantau) di bawah.

## Struktur direktori

```
server-monitor/
├── docker-compose.yml
├── config/
│   ├── prometheus.yml               # target scrape Prometheus (lokal + remote)
│   ├── loki-config.yml              # storage & schema Loki
│   └── promtail-config.yml          # log lokal di server monitoring ini
├── examples/
│   ├── remote-agent-compose.yml     # template agent untuk server yang dipantau
│   └── remote-promtail-config.yml   # template config Promtail untuk agent
└── README.md
```

## Services & Port (server monitoring)

| Service    | Image                     | Port host | Kegunaan                          |
|------------|----------------------------|-----------|-------------------------------------|
| cadvisor   | gcr.io/cadvisor/cadvisor   | 8080      | Metrik container di server monitoring ini sendiri |
| prometheus | prom/prometheus            | 9090      | Query metrik (PromQL), scrape semua target |
| grafana    | grafana/grafana            | 3001      | Dashboard                          |
| loki       | grafana/loki                | 3100      | Menerima log dari semua Promtail (lokal & remote) |
| promtail   | grafana/promtail            | 9080      | Kirim log container lokal ke Loki  |

## Prasyarat

1. **Docker** & **Docker Compose** sudah terpasang.
2. Port berikut harus bisa diakses dari server-server yang ingin dipantau (idealnya lewat **private network/VPN**, bukan internet publik):
   - `9090` — kalau ingin Prometheus (di server ini) menarik metrik dari agent
   - `3100` — supaya Promtail di server lain bisa push log ke Loki di sini

   ⚠️ **Keamanan**: `auth_enabled: false` di `config/loki-config.yml`, artinya siapa pun yang bisa mencapai port 3100 bisa push log tanpa autentikasi, dan Prometheus juga tidak memakai autentikasi ke target scrape. **Batasi lewat firewall/security group** agar hanya IP server yang dipantau yang boleh akses port-port ini, atau taruh di belakang VPN/private network.

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

| Tool       | URL                          | Keterangan                                  |
|------------|-------------------------------|----------------------------------------------|
| Grafana    | `http://<ip-monitoring>:3001` | Login default `admin` / `admin` (ganti saat login pertama) |
| Prometheus | `http://<ip-monitoring>:9090` | Query PromQL & cek status target scrape (**Status → Targets**) |
| cAdvisor   | `http://<ip-monitoring>:8080` | Metrik container di server monitoring sendiri |
| Loki       | `http://<ip-monitoring>:3100` | API, biasanya diakses lewat Grafana, bukan langsung |

### Setup data source di Grafana

1. Buka Grafana → **Connections → Data sources → Add data source**.
2. Tambahkan **Prometheus** dengan URL: `http://prometheus:9090`
3. Tambahkan **Loki** dengan URL: `http://loki:3100`
4. Import dashboard cAdvisor (mis. dashboard ID [`14282`](https://grafana.com/grafana/dashboards/14282)) atau Node Exporter (mis. ID [`1860`](https://grafana.com/grafana/dashboards/1860)) dari Grafana.com.

## Menambahkan server baru untuk dipantau

Setiap server aplikasi yang ingin dipantau memasang **agent** (bukan stack lengkap ini), lalu mengarah ke server monitoring ini.

1. Salin `examples/remote-agent-compose.yml` dan `examples/remote-promtail-config.yml` ke server target.
2. Di `remote-promtail-config.yml`, ganti:
   - `MONITORING_HOST` → IP/hostname server monitoring ini
   - `SERVER_NAME` → nama unik server tersebut (jadi label di Grafana)
3. Jalankan di server target:
   ```bash
   docker compose -f remote-agent-compose.yml up -d
   ```
4. Di server monitoring ini, daftarkan target metrik baru di [`config/prometheus.yml`](config/prometheus.yml) — uncomment/tambahkan blok `cadvisor-remote` dan `node-exporter-remote` dengan IP server target, lalu restart Prometheus:
   ```bash
   docker compose restart prometheus
   ```
5. Log dari server target **otomatis muncul** di Loki begitu Promtail-nya jalan (push-based, tidak perlu konfigurasi tambahan di sisi server monitoring).
6. Cek di Grafana:
   - Metrik: Explore → Prometheus → `up{server="app-server"}`
   - Log: Explore → Loki → `{host="SERVER_NAME"}`

## Catatan penting

- **Data Prometheus & Loki persisten** lewat named volume (`prometheus-data`, `loki-data`), tidak hilang saat container restart/reboot.
- **Grafana data persisten** melalui named volume `grafana-data`.
- **Tidak ada dependensi network eksternal** — stack ini pakai network internal sendiri (`monitoring`), aman dijalankan di server manapun tanpa perlu network Docker dari stack lain.
- Semua service diset `restart: always`, otomatis jalan kembali setelah server reboot (selama Docker daemon juga auto-start).
- Amankan port `3100` (Loki) dan `9090` (Prometheus) dari akses publik — lihat bagian Prasyarat.

## Troubleshooting

| Masalah | Kemungkinan penyebab |
|---|---|
| `network ... declared as external, but could not be found` | Config lama; pastikan pakai `docker-compose.yml` versi terbaru (network `monitoring` sudah internal, tidak eksternal lagi) |
| Prometheus target `cadvisor-remote`/`node-exporter-remote` DOWN | Firewall server target memblokir port 8080/9100, atau IP di `prometheus.yml` salah |
| Grafana tidak menampilkan log dari server lain | Promtail di server target belum jalan, salah isi `MONITORING_HOST`, atau port 3100 di server monitoring diblokir firewall — cek `docker compose logs promtail` di server target |
| Loki menolak log (`entry too far behind`) | Jam (NTP) server target tidak sinkron dengan server monitoring |
