# Shortcut untuk lab Openflow/NiFi. Jalankan `make help` untuk daftar perintah.
# Catatan: jika `docker` butuh sudo di mesin Anda, pakai `make SUDO=sudo up`.

SUDO ?=
COMPOSE = $(SUDO) docker compose
PG_DRIVER_VERSION ?= 42.7.4
DRIVER_JAR = drivers/postgresql-$(PG_DRIVER_VERSION).jar
DRIVER_URL = https://repo1.maven.org/maven2/org/postgresql/postgresql/$(PG_DRIVER_VERSION)/postgresql-$(PG_DRIVER_VERSION).jar

.PHONY: help drivers up down logs ps clean urls psql

help:
	@echo "Perintah lab:"
	@echo "  make drivers   - unduh driver JDBC PostgreSQL ke ./drivers"
	@echo "  make up        - unduh driver lalu jalankan semua service (-d)"
	@echo "  make down      - hentikan service (data tetap tersimpan)"
	@echo "  make clean     - hentikan service + HAPUS semua volume/data"
	@echo "  make logs      - ikuti log semua service"
	@echo "  make ps        - status container"
	@echo "  make urls      - tampilkan URL semua UI"
	@echo "  make psql      - buka shell psql ke PostgreSQL"

drivers:
	@mkdir -p drivers
	@if [ ! -f "$(DRIVER_JAR)" ]; then \
		echo "Mengunduh PostgreSQL JDBC driver $(PG_DRIVER_VERSION)..."; \
		curl -fSL -o "$(DRIVER_JAR)" "$(DRIVER_URL)"; \
		echo "Selesai: $(DRIVER_JAR)"; \
	else \
		echo "Driver sudah ada: $(DRIVER_JAR)"; \
	fi

up: drivers
	$(COMPOSE) up -d
	@echo ""
	@$(MAKE) --no-print-directory urls

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

ps:
	$(COMPOSE) ps

clean:
	$(COMPOSE) down -v
	@echo "Semua volume dihapus."

psql:
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-mlops} -d $${POSTGRES_DB:-mlops}

urls:
	@echo "NiFi (canvas):   https://localhost:8443/nifi    (login lihat .env)"
	@echo "NiFi Registry:   http://localhost:18080/nifi-registry"
	@echo "MinIO Console:   http://localhost:9001          (login lihat .env)"
	@echo "MinIO S3 API:    http://localhost:9000"
	@echo "PostgreSQL:      localhost:5432"
