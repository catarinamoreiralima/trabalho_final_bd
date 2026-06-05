#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-f1db}"
DB_USER="${DB_USER:-f1user}"

docker compose up -d postgres

echo "Aguardando PostgreSQL ficar pronto..."
until docker compose exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  sleep 1
done

echo "Executando create_table.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/create_table.sql

echo "Executando insert_table.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/insert_table.sql

echo "Executando clean_data.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/clean_data.sql

echo "Executando app_users.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/app_users.sql

echo "Executando app_dashboard.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/app_dashboard.sql

echo "Executando app_reports.sql..."
docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -f sql/app_reports.sql

echo "Banco carregado com sucesso."
