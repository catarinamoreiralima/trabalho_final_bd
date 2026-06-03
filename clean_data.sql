BEGIN;

/* ============================================================================================================
   T1
   Base: schema.sql + carga.sql já executados
   SGBD: PostgreSQL

   OBJETIVO DESTA VERSÃO
   ---------------------
   Esta versão tenta ficar o mais próxima possível do conteúdo já trabalhado em aula,
   usando principalmente:
   - ALTER TABLE
   - CREATE TEMP TABLE
   - INSERT
   - UPDATE
   - SELECT
   - JOIN
   - GROUP BY
   - DELETE

   Ela faz 5 coisas:
   1) normaliza a nacionalidade de drivers e constructors;
   2) adiciona o atributo nationality em countries;
   3) deduplica cities de forma conservadora;
   4) corrige os vínculos em airports e circuits;
   5) gera tabelas e consultas de conferência para o relatório.

   OBSERVAÇÃO IMPORTANTE
   ---------------------
   O enunciado do T1 pede que inconsistências sejam tratadas e justificadas.
   Por isso, este script adota uma estratégia conservadora:
   - só faz automaticamente o que está bem justificado;
   - deixa os casos duvidosos em tabelas de conferência/revisão.
   ============================================================================================================ */

/* ============================================================================================================
   0. MÉTRICAS INICIAIS

   Guardamos a quantidade de linhas antes das correções para poder comparar no final.
   Aqui a tabela NÃO é temporária, porque ela pode ser útil depois da execução do script
   para gerar o relatório e revisar as métricas com calma.
   ============================================================================================================ */
DROP TABLE IF EXISTS t1_metrics_before;
CREATE TABLE t1_metrics_before AS
SELECT
    (SELECT COUNT(*) FROM countries)    AS countries_before,
    (SELECT COUNT(*) FROM drivers)      AS drivers_before,
    (SELECT COUNT(*) FROM constructors) AS constructors_before,
    (SELECT COUNT(*) FROM cities)       AS cities_before,
    (SELECT COUNT(*) FROM airports)     AS airports_before,
    (SELECT COUNT(*) FROM circuits)     AS circuits_before;

/* ============================================================================================================
   1. NORMALIZAÇÃO DE NACIONALIDADE

   REQUISITO DO ENUNCIADO
   ----------------------
   - substituir a nacionalidade textual de Pilotos e Construtores por referência a Países;
   - incluir o atributo nationality em Países.

   DECISÃO ADOTADA
   ---------------
   1) criar countries.nationality;
   2) criar drivers.country_id e constructors.country_id;
   3) descobrir as nacionalidades reais presentes na base;
   4) montar um mapa nationality_text -> country_code;
   5) preencher os vínculos;
   6) só depois remover as colunas textuais antigas.
   ============================================================================================================ */
ALTER TABLE countries
ADD COLUMN IF NOT EXISTS nationality VARCHAR(255);

ALTER TABLE drivers
ADD COLUMN IF NOT EXISTS country_id INTEGER;

ALTER TABLE constructors
ADD COLUMN IF NOT EXISTS country_id INTEGER;

/* Levantar as nacionalidades reais da base.
   Isso evita depender apenas de uma lista escrita manualmente. */
CREATE TEMP TABLE tmp_nationalities AS
SELECT DISTINCT LOWER(TRIM(nationality)) AS nationality_text
FROM (
    SELECT nationality FROM drivers
    UNION
    SELECT nationality FROM constructors
) x
WHERE nationality IS NOT NULL
  AND TRIM(nationality) <> '';

/* Tabela auxiliar principal: guarda a correspondência entre o texto da nacionalidade
   e o código ISO de 2 letras do país. */
CREATE TEMP TABLE tmp_nationality_map (
    nationality_text VARCHAR(255) PRIMARY KEY,
    country_code     VARCHAR(2) NOT NULL
);

/* ------------------------------------------------------------------------------------------------------------
   1.1. VARIAÇÕES DO TEXTO DA NACIONALIDADE

   Em alguns casos, o texto da nacionalidade não aparece completo em buscas textuais.
   Exemplo discutido: brazilian -> brazil.

   Regra adotada:
   - tentar o texto original;
   - tentar também versões com 1, 2, 3 e 4 caracteres removidos do final;
   - só manter a variação se o resultado continuar com pelo menos 4 caracteres.

   Essas variações são usadas apenas como apoio para busca textual e sugestão de mapeamento.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TEMP TABLE tmp_nationality_variants AS
SELECT nationality_text, nationality_text AS search_text, 0 AS removed_chars
FROM tmp_nationalities

UNION
SELECT nationality_text,
       SUBSTRING(nationality_text FROM 1 FOR CHAR_LENGTH(nationality_text) - 1) AS search_text,
       1 AS removed_chars
FROM tmp_nationalities
WHERE CHAR_LENGTH(nationality_text) - 1 >= 4

UNION
SELECT nationality_text,
       SUBSTRING(nationality_text FROM 1 FOR CHAR_LENGTH(nationality_text) - 2) AS search_text,
       2 AS removed_chars
FROM tmp_nationalities
WHERE CHAR_LENGTH(nationality_text) - 2 >= 4

UNION
SELECT nationality_text,
       SUBSTRING(nationality_text FROM 1 FOR CHAR_LENGTH(nationality_text) - 3) AS search_text,
       3 AS removed_chars
FROM tmp_nationalities
WHERE CHAR_LENGTH(nationality_text) - 3 >= 4

UNION
SELECT nationality_text,
       SUBSTRING(nationality_text FROM 1 FOR CHAR_LENGTH(nationality_text) - 4) AS search_text,
       4 AS removed_chars
FROM tmp_nationalities
WHERE CHAR_LENGTH(nationality_text) - 4 >= 4;

/* ------------------------------------------------------------------------------------------------------------
   1.2. CONFERÊNCIA AUXILIAR EM CITIES

   Esta etapa NÃO define o país final.
   Ela serve apenas para inspeção textual: verificar se o texto da nacionalidade aparece
   em algum nome de cidade, ascii_name ou alternate_names.

   Isso é útil para o relatório e para entender como as variações textuais aparecem na base.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TEMP TABLE tmp_nationality_found_in_cities AS
SELECT DISTINCT
    v.nationality_text,
    v.search_text,
    v.removed_chars,
    c.id   AS city_id,
    c.name AS city_name
FROM tmp_nationality_variants v
JOIN cities c
  ON LOWER(COALESCE(c.name, ''))            LIKE '%' || v.search_text || '%'
  OR LOWER(COALESCE(c.ascii_name, ''))      LIKE '%' || v.search_text || '%'
  OR LOWER(COALESCE(c.alternate_names, '')) LIKE '%' || v.search_text || '%';

/* ------------------------------------------------------------------------------------------------------------
   1.3. TENTATIVA AUTOMÁTICA DE MAPEAR NACIONALIDADE -> PAÍS

   Regras usadas:
   - igualdade com o nome do país;
   - prefixo do nome do país;
   - ocorrência em keywords do país.

   Como essas regras podem sugerir mais de um país, só aceitamos automaticamente os casos em que
   a nacionalidade aponta para UM único país.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TEMP TABLE tmp_nationality_country_candidates AS
SELECT DISTINCT
    v.nationality_text,
    c.code AS country_code,
    c.name AS country_name,
    v.search_text,
    v.removed_chars
FROM tmp_nationality_variants v
JOIN countries c
  ON LOWER(TRIM(c.name)) = v.search_text
  OR LOWER(TRIM(c.name)) LIKE v.search_text || '%'
  OR LOWER(COALESCE(c.keywords, '')) LIKE '%' || v.search_text || '%';

CREATE TEMP TABLE tmp_nationality_country_auto AS
SELECT nationality_text, MIN(country_code) AS country_code
FROM tmp_nationality_country_candidates
GROUP BY nationality_text
HAVING COUNT(DISTINCT country_code) = 1;

INSERT INTO tmp_nationality_map (nationality_text, country_code)
SELECT nationality_text, country_code
FROM tmp_nationality_country_auto;

/* ------------------------------------------------------------------------------------------------------------
   1.4. COMPLEMENTO MANUAL

   Aqui entram os gentílicos que normalmente não aparecem como nome do país,
   como british, french, swiss etc.

   Esta parte é necessária porque nem toda nacionalidade pode ser inferida com segurança
   apenas por busca textual.
   ------------------------------------------------------------------------------------------------------------ */
