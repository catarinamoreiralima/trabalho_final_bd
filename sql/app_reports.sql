/* ============================================================================================================
   RELATORIOS

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
   5) app_dashboard.sql

   Este arquivo comeca apenas com o Relatorio 1 do Admin.
============================================================================================================ */

BEGIN;

CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

/* ------------------------------------------------------------------------------------------------------------
   ADMIN - RELATORIO 1

   Indica a quantidade de resultados por status, apresentando o nome do status
   e sua respectiva contagem.

   Conceitos usados:
   - JOIN entre results e status;
   - agregacao com COUNT;
   - GROUP BY para agrupar os resultados por status.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_admin_relatorio_status_resultados()
RETURNS TABLE (
    status_corrida TEXT,
    quantidade_resultados INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        st.status::TEXT AS status_corrida,
        COUNT(*)::INTEGER AS quantidade_resultados
    FROM results res
    JOIN status st
      ON st.id = res.status_id
    GROUP BY st.id, st.status
    ORDER BY quantidade_resultados DESC, status_corrida;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_relatorio_status_resultados()
IS 'Relatorio Admin 1: quantidade de resultados por status.';


/* ------------------------------------------------------------------------------------------------------------
   ADMIN - RELATORIO 2

   Entrada:
   - nome de uma cidade.

   Objetivo:
   - para cada cidade brasileira que tenha esse nome, apresentar todos os aeroportos brasileiros
     que estejam a, no maximo, 100 km da respectiva cidade;
   - considerar apenas aeroportos dos tipos:
     - 'medium_airport'
     - 'large_airport'

   Colunas esperadas no resultado:
   - nome da cidade pesquisada;
   - codigo IATA do aeroporto;
   - nome do aeroporto;
   - cidade em que o aeroporto esta localizado;
   - distancia entre a cidade pesquisada e o aeroporto;
   - tipo do aeroporto.

   Observacao:
   - deve ser criado tambem um indice que auxilie essa consulta.
------------------------------------------------------------------------------------------------------------ */

