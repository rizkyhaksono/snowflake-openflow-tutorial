# Lab 1 — CSV → PostgreSQL

**Tujuan:** ingest file CSV mentah ke tabel `raw.transactions` di PostgreSQL. Ini pola ingestion
paling dasar di ML Ops ("file landing → warehouse").

**Yang dipelajari:** Processor, Controller Service, Record Reader, koneksi database (`DBCPConnectionPool`),
relationship & penanganan error, serta tombol **Run Once**.

**Flow yang dibangun:**

```
[GetFile]  --success-->  [PutDatabaseRecord]
 baca CSV                 tulis ke raw.transactions
```

> Prasyarat: `make up` sudah jalan, NiFi `healthy`, dan driver ada di `./drivers/postgresql-42.7.4.jar`.
> Buka NiFi di https://localhost:8443/nifi (login lihat `.env`).

---

## Langkah 0 — (disarankan) buat Process Group

Supaya rapi dan siap untuk Lab 3 (versioning), buat wadah dulu:

1. Drag ikon **Process Group** dari toolbar atas ke canvas.
2. Beri nama `lab-mlops`, klik **Add**. Double-click untuk masuk ke dalamnya.

Semua langkah berikut dilakukan **di dalam** Process Group ini.

---

## Langkah 1 — Controller Service: koneksi database (`DBCPConnectionPool`)

Controller service = komponen bersama. Kita buat sekali, dipakai banyak processor (di Lab 2 juga).

1. Di canvas kosong, klik kanan → **Configure** → tab **Controller Services** → tombol **+**.
   (Atau: hamburger menu kiri-atas → Controller Services.)
2. Cari & tambahkan **DBCPConnectionPool**. Klik ikon ✎ (Configure) → tab **Properties**, isi:

   | Properti | Nilai |
   |---|---|
   | Database Connection URL | `jdbc:postgresql://postgres:5432/mlops` |
   | Database Driver Class Name | `org.postgresql.Driver` |
   | Database Driver Location(s) | `/opt/nifi/drivers/postgresql-42.7.4.jar` |
   | Database User | `mlops` |
   | Password | `mlopspass` |

3. **Apply**, lalu klik ikon ⚡ (Enable) sampai statusnya **Enabled**.

> Catatan: `postgres`, port `5432`, user/db `mlops` — semua sesuai `docker-compose.yml` & `.env`.
> NiFi mengakses PostgreSQL lewat **nama service** `postgres` karena berada di network Docker yang sama.

---

## Langkah 2 — Controller Service: pembaca CSV (`CSVReader`)

1. Masih di Controller Services → **+** → tambahkan **CSVReader**. Configure → Properties:

   | Properti | Nilai |
   |---|---|
   | Schema Access Strategy | `Infer Schema` |
   | Treat First Line as Header | `true` |

2. **Apply** → **Enable**.

---

## Langkah 3 — Processor `GetFile` (baca CSV)

1. Drag ikon **Processor** ke canvas → cari **GetFile** → Add.
2. Double-click → tab **Properties**:

   | Properti | Nilai |
   |---|---|
   | Input Directory | `/data` |
   | File Filter | `sample_transactions.csv` |
   | Keep Source File | `true` |

   > `Keep Source File = true` membuat GetFile **tidak menghapus** file CSV sumber setelah membacanya,
   > jadi `sample_transactions.csv` tetap ada di repo Anda.
   >
   > ⚠️ **Catatan penting:** GetFile mewajibkan direktori input **bisa ditulis (writable)**, bukan cuma
   > dibaca — ini validasi internal processor. Karena itu di `docker-compose.yml`, `/data` di-mount
   > **read-write** (tanpa `:ro`). Kalau Anda melihat error
   > `Directory '/data' does not have sufficient permissions (not writable and readable)`, artinya
   > mount masih read-only — pastikan baris `- ./data:/data` (bukan `:ro`) lalu jalankan ulang
   > `sudo docker compose up -d nifi`.

3. Tab **Relationships**: GetFile hanya punya `success` (otomatis). **Apply**.

---

## Langkah 4 — Processor `PutDatabaseRecord` (tulis ke PostgreSQL)

1. Drag **Processor** → cari **PutDatabaseRecord** → Add.
2. Double-click → tab **Properties**:

   | Properti | Nilai |
   |---|---|
   | Record Reader | `CSVReader` (pilih yang dibuat di Langkah 2) |
   | Database Type | `PostgreSQL` |
   | Statement Type | `INSERT` |
   | Database Connection Pooling Service | `DBCPConnectionPool` |
   | Schema Name | `raw` |
   | Table Name | `transactions` |
   | Translate Field Names | `true` |

3. Tab **Relationships**: centang **terminate** untuk `success`, `failure`, dan `retry`
   (untuk lab ini kita akhiri di sini; di produksi `failure` dirutekan ke penanganan error).
   **Apply**.

---

## Langkah 5 — Sambungkan & jalankan

1. Tarik panah dari **GetFile** ke **PutDatabaseRecord**. Saat dialog muncul, pilih relationship
   `success` → **Add**.
2. Klik kanan **PutDatabaseRecord** → **Start** (biarkan menyala, menunggu input).
3. Klik kanan **GetFile** → **Run Once**.
   > **Run Once** mengeksekusi satu kali saja — pas untuk ingest file sekali tanpa loop berulang.

Amati: queue di antara dua processor sempat terisi 1 FlowFile lalu kosong setelah ditulis ke DB.

---

## Langkah 6 — Verifikasi

Dari terminal:

```bash
make psql
```
lalu:
```sql
SELECT count(*) AS total, min(transaction_id), max(transaction_id) FROM raw.transactions;
-- Harusnya 25 baris total: 5 seed (id 1-5) + 20 dari CSV (id 1001-1020).

SELECT * FROM raw.transactions WHERE transaction_id >= 1001 ORDER BY transaction_id LIMIT 5;
```

Jika `total = 25`, Lab 1 berhasil. 🎉

---

## Telusuri lewat Data Provenance (fitur khas NiFi/Openflow)

Klik kanan **PutDatabaseRecord** → **View data provenance**. Anda bisa melihat setiap event
(RECEIVE, SEND), isi FlowFile, dan atributnya — inilah "observability/lineage" yang juga jadi nilai
jual Openflow.

---

## Troubleshooting

- **GetFile error `Directory '/data' does not have sufficient permissions`** → mount `/data` masih
  read-only. Di `docker-compose.yml` gunakan `- ./data:/data` (tanpa `:ro`), lalu
  `sudo docker compose up -d nifi` untuk menerapkannya (flow Anda aman, tersimpan di volume).
- **GetFile error "Unable to delete"** → pastikan `Keep Source File = true`.
- **PutDatabaseRecord `failure` + error driver** → cek `Database Driver Location(s)` menunjuk file jar
  yang benar; pastikan `make drivers` sudah mengunduhnya (`ls drivers/`).
- **Koneksi DB gagal** → pastikan container `postgres` healthy (`make ps`); URL harus pakai host
  `postgres` (nama service), bukan `localhost`.
- **Bentrok PK saat dijalankan dua kali** → GetFile yang di-Run Once lagi akan mengirim ulang baris
  yang sama → `INSERT` kena duplicate PK → masuk `failure`. Normal; untuk reset bersih: `make clean && make up`.

➡️ Lanjut ke [Lab 2 — PostgreSQL → Data Lake (MinIO/Parquet)](02-lab-postgres-ke-datalake-minio.md).