INSERT INTO tmp_nationality_map (nationality_text, country_code) VALUES
    ('american', 'US'),
    ('argentine', 'AR'),
    ('argentinian', 'AR'),
    ('australian', 'AU'),
    ('austrian', 'AT'),
    ('belgian', 'BE'),
    ('british', 'GB'),
    ('canadian', 'CA'),
    ('chilean', 'CL'),
    ('chinese', 'CN'),
    ('czech', 'CZ'),
    ('danish', 'DK'),
    ('dutch', 'NL'),
    ('east german', 'DE'),
    ('emirati', 'AE'),
    ('finnish', 'FI'),
    ('french', 'FR'),
    ('german', 'DE'),
    ('hungarian', 'HU'),
    ('indian', 'IN'),
    ('indonesian', 'ID'),
    ('irish', 'IE'),
    ('italian', 'IT'),
    ('japanese', 'JP'),
    ('liechtensteiner', 'LI'),
    ('malaysian', 'MY'),
    ('monegasque', 'MC'),
    ('new zealander', 'NZ'),
    ('polish', 'PL'),
    ('portuguese', 'PT'),
    ('rhodesian', 'ZW'),
    ('romanian', 'RO'),
    ('russian', 'RU'),
    ('south african', 'ZA'),
    ('spanish', 'ES'),
    ('swedish', 'SE'),
    ('swiss', 'CH'),
    ('thai', 'TH'),
    ('uruguayan', 'UY'),
    ('venezuelan', 'VE')
ON CONFLICT (nationality_text) DO NOTHING;

/* Conferência auxiliar: mostra quais nacionalidades da base ainda ficaram sem mapeamento.
   Idealmente, esta tabela deve ficar vazia antes do fechamento da normalização. */
CREATE TEMP TABLE tmp_nationality_not_mapped AS
SELECT n.nationality_text
FROM tmp_nationalities n
LEFT JOIN tmp_nationality_map m
       ON m.nationality_text = n.nationality_text
WHERE m.nationality_text IS NULL;

/* ------------------------------------------------------------------------------------------------------------
   1.5. DEFINIR UM GENTÍLICO CANÔNICO POR PAÍS

   Um mesmo país pode aparecer associado a mais de um texto de nacionalidade.
   Exemplos:
   - AR -> argentine / argentinian
   - DE -> german / east german / west german

   Para evitar que countries.nationality fique com um valor arbitrário, escolhemos uma forma
   canônica por país.

   Estratégia adotada:
   - primeiro escolher um valor por país usando MIN;
   - depois corrigir manualmente os casos em que queremos uma forma mais representativa.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TEMP TABLE tmp_country_nationality_canonical AS
SELECT
    country_code,
    MIN(nationality_text) AS nationality_text
FROM tmp_nationality_map
GROUP BY country_code;

/* Ajustes manuais dos casos com mais de uma forma possível. */
UPDATE tmp_country_nationality_canonical
SET nationality_text = 'german'
WHERE country_code = 'DE';

UPDATE tmp_country_nationality_canonical
SET nationality_text = 'argentine'
WHERE country_code = 'AR';

UPDATE tmp_country_nationality_canonical
SET nationality_text = 'new zealander'
WHERE country_code = 'NZ';

/* Preencher countries.nationality com a forma canônica escolhida. */
UPDATE countries c
SET nationality = INITCAP(t.nationality_text)
FROM tmp_country_nationality_canonical t
WHERE c.code = t.country_code;

/* ------------------------------------------------------------------------------------------------------------
   1.6. PREENCHER OS VÍNCULOS EM DRIVERS E CONSTRUCTORS
   ------------------------------------------------------------------------------------------------------------ */
UPDATE drivers d
SET country_id = c.id
FROM tmp_nationality_map m
JOIN countries c
  ON c.code = m.country_code
WHERE LOWER(TRIM(d.nationality)) = m.nationality_text;

UPDATE constructors ct
SET country_id = c.id
FROM tmp_nationality_map m
JOIN countries c
  ON c.code = m.country_code
WHERE LOWER(TRIM(ct.nationality)) = m.nationality_text;

/* Guardar as linhas que ainda não foram resolvidas.
   Essas tabelas ajudam a revisar casos problemáticos antes do fechamento. */
CREATE TEMP TABLE tmp_drivers_not_migrated AS
SELECT id, driver_ref, given_name, family_name, nationality
FROM drivers
WHERE country_id IS NULL;

CREATE TEMP TABLE tmp_constructors_not_migrated AS
SELECT id, constructor_ref, name, nationality
FROM constructors
WHERE country_id IS NULL;


/* ------------------------------------------------------------------------------------------------------------
   1.7. TABELA DE MÉTRICAS PARA VALIDAR A REFERENCIAÇÃO DE DRIVERS E CONSTRUCTORS PARA COUNTRIES

   OBJETIVO
   --------
   Esta tabela é mantida de forma permanente para apoiar a validação do processo de normalização.
   Ela guarda, para cada entidade (drivers/constructors) e para cada nacionalidade textual original:
   - quantos registros existiam;
   - para qual país eles foram referenciados;
   - qual o nome do país e o gentílico canônico armazenado em countries;
   - se ainda restou algum caso sem referência.

   Isso ajuda a responder, no relatório, se os registros foram associados ao país esperado.
   ------------------------------------------------------------------------------------------------------------ */
DROP TABLE IF EXISTS t1_nationality_reference_metrics;
CREATE TABLE t1_nationality_reference_metrics AS
SELECT
    'drivers' AS entity_type,
    LOWER(TRIM(d.nationality)) AS original_nationality,
    c.code AS country_code,
    c.name AS country_name,
    c.nationality AS country_nationality,
    COUNT(*) AS quantity,
    CASE
        WHEN c.id IS NULL THEN 'NAO_REFERENCIADO'
        ELSE 'REFERENCIADO'
    END AS reference_status
