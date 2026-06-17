# Trabalho Final BD

Projeto final da disciplina de Laboratório de Bases de Dados, com uma base relacional sobre Fórmula 1 integrada a dados geográficos de países, cidades e aeroportos.

O projeto cria o esquema do banco, carrega arquivos CSV/TSV, executa limpeza e normalização, define usuários da aplicação, cria views reutilizáveis e disponibiliza funções para dashboards e relatórios.

## Requisitos

- Docker
- Docker Compose

## Como Rodar

Para subir o PostgreSQL, carregar a base e depois carregar a camada da aplicação:

```bash
chmod +x scripts/load_database.sh scripts/load_app.sh scripts/psql.sh
./scripts/load_database.sh
./scripts/load_app.sh
```

Depois que a base já estiver carregada, use apenas o script da aplicação para testar mudanças em funções, views, índices, dashboards ou relatórios:

```bash
./scripts/load_app.sh
```

Para abrir o `psql` no banco:

```bash
./scripts/psql.sh
```

Para apagar o banco e começar do zero:

```bash
docker compose down -v
./scripts/load_database.sh
./scripts/load_app.sh
```

## Dados de Conexão

```text
Host: localhost
Porta: 5433
Banco: f1db
Usuário: f1user
Senha: f1pass
```

## Ordem de Execução

O script `scripts/load_database.sh` carrega apenas a base de dados:

1. `sql/create_table.sql`
2. `sql/insert_table.sql`
3. `sql/clean_data.sql`

O script `scripts/load_app.sh` carrega a camada da aplicação:

1. `sql/app_users.sql`
2. `sql/app_actions.sql`
3. `sql/app_indexes.sql`
4. `sql/app_views.sql`
5. `sql/app_dashboard.sql`
6. `sql/app_reports.sql`

Essa separação evita recarregar todos os dados sempre que uma função, relatório, view ou índice da aplicação for alterado.

## Estrutura do Projeto

```text
.
├── data/                  Arquivos CSV e TSV usados na carga do banco
├── docs/                  Relatório do projeto em LaTeX e PDF gerado
├── scripts/               Scripts auxiliares para carregar e acessar o banco
├── sql/                   Scripts SQL de criação, carga, limpeza e aplicação
├── docker-compose.yml     Configuração do PostgreSQL em Docker
├── .gitignore             Arquivos e pastas ignorados pelo Git
└── README.md              Documentação principal do projeto
```

## Arquivos SQL

### `sql/create_table.sql`

Cria o esquema relacional principal da base.

Conteúdo principal:

- remove tabelas antigas com `DROP TABLE IF EXISTS`;
- define tabelas geográficas: `continents`, `countries`, `time_zones`, `language_names`, `iso_language_codes`, `country_languages`, `feature_codes`, `cities`, `airport_types` e `airports`;
- define tabelas da Fórmula 1: `status`, `seasons`, `circuits`, `constructors`, `drivers`, `races`, `qualifying`, `results`, `standings`, `driver_standings` e `constructor_standings`;
- cria chaves primárias, chaves estrangeiras, restrições `UNIQUE` e comentários de documentação.

### `sql/insert_table.sql`

Carrega os dados brutos dos arquivos em `data/` e insere as informações nas tabelas finais.

Conteúdo principal:

- cria tabelas temporárias de staging para receber os CSV/TSV;
- usa `\copy` para carregar dados da Fórmula 1 e dados geográficos;
- carrega dimensões geográficas antes das tabelas de fatos;
- cria cidades complementares a partir de aeroportos e circuitos;
- cria a extensão `unaccent`;
- cria a função e trigger `normalize_city_name`, usadas para normalizar nomes de cidades;
- carrega temporadas, status, escuderias, pilotos, circuitos, corridas, qualificações e resultados;
- normaliza standings em `standings`, `driver_standings` e `constructor_standings`.

### `sql/clean_data.sql`

Executa a etapa de limpeza, padronização e deduplicação dos dados.

Conteúdo principal:

- cria métricas antes e depois da limpeza;
- normaliza nacionalidades de pilotos e escuderias;
- referencia nacionalidades à tabela `countries`;
- adiciona `country_id` em `drivers` e `constructors`;
- remove as colunas textuais antigas de nacionalidade depois da migração;
- identifica e trata possíveis duplicidades em cidades;
- atualiza referências de aeroportos e circuitos para cidades canônicas;
- mantém tabelas auxiliares de auditoria e validação, como `t1_metrics_before`, `t1_metrics_after`, `t1_nationality_reference_metrics`, `t1_city_group_validation` e `t1_city_manual_review`.

