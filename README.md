# Lab Belajar Snowflake Openflow untuk ML Ops (via Apache NiFi + Docker Compose)

Lab lokal untuk **belajar konsep Snowflake Openflow** tanpa akun Snowflake berbayar — dengan
menjalankan **Apache NiFi**, yaitu engine open-source yang sama persis yang dipakai Openflow di baliknya.

---

## TL;DR — Bisakah Snowflake Openflow di-deploy sendiri dengan Docker Compose?

**Tidak.** Snowflake Openflow adalah *managed service*; **control plane**-nya (UI canvas di Snowsight,
autentikasi, orkestrasi) **selalu** berjalan di dalam Snowflake. Hanya ada dua model deployment dan
keduanya **bukan** Docker Compose:

| Model | Di mana data plane berjalan | Catatan |
|---|---|---|
| **Snowflake Deployment (SPCS)** | Snowpark Container Services, managed penuh Snowflake | GA di AWS/Azure/GCP. **Tidak tersedia di trial account** (butuh akun berbayar) |
| **BYOC** (Bring Your Own Cloud) | AWS account Anda, tapi pakai **EKS (Kubernetes)** + EC2 agent | Hanya AWS; tetap diorkestrasi control plane Snowflake |

**Kabar baiknya:** Openflow secara harfiah adalah **Apache NiFi yang di-manage**
(Snowflake mengakuisisi Datavolo — pembuat NiFi — pada 2024). Runtime Openflow = *"containerized Apache
NiFi instances"*. Jadi menjalankan **Apache NiFi lokal** mengajarkan ~90% konsep yang **langsung
transfer** ke Openflow: canvas, processors, controller services, FlowFiles, data provenance,
parameter contexts, dan Registry untuk versioning. Yang **tidak** Anda dapat secara lokal hanyalah
konektor Snowflake-native + lapisan managed-nya.

> Detail pemetaan konsep ada di [docs/00-konsep-openflow-vs-nifi.md](docs/00-konsep-openflow-vs-nifi.md).

---

## Di mana ini cocok dalam ML Ops?

NiFi/Openflow adalah **lapisan data movement / ingestion** dari pipeline ML Ops — bagian yang
memindahkan & membentuk data sebelum feature engineering dan training:

```
  Sumber (DB, file, API, stream)
        │
        ▼
  ┌─────────────────────┐
  │  NiFi / Openflow     │  ← ingestion, parsing, validasi, format, routing
  │  (lab ini)           │
  └─────────────────────┘
        │
        ▼
  Data lake / warehouse (MinIO/S3, PostgreSQL, Snowflake)
        │
        ▼
  Feature pipeline → Training → Model registry → Serving
```

Di lab ini Anda berlatih pola yang paling sering dipakai di ML Ops: **ingest file mentah ke
warehouse**, lalu **mengalirkan tabel database ke data lake sebagai Parquet** yang siap dikonsumsi
proses training.

---

## Yang dijalankan stack ini

| Service | Image | URL / Port | Peran (analogi Openflow) |
|---|---|---|---|
| **NiFi** | `apache/nifi:2.9.0` | https://localhost:8443/nifi | Canvas + engine = **runtime Openflow** |
| **NiFi Registry** | `apache/nifi-registry:2.9.0` | http://localhost:18080/nifi-registry | Versioning flow |
| **PostgreSQL** | `postgres:16` | localhost:5432 | DB sumber/sink relational |
| **MinIO** | `minio/minio` | http://localhost:9001 (console), :9000 (S3 API) | Data lake / S3 sink |

Kredensial ada di [.env](.env) (dummy, hanya untuk lab lokal).

---

## Prasyarat

- **Docker** + **Docker Compose v2** (`docker compose version`).
- RAM bebas ~4 GB (NiFi JVM di-set heap maks 2 GB di [docker-compose.yml](docker-compose.yml)).
- `make` dan `curl` (untuk mengunduh driver JDBC). Tanpa `make`, lihat perintah manual di bawah.

> **Izin Docker:** jika `docker` butuh `sudo` di mesin Anda (mis. user belum masuk grup `docker`),
> jalankan perintah `make` dengan `make SUDO=sudo up`, atau tambahkan user ke grup docker:
> `sudo usermod -aG docker $USER` lalu logout/login.