FROM drivers d
LEFT JOIN countries c
       ON c.id = d.country_id
GROUP BY
    LOWER(TRIM(d.nationality)),
    c.id,
    c.code,
    c.name,
    c.nationality

UNION ALL

SELECT
    'constructors' AS entity_type,
    LOWER(TRIM(ct.nationality)) AS original_nationality,
    c.code AS country_code,
    c.name AS country_name,
    c.nationality AS country_nationality,
    COUNT(*) AS quantity,
    CASE
        WHEN c.id IS NULL THEN 'NAO_REFERENCIADO'
        ELSE 'REFERENCIADO'
    END AS reference_status
FROM constructors ct
LEFT JOIN countries c
       ON c.id = ct.country_id
GROUP BY
    LOWER(TRIM(ct.nationality)),
    c.id,
    c.code,
    c.name,
    c.nationality;


/* Tabela resumo: quantos registros foram referenciados e quantos ficaram pendentes. */
DROP TABLE IF EXISTS t1_nationality_reference_summary;
CREATE TABLE t1_nationality_reference_summary AS
SELECT
    entity_type,
    SUM(quantity) AS total_rows,
    SUM(CASE WHEN reference_status = 'REFERENCIADO' THEN quantity ELSE 0 END) AS referenced_rows,
    SUM(CASE WHEN reference_status = 'NAO_REFERENCIADO' THEN quantity ELSE 0 END) AS not_referenced_rows,
    COUNT(DISTINCT original_nationality) AS distinct_nationalities,
    COUNT(DISTINCT country_code) AS distinct_countries_referenced
FROM t1_nationality_reference_metrics
GROUP BY entity_type;

/* ------------------------------------------------------------------------------------------------------------
   1.8. FECHAMENTO DA NORMALIZAÇÃO

   OBSERVAÇÃO DIDÁTICA
   -------------------
   O script segue em frente e tenta impor a integridade com FOREIGN KEY + NOT NULL.
   Se ainda existir alguma linha sem country_id, o PostgreSQL vai acusar erro no SET NOT NULL.
   Isso é bom aqui, porque impede concluir a migração com dados faltando.
   ------------------------------------------------------------------------------------------------------------ */
ALTER TABLE drivers
DROP CONSTRAINT IF EXISTS fk_drivers_country;

ALTER TABLE constructors
DROP CONSTRAINT IF EXISTS fk_constructors_country;

ALTER TABLE drivers
ADD CONSTRAINT fk_drivers_country
FOREIGN KEY (country_id) REFERENCES countries(id);

ALTER TABLE constructors
ADD CONSTRAINT fk_constructors_country
FOREIGN KEY (country_id) REFERENCES countries(id);

ALTER TABLE drivers
ALTER COLUMN country_id SET NOT NULL;

ALTER TABLE constructors
ALTER COLUMN country_id SET NOT NULL;

/* Depois de garantir que country_id está preenchido, podemos remover a coluna textual antiga. */
ALTER TABLE drivers
DROP COLUMN IF EXISTS nationality;

ALTER TABLE constructors
DROP COLUMN IF EXISTS nationality;

/* ============================================================================================================

   2. DEDUPLICAÇÃO DE CITIES

   REQUISITO DO ENUNCIADO
   ----------------------
   A deduplicação deve considerar nome, país e/ou proximidade geográfica, atualizar os vínculos
   nas tabelas dependentes e manter métricas do processo.

   NOVA ESTRATÉGIA ADOTADA
   -----------------------
   Nesta versão, a deduplicação foi ajustada com base no diagnóstico dos casos que ficaram para
   revisão manual.

   As decisões foram as seguintes:
   1) usar o país e o nome normalizado como filtro inicial;
   2) usar distância euclidiana aproximada em km sobre latitude/longitude;
   3) aumentar o raio automático de 1 km para 5 km;
   4) formar componentes de cidades próximas dentro de cada grupo;
   5) escolher a cidade canônica de cada componente pela "qualidade" do registro,
      e não mais apenas pelo menor id;
   6) preencher a cidade canônica com dados faltantes vindos das outras linhas do componente.

   OBSERVAÇÃO
   ----------
   A parte mais avançada desta seção é a montagem dos componentes conectados por proximidade.
   Ela foi mantida porque resolve um problema real identificado no diagnóstico:
   algumas cidades não estavam a <= raio da canônica antiga, mas estavam próximas de outras
   cidades do mesmo grupo.
   ============================================================================================================ */


/* ------------------------------------------------------------------------------------------------------------
   2.0. PARÂMETROS DA DEDUPLICAÇÃO

   Estes valores foram separados em uma tabela para evitar "números mágicos" soltos no script.
   Assim, cada decisão fica documentada e pode ser justificada no relatório.

   SIGNIFICADO DOS PARÂMETROS
   --------------------------
   km_per_degree
     Valor aproximado de quantos quilômetros existem em 1 grau de latitude.
     Foi usado o valor 111,32 km/grau, que é uma aproximação comum quando queremos converter
     diferenças angulares em uma distância aproximada sobre a superfície da Terra.

   merge_radius_km
     Raio principal da deduplicação automática.
     Nesta versão, foi adotado 10 km para absorver casos em que a mesma cidade aparece com
     coordenadas um pouco deslocadas entre fontes diferentes, mas sem abrir demais a regra.

   relaxed_suffix_radius_km
     Raio maior usado apenas em um caso especial:
     quando dois registros têm o mesmo nome "relaxado", mas um deles possui um sufixo genérico
     como "City". Exemplo: "6th of October" e "6th of October City".
     O valor 30 km foi escolhido para permitir esse ajuste específico sem transformar toda a
     deduplicação em algo permissivo demais.

   bbox_lat_margin_degrees e bbox_lon_margin_degrees
     Margens em graus usadas antes do cálculo da distância.
     Elas funcionam como um filtro barato: se duas cidades já estão muito longe em latitude
     ou longitude, não vale a pena calcular a distância completa entre elas.
     O valor 0,30 grau equivale a algo da ordem de dezenas de quilômetros, portanto é maior do
     que os raios de merge usados aqui e serve apenas para reduzir comparações desnecessárias.

   min_filled_attribute_difference
     Diferença mínima na quantidade de atributos preenchidos para ativar a regra especial dos
     sufixos genéricos. O valor 2 foi adotado para exigir que um registro seja claramente mais
     completo do que o outro, evitando merges precipitados.
   ------------------------------------------------------------------------------------------------------------ */
DROP TABLE IF EXISTS t1_dedup_parameters;
CREATE TABLE t1_dedup_parameters AS
SELECT
    'euclidean_approx_km'::VARCHAR(50) AS distance_method,
    111.32::NUMERIC(10,3)              AS km_per_degree,
    10.0::NUMERIC(10,3)                AS merge_radius_km,
    30.0::NUMERIC(10,3)                AS relaxed_suffix_radius_km,
    0.30::NUMERIC(10,3)                AS bbox_lat_margin_degrees,
    0.30::NUMERIC(10,3)                AS bbox_lon_margin_degrees,
    2::INTEGER                         AS min_filled_attribute_difference,
    'Mesmo país + nome relaxado + distância euclidiana aproximada. Há uma regra especial para nomes com sufixo genérico, como "City".'::VARCHAR(255) AS rule_summary;

