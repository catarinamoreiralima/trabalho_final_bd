/* ============================================================================================================
   VIEWS

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
   5) app_actions.sql
   6) app_indexes.sql

   Este arquivo centraliza views reutilizaveis pelos dashboards e relatorios.
============================================================================================================ */

BEGIN;

/* ------------------------------------------------------------------------------------------------------------
   VIEW BASE - RESULTADOS DE CORRIDA ENRIQUECIDOS

   Centraliza os joins mais usados entre resultados, corridas, temporadas, pilotos, escuderias,
   status e circuitos. As funcoes continuam aplicando filtros por usuario logado quando necessario.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE VIEW vw_resultados_corridas AS
SELECT
    res.id AS resultado_id,
    res.race_id,
    res.driver_id,
    res.constructor_id,
    res.status_id,
    res.points,
    res.position_order,
    res.laps,
    r.season_id,
    s.year AS ano,
    r.round AS rodada,
    r.race_name AS corrida,
    r.race_date AS data_corrida,
    r.race_time AS horario_corrida,
    r.circuit_id,
    ci.name AS circuito,
    d.given_name AS piloto_nome,
    d.family_name AS piloto_sobrenome,
    c.name AS escuderia,
    st.status AS status_corrida
FROM results res
JOIN races r
  ON r.id = res.race_id
JOIN seasons s
  ON s.id = r.season_id
JOIN drivers d
  ON d.id = res.driver_id
JOIN constructors c
  ON c.id = res.constructor_id
JOIN status st
  ON st.id = res.status_id
JOIN circuits ci
  ON ci.id = r.circuit_id;

COMMENT ON VIEW vw_resultados_corridas
IS 'View base com resultados de corrida enriquecidos com temporada, piloto, escuderia, status e circuito.';

/* ------------------------------------------------------------------------------------------------------------
   VIEW BASE - RESUMO POR CORRIDA

   Resume cada corrida cadastrada com circuito, ano, rodada, voltas registradas e quantidade de pilotos.
   E usada pelo relatorio hierarquico de corridas do administrador.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE VIEW vw_corridas_resumo AS
SELECT
    r.id AS race_id,
    s.year AS ano,
    r.round AS rodada,
    r.race_name AS corrida,
    ci.id AS circuito_id,
    ci.name AS circuito,
    MAX(res.laps)::INTEGER AS voltas_registradas,
    COUNT(DISTINCT res.driver_id)::INTEGER AS quantidade_pilotos
FROM races r
JOIN seasons s
  ON s.id = r.season_id
JOIN circuits ci
  ON ci.id = r.circuit_id
LEFT JOIN results res
  ON res.race_id = r.id
GROUP BY
    r.id,
    s.year,
    r.round,
    r.race_name,
    ci.id,
    ci.name;

COMMENT ON VIEW vw_corridas_resumo
IS 'View base com resumo por corrida: circuito, ano, rodada, voltas registradas e quantidade de pilotos.';

/* ------------------------------------------------------------------------------------------------------------
   VIEW BASE - AEROPORTOS ENRIQUECIDOS COM CIDADE, PAIS E TIPO

   Centraliza os joins geograficos usados nos relatorios de aeroportos. A cidade pesquisada
   continua sendo filtrada na funcao, pois o calculo de distancia depende do parametro recebido.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE VIEW vw_aeroportos_cidades_paises AS
SELECT
    a.id AS aeroporto_id,
    a.ident AS aeroporto_ident,
    a.iata_code AS codigo_iata,
    a.icao_code AS codigo_icao,
    a.name AS nome_aeroporto,
    a.latitude_deg AS latitude_aeroporto,
    a.longitude_deg AS longitude_aeroporto,
    at.id AS tipo_aeroporto_id,
    at.type AS tipo_aeroporto,
    city_airport.id AS cidade_aeroporto_id,
    city_airport.name AS cidade_aeroporto,
    city_airport.latitude AS latitude_cidade_aeroporto,
    city_airport.longitude AS longitude_cidade_aeroporto,
    country_airport.id AS pais_aeroporto_id,
    country_airport.code AS codigo_pais_aeroporto,
    country_airport.name AS pais_aeroporto
FROM airports a
JOIN airport_types at
  ON at.id = a.airport_type_id
JOIN cities city_airport
  ON city_airport.id = a.city_id
JOIN countries country_airport
  ON country_airport.id = city_airport.country_id;

COMMENT ON VIEW vw_aeroportos_cidades_paises
IS 'View base com aeroportos enriquecidos com cidade, pais e tipo de aeroporto.';

/* ------------------------------------------------------------------------------------------------------------
   VIEW BASE - PILOTOS VINCULADOS A ESCUDERIAS

   Expõe a tabela app_escuderia_pilotos com dados completos de escuderia, piloto e pais. A relacao
   pode ter origem no historico de results ou em importacoes feitas pela aplicacao.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE VIEW vw_escuderia_pilotos AS
SELECT
    ep.escuderia_id,
    c.constructor_ref,
    c.name AS escuderia,
    ep.piloto_id,
    d.driver_ref,
    d.given_name AS piloto_nome,
    d.family_name AS piloto_sobrenome,
    (d.given_name || ' ' || d.family_name) AS piloto_nome_completo,
    d.date_of_birth AS piloto_data_nascimento,
    co.id AS pais_id,
    co.name AS pais,
    ep.origem,
    ep.created_at AS vinculo_criado_em
FROM app_escuderia_pilotos ep
JOIN constructors c
  ON c.id = ep.escuderia_id
JOIN drivers d
  ON d.id = ep.piloto_id
JOIN countries co
  ON co.id = d.country_id;

COMMENT ON VIEW vw_escuderia_pilotos
IS 'View base com pilotos vinculados a escuderias, incluindo origem do vinculo e dados de pais.';

COMMIT;