---

## Quickstart

```bash
# 1. Unduh driver JDBC PostgreSQL ke ./drivers lalu jalankan semua service
make up
#    (atau: make SUDO=sudo up   jika docker butuh sudo)

# 2. Lihat URL semua UI
make urls

# 3. Pantau sampai NiFi siap (~1-2 menit untuk boot pertama)
make ps        # tunggu kolom STATUS nifi jadi "healthy"
make logs      # opsional: ikuti log
```

Tanpa `make`:

```bash
mkdir -p drivers
curl -fSL -o drivers/postgresql-42.7.4.jar \
  https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar
docker compose up -d
```

Lalu buka:
- **NiFi**: https://localhost:8443/nifi — login `admin` / `openflowlab2026` (lihat `.env`).
  Sertifikat self-signed → klik "lanjutkan/terima risiko" di browser, itu normal.
- **NiFi Registry**: http://localhost:18080/nifi-registry
- **MinIO Console**: http://localhost:9001 — login `minioadmin` / `minioadmin123`.

---

## Tutorial (kerjakan berurutan)

| # | Materi | Yang dipelajari |
|---|---|---|
| 00 | [Konsep: Openflow vs NiFi](docs/00-konsep-openflow-vs-nifi.md) | Peta istilah & arsitektur |
| 01 | [Lab 1 — CSV → PostgreSQL](docs/01-lab-csv-ke-postgres.md) | Processor, controller service, record reader/writer, relationship |
| 02 | [Lab 2 — PostgreSQL → Data Lake (MinIO/Parquet)](docs/02-lab-postgres-ke-datalake-minio.md) | Incremental fetch, konversi Parquet, S3 sink (pola inti ML Ops) |
| 03 | [Lab 3 — Versioning & Parameter Context](docs/03-lab-registry-versioning-parameter-context.md) | NiFi Registry, parameter (kredensial tanpa hardcode) |

---

## Perintah berguna

```bash
make ps        # status container
make logs      # ikuti log
make psql      # buka shell psql ke PostgreSQL
make down      # stop (data TETAP tersimpan di volume)
make clean     # stop + HAPUS semua volume/data (reset bersih)
```

Cek data hasil lab:

```bash
# Baris di PostgreSQL (hasil Lab 1)
make psql
mlops=# SELECT count(*), max(transaction_id) FROM raw.transactions;

# Objek di data lake (hasil Lab 2) — via MinIO Console http://localhost:9001 (bucket "curated")
```

---

## Persistensi

Semua state disimpan di **named volumes** Docker (lihat bagian `volumes:` di `docker-compose.yml`),
termasuk definisi flow NiFi (`conf/flow.json.gz`). Jadi `make down` lalu `make up` **tidak**
menghilangkan flow atau data. Gunakan `make clean` hanya jika ingin reset total.

---

## "Lulus" ke Snowflake Openflow asli (nanti)

Setelah nyaman dengan konsep di lab ini, untuk mencoba Openflow sungguhan:

1. **Openflow Snowflake Deployment (SPCS)** — paling mudah. Butuh akun Snowflake **berbayar**
   (bukan trial). Ada quickstart resmi ~25 menit:
   <https://quickstarts.snowflake.com/guide/getting_started_with_Openflow_spcs/index.html>
2. **Openflow BYOC** — data plane di AWS account Anda (EKS). Lebih kompleks/biaya lebih besar.

Konsep canvas, processor, controller service, parameter context, dan versioning yang Anda kuasai di
sini berlaku langsung — yang baru hanya konektor Snowflake-native dan setup deployment-nya.

---

## Referensi

- Snowflake — About Openflow: <https://docs.snowflake.com/en/user-guide/data-integration/openflow/about>
- Snowflake — Openflow BYOC: <https://docs.snowflake.com/en/user-guide/data-integration/openflow/setup-openflow-byoc>
- Apache NiFi docs: <https://nifi.apache.org/docs.html>
- Apache NiFi Docker image: <https://hub.docker.com/r/apache/nifi>