/* ------------------------------------------------------------------------------------------------------------
   2.1. LIMPEZA DAS TABELAS PERMANENTES DE APOIO DA DEDUPLICAÇÃO

   Todas essas tabelas são recriadas para que o script possa ser executado novamente sem depender
   de uma execução anterior.
   ------------------------------------------------------------------------------------------------------------ */
DROP TABLE IF EXISTS t1_city_suffix_rule_validation;
DROP TABLE IF EXISTS t1_city_manual_review;
DROP TABLE IF EXISTS t1_city_group_validation;
DROP TABLE IF EXISTS t1_city_canonical_pairs;
DROP TABLE IF EXISTS t1_city_merge_values;
DROP TABLE IF EXISTS t1_city_merge_map;
DROP TABLE IF EXISTS t1_city_canonical;
DROP TABLE IF EXISTS t1_city_quality;
DROP TABLE IF EXISTS t1_city_component_stats;
DROP TABLE IF EXISTS t1_city_component_map;
DROP TABLE IF EXISTS t1_city_candidate_pairs;
DROP TABLE IF EXISTS t1_city_groups;
DROP TABLE IF EXISTS t1_cities_base;
DROP TABLE IF EXISTS t1_link_metrics;

/* ------------------------------------------------------------------------------------------------------------
   2.2. BASE AUXILIAR DAS CIDADES

   Nesta tabela guardamos informações úteis para a deduplicação:
   - o nome original;
   - uma versão "estrita" do nome normalizado;
   - uma versão "relaxada" do nome normalizado;
   - quantidades de vínculos com aeroportos e circuitos;
   - quantidade de atributos preenchidos.

   NOME ESTRITO
   ------------
   O nome estrito:
   - usa ascii_name quando existir; caso contrário, usa name;
   - remove acentos;
   - remove pontuação;
   - converte tudo para minúsculas.

   NOME RELAXADO
   -------------
   O nome relaxado faz tudo o que o nome estrito faz e, além disso, remove do final palavras
   muito genéricas, como:
   - city
   - town
   - village
   - district
   - municipality

   Isso foi incluído para tratar casos como:
   - "6th of October"
   - "6th of October City"

   A remoção é feita apenas no final do texto, para não descaracterizar nomes em que essas palavras
   façam parte do nome principal.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_cities_base AS
SELECT
    c.id,
    c.country_id,
    c.name,
    c.ascii_name,
    c.alternate_names,
    c.latitude,
    c.longitude,
    c.feature_code_id,
    c.time_zone_id,
    c.population,
    c.elevation,
    c.dem,
    c.modification_date,

    TRIM(
        REGEXP_REPLACE(
            LOWER(
                TRANSLATE(
                    TRIM(COALESCE(NULLIF(c.ascii_name, ''), c.name)),
                    'áàâãäåéèêëíìîïóòôõöúùûüçñýÿÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑÝ',
                    'aaaaaaeeeeiiiiooooouuuucnyyAAAAAAEEEEIIIIOOOOOUUUUCNY'
                )
            ),
            '[^a-z0-9]+',
            ' ',
            'g'
        )
    ) AS normalized_name_strict,

    TRIM(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                LOWER(
                    TRANSLATE(
                        TRIM(COALESCE(NULLIF(c.ascii_name, ''), c.name)),
                        'áàâãäåéèêëíìîïóòôõöúùûüçñýÿÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑÝ',
                        'aaaaaaeeeeiiiiooooouuuucnyyAAAAAAEEEEIIIIOOOOOUUUUCNY'
                    )
                ),
                '[^a-z0-9]+',
                ' ',
                'g'
            ),
            '\m(city|town|village|district|municipality)\M\s*$',
            '',
            'i'
        )
    ) AS normalized_name_relaxed,

    (SELECT COUNT(*) FROM airports a WHERE a.city_id = c.id) AS airports_count,
    (SELECT COUNT(*) FROM circuits cr WHERE cr.city_id = c.id) AS circuits_count,

    (
        CASE WHEN c.name IS NOT NULL AND TRIM(c.name) <> '' THEN 1 ELSE 0 END +
        CASE WHEN c.ascii_name IS NOT NULL AND TRIM(c.ascii_name) <> '' THEN 1 ELSE 0 END +
        CASE WHEN c.alternate_names IS NOT NULL AND TRIM(c.alternate_names) <> '' THEN 1 ELSE 0 END +
        CASE WHEN c.latitude IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.longitude IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.feature_code_id IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.time_zone_id IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.population IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.elevation IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.dem IS NOT NULL THEN 1 ELSE 0 END +
        CASE WHEN c.modification_date IS NOT NULL THEN 1 ELSE 0 END
    ) AS filled_attribute_count
FROM cities c
WHERE COALESCE(NULLIF(c.ascii_name, ''), c.name) IS NOT NULL;

/* ------------------------------------------------------------------------------------------------------------
   2.3. GRUPOS DE POSSÍVEIS DUPLICATAS

   O agrupamento inicial é feito por:
   - país
   - nome relaxado

   Isso permite que nomes como "6th of October" e "6th of October City" sejam colocados no
   mesmo grupo candidato.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_groups AS
SELECT
    country_id,
    normalized_name_relaxed AS normalized_name,
    COUNT(*) AS quantity
FROM t1_cities_base
WHERE normalized_name_relaxed IS NOT NULL
  AND normalized_name_relaxed <> ''
GROUP BY country_id, normalized_name_relaxed
HAVING COUNT(*) > 1;

/* ------------------------------------------------------------------------------------------------------------
   2.4. PARES CANDIDATOS AO MERGE AUTOMÁTICO

   Regras usadas:
   1) mesmo país;
   2) mesmo nome relaxado;
   3) coordenadas presentes nas duas linhas.

   Depois disso, há dois cenários.

   CENÁRIO A - REGRA PADRÃO
   ------------------------
   Se a distância euclidiana aproximada for menor ou igual ao raio principal de merge
   (merge_radius_km), o par entra como candidato normal.

   CENÁRIO B - REGRA ESPECIAL PARA SUFIXOS GENÉRICOS
   -------------------------------------------------
   Se os nomes estritos diferem dos nomes relaxados, significa que há algo como "City",
   "Town" etc. no final do texto.
   Nessa situação, o par também pode entrar como candidato, desde que:
   - a diferença na quantidade de atributos preenchidos seja pelo menos a mínima definida;
   - a distância fique dentro do raio maior relaxed_suffix_radius_km.

   A distância utilizada é a distância euclidiana aproximada em quilômetros:
     dist_km = sqrt( ((lat1-lat2)*km_per_degree)^2 +
                     ((lon1-lon2)*km_per_degree*cos(latitude_media))^2 )

   Essa aproximação é suficiente aqui porque estamos tratando raios relativamente pequenos
   e queremos uma conta simples, próxima do conteúdo já visto em aula.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_candidate_pairs AS
SELECT DISTINCT
    b1.country_id,
    g.normalized_name,
    b1.id AS city_id_1,
    b2.id AS city_id_2,
    ROUND(
        SQRT(
            POWER((b2.latitude - b1.latitude) * p.km_per_degree, 2) +
            POWER((b2.longitude - b1.longitude) * p.km_per_degree * COS(RADIANS((b1.latitude + b2.latitude) / 2.0)), 2)
        )::NUMERIC,
        3
    ) AS distance_km,
    CASE
        WHEN SQRT(
                 POWER((b2.latitude - b1.latitude) * p.km_per_degree, 2) +
                 POWER((b2.longitude - b1.longitude) * p.km_per_degree * COS(RADIANS((b1.latitude + b2.latitude) / 2.0)), 2)
             ) <= p.merge_radius_km
        THEN 'REGRA_PADRAO'
        ELSE 'REGRA_ESPECIAL_SUFIXO'
    END AS pair_rule
FROM t1_city_groups g
JOIN t1_cities_base b1
  ON b1.country_id = g.country_id
 AND b1.normalized_name_relaxed = g.normalized_name
JOIN t1_cities_base b2
  ON b2.country_id = g.country_id
 AND b2.normalized_name_relaxed = g.normalized_name
 AND b1.id < b2.id
CROSS JOIN t1_dedup_parameters p
WHERE b1.latitude IS NOT NULL
  AND b1.longitude IS NOT NULL
  AND b2.latitude IS NOT NULL
  AND b2.longitude IS NOT NULL
  AND ABS(b2.latitude - b1.latitude) <= p.bbox_lat_margin_degrees
  AND ABS(b2.longitude - b1.longitude) <= p.bbox_lon_margin_degrees
  AND (
        SQRT(
            POWER((b2.latitude - b1.latitude) * p.km_per_degree, 2) +
            POWER((b2.longitude - b1.longitude) * p.km_per_degree * COS(RADIANS((b1.latitude + b2.latitude) / 2.0)), 2)
        ) <= p.merge_radius_km

        OR

        (
            (
                b1.normalized_name_strict <> b1.normalized_name_relaxed
                OR
                b2.normalized_name_strict <> b2.normalized_name_relaxed
            )
            AND ABS(b1.filled_attribute_count - b2.filled_attribute_count) >= p.min_filled_attribute_difference
            AND SQRT(
                    POWER((b2.latitude - b1.latitude) * p.km_per_degree, 2) +
                    POWER((b2.longitude - b1.longitude) * p.km_per_degree * COS(RADIANS((b1.latitude + b2.latitude) / 2.0)), 2)
                ) <= p.relaxed_suffix_radius_km
        )
      );

/* ------------------------------------------------------------------------------------------------------------
   2.5. VALIDAÇÃO ESPECÍFICA DA REGRA DE SUFIXO

   Esta tabela foi criada para facilitar a explicação de casos como:
   - "6th of October"
   - "6th of October City"

   Ela mostra:
   - os dois nomes originais;
   - os nomes estritos e relaxados;
   - quantos atributos cada lado possui;
   - a distância entre eles;
   - por qual regra o par entrou como candidato.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_suffix_rule_validation AS
SELECT
    co.name AS country_name,
    p.normalized_name,
    p.city_id_1,
    c1.name AS city_name_1,
    c1.ascii_name AS city_ascii_name_1,
    b1.normalized_name_strict AS strict_name_1,
    b1.normalized_name_relaxed AS relaxed_name_1,
    b1.filled_attribute_count AS filled_attributes_1,
    p.city_id_2,
    c2.name AS city_name_2,
    c2.ascii_name AS city_ascii_name_2,
    b2.normalized_name_strict AS strict_name_2,
    b2.normalized_name_relaxed AS relaxed_name_2,
    b2.filled_attribute_count AS filled_attributes_2,
    p.distance_km,
    p.pair_rule
FROM t1_city_candidate_pairs p
JOIN countries co
  ON co.id = p.country_id
JOIN cities c1
  ON c1.id = p.city_id_1
JOIN cities c2
  ON c2.id = p.city_id_2
JOIN t1_cities_base b1
  ON b1.id = p.city_id_1
JOIN t1_cities_base b2
  ON b2.id = p.city_id_2
WHERE b1.normalized_name_strict <> b1.normalized_name_relaxed
   OR b2.normalized_name_strict <> b2.normalized_name_relaxed
ORDER BY co.name, p.normalized_name, p.distance_km, p.city_id_1, p.city_id_2;

/* ------------------------------------------------------------------------------------------------------------
   2.6. COMPONENTES CONECTADOS

   Cada par próximo funciona como uma ligação entre duas cidades.
   Se:
   - A está perto de B
   - B está perto de C

   então A, B e C ficam no mesmo componente, mesmo que A e C não estejam diretamente dentro
   do raio. Essa parte resolve uma limitação importante da estratégia antiga.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_component_map AS
WITH RECURSIVE
edges AS (
    SELECT country_id, normalized_name, city_id_1 AS src, city_id_2 AS dst
    FROM t1_city_candidate_pairs
    UNION ALL
    SELECT country_id, normalized_name, city_id_2 AS src, city_id_1 AS dst
    FROM t1_city_candidate_pairs
),
nodes AS (
    SELECT
        g.country_id,
        g.normalized_name,
        b.id AS city_id
    FROM t1_city_groups g
    JOIN t1_cities_base b
      ON b.country_id = g.country_id
     AND b.normalized_name_relaxed = g.normalized_name
),
walk AS (
    SELECT
        n.country_id,
        n.normalized_name,
        n.city_id AS origin_city_id,
        n.city_id AS reachable_city_id
    FROM nodes n
    UNION
    SELECT
        w.country_id,
        w.normalized_name,
        w.origin_city_id,
        e.dst AS reachable_city_id
    FROM walk w
    JOIN edges e
      ON e.country_id = w.country_id
     AND e.normalized_name = w.normalized_name
     AND e.src = w.reachable_city_id
),
components AS (
    SELECT
        country_id,
        normalized_name,
        origin_city_id AS city_id,
        MIN(reachable_city_id) AS component_id
    FROM walk
    GROUP BY country_id, normalized_name, origin_city_id
)
SELECT *
FROM components;

/* ------------------------------------------------------------------------------------------------------------
   2.7. TAMANHO DOS COMPONENTES
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_component_stats AS
SELECT
    country_id,
    normalized_name,
    component_id,
    COUNT(*) AS component_size
FROM t1_city_component_map
GROUP BY country_id, normalized_name, component_id;

/* ------------------------------------------------------------------------------------------------------------
   2.8. QUALIDADE DOS REGISTROS

   A escolha da cidade canônica em cada componente segue este critério de desempate:
   1) mais circuitos vinculados;
   2) mais aeroportos vinculados;
   3) mais atributos preenchidos;
   4) maior população;
   5) menor id.

   A ideia é manter como principal a linha que parece mais útil para o restante da base.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_quality AS
SELECT
    cm.country_id,
    cm.normalized_name,
    cm.component_id,
    b.id AS city_id,
    b.filled_attribute_count,
    b.circuits_count,
    b.airports_count,
    COALESCE(b.population, -1) AS population_score
FROM t1_city_component_map cm
JOIN t1_cities_base b
  ON b.id = cm.city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.9. ESCOLHA DA CIDADE CANÔNICA DE CADA COMPONENTE
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_canonical AS
SELECT
    d.country_id,
    d.normalized_name,
    d.component_id,
    (
        SELECT q.city_id
        FROM t1_city_quality q
        WHERE q.country_id = d.country_id
          AND q.normalized_name = d.normalized_name
          AND q.component_id = d.component_id
        ORDER BY
            q.circuits_count DESC,
            q.airports_count DESC,
            q.filled_attribute_count DESC,
            q.population_score DESC,
            q.city_id ASC
        LIMIT 1
    ) AS canonical_city_id
FROM (
    SELECT DISTINCT country_id, normalized_name, component_id
    FROM t1_city_component_map
) d;

/* ------------------------------------------------------------------------------------------------------------
   2.10. DISTÂNCIAS ENTRE AS CANÔNICAS QUE CONTINUARAM SEPARADAS

   Depois do merge automático, um mesmo grupo textual pode ainda ficar dividido em vários
   componentes. Esta tabela ajuda a medir quão perto ou longe ficaram essas canônicas.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_canonical_pairs AS
SELECT
    c1.country_id,
    c1.normalized_name,
    c1.component_id AS component_id_1,
    c1.canonical_city_id AS city_id_1,
    c2.component_id AS component_id_2,
    c2.canonical_city_id AS city_id_2,
    ROUND(
        SQRT(
            POWER((b2.latitude - b1.latitude) * p.km_per_degree, 2) +
            POWER((b2.longitude - b1.longitude) * p.km_per_degree * COS(RADIANS((b1.latitude + b2.latitude) / 2.0)), 2)
        )::NUMERIC,
        3
    ) AS distance_km
FROM t1_city_canonical c1
JOIN t1_city_canonical c2
  ON c1.country_id = c2.country_id
 AND c1.normalized_name = c2.normalized_name
 AND c1.component_id < c2.component_id
JOIN t1_cities_base b1
  ON b1.id = c1.canonical_city_id
JOIN t1_cities_base b2
  ON b2.id = c2.canonical_city_id
CROSS JOIN t1_dedup_parameters p
WHERE b1.latitude IS NOT NULL
  AND b1.longitude IS NOT NULL
  AND b2.latitude IS NOT NULL
  AND b2.longitude IS NOT NULL;

/* ------------------------------------------------------------------------------------------------------------
   2.11. MAPEAMENTO DE MERGE

   Apenas as cidades que:
   - não são canônicas;
   - pertencem a componentes com mais de um elemento
   entram no merge automático.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_merge_map AS
SELECT
    cm.country_id,
    cm.normalized_name,
    cm.component_id,
    cm.city_id AS old_city_id,
    cc.canonical_city_id,
    ROUND(
        SQRT(
            POWER((b_old.latitude - b_can.latitude) * p.km_per_degree, 2) +
            POWER((b_old.longitude - b_can.longitude) * p.km_per_degree * COS(RADIANS((b_old.latitude + b_can.latitude) / 2.0)), 2)
        )::NUMERIC,
        3
    ) AS distance_km_to_canonical
FROM t1_city_component_map cm
JOIN t1_city_component_stats cs
  ON cs.country_id = cm.country_id
 AND cs.normalized_name = cm.normalized_name
 AND cs.component_id = cm.component_id
JOIN t1_city_canonical cc
  ON cc.country_id = cm.country_id
 AND cc.normalized_name = cm.normalized_name
 AND cc.component_id = cm.component_id
JOIN t1_cities_base b_old
  ON b_old.id = cm.city_id
JOIN t1_cities_base b_can
  ON b_can.id = cc.canonical_city_id
CROSS JOIN t1_dedup_parameters p
WHERE cs.component_size > 1
  AND cm.city_id <> cc.canonical_city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.12. VALORES A SEREM APROVEITADOS DAS LINHAS DUPLICADAS

   O usuário pediu a seguinte regra de merge:
   - manter a cidade mais completa;
   - preencher nela apenas o que estiver faltando com dados das outras linhas.

   Por isso, agregamos aqui apenas os valores que podem servir como complemento.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_merge_values AS
SELECT
    m.canonical_city_id,
    MAX(CASE WHEN c.name IS NOT NULL AND TRIM(c.name) <> '' THEN c.name END) AS name,
    MAX(CASE WHEN c.ascii_name IS NOT NULL AND TRIM(c.ascii_name) <> '' THEN c.ascii_name END) AS ascii_name,
    MAX(CASE WHEN c.alternate_names IS NOT NULL AND TRIM(c.alternate_names) <> '' THEN c.alternate_names END) AS alternate_names,
    MAX(c.latitude)          AS latitude,
    MAX(c.longitude)         AS longitude,
    MAX(c.feature_code_id)   AS feature_code_id,
    MAX(c.time_zone_id)      AS time_zone_id,
    MAX(c.population)        AS population,
    MAX(c.elevation)         AS elevation,
    MAX(c.dem)               AS dem,
    MAX(c.modification_date) AS modification_date
FROM t1_city_merge_map m
JOIN cities c
  ON c.id = m.old_city_id
GROUP BY m.canonical_city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.13. ATUALIZAÇÃO DA CIDADE CANÔNICA

   Cada atributo da cidade canônica só é preenchido quando ainda está nulo.
   Assim, evitamos substituir indevidamente o registro que foi escolhido como principal.
   ------------------------------------------------------------------------------------------------------------ */
