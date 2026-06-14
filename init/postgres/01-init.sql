-- Dijalankan otomatis oleh PostgreSQL saat volume pertama kali dibuat
-- (mekanisme /docker-entrypoint-initdb.d). Jalankan `make clean` lalu `make up`
-- jika ingin skrip ini dieksekusi ulang dari awal.

-- Skema "raw" = zona landing di warehouse (analogi tabel mentah di Snowflake).
CREATE SCHEMA IF NOT EXISTS raw;

-- Tabel sink untuk LAB 1 (CSV -> PostgreSQL) sekaligus sumber untuk LAB 2 (PostgreSQL -> data lake).
CREATE TABLE IF NOT EXISTS raw.transactions (
    transaction_id BIGINT PRIMARY KEY,
    customer_id    BIGINT,
    amount         NUMERIC(12,2),
    currency       TEXT,
    event_ts       TIMESTAMP,
    status         TEXT,
    ingested_at    TIMESTAMP DEFAULT now()   -- kapan baris masuk (untuk observasi)
);

-- Beberapa baris seed (id 1-5) supaya LAB 2 bisa langsung dicoba walau LAB 1 belum dijalankan.
-- LAB 1 akan menambah baris dengan id 1001+ dari file CSV (tidak bentrok dengan seed).
INSERT INTO raw.transactions (transaction_id, customer_id, amount, currency, event_ts, status) VALUES
    (1, 101,  25000.00, 'IDR', '2026-06-01 08:15:00', 'settled'),
    (2, 102,  12500.50, 'IDR', '2026-06-01 09:02:11', 'settled'),
    (3, 103, 340000.00, 'IDR', '2026-06-01 10:45:30', 'pending'),
    (4, 101,   5000.00, 'IDR', '2026-06-02 11:20:05', 'settled'),
    (5, 104,  98000.75, 'IDR', '2026-06-02 14:33:48', 'failed')
ON CONFLICT (transaction_id) DO NOTHING;

-- Index pada kolom inkremental yang dipakai QueryDatabaseTable di LAB 2.
CREATE INDEX IF NOT EXISTS idx_transactions_id ON raw.transactions (transaction_id);