CREATE OR REPLACE FUNCTION app_admin_relatorio_aeroportos_por_cidade(p_city_name TEXT)
RETURNS TABLE (
    nome_cidade TEXT,
    codigo_iata TEXT,
    nome_aeroporto TEXT,
    cidade_aeroporto TEXT,
    distancia_km DOUBLE PRECISION,
    tipo_aeroporto TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name::TEXT AS nome_cidade,
        a.iata_code::TEXT AS codigo_iata,
        a.name::TEXT AS nome_aeroporto,
        city_airport.name::TEXT AS cidade_aeroporto,
        (
            earth_distance(
                ll_to_earth(c.latitude, c.longitude),
                ll_to_earth(a.latitude_deg, a.longitude_deg)
            ) / 1000.0
        )::DOUBLE PRECISION AS distancia_km,
        at.type::TEXT AS tipo_aeroporto
    FROM cities c
    JOIN countries country_city
      ON country_city.id = c.country_id
    JOIN airports a
      ON a.latitude_deg IS NOT NULL
     AND a.longitude_deg IS NOT NULL
    JOIN airport_types at
      ON at.id = a.airport_type_id
    JOIN cities city_airport
      ON city_airport.id = a.city_id
    JOIN countries country_airport
      ON country_airport.id = city_airport.country_id
    WHERE lower(c.name) = lower(p_city_name)
      AND country_city.code = 'BR'
      AND country_airport.code = 'BR'
      AND at.type IN ('medium_airport', 'large_airport')
      AND c.latitude IS NOT NULL
      AND c.longitude IS NOT NULL
      AND earth_distance(
            ll_to_earth(c.latitude, c.longitude),
            ll_to_earth(a.latitude_deg, a.longitude_deg)
          ) <= 100000
    ORDER BY distancia_km, nome_aeroporto;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_relatorio_aeroportos_por_cidade(TEXT)
IS 'Relatorio Admin 2: aeroportos brasileiros medium/large a ate 100 km de uma cidade brasileira.';



/* ------------------------------------------------------------------------------------------------------------
   ADMIN - RELATORIO 3

   Parte A:
   - listar todas as escuderias cadastradas;
   - para cada escuderia, mostrar a respectiva quantidade de pilotos.

   Parte B:
   - gerar um relatorio hierarquico em tres niveis:

   Nivel 1:
   - quantidade de corridas cadastradas no total.

   Nivel 2:
   - quantidade de corridas cadastradas por circuito;
   - quantidade minima de voltas registradas nos resultados;
   - quantidade media de voltas registradas nos resultados;
   - quantidade maxima de voltas registradas nos resultados.

   Nivel 3:
   - para cada corrida por circuito:
     - quantidade de voltas registradas;
     - quantidade de pilotos participantes.
------------------------------------------------------------------------------------------------------------ */






/* ------------------------------------------------------------------------------------------------------------
   ESCUDERIA - RELATORIO 4

   Entrada:
   - identificador da escuderia logada.

   Objetivo:
   - listar os pilotos da escuderia;
   - apresentar a quantidade de vezes em que cada piloto alcancou a primeira posicao em uma corrida;
   - identificar os pilotos pelo nome completo.

   Observacao:
   - para verificar se um piloto ja correu por uma escuderia e se houve vitoria, usar a tabela results;
   - devem ser criados os indices necessarios para auxiliar essa consulta.
------------------------------------------------------------------------------------------------------------ */

DROP FUNCTION IF EXISTS app_escuderia_relatorio_4(INTEGER);

CREATE OR REPLACE FUNCTION app_escuderia_relatorio_4(escuderia_id INTEGER)
RETURNS TABLE (
    escuderia_nome TEXT,
    nome_piloto TEXT,
    quantidade_vitorias INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name::TEXT AS escuderia_nome,
        (d.given_name || ' ' || d.family_name)::TEXT AS nome_piloto,
        COUNT(CASE WHEN res.position_order = 1 THEN 1 END)::INTEGER AS quantidade_vitorias
    FROM constructors c
    LEFT JOIN results res
      ON res.constructor_id = c.id
    LEFT JOIN drivers d
      ON d.id = res.driver_id
    WHERE c.id = escuderia_id
      AND d.id IS NOT NULL
    GROUP BY c.id, c.name, d.id, d.given_name, d.family_name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_relatorio_4(escuderia_id INTEGER)
IS 'Relatorio Escuderia 4: quantidade de vitorias por piloto.';






/* ------------------------------------------------------------------------------------------------------------
   ESCUDERIA - RELATORIO 5

   Entrada:
   - identificador da escuderia logada.

   Objetivo:
   - listar a quantidade de resultados por status;
   - apresentar o status e sua contagem;
   - limitar os resultados ao escopo da escuderia logada.
------------------------------------------------------------------------------------------------------------ */


DROP FUNCTION IF EXISTS app_escuderia_relatorio_5(INTEGER);

CREATE OR REPLACE FUNCTION app_escuderia_relatorio_5(escuderia_id INTEGER)
RETURNS TABLE (
    escuderia_nome TEXT,
    status_corrida TEXT,
    quantidade_corridas INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name::TEXT AS escuderia_nome,
        st.status::TEXT AS status_corrida,
        COUNT(*)::INTEGER AS quantidade_corridas
    FROM constructors c
    LEFT JOIN results res
      ON res.constructor_id = c.id
    LEFT JOIN status st
      ON st.id = res.status_id
    WHERE c.id = escuderia_id
    GROUP BY c.name, st.status;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_relatorio_5(escuderia_id INTEGER)
IS 'Relatorio Escuderia 5: quantidade de resultados por status.';


/* ------------------------------------------------------------------------------------------------------------
   PILOTO - RELATORIO 6

   Entrada:
   - identificador do piloto logado.

   Objetivo:
   - consultar a quantidade total de pontos obtidos por ano de participacao na Formula 1;
   - apresentar, para cada ano, as corridas em que os pontos foram obtidos;
   - restringir as informacoes apenas ao piloto logado.

   Observacao:
   - devem ser criados os indices necessarios para auxiliar essa consulta.
------------------------------------------------------------------------------------------------------------ */

/* ------------------------------------------------------------------------------------------------------------
   PILOTO - RELATORIO 7

   Entrada:
   - identificador do piloto logado.

   Objetivo:
   - listar a quantidade de resultados por status nas corridas em que o piloto participou;
   - apresentar o status e a contagem de cada um;
   - limitar os resultados ao escopo do piloto logado.
------------------------------------------------------------------------------------------------------------ */

COMMIT;
