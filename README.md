# Trabalho Final BD

## Como rodar com Docker

Requisitos:

- Docker
- Docker Compose

Para subir o PostgreSQL e carregar a base:

```bash
chmod +x scripts/load_database.sh scripts/psql.sh
./scripts/load_database.sh
```

Esse comando executa os scripts nesta ordem:

1. `sql/create_table.sql`
2. `sql/insert_table.sql`
3. `sql/clean_data.sql`
4. `sql/app_users.sql`

Para abrir o `psql` no banco:

```bash
./scripts/psql.sh
```

Dados de conexão:

```text
Host: localhost
Porta: 5433
Banco: f1db
Usuario: f1user
Senha: f1pass
```

Para apagar o banco e começar do zero:

```bash
docker compose down -v
./scripts/load_database.sh
```
