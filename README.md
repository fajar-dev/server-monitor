# server-monitor

Stack observability (metrik + log) berbasis Docker Compose untuk memantau resource server dan container, terintegrasi dengan network aplikasi **is5x**.

## Arsitektur

```
                     ┌────────────┐      ┌────────────┐
                     │  cAdvisor  │─────▶│ Prometheus │───┐
                     │  (metrik)  │      │            │   │
                     └────────────┘      └────────────┘   │
                                                            ▼
┌──────────────┐     ┌────────────┐                  ┌─────────┐
│ Docker logs  │────▶│  Promtail  │─────▶ Loki ───────▶│ Grafana │
│ + mail-svc   │     │ (log agent)│                    │(dashboard)│
└──────────────┘     └────────────┘                  └─────────┘
```

- **cAdvisor** — mengumpulkan metrik resource (CPU, memory, network, disk I/O) dari setiap container Docker yang berjalan di host.
- **Prometheus** — scrape & menyimpan metrik time-series dari cAdvisor.
- **Loki** — database log, menyimpan log yang dikirim oleh Promtail.
- **Promtail** — agent yang membaca log container Docker dan log aplikasi lain (`mail-sending-service`), lalu mengirimkannya ke Loki.
- **Grafana** — dashboard visualisasi, menggunakan Prometheus dan Loki sebagai data source.

## Struktur direktori

```
server-monitor/
├── docker-compose.yml
├── config/
│   ├── prometheus.yml        # target scrape Prometheus
│   ├── loki-config.yml       # konfigurasi storage & schema Loki
│   └── promtail-config.yml   # sumber log & tujuan kirim (Loki)
└── README.md
```

## Services & Port

| Service    | Image                        | Port host | Kegunaan                          |
|------------|-------------------------------|-----------|------------------------------------|
| cadvisor   | gcr.io/cadvisor/cadvisor      | 8080      | UI metrik container real-time      |
| prometheus | prom/prometheus               | 9090      | Query metrik (PromQL)              |
| grafana    | grafana/grafana                | 3000      | Dashboard                          |
| loki       | grafana/loki                   | 3100      | API log                            |
| promtail   | grafana/promtail               | 9080      | Agent pengumpul log (tidak perlu diakses langsung) |

## Prasyarat

1. **Docker** & **Docker Compose** sudah terpasang di server.
2. Network eksternal `is5x_network` sudah ada (dibuat oleh stack aplikasi **is5x**, bukan oleh compose ini). Cek dengan:
   ```bash
   docker network ls | grep is5x_network
   ```
   Jika belum ada, buat manual atau jalankan stack is5x terlebih dahulu:
   ```bash
   docker network create is5x_network
   ```
3. File config di-mount dari path host `/root/config/` (lihat `docker-compose.yml`). Pastikan isi folder `config/` di repo ini disalin ke `/root/config/` di server:
   ```bash
   sudo mkdir -p /root/config
   sudo cp config/*.yml /root/config/
   ```

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
| Grafana    | `http://<server-ip>:3000`     | Login default `admin` / `admin` (ganti saat login pertama) |
| Prometheus | `http://<server-ip>:9090`     | Query PromQL & cek target scrape             |
| cAdvisor   | `http://<server-ip>:8080`     | Metrik container mentah                      |
| Loki       | `http://<server-ip>:3100`     | API, biasanya diakses lewat Grafana, bukan langsung |

### Setup data source di Grafana

1. Buka Grafana → **Connections → Data sources → Add data source**.
2. Tambahkan **Prometheus** dengan URL: `http://prometheus:9090`
3. Tambahkan **Loki** dengan URL: `http://loki:3100`
4. Import dashboard cAdvisor (mis. dashboard ID [`14282`](https://grafana.com/grafana/dashboards/14282) di Grafana.com) atau buat dashboard sendiri.

## Sumber log yang dipantau Promtail

Didefinisikan di [`config/promtail-config.yml`](config/promtail-config.yml):

- **docker** — seluruh log container Docker (`/var/lib/docker/containers/*/*.log`)
- **mail-sending-service** — log aplikasi `mail-sending-service` (`/var/log/mail-sending-service/*.log`)

Untuk menambah sumber log baru, tambahkan `job_name` baru di bagian `scrape_configs` pada file tersebut, lalu restart promtail:

```bash
docker compose restart promtail
```

## Catatan penting

- **Penyimpanan Loki bersifat sementara.** `config/loki-config.yml` menyimpan data di `path_prefix: /tmp/loki`, yang biasanya dibersihkan saat server reboot. Untuk histori log yang persisten, arahkan `path_prefix` ke volume Docker atau path permanen (mis. `/var/lib/loki`) dan tambahkan volume mapping di `docker-compose.yml`.
- **Grafana data persisten** melalui named volume `grafana-data`, jadi dashboard & konfigurasi tidak hilang saat container di-restart.
- **Network eksternal wajib ada** sebelum `docker compose up`, karena `shared_network` menggunakan `external: true` dan menunjuk ke `is5x_network`.
- Semua service diset `restart: always`, jadi otomatis jalan kembali setelah server reboot (selama Docker daemon juga auto-start).

## Troubleshooting

| Masalah | Kemungkinan penyebab |
|---|---|
| `docker compose up` gagal, error network not found | Network `is5x_network` belum dibuat — lihat bagian Prasyarat |
| Prometheus target `cadvisor` DOWN | cAdvisor belum running / typo hostname di `prometheus.yml` |
| Grafana tidak menampilkan log | Data source Loki belum ditambahkan, atau Promtail gagal kirim (cek `docker compose logs promtail`) |
| Log `mail-sending-service` tidak muncul | Path `/var/log/mail-sending-service/` tidak ada/kosong di host |
