/* ============================================================================================================
   DASHBOARDS

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
============================================================================================================ */

/* ============================================================================================================
   DASHBOARD DO ADMINISTRADOR
============================================================================================================ */


BEGIN;

/* ------------------------------------------------------------------------------------------------------------
   1. RESUMO GERAL DO ADMINISTRADORt

   Retorna os totais principais pedidos no enunciado:
   - quantidade total de pilotos;
   - quantidade total de escuderias;
   - quantidade total de temporadas;
   - temporada mais recente da base.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_admin_dashboard_resumo()
RETURNS TABLE (
    total_pilotos INTEGER,
    total_escuderias INTEGER,
    total_temporadas INTEGER,
    temporada_mais_recente INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*)::INTEGER FROM drivers) AS total_pilotos,
        (SELECT COUNT(*)::INTEGER FROM constructors) AS total_escuderias,
        (SELECT COUNT(*)::INTEGER FROM seasons) AS total_temporadas,
        (SELECT MAX(year)::INTEGER FROM seasons) AS temporada_mais_recente;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_dashboard_resumo()
IS 'Dashboard Admin: totais de pilotos, escuderias, temporadas e temporada mais recente.';

/* ------------------------------------------------------------------------------------------------------------
   2. CORRIDAS DA TEMPORADA MAIS RECENTE

   A quantidade de voltas e obtida por MAX(results.laps), pois cada piloto possui uma linha
   em results e o maior valor representa a maior quantidade de voltas registrada para a corrida.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_admin_corridas_temporada_mais_recente()
RETURNS TABLE (
    temporada INTEGER,
    rodada INTEGER,
    corrida TEXT,
    circuito TEXT,
    data_corrida DATE,
    horario_corrida TIME,
    voltas_registradas INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.year AS temporada,
        r.round AS rodada,
        r.race_name AS corrida,
        c.name AS circuito,
        r.race_date AS data_corrida,
        r.race_time AS horario_corrida,
        MAX(res.laps)::INTEGER AS voltas_registradas
    FROM races r
    JOIN seasons s
      ON s.id = r.season_id
    JOIN circuits c
      ON c.id = r.circuit_id
    LEFT JOIN results res
      ON res.race_id = r.id
    WHERE s.year = (SELECT MAX(year) FROM seasons)
    GROUP BY
        s.year,
        r.round,
        r.race_name,
        c.name,
        r.race_date,
        r.race_time
    ORDER BY r.round;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_corridas_temporada_mais_recente()
IS 'Dashboard Admin: corridas da temporada mais recente, com circuito, data, horario e voltas registradas.';

/* ------------------------------------------------------------------------------------------------------------
   3. ESCUDERIAS DA TEMPORADA MAIS RECENTE COM TOTAL DE PONTOS

   Usa JOIN entre results, races, seasons e constructors para somar os pontos obtidos
   por cada escuderia na temporada mais recente.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_admin_escuderias_temporada_mais_recente()
RETURNS TABLE (
    temporada INTEGER,
    escuderia TEXT,
    total_pontos NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.year AS temporada,
        c.name AS escuderia,
        SUM(res.points) AS total_pontos
    FROM results res
    JOIN races r
      ON r.id = res.race_id
    JOIN seasons s
      ON s.id = r.season_id
    JOIN constructors c
      ON c.id = res.constructor_id
    WHERE s.year = (SELECT MAX(year) FROM seasons)
    GROUP BY s.year, c.id, c.name
    ORDER BY total_pontos DESC, c.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_escuderias_temporada_mais_recente()
IS 'Dashboard Admin: escuderias da temporada mais recente com total de pontos.';

/* ------------------------------------------------------------------------------------------------------------
   4. PILOTOS DA TEMPORADA MAIS RECENTE COM TOTAL DE PONTOS

   Usa JOIN entre results, races, seasons e drivers para somar os pontos obtidos
   por cada piloto na temporada mais recente.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_admin_pilotos_temporada_mais_recente()
RETURNS TABLE (
    temporada INTEGER,
    piloto TEXT,
    total_pontos NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.year AS temporada,
        d.given_name || ' ' || d.family_name AS piloto,
        SUM(res.points) AS total_pontos
    FROM results res
    JOIN races r
      ON r.id = res.race_id
    JOIN seasons s
      ON s.id = r.season_id
    JOIN drivers d
      ON d.id = res.driver_id
    WHERE s.year = (SELECT MAX(year) FROM seasons)
    GROUP BY s.year, d.id, d.given_name, d.family_name
    ORDER BY total_pontos DESC, piloto;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_pilotos_temporada_mais_recente()
IS 'Dashboard Admin: pilotos da temporada mais recente com total de pontos.';

COMMIT;

/* ============================================================================================================
   DASHBOARD DO PILOTO
============================================================================================================ */

BEGIN;

/* ------------------------------------------------------------------------------------------------------------
   1. RESUMO GERAL DO PILOTO

   Retorna os totais principais pedidos no enunciado:
   - primeiro e ultimo ano do piloto na base
   - para cada ano e circuito:
        - quantidade de pontos obtidos
        - quantidade de vitórias
        - quantidade total de corridas disputadas
------------------------------------------------------------------------------------------------------------ */

