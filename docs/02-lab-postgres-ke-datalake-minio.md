# Lab 2 — PostgreSQL → Data Lake (MinIO, format Avro)

**Tujuan:** mengalirkan tabel `raw.transactions` dari PostgreSQL ke **data lake** (MinIO/S3) sebagai
file **Avro** di bucket `curated`. Ini pola inti ML Ops: menyiapkan data biner ber-schema yang efisien
untuk dikonsumsi proses feature engineering & training.

> ℹ️ **Kenapa Avro, bukan Parquet?** Sejak **NiFi 2.x**, bundle Parquet (`nifi-parquet-nar`)
> **tidak lagi disertakan** di distribusi default (ticket NIFI-12282), sehingga `ParquetRecordSetWriter`
> tidak ada di image `apache/nifi:2.9.0`. Kita pakai **Avro** (sudah bawaan, satu bundle dengan CSVReader)
> — format data-lake biner yang umum, dengan schema menyatu di file. Pola pipeline-nya **identik**.
> Mau Parquet sungguhan? Lihat bagian [Opsional: mengaktifkan Parquet](#opsional-mengaktifkan-parquet) di bawah.

**Yang dipelajari:** fetch **inkremental** dari DB (`QueryDatabaseTableRecord`), penulisan format biner
via Record Writer, dan **S3 sink** (`PutS3Object`) ke endpoint S3-compatible (MinIO) — persis
seperti menulis ke S3 dari Openflow.

**Flow yang dibangun:**

```
[QueryDatabaseTableRecord]  --success-->  [PutS3Object]
 baca raw.transactions                     tulis Avro ke s3://curated/
 (output Avro via writer)
```

> Prasyarat: Lab 1 selesai (atau cukup pakai 5 baris seed), `DBCPConnectionPool` sudah Enabled.

---

## Langkah 1 — Controller Service: penulis Avro (`AvroRecordSetWriter`)

1. Controller Services → **+** → tambahkan **AvroRecordSetWriter**. Configure → Properties:

   | Properti | Nilai |
   |---|---|
   | Schema Write Strategy | `Embed Avro Schema` (default) |
   | Schema Access Strategy | `Inherit Record Schema` |

   (Sisanya biarkan default — Avro otomatis menyertakan schema di file.) **Apply** → **Enable**.

---

## Langkah 2 — Processor `QueryDatabaseTableRecord` (sumber inkremental)

Processor ini membaca tabel dan **mengingat** nilai maksimum kolom tertentu, sehingga run berikutnya
hanya mengambil baris baru (incremental load) — bukan full-scan ulang.

1. Drag **Processor** → cari **QueryDatabaseTableRecord** → Add.
2. Properties:

  | Properti                            | Nilai                                     |
  | ----------------------------------- | ----------------------------------------- |
  | Database Connection Pooling Service | `DBCPConnectionPool`                      |
  | Database Type                       | `PostgreSQL`                              |
  | Table Name                          | `raw.transactions`                        |
  | Maximum-value Columns               | `transaction_id`                          |
  | Record Writer                       | `AvroRecordSetWriter` (dari Langkah 1)    |

3. **Apply**. (Relationship: hanya `success`.)
  > **Inti incremental:** karena `Maximum-value Columns = transaction_id`, NiFi menyimpan nilai
  > tertinggi yang sudah diproses di *state*. Jalankan lagi setelah ada baris baru ber-id lebih besar,
  > maka hanya baris baru itu yang diambil. Ini fondasi pipeline yang idempoten & hemat.

---

## Langkah 3 — Processor `PutS3Object` (tulis ke MinIO)

1. Drag **Processor** → cari **PutS3Object** → Add.

2. **Kredensial lewat controller service (WAJIB di NiFi 2.x).** Di NiFi 2.x, PutS3Object **tidak punya**
   properti `Access Key ID` / `Secret Access Key` langsung — kredensial harus via controller service:
   - Di properti **`AWS Credentials Provider Service`** → klik value → **`Create new service...`** →
     pilih **`AWSCredentialsProviderControllerService`** → **Create**.
   - Configure service tsb: **Access Key ID** = `minioadmin`, **Secret Access Key** = `minioadmin123`
     (biarkan `Use Default Credentials = false`) → **Apply** → **⚡ Enable**.
   - Kembali ke PutS3Object, set **`AWS Credentials Provider Service`** = service yang baru dibuat.

3. Set properti lainnya:

  | Properti                       | Nilai                             |
  | ------------------------------ | --------------------------------- |
  | Bucket                         | `curated`                         |
  | Object Key                     | `transactions/tx-${uuid}.avro`    |
  | Region                         | `us-east-1`                       |
  | Endpoint Override URL          | `http://minio:9000`               |
  | Use Path Style Access          | `true`                            |
  | AWS Credentials Provider Service | (service dari langkah 2)        |

  > **Penting untuk MinIO:** `Endpoint Override URL` mengarahkan SDK AWS ke MinIO (bukan AWS asli),
  > dan **Use Path Style Access = true** WAJIB agar URL berbentuk `minio:9000/curated/...` bukan
  > `curated.minio:9000` (virtual-host yang tidak didukung MinIO).
  >
  > `Region` diisi `us-east-1` hanya karena SDK mewajibkannya; MinIO mengabaikannya (region lain juga jalan).

4. Tab **Relationships**: terminate `success` dan `failure`. **Apply**. Status processor harus jadi
   valid (bukan `Invalid`) setelah credentials service terisi.

---

## Langkah 4 — Sambungkan & jalankan

1. Tarik panah **QueryDatabaseTableRecord** → **PutS3Object**, pilih relationship `success`.
2. Start **PutS3Object**.
3. Klik kanan **QueryDatabaseTableRecord** → **Run Once**.

---

## Langkah 5 — Verifikasi

Buka **MinIO Console**: [http://localhost:19001](http://localhost:19001) (login `minioadmin` / `minioadmin123`).

1. Masuk bucket **curated** → folder **transactions/** → harus ada file `tx-<uuid>.avro`.
2. Klik file → bisa diunduh. (Isinya Avro biner; untuk inspeksi cepat lihat ukuran > 0.)

Berhasil bila objek Avro muncul di `curated/transactions/`. 🎉

### (Opsional) baca isi Avro dengan Python

Jika punya Python + `fastavro` di host (`pip install fastavro`):

```python
import fastavro
# unduh file dari MinIO Console dulu, lalu:
with open("tx-xxxx.avro", "rb") as f:
    for record in fastavro.reader(f):
        print(record)
```

---

## Hubungannya dengan ML Ops

- **Zona `raw` → `curated`**: pola "medallion" (raw → curated/cleaned → siap fitur). Di sini kita
memindahkan dari warehouse relational ke object storage data lake.
- **Format biner ber-schema (Avro)**: schema menyatu di file, efisien & self-describing — umum sebagai
format landing di data lake. Untuk training skala besar, biasanya di-*compact* lagi ke **Parquet**
(kolumnar) di tahap berikutnya.
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
- **`AvroRecordSetWriter`/`QueryDatabaseTableRecord` tidak muncul saat dicari** → keduanya bawaan;
coba refresh. (Yang TIDAK ada di image ini hanyalah komponen **Parquet** — lihat bagian di bawah.)

---

## Opsional: mengaktifkan Parquet

Kalau Anda benar-benar ingin `ParquetRecordSetWriter` (kolumnar), tambahkan NAR-nya secara manual —
NiFi 2.x tidak menyertakannya by default.

1. Buat folder dan unduh 2 NAR (versi cocokkan dengan NiFi, mis. `2.9.0`):
   ```bash
   mkdir -p ext-nars
   BASE=https://repo1.maven.org/maven2/org/apache/nifi
   curl -fSL -o ext-nars/nifi-parquet-nar-2.9.0.nar            $BASE/nifi-parquet-nar/2.9.0/nifi-parquet-nar-2.9.0.nar
   curl -fSL -o ext-nars/nifi-hadoop-libraries-nar-2.9.0.nar   $BASE/nifi-hadoop-libraries-nar/2.9.0/nifi-hadoop-libraries-nar-2.9.0.nar
   ```
   > `nifi-hadoop-libraries-nar` adalah dependency Parquet dan ukurannya **besar (~ratusan MB)**.
2. Mount folder itu ke direktori extensions NiFi di `docker-compose.yml` (service `nifi`):
   ```yaml
       volumes:
         # ...volume lain...
         - ./ext-nars:/opt/nifi/nifi-current/extensions:ro
   ```
3. Terapkan: `sudo docker compose up -d nifi`, tunggu NiFi siap. Setelah itu `ParquetRecordSetWriter`
   akan muncul di daftar Controller Service. Ganti writer di Langkah 1–2 ke Parquet dan Object Key ke
   `.parquet`.

---

➡️ Lanjut ke [Lab 3 — Versioning & Parameter Context](03-lab-registry-versioning-parameter-context.md).