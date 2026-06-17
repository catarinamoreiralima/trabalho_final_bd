/* ============================================================================================================
   INDICES DA APLICACAO

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
   5) app_actions.sql

   Este arquivo centraliza indices auxiliares para dashboards e relatorios.
============================================================================================================ */

BEGIN;

/* ------------------------------------------------------------------------------------------------------------
   RELATORIO ADMIN 2 - AEROPORTOS PROXIMOS A CIDADE BRASILEIRA

   Auxilia a busca da cidade brasileira pelo nome informado e a selecao de aeroportos com coordenadas.
   Exemplo de uso:
   - app_admin_relatorio_aeroportos_por_cidade(p_city_name)
------------------------------------------------------------------------------------------------------------ */
CREATE INDEX IF NOT EXISTS idx_cities_country_lower_name_coordinates
ON cities (country_id, lower(name))
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL;

COMMENT ON INDEX idx_cities_country_lower_name_coordinates
IS 'Auxilia a busca de cidades por pais e nome normalizado em relatorios geograficos.';

CREATE INDEX IF NOT EXISTS idx_airports_city_type_coordinates
ON airports (city_id, airport_type_id)
WHERE latitude_deg IS NOT NULL
  AND longitude_deg IS NOT NULL;

COMMENT ON INDEX idx_airports_city_type_coordinates
IS 'Auxilia consultas de aeroportos com cidade, tipo e coordenadas disponiveis.';

/* ------------------------------------------------------------------------------------------------------------
   RELATORIOS POR STATUS

   Auxilia consultas que agrupam ou filtram resultados por status.
   Exemplo de uso:
   - app_admin_relatorio_status_resultados()
   - app_escuderia_relatorio_5()
   - app_piloto_relatorio_7()
------------------------------------------------------------------------------------------------------------ */
CREATE INDEX IF NOT EXISTS idx_results_status
ON results (status_id);

COMMENT ON INDEX idx_results_status
IS 'Auxilia consultas que agrupam ou filtram resultados por status_id.';

/* ------------------------------------------------------------------------------------------------------------
   RELATORIOS DE ESCUDERIAS E RELATORIO ADMIN 3

   Auxilia consultas que agrupam ou filtram resultados por escuderia e contam pilotos distintos.
   Exemplo de uso:
   - app_admin_relatorio_3_escuderias_pilotos()
   - app_escuderia_relatorio_4()
   - app_escuderia_relatorio_5()
------------------------------------------------------------------------------------------------------------ */
CREATE INDEX IF NOT EXISTS idx_results_constructor_driver
ON results (constructor_id, driver_id);

COMMENT ON INDEX idx_results_constructor_driver
IS 'Auxilia consultas por escuderia em results, especialmente contagem de pilotos distintos por constructor_id.';

/* ------------------------------------------------------------------------------------------------------------
   RELATORIO PILOTO 6

   Auxilia consultas que buscam corridas pontuadas por piloto.
   Exemplo de uso:
   - app_piloto_relatorio_6(piloto_id)
------------------------------------------------------------------------------------------------------------ */
CREATE INDEX IF NOT EXISTS idx_results_driver_race_points_positive
ON results (driver_id, race_id)
INCLUDE (points)
WHERE points > 0;

COMMENT ON INDEX idx_results_driver_race_points_positive
IS 'Auxilia o relatorio de pontos por ano do piloto, filtrando resultados pontuados por driver_id.';

/* ------------------------------------------------------------------------------------------------------------
   ACOES DE ESCUDERIA - VINCULO E IMPORTACAO DE PILOTOS

   Auxilia a consulta de pilotos vinculados a uma escuderia e o processamento de linhas pendentes
   carregadas por arquivo.
------------------------------------------------------------------------------------------------------------ */
CREATE INDEX IF NOT EXISTS idx_app_escuderia_pilotos_piloto
ON app_escuderia_pilotos (piloto_id);

COMMENT ON INDEX idx_app_escuderia_pilotos_piloto
IS 'Auxilia consultas que partem do piloto para encontrar escuderias vinculadas na aplicacao.';

CREATE INDEX IF NOT EXISTS idx_app_import_pilotos_escuderia_pendentes
ON app_import_pilotos_escuderia (escuderia_id, importado, import_id);

COMMENT ON INDEX idx_app_import_pilotos_escuderia_pendentes
IS 'Auxilia o processamento de linhas pendentes de importacao de pilotos por escuderia.';

CREATE INDEX IF NOT EXISTS idx_drivers_lower_family_name
ON drivers (lower(family_name));

COMMENT ON INDEX idx_drivers_lower_family_name
IS 'Auxilia buscas case-insensitive de pilotos por sobrenome.';

COMMIT;
