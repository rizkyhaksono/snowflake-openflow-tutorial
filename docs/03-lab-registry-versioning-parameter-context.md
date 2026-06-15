# Lab 3 — Versioning Flow (NiFi Registry) & Parameter Context

**Tujuan:** memperlakukan flow seperti kode — **di-versioning** lewat NiFi Registry — dan memindahkan
kredensial dari hardcode ke **Parameter Context**. Dua hal ini adalah praktik wajib ML Ops
(reproducibility + secret management) dan punya padanan langsung di Snowflake Openflow.

**Yang dipelajari:** mendaftarkan Registry Client, version control sebuah Process Group, commit &
revert versi, serta parameterisasi kredensial dengan `#{...}`.

> Prasyarat: sudah punya Process Group `lab-mlops` berisi flow Lab 1/2. NiFi Registry jalan di
> http://localhost:18081/nifi-registry.
>
> ⚠️ **Kalau Registry tidak bisa dibuka (`ERR_EMPTY_RESPONSE`):** container-nya crash-loop karena izin
> tulis. Pastikan service `nifi-registry` di `docker-compose.yml` **tanpa named volume** untuk
> `database`/`flow_storage` (named volume owner root vs proses nifi uid 1000 →
> `AccessDeniedException`). Setelah dibetulkan: `sudo docker compose up -d nifi-registry`, tunggu ~60 detik.
> Konsekuensi tanpa volume: data registry hilang saat `docker compose down` (cukup untuk lab ini).

---

## Bagian A — Versioning dengan NiFi Registry

> ℹ️ **Anda akan melihat banner oranye "Apache NiFi Registry has been deprecated..." di UI Registry.**
> Itu **normal, bukan error**. NiFi Registry (server terpisah) memang dipensiunkan dan akan dihapus di
> NiFi 3.0, karena NiFi 2.x kini bisa versioning flow **langsung ke Git** (mis.
> `GitHubFlowRegistryClient`) tanpa server Registry terpisah. Untuk belajar **konsep** versioning,
> Registry ini masih berfungsi penuh. Di dunia nyata/ke depan, pakai Git-based registry; di Snowflake
> Openflow, versioning sudah bawaan/managed.

### A1. Buat bucket di Registry

1. Buka **NiFi Registry**: http://localhost:18081/nifi-registry.
2. Pojok kanan atas → ikon **gear/Settings** → tab **Buckets** → **New Bucket**.
3. Nama: `mlops-flows` → **Create**.

   > Bucket di Registry = wadah untuk menyimpan riwayat versi flow (mirip repo Git untuk flow).

### A2. Daftarkan Registry ke NiFi