UPDATE cities c
SET name              = COALESCE(c.name, v.name),
    ascii_name        = COALESCE(c.ascii_name, v.ascii_name),
    alternate_names   = COALESCE(c.alternate_names, v.alternate_names),
    latitude          = COALESCE(c.latitude, v.latitude),
    longitude         = COALESCE(c.longitude, v.longitude),
    feature_code_id   = COALESCE(c.feature_code_id, v.feature_code_id),
    time_zone_id      = COALESCE(c.time_zone_id, v.time_zone_id),
    population        = COALESCE(c.population, v.population),
    elevation         = COALESCE(c.elevation, v.elevation),
    dem               = COALESCE(c.dem, v.dem),
    modification_date = COALESCE(c.modification_date, v.modification_date)
FROM t1_city_merge_values v
WHERE c.id = v.canonical_city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.14. MÉTRICAS DE RELIGAÇÃO ANTES DAS TABELAS FILHAS

   Essas métricas ajudam a responder:
   - quantas linhas de cities foram removidas por merge;
   - quantos aeroportos precisaram ser religados;
   - quantos circuitos precisaram ser religados.
   ------------------------------------------------------------------------------------------------------------ */
DROP TABLE IF EXISTS t1_link_metrics;
CREATE TABLE t1_link_metrics AS
SELECT
    (SELECT COUNT(*) FROM t1_city_merge_map) AS duplicate_city_rows_to_remove,
    (SELECT COUNT(*) FROM airports a JOIN t1_city_merge_map m ON a.city_id = m.old_city_id) AS airports_to_relink,
    (SELECT COUNT(*) FROM circuits c JOIN t1_city_merge_map m ON c.city_id = m.old_city_id) AS circuits_to_relink;