### `sql/app_users.sql`

Cria a camada de usuários, autenticação e auditoria da aplicação.

Conteúdo principal:

- cria a extensão `pgcrypto`;
- cria a tabela `users`, com usuários dos tipos `Admin`, `Escuderia` e `Piloto`;
- cria a tabela `users_log`, para registrar `LOGIN` e `LOGOUT`;
- cria o índice único `uq_users_tipo_id_original`, evitando duplicidade de usuário para a mesma escuderia ou piloto;
- cria funções de senha: `app_hash_password`, `app_check_password` e `app_alterar_senha`;
- cria a trigger `trg_users_set_updated_at`;
- cria usuários iniciais:
  - `admin / admin`;
  - `<constructor_ref>_c / <constructor_ref>`;
  - `<driver_ref>_d / <driver_ref>`;
- cria triggers para sincronizar novos pilotos e escuderias com a tabela `users`, preservando senhas alteradas;
- cria as funções `app_login` e `app_logout`.

### `sql/app_actions.sql`

Centraliza funções que representam ações da aplicação solicitadas na especificação.

Conteúdo principal:

- cria a tabela `app_escuderia_pilotos`, que mantém o vínculo entre escuderias e pilotos;
- popula `app_escuderia_pilotos` com os vínculos históricos inferidos da tabela `results`;
- cria trigger em `results` para sincronizar novos vínculos históricos entre pilotos e escuderias;
- cria a tabela `app_import_pilotos_escuderia`, usada como staging para arquivos CSV de pilotos;
- `app_admin_cadastrar_escuderia`: cadastra uma nova escuderia em `constructors`;
- `app_admin_cadastrar_piloto`: cadastra um novo piloto em `drivers`;
- `app_escuderia_processar_importacao_pilotos`: processa pilotos carregados por arquivo e cria o vínculo com a escuderia;
- `app_escuderia_listar_pilotos`: lista os pilotos vinculados à escuderia no cadastro da aplicação;
- `app_escuderia_consultar_piloto_por_sobrenome`: busca pilotos pelo sobrenome dentro do escopo da escuderia logada.

As funções de cadastro dependem das triggers criadas em `app_users.sql` para gerar automaticamente os usuários correspondentes.
O vínculo entre escuderia e piloto é mantido em uma tabela própria porque pilotos recém-importados ainda podem não ter resultados de corrida em `results`. A tabela aceita que um mesmo piloto esteja associado a mais de uma escuderia, preservando mudanças de escuderia e histórico de carreira.
Dashboards e relatórios de desempenho continuam usando `results`/`vw_resultados_corridas`, pois dependem de corridas reais. Consultas cadastrais de vínculo usam `app_escuderia_pilotos` ou `vw_escuderia_pilotos`.

### `sql/app_indexes.sql`

Centraliza índices auxiliares para consultas usadas em dashboards e relatórios.

Conteúdo principal:

- `idx_cities_country_lower_name_coordinates`: índice parcial em `cities` para busca de cidades com coordenadas por país e nome;
- `idx_airports_city_type_coordinates`: índice parcial em `airports` para aeroportos com cidade, tipo e coordenadas;
- `idx_results_status`: índice em `results (status_id)`;
- `idx_results_constructor_driver`: índice em `results (constructor_id, driver_id)`;
- `idx_results_driver_race_points_positive`: índice parcial em `results (driver_id, race_id)`, incluindo `points`, apenas para resultados pontuados;
- `idx_app_escuderia_pilotos_piloto`: índice em `app_escuderia_pilotos (piloto_id)`;
- `idx_app_import_pilotos_escuderia_pendentes`: índice em `app_import_pilotos_escuderia (escuderia_id, importado, import_id)`;
- `idx_drivers_lower_family_name`: índice funcional para busca de pilotos por sobrenome;
- auxilia consultas que agrupam ou filtram resultados por status;
- auxilia consultas que agrupam ou filtram resultados por escuderia;
- ajuda a contagem de pilotos distintos por escuderia no Relatório Admin 3;
- beneficia relatórios de escuderia que usam `constructor_id`;
- auxilia o Relatório 2 com filtros geográficos, o Relatório 6 com pontos por piloto e as ações de importação/consulta de pilotos por escuderia.

