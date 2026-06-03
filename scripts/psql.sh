#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-f1db}"
DB_USER="${DB_USER:-f1user}"

docker compose exec postgres psql -U "$DB_USER" -d "$DB_NAME"
