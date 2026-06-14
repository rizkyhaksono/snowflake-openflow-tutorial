#!/bin/sh
# Dijalankan oleh container minio-init (image minio/mc) saat `docker compose up`.
# Tugasnya: tunggu MinIO siap, lalu buat bucket data lake "raw" dan "curated".
set -e

echo "[minio-init] Menunggu MinIO siap..."
until mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
  echo "[minio-init]   MinIO belum siap, coba lagi dalam 2 detik..."
  sleep 2
done

echo "[minio-init] MinIO terhubung. Membuat bucket..."
mc mb -p local/raw      || true   # zona landing data mentah
mc mb -p local/curated  || true   # zona data tersusun (Parquet) untuk konsumsi ML

echo "[minio-init] Daftar bucket sekarang:"
mc ls local
echo "[minio-init] Selesai."