1. Di **NiFi** (https://localhost:8443/nifi): hamburger menu kiri-atas → **Controller Settings** →
   tab **Registry Clients** → **+**.
2. Isi:

   | Properti | Nilai |
   |---|---|
   | Name | `local-registry` |
   | Type | `NifiRegistryFlowRegistryClient` |
   | URL | `http://nifi-registry:18080` |

   > URL memakai nama service `nifi-registry` (network Docker), bukan `localhost`.

3. **Add**.

### A3. Mulai version control

1. Klik kanan Process Group **lab-mlops** → **Version** → **Start version control**.
2. Pilih: Registry `local-registry`, Bucket `mlops-flows`, beri nama flow `mlops-ingestion`,
   tulis komentar versi pertama → **Save**.
3. Perhatikan badge ✓ hijau pada Process Group → artinya "tersimpan & up-to-date".

### A4. Buat perubahan → lihat versi bertambah

1. Buat perubahan apa saja. Badge Process Group berubah dari ✓ jadi ● (ada perubahan lokal belum di-commit).
   - **Termudah (tanpa stop):** cukup **geser posisi** salah satu processor di kanvas — itu sudah
     terhitung perubahan flow.
   - **Mengedit properti:** processor yang sedang **Running tidak bisa diedit** (dialognya jadi
     "Processor Details" read-only). **Stop dulu** processor (klik kanan → Stop), baru double-click →
     "Edit Processor" → ubah mis. `Object Key` → Apply → (Start lagi bila perlu).
2. Klik kanan Process Group → **Version** → **Commit local changes**, tulis komentar → **Save**.
   Versi naik ke 2.
3. Coba **Version** → **Change version** untuk kembali ke versi 1 (revert) — lalu maju lagi ke 2.

   > Inilah reproducibility: setiap perubahan flow tercatat, bisa di-rollback, dan bisa di-promote
   > antar-environment. Di Openflow, versioning flow memberi manfaat yang sama.

---

## Bagian B — Parameter Context (kredensial tanpa hardcode)

Sekarang kita pindahkan kredensial DB & S3 (yang tadi diketik langsung) ke parameter, supaya tidak
ada secret yang "menempel" di processor/flow yang di-commit.

### B1. Buat Parameter Context

1. Hamburger menu → **Parameter Contexts** → **+**.
2. Name: `mlops-params`. Tab **Parameters** → **+**, tambahkan satu per satu:

   | Nama Parameter | Value | Sensitive? |
   |---|---|---|
   | `db.user` | `mlops` | tidak |
   | `db.password` | `mlopspass` | **ya** |
   | `s3.access.key` | `minioadmin` | tidak |
   | `s3.secret.key` | `minioadmin123` | **ya** |

   > Tandai **Sensitive = Yes** untuk password/secret — nilainya akan dienkripsi dan tidak pernah
   > ditampilkan lagi (analogi "secret" di Openflow).

3. **Apply**.

### B2. Bind context ke Process Group

1. Klik kanan Process Group **lab-mlops** → **Configure** → tab **General** → **Process Group Parameter
   Context** = `mlops-params` → **Apply**.

### B3. Pakai parameter di komponen

Ganti nilai hardcode dengan referensi `#{nama.parameter}`:

1. **DBCPConnectionPool** (Controller Service): disable dulu → ubah `Password` menjadi `#{db.password}`,
   `Database User` menjadi `#{db.user}` → Apply → enable lagi.
2. **PutS3Object**: ubah `Access Key ID` → `#{s3.access.key}`, `Secret Access Key` → `#{s3.secret.key}`
   → Apply.

3. Jalankan ulang Lab 1/Lab 2 untuk memastikan semua tetap bekerja dengan parameter.

### B4. Commit

Klik kanan Process Group → **Version** → **Commit local changes**. Sekarang flow yang tersimpan di
Registry **tidak** mengandung secret mentah — hanya referensi parameter. 👍

---

## Pemetaan ke Snowflake Openflow

| Yang dilakukan di sini | Padanan di Openflow |
|---|---|
| NiFi Registry + bucket + versi | Versioning flow di Openflow |
| Parameter Context + parameter sensitive | Parameter di deployment + secret management |
| Promote versi 1 → 2, revert | Mengelola perubahan flow secara terkontrol |

Anda kini sudah menjalankan siklus penuh ala Openflow secara lokal: **rancang → versioning →
parameterisasi → jalankan**, untuk pipeline ingestion ML Ops (file → DB → data lake).

---

## Langkah selanjutnya (ide eksplorasi)

- Jadwalkan `QueryDatabaseTableRecord` (tab Scheduling → Run Schedule, mis. `60 sec`) agar
  ingestion berjalan periodik (mendekati perilaku konektor Openflow).
- Tambah processor transformasi: `UpdateRecord`/`QueryRecord` untuk membersihkan/menyaring data
  sebelum masuk `curated` (feature prep).
- Coba sumber lain: `ConsumeKafka`, `InvokeHTTP` (API), `ListenHTTP` — semua processor ini juga ada
  di Openflow.
- Saat siap, ikuti quickstart Openflow SPCS resmi (butuh akun Snowflake berbayar) — lihat README.