/* ------------------------------------------------------------------------------------------------------------
   2.15. CORREÇÃO DOS VÍNCULOS NAS TABELAS DEPENDENTES
   ------------------------------------------------------------------------------------------------------------ */
UPDATE airports a
SET city_id = m.canonical_city_id
FROM t1_city_merge_map m
WHERE a.city_id = m.old_city_id;

UPDATE circuits c
SET city_id = m.canonical_city_id
FROM t1_city_merge_map m
WHERE c.city_id = m.old_city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.16. REMOÇÃO DAS LINHAS DUPLICADAS QUE FORAM FUNDIDAS
   ------------------------------------------------------------------------------------------------------------ */
DELETE FROM cities c
USING t1_city_merge_map m
WHERE c.id = m.old_city_id;

/* ------------------------------------------------------------------------------------------------------------
   2.17. VALIDAÇÃO DOS GRUPOS DE DEDUPLICAÇÃO

   Para cada grupo textual, esta tabela registra:
   - quantas linhas havia antes;
   - quantos pares entraram na regra automática;
   - quantos componentes restaram;
   - quantas linhas foram realmente fundidas;
   - qual a menor e a maior distância entre pares candidatos;
   - qual a menor distância entre canônicas que continuaram separadas.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_group_validation AS
SELECT
    co.name AS country_name,
    g.country_id,
    g.normalized_name,
    g.quantity AS rows_in_group_before,
    COALESCE(pairs.pair_count, 0) AS candidate_pairs_within_radius,
    COALESCE(comp.component_count, 0) AS component_count,
    COALESCE(m.merged_rows, 0) AS merged_rows,
    g.quantity - COALESCE(m.merged_rows, 0) AS rows_remaining_after_merge,
    pairs.min_distance_km,
    pairs.max_distance_km,
    cp.nearest_remaining_component_distance_km
FROM t1_city_groups g
JOIN countries co
  ON co.id = g.country_id
LEFT JOIN (
    SELECT
        country_id,
        normalized_name,
        COUNT(*) AS pair_count,
        MIN(distance_km) AS min_distance_km,
        MAX(distance_km) AS max_distance_km
    FROM t1_city_candidate_pairs
    GROUP BY country_id, normalized_name
) pairs
  ON pairs.country_id = g.country_id
 AND pairs.normalized_name = g.normalized_name
LEFT JOIN (
    SELECT
        country_id,
        normalized_name,
        COUNT(*) AS component_count
    FROM t1_city_component_stats
    GROUP BY country_id, normalized_name
) comp
  ON comp.country_id = g.country_id
 AND comp.normalized_name = g.normalized_name
LEFT JOIN (
    SELECT
        country_id,
        normalized_name,
        COUNT(*) AS merged_rows
    FROM t1_city_merge_map
    GROUP BY country_id, normalized_name
) m
  ON m.country_id = g.country_id
 AND m.normalized_name = g.normalized_name
LEFT JOIN (
    SELECT
        country_id,
        normalized_name,
        MIN(distance_km) AS nearest_remaining_component_distance_km
    FROM t1_city_canonical_pairs
    GROUP BY country_id, normalized_name
) cp
  ON cp.country_id = g.country_id
 AND cp.normalized_name = g.normalized_name;

/* ------------------------------------------------------------------------------------------------------------
   2.18. TABELA DE REVISÃO MANUAL

   Aqui ficam os grupos que, mesmo após o merge automático, continuaram com mais de um componente.
   Em vez de mostrar todas as linhas do grupo, mostramos a canônica de cada componente remanescente,
   para facilitar a revisão humana.

   A coluna review_reason resume a situação do grupo.
   ------------------------------------------------------------------------------------------------------------ */
