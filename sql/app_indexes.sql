/* ============================================================================================================
   INDICES DA APLICACAO

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
   5) app_actions.sql

   Este arquivo centraliza indices auxiliares para dashboards e relatorios.
   Cada indice esta ligado ao relatorio/acao que ele acelera.
============================================================================================================ */

BEGIN;

-- (1) Índice PARCIAL + FUNCIONAL: cidade por país e nome normalizado, só com coordenadas
--     Acelera o Relatório 2 (aeroportos próximos a uma cidade brasileira)
CREATE INDEX IF NOT EXISTS idx_cities_country_lower_name_coordinates
ON cities (country_id, lower(name))                      -- funcional: lower(name) p/ busca case-insensitive
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;    -- parcial: só cidades com coordenadas

COMMENT ON INDEX idx_cities_country_lower_name_coordinates
IS 'Auxilia a busca de cidades por pais e nome normalizado em relatorios geograficos.';

-- (2) Índice PARCIAL: aeroportos com cidade, tipo e coordenadas disponíveis
--     Complementa o Relatório 2 ao selecionar aeroportos com posição conhecida
CREATE INDEX IF NOT EXISTS idx_airports_city_type_coordinates
ON airports (city_id, airport_type_id)
WHERE latitude_deg IS NOT NULL AND longitude_deg IS NOT NULL;  -- parcial: só aeroportos georreferenciados

COMMENT ON INDEX idx_airports_city_type_coordinates
IS 'Auxilia consultas de aeroportos com cidade, tipo e coordenadas disponiveis.';

-- (3) Índice SIMPLES: resultados por status
--     Acelera os relatórios de "resultados por status" (R1 admin, R5 escuderia, R7 piloto)
CREATE INDEX IF NOT EXISTS idx_results_status
ON results (status_id);

COMMENT ON INDEX idx_results_status
IS 'Auxilia consultas que agrupam ou filtram resultados por status_id.';

-- (4) Índice COMPOSTO: resultados por escuderia (e piloto)
--     Acelera a contagem de pilotos distintos por escuderia (R3 admin, R4 e R5 escuderia)
CREATE INDEX IF NOT EXISTS idx_results_constructor_driver
ON results (constructor_id, driver_id);

COMMENT ON INDEX idx_results_constructor_driver
IS 'Auxilia consultas por escuderia em results, especialmente contagem de pilotos distintos por constructor_id.';

-- (5) Índice PARCIAL + COBERTURA (INCLUDE): só resultados pontuados
--     Acelera o Relatório 6 (pontos por ano do piloto)
CREATE INDEX IF NOT EXISTS idx_results_driver_race_points_positive
ON results (driver_id, race_id)
INCLUDE (points)        -- cobertura: o índice já carrega os pontos, evita ir à tabela
WHERE points > 0;       -- parcial: indexa só as linhas que importam

COMMENT ON INDEX idx_results_driver_race_points_positive
IS 'Auxilia o relatorio de pontos por ano do piloto, filtrando resultados pontuados por driver_id.';

-- (6) Índice SIMPLES: pilotos vinculados a uma escuderia
--     Acelera a consulta de vínculo partindo do piloto (ações da Escuderia)
CREATE INDEX IF NOT EXISTS idx_app_escuderia_pilotos_piloto
ON app_escuderia_pilotos (piloto_id);

COMMENT ON INDEX idx_app_escuderia_pilotos_piloto
IS 'Auxilia consultas que partem do piloto para encontrar escuderias vinculadas na aplicacao.';

-- (7) Índice COMPOSTO: linhas pendentes de importação por escuderia
--     Acelera o processamento do CSV de pilotos importados
CREATE INDEX IF NOT EXISTS idx_app_import_pilotos_escuderia_pendentes
ON app_import_pilotos_escuderia (escuderia_id, importado, import_id);

COMMENT ON INDEX idx_app_import_pilotos_escuderia_pendentes
IS 'Auxilia o processamento de linhas pendentes de importacao de pilotos por escuderia.';

-- (8) Índice FUNCIONAL: busca de piloto por sobrenome sem diferenciar maiúsc/minúsc
--     Usado na ação "consultar piloto por sobrenome" (Escuderia)
CREATE INDEX IF NOT EXISTS idx_drivers_lower_family_name
ON drivers (lower(family_name));                         -- funcional: lower(family_name)

COMMENT ON INDEX idx_drivers_lower_family_name
IS 'Auxilia buscas case-insensitive de pilotos por sobrenome.';

COMMIT;
