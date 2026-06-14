# Lab 2 — PostgreSQL → Data Lake (MinIO, format Parquet)

**Tujuan:** mengalirkan tabel `raw.transactions` dari PostgreSQL ke **data lake** (MinIO/S3) sebagai
file **Parquet** di bucket `curated`. Ini pola inti ML Ops: menyiapkan data kolumnar yang efisien
untuk dikonsumsi proses feature engineering & training.

**Yang dipelajari:** fetch **inkremental** dari DB (`QueryDatabaseTableRecord`), penulisan format
Parquet via Record Writer, dan **S3 sink** (`PutS3Object`) ke endpoint S3-compatible (MinIO) — persis
seperti menulis ke S3 dari Openflow.

**Flow yang dibangun:**

```
[QueryDatabaseTableRecord]  --success-->  [PutS3Object]
 baca raw.transactions                     tulis Parquet ke s3://curated/
 (output Parquet via writer)
```

> Prasyarat: Lab 1 selesai (atau cukup pakai 5 baris seed), `DBCPConnectionPool` sudah Enabled.

---

## Langkah 1 — Controller Service: penulis Parquet (`ParquetRecordSetWriter`)

1. Controller Services → **+** → tambahkan **ParquetRecordSetWriter**. Configure → Properties:

   | Properti | Nilai |
   |---|---|
   | Schema Access Strategy | `Inherit Record Schema` |

   (Sisanya biarkan default.) **Apply** → **Enable**.

---

## Langkah 2 — Processor `QueryDatabaseTableRecord` (sumber inkremental)

Processor ini membaca tabel dan **mengingat** nilai maksimum kolom tertentu, sehingga run berikutnya
hanya mengambil baris baru (incremental load) — bukan full-scan ulang.

1. Drag **Processor** → cari **QueryDatabaseTableRecord** → Add.
2. Properties:

   | Properti | Nilai |
   |---|---|
   | Database Connection Pooling Service | `DBCPConnectionPool` |
   | Database Type | `PostgreSQL` |
   | Table Name | `raw.transactions` |
   | Maximum-value Columns | `transaction_id` |
   | Record Writer | `ParquetRecordSetWriter` (dari Langkah 1) |

3. **Apply**. (Relationship: hanya `success`.)

   > **Inti incremental:** karena `Maximum-value Columns = transaction_id`, NiFi menyimpan nilai
   > tertinggi yang sudah diproses di *state*. Jalankan lagi setelah ada baris baru ber-id lebih besar,
   > maka hanya baris baru itu yang diambil. Ini fondasi pipeline yang idempoten & hemat.

---

## Langkah 3 — Processor `PutS3Object` (tulis ke MinIO)

1. Drag **Processor** → cari **PutS3Object** → Add.
2. Properties (nilai sesuai `.env`/`docker-compose.yml`):

   | Properti | Nilai |
   |---|---|
   | Bucket | `curated` |
   | Object Key | `transactions/tx-${uuid}.parquet` |
   | Region | `us-east-1` |
   | Endpoint Override URL | `http://minio:9000` |
   | Access Key ID | `minioadmin` |
   | Secret Access Key | `minioadmin123` |
   | Use Path Style Access | `true` |

   > **Penting untuk MinIO:** `Endpoint Override URL` mengarahkan SDK AWS ke MinIO (bukan AWS asli),
   > dan **Use Path Style Access = true** wajib agar URL berbentuk `minio:9000/curated/...` bukan
   > `curated.minio:9000`. Jika versi NiFi Anda tidak punya properti "Use Path Style Access",
   > cukup andalkan Endpoint Override URL (NiFi memakai path-style untuk endpoint kustom).
   >
   > `Region` diisi `us-east-1` hanya karena SDK mewajibkannya; MinIO mengabaikannya.

3. Tab **Relationships**: terminate `success` dan `failure`. **Apply**.

---

## Langkah 4 — Sambungkan & jalankan

1. Tarik panah **QueryDatabaseTableRecord** → **PutS3Object**, pilih relationship `success`.
2. Start **PutS3Object**.
3. Klik kanan **QueryDatabaseTableRecord** → **Run Once**.

---

## Langkah 5 — Verifikasi

Buka **MinIO Console**: http://localhost:9001 (login `minioadmin` / `minioadmin123`).

1. Masuk bucket **curated** → folder **transactions/** → harus ada file `tx-<uuid>.parquet`.
2. Klik file → bisa diunduh. (Isinya Parquet biner; untuk inspeksi cepat lihat ukuran > 0.)

Berhasil bila objek Parquet muncul di `curated/transactions/`. 🎉

### (Opsional) baca isi Parquet dengan Python

Jika punya Python + `pandas`/`pyarrow` di host:

```python
import pandas as pd
# unduh file dari MinIO Console dulu, lalu:
df = pd.read_parquet("tx-xxxx.parquet")
print(df.head())
```

---

## Hubungannya dengan ML Ops

- **Zona `raw` → `curated`**: pola "medallion" (raw → curated/cleaned → siap fitur). Di sini kita
  memindahkan dari warehouse relational ke lake kolumnar.
- **Parquet**: format kolumnar standar untuk pelatihan model — efisien dibaca Spark, pandas, Ray, dll.
- **Incremental**: pipeline yang aman dijalankan berkala (lewat scheduler NiFi) tanpa duplikasi —
  fondasi untuk *feature freshness*.

Di Openflow asli, pola identik dipakai, hanya tujuannya sering Snowflake (lewat konektor native) atau
S3 sungguhan.

---

## Troubleshooting

- **PutS3Object `failure` — connection refused** → cek container `minio` healthy; Endpoint Override URL
  harus `http://minio:9000` (nama service), bukan `localhost`.
- **403 / SignatureDoesNotMatch** → cek Access Key/Secret sama dengan `.env`; aktifkan
  **Use Path Style Access = true**.
- **Bucket tidak ada** → pastikan container `minio-init` sudah jalan (`make logs` cari `[minio-init]`),
  atau buat manual bucket `curated` lewat MinIO Console.
- **QueryDatabaseTableRecord tidak mengeluarkan apa-apa di run kedua** → itu benar; state incremental
  sudah mencatat id maksimum. Untuk uji ulang: tambahkan baris ber-id lebih besar di DB, atau clear
  state via klik kanan processor → **View state** → **Clear state**.

➡️ Lanjut ke [Lab 3 — Versioning & Parameter Context](03-lab-registry-versioning-parameter-context.md).