CREATE TABLE t1_city_manual_review AS
SELECT
    gv.country_name,
    cc.country_id,
    gv.normalized_name,
    cc.component_id,
    cs.component_size,
    gv.component_count,
    cc.canonical_city_id AS city_id,
    c.name AS city_name,
    c.name AS canonical_city_name,
    b.latitude,
    b.longitude,
    b.population,
    b.airports_count,
    b.circuits_count,
    COALESCE(cp.nearest_component_distance_km, NULL) AS nearest_other_component_distance_km,
    COALESCE(cp.nearest_component_distance_km, NULL) AS distance_km_to_canonical,
    CASE
        WHEN gv.candidate_pairs_within_radius = 0 THEN 'NAO_HA_PARES_DENTRO_DO_RAIO'
        WHEN cs.component_size = 1 AND gv.component_count > 1 THEN 'COMPONENTE_ISOLADO'
        WHEN cs.component_size > 1 AND gv.component_count > 1 THEN 'GRUPO_COM_VARIOS_COMPONENTES'
        ELSE 'REVISAR'
    END AS review_reason
FROM t1_city_group_validation gv
JOIN t1_city_canonical cc
  ON cc.country_id = gv.country_id
 AND cc.normalized_name = gv.normalized_name
JOIN t1_city_component_stats cs
  ON cs.country_id = cc.country_id
 AND cs.normalized_name = cc.normalized_name
 AND cs.component_id = cc.component_id
JOIN cities c
  ON c.id = cc.canonical_city_id
JOIN t1_cities_base b
  ON b.id = cc.canonical_city_id
LEFT JOIN (
    SELECT
        country_id,
        normalized_name,
        component_id,
        MIN(nearest_component_distance_km) AS nearest_component_distance_km
    FROM (
        SELECT
            country_id,
            normalized_name,
            component_id_1 AS component_id,
            distance_km AS nearest_component_distance_km
        FROM t1_city_canonical_pairs
        UNION ALL
        SELECT
            country_id,
            normalized_name,
            component_id_2 AS component_id,
            distance_km AS nearest_component_distance_km
        FROM t1_city_canonical_pairs
    ) x
    GROUP BY country_id, normalized_name, component_id
) cp
  ON cp.country_id = cc.country_id
 AND cp.normalized_name = cc.normalized_name
 AND cp.component_id = cc.component_id
WHERE gv.component_count > 1;
/* ============================================================================================================
   3. MÉTRICAS FINAIS

   Assim como a tabela inicial de métricas, esta tabela também fica criada
   de forma permanente para consulta posterior no relatório.
   ============================================================================================================ */
DROP TABLE IF EXISTS t1_metrics_after;
CREATE TABLE t1_metrics_after AS
SELECT
    (SELECT COUNT(*) FROM countries)    AS countries_after,
    (SELECT COUNT(*) FROM drivers)      AS drivers_after,
    (SELECT COUNT(*) FROM constructors) AS constructors_after,
    (SELECT COUNT(*) FROM cities)       AS cities_after,
    (SELECT COUNT(*) FROM airports)     AS airports_after,
    (SELECT COUNT(*) FROM circuits)     AS circuits_after;

COMMIT;