CREATE OR REPLACE FUNCTION app_piloto_anos(piloto_id INTEGER)
RETURNS TABLE (
    piloto_nome VARCHAR(255),
    piloto_sobrenome VARCHAR(255),
    primeiro_ano INTEGER,
    ultimo_ano INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.given_name AS piloto_nome,
        d.family_name AS piloto_sobrenome,
        MIN(s.year)::INTEGER AS primeiro_ano,
        MAX(s.year)::INTEGER AS ultimo_ano
    FROM drivers d
    JOIN results res
      ON res.driver_id = d.id
    JOIN races r
      ON r.id = res.race_id
    JOIN seasons s
      ON s.id = r.season_id
    WHERE d.id = piloto_id
    GROUP BY d.id, d.given_name, d.family_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_piloto_anos(piloto_id INTEGER)
IS 'Dashboard piloto: anos de atuação do piloto.';

DROP FUNCTION IF EXISTS app_piloto_resumo(INTEGER);

CREATE OR REPLACE FUNCTION app_piloto_resumo(piloto_id INTEGER)
RETURNS TABLE (
    piloto_nome VARCHAR(255),
    piloto_sobrenome VARCHAR(255),
    ano INTEGER,
    circuito TEXT,
    pontos NUMERIC(10,2),
    vitorias INTEGER,
    corridas_disputadas INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.given_name AS piloto_nome,
        d.family_name AS piloto_sobrenome,
        s.year AS ano,
        c.name AS circuito,
        SUM(res.points)::NUMERIC(10,2) AS pontos,
        COUNT(CASE WHEN res.position_order = 1 THEN 1 END)::INTEGER AS vitorias,
        COUNT(*)::INTEGER AS corridas_disputadas
    FROM drivers d
    JOIN results res
      ON res.driver_id = d.id
    JOIN races r
      ON r.id = res.race_id
    JOIN seasons s
      ON s.id = r.season_id
    JOIN circuits c
      ON c.id = r.circuit_id
    WHERE d.id = piloto_id
    GROUP BY d.id, d.given_name, d.family_name, s.year, c.id, c.name
    ORDER BY s.year;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_piloto_resumo(piloto_id INTEGER)
IS 'Dashboard piloto: resumo de desempenho do piloto por ano e circuito.';

/* ------------------------------------------------------------------------------------------------------------
   3. RESUMO GERAL DA ESCUDERIA

   Retorna os totais principais pedidos no enunciado:
  1. quantidade de vitórias da escuderia, considerando as corridas em que obteve a primeira posição;
    2. quantidade de pilotos diferentes que já correram pela escuderia;
    3. primeiro e último ano em que há dados da escuderia na base, considerando a tabela RESULTS.
------------------------------------------------------------------------------------------------------------ */

CREATE OR REPLACE FUNCTION app_escuderia_anos(escuderia_id INTEGER)
RETURNS TABLE (
    escuderia_nome VARCHAR(255),
    primeiro_ano INTEGER,
    ultimo_ano INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name AS escuderia_nome,
        MIN(s.year)::INTEGER AS primeiro_ano,
        MAX(s.year)::INTEGER AS ultimo_ano
    FROM constructors c
    JOIN results res
      ON res.constructor_id = c.id
    JOIN races r
      ON r.id = res.race_id
    JOIN seasons s
      ON s.id = r.season_id
    WHERE c.id = escuderia_id
    GROUP BY c.id, c.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_anos(escuderia_id INTEGER)
IS 'Dashboard escuderia: anos de atuação da escuderia.';

CREATE OR REPLACE FUNCTION app_escuderia_quantidade_pilotos(escuderia_id INTEGER)
RETURNS TABLE (
    escuderia_nome VARCHAR(255),
    quantidade_pilotos INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name AS escuderia_nome,
        COUNT(DISTINCT res.driver_id)::INTEGER AS quantidade_pilotos
    FROM constructors c
    LEFT JOIN results res
      ON res.constructor_id = c.id
    WHERE c.id = escuderia_id
    GROUP BY c.id, c.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_quantidade_pilotos(escuderia_id INTEGER)
IS 'Dashboard escuderia: quantidade de pilotos que correram pela escuderia.';


CREATE OR REPLACE FUNCTION app_escuderia_quantidade_vitorias(escuderia_id INTEGER)
RETURNS TABLE (
    escuderia_nome VARCHAR(255),
    quantidade_vitorias INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name AS escuderia_nome,
        COUNT(CASE WHEN res.position_order = 1 THEN 1 END)::INTEGER AS quantidade_vitorias
    FROM constructors c
    LEFT JOIN results res
      ON res.constructor_id = c.id
    WHERE c.id = escuderia_id
    GROUP BY c.id, c.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_quantidade_vitorias(escuderia_id INTEGER)
IS 'Dashboard escuderia: quantidade de vitorias da escuderia.';



COMMIT;