### `sql/app_views.sql`

Centraliza views reutilizáveis por dashboards e relatórios.

Conteúdo principal:

- `vw_resultados_corridas`: reúne resultados de corrida com temporada, corrida, piloto, escuderia, status e circuito;
- `vw_corridas_resumo`: resume cada corrida com circuito, ano, rodada, voltas registradas e quantidade de pilotos;
- `vw_aeroportos_cidades_paises`: reúne aeroportos com cidade, país e tipo de aeroporto;
- `vw_escuderia_pilotos`: reúne escuderias, pilotos, países e a origem do vínculo entre eles.

Essas views reduzem repetição de joins nas funções da aplicação. Os filtros específicos continuam nas funções, de acordo com o perfil do usuário ou com o parâmetro recebido.

### `sql/app_dashboard.sql`

Cria funções para os dashboards da aplicação.

Conteúdo principal:

- dashboard do administrador:
  - `app_admin_dashboard_resumo`;
  - `app_admin_corridas_temporada_mais_recente`;
  - `app_admin_escuderias_temporada_mais_recente`;
  - `app_admin_pilotos_temporada_mais_recente`;
- dashboard do piloto:
  - `app_piloto_anos`;
  - `app_piloto_resumo`;
- dashboard da escuderia:
  - `app_escuderia_anos`;
  - `app_escuderia_quantidade_pilotos`;
  - `app_escuderia_quantidade_vitorias`.

As funções usam a view `vw_resultados_corridas` quando precisam consultar resultados enriquecidos com ano, corrida, piloto, escuderia, status ou circuito.

### `sql/app_reports.sql`

Cria funções para relatórios da aplicação.

Conteúdo principal:

- cria as extensões `cube` e `earthdistance`, usadas no cálculo de distância geográfica;
- Relatório 1, administrador: `app_admin_relatorio_status_resultados`;
- Relatório 2, administrador: `app_admin_relatorio_aeroportos_por_cidade`;
- Relatório 3, administrador:
  - Parte A: `app_admin_relatorio_3_escuderias_pilotos`;
  - Parte B: `app_admin_relatorio_3_hierarquico_corridas`;
- Relatório 4, escuderia: `app_escuderia_relatorio_4`;
- Relatório 5, escuderia: `app_escuderia_relatorio_5`;
- Relatório 6, piloto: `app_piloto_relatorio_6`;
- Relatório 7, piloto: `app_piloto_relatorio_7`.

O relatório de aeroportos usa `vw_aeroportos_cidades_paises` e calcula a distância entre a cidade pesquisada e os aeroportos com `earth_distance`.

## Scripts

### `scripts/load_database.sh`

Script de carga da base de dados.

Conteúdo principal:

- sobe o serviço `postgres` com Docker Compose;
- espera o PostgreSQL ficar pronto;
- executa `create_table.sql`, `insert_table.sql` e `clean_data.sql`;
- recria o esquema, carrega os CSV/TSV e executa a limpeza dos dados;
- usa as variáveis `DB_NAME` e `DB_USER`, com valores padrão `f1db` e `f1user`.

### `scripts/load_app.sh`

Script de carga da camada da aplicação.

Conteúdo principal:

- sobe o serviço `postgres` com Docker Compose, caso ele ainda não esteja em execução;
- espera o PostgreSQL ficar pronto;
- executa `app_users.sql`, `app_actions.sql`, `app_indexes.sql`, `app_views.sql`, `app_dashboard.sql` e `app_reports.sql`;
- permite testar alterações em funções, views, índices e relatórios sem recarregar a base inteira;
- usa as variáveis `DB_NAME` e `DB_USER`, com valores padrão `f1db` e `f1user`.

### `scripts/psql.sh`

Abre um terminal `psql` dentro do contêiner PostgreSQL.

Conteúdo principal:

- usa `docker compose exec postgres`;
- conecta no banco definido por `DB_NAME`;
- conecta com o usuário definido por `DB_USER`.

## Docker

### `docker-compose.yml`

Define o serviço PostgreSQL usado pelo projeto.

Conteúdo principal:

- imagem `postgres:16`;
- contêiner `trabalho-final-bd-postgres`;
- banco `f1db`;
- usuário `f1user`;
- senha `f1pass`;
- porta local `5433`, mapeada para a porta interna `5432`;
- volume persistente `postgres_data`;
- montagem do diretório do projeto em `/work`, permitindo que o PostgreSQL leia os arquivos SQL e dados.