/* ============================================================================================================
   4. SAÍDAS DE CONFERÊNCIA

   Como o script será executado com o psql, os comandos de validação com tabelas temporárias
   ficam comentados no final. Assim, o script faz a transformação principal sem imprimir tudo
   automaticamente na execução. Quando desejar conferir algum ponto, basta descomentar apenas
   os trechos necessários.
   ============================================================================================================ */

/* ------------------------------------------------------------------------------------------------------------
   4.1. CONSULTAS DE MÉTRICAS (TABELAS PERMANENTES)

   Estas consultas usam apenas as tabelas de métricas permanentes criadas pelo script.
   Elas podem permanecer ativas porque normalmente geram pouca saída e são úteis para o relatório.
   ------------------------------------------------------------------------------------------------------------ */
SELECT
    b.countries_before,
    a.countries_after,
    b.drivers_before,
    a.drivers_after,
    b.constructors_before,
    a.constructors_after,
    b.cities_before,
    a.cities_after,
    l.duplicate_city_rows_to_remove,
    l.airports_to_relink,
    l.circuits_to_relink
FROM t1_metrics_before b,
     t1_metrics_after a,
     t1_link_metrics l;

/* ------------------------------------------------------------------------------------------------------------
   4.2. CONSULTAS DE VALIDAÇÃO COM TABELAS TEMPORÁRIAS

   Deixe comentado ao rodar pelo psql.
   Descomente apenas as consultas que quiser inspecionar manualmente.
   ------------------------------------------------------------------------------------------------------------ */

-- /* Linhas que eventualmente ainda não migraram para country_id.
--    Idealmente, ambas as consultas devem retornar 0 linhas. */
-- SELECT *
-- FROM tmp_drivers_not_migrated
-- ORDER BY family_name, given_name;

-- SELECT *
-- FROM tmp_constructors_not_migrated
-- ORDER BY name;

-- /* Nacionalidades encontradas na base. */
-- SELECT *
-- FROM tmp_nationalities
-- ORDER BY nationality_text;

-- /* Resumo: indica se cada nacionalidade apareceu ou não em alguma linha de cities.
--    Isso é apenas conferência textual auxiliar. */
-- SELECT
--     n.nationality_text,
--     CASE
--         WHEN EXISTS (
--             SELECT 1
--             FROM tmp_nationality_found_in_cities f
--             WHERE f.nationality_text = n.nationality_text
--         ) THEN 'SIM'
--         ELSE 'NAO'
--     END AS found_in_cities
-- FROM tmp_nationalities n
-- ORDER BY n.nationality_text;

-- /* Em quais cidades apareceu algum texto compatível com a nacionalidade. */
-- SELECT *
-- FROM tmp_nationality_found_in_cities
-- ORDER BY nationality_text, removed_chars, city_name;

-- /* Nacionalidades resolvidas automaticamente para um único país. */
-- SELECT *
-- FROM tmp_nationality_country_auto
-- ORDER BY nationality_text;

-- /* Nacionalidades que ainda exigem tratamento manual. */
-- SELECT *
-- FROM tmp_nationality_not_mapped
-- ORDER BY nationality_text;

/* Tabela permanente de métricas da referenciação de nacionalidade para país. */
SELECT *
FROM t1_nationality_reference_summary
ORDER BY entity_type;

-- SELECT *
-- FROM t1_nationality_reference_metrics
-- ORDER BY entity_type, original_nationality, country_code;

-- /* Gentílico canônico escolhido para cada país usado na normalização. */
-- SELECT *
-- FROM tmp_country_nationality_canonical
-- ORDER BY country_code;

-- /* Parâmetros permanentes adotados para a deduplicação. */
-- SELECT *
-- FROM t1_dedup_parameters;

-- /* Visão resumida da validação dos grupos de cidades duplicadas. */
-- SELECT *
-- FROM t1_city_group_validation
-- ORDER BY rows_in_group_before DESC, country_name, normalized_name;

-- /* Pares candidatos que entraram no raio automático. */
-- SELECT *
-- FROM t1_city_candidate_pairs
-- ORDER BY country_id, normalized_name, distance_km;

-- /* Validação específica da regra de sufixo, útil para casos como
--    "6th of October" x "6th of October City". */
-- SELECT *
-- FROM t1_city_suffix_rule_validation
-- WHERE normalized_name = '6th of october'
-- ORDER BY distance_km, city_id_1, city_id_2;

-- /* Pares de canônicas remanescentes após o merge automático. */
-- SELECT *
-- FROM t1_city_canonical_pairs
-- ORDER BY country_id, normalized_name, distance_km;

-- /* Casos de cidade deixados para revisão manual. */
-- SELECT *
-- FROM t1_city_manual_review
-- ORDER BY country_name, city_name, canonical_city_name;

/* ------------------------------------------------------------------------------------------------------------
   4.3. LIMPEZA OPCIONAL DAS TABELAS AUXILIARES

   As tabelas da deduplicação de cities foram mantidas como tabelas permanentes, porque elas
   são úteis para auditoria, depuração e para explicar o processo no relatório.

   Por isso, os DROP abaixo ficam comentados: use apenas se quiser apagar manualmente essas
   tabelas depois de extrair as métricas e revisar os resultados.
   ------------------------------------------------------------------------------------------------------------ */

-- DROP TABLE IF EXISTS t1_nationality_reference_summary;
-- DROP TABLE IF EXISTS t1_nationality_reference_metrics;
-- DROP TABLE IF EXISTS t1_city_manual_review;
-- DROP TABLE IF EXISTS t1_city_group_validation;
-- DROP TABLE IF EXISTS t1_city_suffix_rule_validation;
-- DROP TABLE IF EXISTS t1_city_canonical_pairs;
-- DROP TABLE IF EXISTS t1_city_merge_values;
-- DROP TABLE IF EXISTS t1_city_merge_map;
-- DROP TABLE IF EXISTS t1_city_canonical;
-- DROP TABLE IF EXISTS t1_city_quality;
-- DROP TABLE IF EXISTS t1_city_component_stats;
-- DROP TABLE IF EXISTS t1_city_component_map;
-- DROP TABLE IF EXISTS t1_city_candidate_pairs;
-- DROP TABLE IF EXISTS t1_city_groups;
-- DROP TABLE IF EXISTS t1_cities_base;
-- DROP TABLE IF EXISTS t1_dedup_parameters;
-- DROP TABLE IF EXISTS tmp_drivers_not_migrated;
-- DROP TABLE IF EXISTS tmp_constructors_not_migrated;
-- DROP TABLE IF EXISTS tmp_country_nationality_canonical;
-- DROP TABLE IF EXISTS tmp_nationality_not_mapped;
-- DROP TABLE IF EXISTS tmp_nationality_country_auto;
-- DROP TABLE IF EXISTS tmp_nationality_country_candidates;
-- DROP TABLE IF EXISTS tmp_nationality_found_in_cities;
-- DROP TABLE IF EXISTS tmp_nationality_variants;
-- DROP TABLE IF EXISTS tmp_nationality_map;
-- DROP TABLE IF EXISTS tmp_nationalities;