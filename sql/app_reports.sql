/* ============================================================================================================
   RELATORIOS

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql
   5) app_actions.sql
   6) app_indexes.sql
   7) app_views.sql
   8) app_dashboard.sql
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
        vrc.status_corrida::TEXT AS status_corrida,
        COUNT(*)::INTEGER AS quantidade_resultados
    FROM vw_resultados_corridas vrc
    GROUP BY vrc.status_id, vrc.status_corrida
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
     - 'large_airport'e

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
        vap.codigo_iata::TEXT AS codigo_iata,
        vap.nome_aeroporto::TEXT AS nome_aeroporto,
        vap.cidade_aeroporto::TEXT AS cidade_aeroporto,
        (
            earth_distance(
                ll_to_earth(c.latitude, c.longitude),
                ll_to_earth(vap.latitude_aeroporto, vap.longitude_aeroporto)
            ) / 1000.0
        )::DOUBLE PRECISION AS distancia_km,
        vap.tipo_aeroporto::TEXT AS tipo_aeroporto
    FROM cities c
    JOIN countries country_city
      ON country_city.id = c.country_id
    JOIN vw_aeroportos_cidades_paises vap
      ON vap.latitude_aeroporto IS NOT NULL
     AND vap.longitude_aeroporto IS NOT NULL
    -- Filtro accent-insensitive: usa unaccent (extensao criada em insert_table.sql) para que
    -- "sao paulo", "SÃO PAULO" e "São Paulo" casem com o nome acentuado armazenado em cities.
    WHERE unaccent(lower(c.name)) = unaccent(lower(p_city_name))
      AND country_city.code = 'BR'
      AND vap.codigo_pais_aeroporto = 'BR'
      AND vap.tipo_aeroporto IN ('medium_airport', 'large_airport')
      AND c.latitude IS NOT NULL
      AND c.longitude IS NOT NULL
      AND earth_distance(
            ll_to_earth(c.latitude, c.longitude),
            ll_to_earth(vap.latitude_aeroporto, vap.longitude_aeroporto)
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

DROP FUNCTION IF EXISTS app_admin_relatorio_3_escuderias_pilotos();

CREATE OR REPLACE FUNCTION app_admin_relatorio_3_escuderias_pilotos()
RETURNS TABLE (
    escuderia_nome TEXT,
    quantidade_pilotos INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.name::TEXT AS escuderia_nome,
        COUNT(DISTINCT vrc.driver_id)::INTEGER AS quantidade_pilotos
    FROM constructors c
    LEFT JOIN vw_resultados_corridas vrc
      ON vrc.constructor_id = c.id
    GROUP BY c.id, c.name
    ORDER BY quantidade_pilotos DESC, escuderia_nome;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_relatorio_3_escuderias_pilotos()
IS 'Relatorio Admin 3 Parte A: todas as escuderias e a quantidade de pilotos que correram por cada uma.';


DROP FUNCTION IF EXISTS app_admin_relatorio_3_hierarquico_corridas();

CREATE OR REPLACE FUNCTION app_admin_relatorio_3_hierarquico_corridas()
RETURNS TABLE (
    nivel INTEGER,
    descricao_nivel TEXT,
    circuito TEXT,
    ano INTEGER,
    rodada INTEGER,
    corrida TEXT,
    quantidade_corridas INTEGER,
    minimo_voltas INTEGER,
    media_voltas NUMERIC(10,2),
    maximo_voltas INTEGER,
    voltas_registradas INTEGER,
    quantidade_pilotos INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH corridas_base AS (
        SELECT
            vcr.race_id,
            vcr.ano,
            vcr.rodada,
            vcr.corrida,
            vcr.circuito_id,
            vcr.circuito,
            vcr.voltas_registradas,
            vcr.quantidade_pilotos
        FROM vw_corridas_resumo vcr
    ),
    linhas_hierarquicas AS (
        SELECT
            1 AS nivel,
            'Total geral de corridas'::TEXT AS descricao_nivel,
            NULL::TEXT AS circuito,
            NULL::INTEGER AS ano,
            NULL::INTEGER AS rodada,
            NULL::TEXT AS corrida,
            COUNT(*)::INTEGER AS quantidade_corridas,
            NULL::INTEGER AS minimo_voltas,
            NULL::NUMERIC(10,2) AS media_voltas,
            NULL::INTEGER AS maximo_voltas,
            NULL::INTEGER AS voltas_registradas,
            NULL::INTEGER AS quantidade_pilotos,
            0 AS ordem_circuito_id,
            0 AS ordem_ano,
            0 AS ordem_rodada
        FROM corridas_base

        UNION ALL

        SELECT
            2 AS nivel,
            'Resumo por circuito'::TEXT AS descricao_nivel,
            cb.circuito::TEXT AS circuito,
            NULL::INTEGER AS ano,
            NULL::INTEGER AS rodada,
            NULL::TEXT AS corrida,
            COUNT(*)::INTEGER AS quantidade_corridas,
            MIN(cb.voltas_registradas)::INTEGER AS minimo_voltas,
            AVG(cb.voltas_registradas)::NUMERIC(10,2) AS media_voltas,
            MAX(cb.voltas_registradas)::INTEGER AS maximo_voltas,
            NULL::INTEGER AS voltas_registradas,
            NULL::INTEGER AS quantidade_pilotos,
            cb.circuito_id AS ordem_circuito_id,
            0 AS ordem_ano,
            0 AS ordem_rodada
        FROM corridas_base cb
        GROUP BY cb.circuito_id, cb.circuito

        UNION ALL

        SELECT
            3 AS nivel,
            'Corrida do circuito'::TEXT AS descricao_nivel,
            cb.circuito::TEXT AS circuito,
            cb.ano::INTEGER AS ano,
            cb.rodada::INTEGER AS rodada,
            cb.corrida::TEXT AS corrida,
            NULL::INTEGER AS quantidade_corridas,
            NULL::INTEGER AS minimo_voltas,
            NULL::NUMERIC(10,2) AS media_voltas,
            NULL::INTEGER AS maximo_voltas,
            cb.voltas_registradas::INTEGER AS voltas_registradas,
            cb.quantidade_pilotos::INTEGER AS quantidade_pilotos,
            cb.circuito_id AS ordem_circuito_id,
            cb.ano AS ordem_ano,
            cb.rodada AS ordem_rodada
        FROM corridas_base cb
    )
    SELECT
        lh.nivel,
        lh.descricao_nivel,
        lh.circuito,
        lh.ano,
        lh.rodada,
        lh.corrida,
        lh.quantidade_corridas,
        lh.minimo_voltas,
        lh.media_voltas,
        lh.maximo_voltas,
        lh.voltas_registradas,
        lh.quantidade_pilotos
    FROM linhas_hierarquicas lh
    ORDER BY
        lh.ordem_circuito_id,
        lh.nivel,
        lh.ordem_ano,
        lh.ordem_rodada;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_relatorio_3_hierarquico_corridas()
IS 'Relatorio Admin 3 Parte B: relatorio hierarquico em tres niveis com total de corridas, resumo por circuito e detalhes por corrida.';





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
        (vrc.piloto_nome || ' ' || vrc.piloto_sobrenome)::TEXT AS nome_piloto,
        COUNT(CASE WHEN vrc.position_order = 1 THEN 1 END)::INTEGER AS quantidade_vitorias
    FROM constructors c
    LEFT JOIN vw_resultados_corridas vrc
      ON vrc.constructor_id = c.id
    WHERE c.id = escuderia_id
      AND vrc.driver_id IS NOT NULL
    GROUP BY c.id, c.name, vrc.driver_id, vrc.piloto_nome, vrc.piloto_sobrenome;
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
        vrc.status_corrida::TEXT AS status_corrida,
        COUNT(*)::INTEGER AS quantidade_corridas
    FROM constructors c
    LEFT JOIN vw_resultados_corridas vrc
      ON vrc.constructor_id = c.id
    WHERE c.id = escuderia_id
    GROUP BY c.name, vrc.status_corrida;
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

DROP FUNCTION IF EXISTS app_piloto_relatorio_6(INTEGER);

CREATE OR REPLACE FUNCTION app_piloto_relatorio_6(piloto_id INTEGER)
RETURNS TABLE (
    ano_participacao INTEGER,
    -- NUMERIC(10,2) e nao INTEGER: a F1 atribui meios-pontos (ex.: corridas encurtadas).
    quantidade_total_pontos NUMERIC(10,2),
    corridas_pontuadas TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        vrc.ano::INTEGER AS ano_participacao,
        SUM(vrc.points)::NUMERIC(10,2) AS quantidade_total_pontos,
        STRING_AGG(vrc.corrida, ', ' ORDER BY vrc.rodada)::TEXT AS corridas_pontuadas
    FROM vw_resultados_corridas vrc
    WHERE vrc.driver_id = piloto_id
      AND vrc.points > 0
    GROUP BY vrc.ano;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_piloto_relatorio_6(piloto_id INTEGER)
IS 'Relatorio Piloto 6: quantidade total de pontos por ano de participacao.';





/* ------------------------------------------------------------------------------------------------------------
   PILOTO - RELATORIO 7

   Entrada:
   - identificador do piloto logado.

   Objetivo:
   - listar a quantidade de resultados por status nas corridas em que o piloto participou;
   - apresentar o status e a contagem de cada um;
   - limitar os resultados ao escopo do piloto logado.
------------------------------------------------------------------------------------------------------------ */

DROP FUNCTION IF EXISTS app_piloto_relatorio_7(INTEGER);

CREATE OR REPLACE FUNCTION app_piloto_relatorio_7(piloto_id INTEGER)
RETURNS TABLE (
    status_corrida TEXT,
    quantidade_corridas INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        vrc.status_corrida::TEXT AS status_corrida,
        COUNT(*)::INTEGER AS quantidade_corridas
    FROM vw_resultados_corridas vrc
    WHERE vrc.driver_id = piloto_id
    GROUP BY vrc.status_corrida;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_piloto_relatorio_7(piloto_id INTEGER)
IS 'Relatorio Piloto 7: quantidade de resultados por status.';



COMMIT;
