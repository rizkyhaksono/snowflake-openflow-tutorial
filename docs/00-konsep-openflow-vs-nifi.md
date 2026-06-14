# 00 — Konsep: Snowflake Openflow vs Apache NiFi

Tujuan dokumen ini: memberi peta mental supaya setiap hal yang Anda pelajari di NiFi lokal langsung
"nyambung" ke Snowflake Openflow.

## Apa itu Snowflake Openflow?

Openflow adalah **layanan integrasi data managed** dari Snowflake untuk memindahkan data dari banyak
sumber ke (atau dari) Snowflake. Ia dibangun **di atas Apache NiFi** — Snowflake mengakuisisi
**Datavolo** (perusahaan yang didirikan para pembuat NiFi) pada 2024, lalu menjadikannya Openflow.

Arsitektur Openflow memisahkan dua "plane":

- **Control Plane** — hidup di dalam Snowflake. Tempat Anda login (Snowsight), membuat *deployment*,
  mengatur akses, dan merancang flow di canvas.
- **Data Plane / Deployment** — tempat flow benar-benar dieksekusi:
  - **SPCS** → di Snowpark Container Services (managed Snowflake), atau
  - **BYOC** → di AWS account Anda (Snowflake membuat EC2 agent + cluster **EKS/Kubernetes**).

Di dalam sebuah deployment ada satu/lebih **runtime**, dan **runtime = instance Apache NiFi
ter-kontainerisasi**. Itulah kenapa belajar NiFi = belajar inti Openflow.

## Kenapa tidak bisa Docker Compose?

Karena control plane (canvas, auth, orkestrasi) **selalu** di Snowflake, dan data plane resmi hanya
SPCS atau EKS. Tidak ada paket "Openflow" yang bisa Anda `docker compose up` sendiri. Yang bisa
Anda jalankan lokal adalah **engine-nya**: Apache NiFi.

## Peta istilah (yang ini ⇄ yang itu)

| Snowflake Openflow | Apache NiFi (lab ini) | Catatan |
|---|---|---|
| Deployment (SPCS / BYOC) | Container/cluster NiFi | "Di mana flow dieksekusi" |
| Runtime | Instance NiFi yang menjalankan flow | Openflow runtime = NiFi |
| Canvas di Snowsight | NiFi web UI (canvas) | Drag-drop processor yang sama |
| Connector (pre-built) | Process Group / template / kumpulan processor | Openflow mengemasnya jadi konektor siap pakai |
| Processor | Processor | **Identik** — komponen yang sama |
| Controller Service | Controller Service | **Identik** (mis. koneksi DB, reader/writer) |
| Parameter (di deployment) | Parameter Context | Untuk kredensial/konfigurasi tanpa hardcode |
| Snowflake Managed Token (auth) | Single-user / controller service credentials | Cara autentikasi berbeda, konsep sama |
| Versioning flow | NiFi Registry | Lab 3 |
| Observability / lineage | Data Provenance (bawaan NiFi) | Telusuri tiap FlowFile |
| Connector ke Snowflake (native) | *Tidak ada di lokal* | Ini bagian yang khas Openflow |

## Istilah inti NiFi yang akan sering muncul

- **FlowFile** — satu unit data yang mengalir (isi + atribut/metadata). Bayangkan "amplop berisi
  data + label".
- **Processor** — kotak kerja: membaca, mengubah, merutekan, atau menulis data
  (mis. `GetFile`, `PutDatabaseRecord`, `PutS3Object`).
- **Connection** — panah antar-processor; punya **queue** dan **back-pressure** (otomatis menahan laju
  bila hilir penuh).
- **Relationship** — hasil dari processor (`success`, `failure`, dll.) yang menentukan ke mana
  FlowFile diteruskan.
- **Controller Service** — komponen bersama yang dipakai banyak processor (mis. pool koneksi DB
  `DBCPConnectionPool`, `CSVReader`, `ParquetRecordSetWriter`).
- **Process Group** — folder/wadah untuk mengelompokkan flow; unit yang di-versioning di Registry.
- **Parameter Context** — kumpulan parameter (mis. host DB, password) yang di-bind ke Process Group.

## Apa yang TIDAK didapat secara lokal

- Konektor Snowflake-native (mis. CDC ke Snowflake, ingest siap pakai).
- Control plane managed + observability terpusat ala Snowsight.
- Penagihan/billing & skalabilitas managed.

Tetapi semua **keterampilan merancang flow** sepenuhnya transfer.

➡️ Lanjut ke [Lab 1 — CSV → PostgreSQL](01-lab-csv-ke-postgres.md).