## Arquivos de Dados

Os arquivos em `data/` são usados por `sql/insert_table.sql`.

### Dados da Fórmula 1

- `data/circuits.csv`: circuitos/autódromos.
- `data/constructors.csv`: escuderias.
- `data/drivers.csv`: pilotos.
- `data/races.csv`: corridas por temporada e rodada.
- `data/results.csv`: resultados de pilotos em corridas.
- `data/qualifying.csv`: resultados de qualificação.
- `data/driver_standings.csv`: classificação de pilotos.
- `data/constructor_standings.csv`: classificação de escuderias.

### Dados Geográficos

- `data/countries.csv`: países.
- `data/regions.csv`: regiões/continentes associadas aos países.
- `data/cities.tsv`: cidades e localidades do GeoNames.
- `data/airports.csv`: aeroportos.
- `data/timeZones.tsv`: fusos horários.
- `data/featureCodes_en.tsv`: códigos de características geográficas.
- `data/iso-languagecodes.tsv`: códigos ISO de idiomas.

## Documentação

### `docs/relatorio.tex`

Arquivo LaTeX do relatório do projeto.

Conteúdo principal:

- introdução e objetivo;
- preparação da base;
- execução com Docker;
- modelo de usuários e autenticação;
- views reutilizáveis;
- triggers implementadas;
- dashboards;
- relatórios;
- índices;
- interface da aplicação;
- decisões de projeto, dificuldades e conclusão.

### `docs/relatorio.pdf`

PDF gerado a partir de `docs/relatorio.tex`.

### Arquivos auxiliares do LaTeX

Os arquivos `docs/relatorio.aux`, `docs/relatorio.out`, `docs/relatorio.fdb_latexmk`, `docs/relatorio.fls`, `docs/relatorio.log` e `docs/relatorio.synctex.gz` são arquivos gerados automaticamente durante a compilação do LaTeX.

## Outros Arquivos

### `.gitignore`

Define arquivos que não devem ser versionados pelo Git, como saídas temporárias, arquivos gerados automaticamente e artefatos locais de execução.

## Views Principais

### `vw_resultados_corridas`

View base para dados de corrida enriquecidos.

Inclui:

- resultado;
- corrida;
- temporada;
- piloto;
- escuderia;
- status;
- circuito;
- pontos, posição, voltas e rodada.

É usada em dashboards e relatórios que precisam consultar resultados por ano, piloto, escuderia, status ou circuito.

### `vw_aeroportos_cidades_paises`

View base para dados geográficos de aeroportos.

Inclui:

- aeroporto;
- código IATA e ICAO;
- latitude e longitude do aeroporto;
- tipo do aeroporto;
- cidade do aeroporto;
- país do aeroporto.

É usada no relatório de aeroportos próximos a uma cidade brasileira.

### `vw_corridas_resumo`

View base para o relatório hierárquico de corridas.

Inclui:

- corrida;
- ano;
- rodada;
- circuito;
- voltas registradas;
- quantidade de pilotos participantes.

É usada na Parte B do Relatório Admin 3, evitando repetir a agregação de corridas dentro da função.

### `vw_escuderia_pilotos`

View base para consultar os pilotos vinculados a cada escuderia.

Inclui:

- escuderia;
- piloto;
- país do piloto;
- data de nascimento;
- origem do vínculo.

É usada como visão consolidada da tabela `app_escuderia_pilotos`, que combina vínculos históricos vindos de `results` e vínculos criados por importação de arquivo.

## Usuários Padrão

Após executar `sql/app_users.sql`, ficam disponíveis:

- administrador:
  - login: `admin`;
  - senha: `admin`;
- escuderias:
  - login: `<constructor_ref>_c`;
  - senha: `<constructor_ref>`;
- pilotos:
  - login: `<driver_ref>_d`;
  - senha: `<driver_ref>`.

As senhas são armazenadas como hash usando `pgcrypto`, não em texto puro.

## Observações

- O banco é persistido no volume Docker `postgres_data`.
- Para recarregar tudo do zero, é necessário remover o volume com `docker compose down -v`.
- Os scripts SQL foram pensados para serem executados na ordem definida por `scripts/load_database.sh` e `scripts/load_app.sh`.
- As views ficam separadas em `sql/app_views.sql` para facilitar reutilização e manutenção.
