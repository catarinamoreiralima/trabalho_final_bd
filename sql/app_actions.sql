/* ============================================================================================================
   ACOES DA APLICACAO

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql
   4) app_users.sql

   Este arquivo centraliza funcoes de acoes solicitadas pela especificacao:
   - cadastro de escuderias pelo administrador;
   - cadastro de pilotos pelo administrador;
   - listagem cadastral de pilotos vinculados a escuderia;
   - consulta de piloto por sobrenome no escopo da escuderia logada;
   - importacao de novos pilotos por arquivo para uma escuderia.
============================================================================================================ */

BEGIN;

/* ------------------------------------------------------------------------------------------------------------
   RELACAO ENTRE ESCUDERIAS E PILOTOS NA APLICACAO

   A base original relaciona pilotos e escuderias por meio de results, isto e, apenas quando ja existe
   participacao em corrida. Esta tabela permite registrar tambem pilotos cadastrados/importados por
   uma escuderia, mesmo antes de existirem resultados de corrida para eles.
------------------------------------------------------------------------------------------------------------ */
CREATE TABLE IF NOT EXISTS app_escuderia_pilotos (
    escuderia_id INTEGER NOT NULL,
    piloto_id    INTEGER NOT NULL,
    origem       VARCHAR(30) NOT NULL DEFAULT 'importacao_arquivo',
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_app_escuderia_pilotos
        PRIMARY KEY (escuderia_id, piloto_id),

    CONSTRAINT fk_app_escuderia_pilotos_escuderia
        FOREIGN KEY (escuderia_id) REFERENCES constructors(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_app_escuderia_pilotos_piloto
        FOREIGN KEY (piloto_id) REFERENCES drivers(id)
        ON DELETE CASCADE,

    CONSTRAINT ck_app_escuderia_pilotos_origem
        CHECK (origem IN ('historico_results', 'importacao_arquivo', 'cadastro_manual'))
);

COMMENT ON TABLE app_escuderia_pilotos
IS 'Relaciona escuderias e pilotos no escopo da aplicacao, incluindo historico da base e importacoes por arquivo.';

COMMENT ON COLUMN app_escuderia_pilotos.origem
IS 'Indica se o vinculo veio dos resultados historicos, de importacao por arquivo ou de cadastro manual.';

INSERT INTO app_escuderia_pilotos (escuderia_id, piloto_id, origem)
SELECT DISTINCT
    res.constructor_id,
    res.driver_id,
    'historico_results'
FROM results res
ON CONFLICT (escuderia_id, piloto_id) DO NOTHING;

CREATE OR REPLACE FUNCTION trg_sync_result_escuderia_piloto()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO app_escuderia_pilotos (
        escuderia_id,
        piloto_id,
        origem
    )
    VALUES (
        NEW.constructor_id,
        NEW.driver_id,
        'historico_results'
    )
    ON CONFLICT (escuderia_id, piloto_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_result_escuderia_piloto ON results;

CREATE TRIGGER trg_sync_result_escuderia_piloto
AFTER INSERT OR UPDATE OF constructor_id, driver_id ON results
FOR EACH ROW
EXECUTE FUNCTION trg_sync_result_escuderia_piloto();

COMMENT ON FUNCTION trg_sync_result_escuderia_piloto()
IS 'Mantem app_escuderia_pilotos sincronizada quando results recebe ou altera vinculos entre pilotos e escuderias.';

/* ------------------------------------------------------------------------------------------------------------
   STAGING PARA IMPORTACAO DE PILOTOS POR ARQUIVO

   A aplicacao pode carregar um CSV para esta tabela usando \copy no psql. Depois disso, a funcao
   app_escuderia_processar_importacao_pilotos processa as linhas pendentes da escuderia.

   Antes de inserir, a funcao verifica se ja existe outro piloto com o mesmo given_name e
   family_name (conforme exigido na especificacao). Se existir, a linha e rejeitada com uma
   mensagem explicativa e nenhum piloto/vinculo e criado para ela.
------------------------------------------------------------------------------------------------------------ */
CREATE TABLE IF NOT EXISTS app_import_pilotos_escuderia (
    import_id     SERIAL PRIMARY KEY,
    escuderia_id  INTEGER NOT NULL,
    driver_ref    TEXT NOT NULL,
    given_name    TEXT NOT NULL,
    family_name   TEXT NOT NULL,
    date_of_birth DATE,
    country_id    INTEGER NOT NULL,
    importado     BOOLEAN NOT NULL DEFAULT FALSE,
    mensagem      TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at  TIMESTAMP,

    CONSTRAINT fk_app_import_pilotos_escuderia
        FOREIGN KEY (escuderia_id) REFERENCES constructors(id)
        ON DELETE CASCADE
);

COMMENT ON TABLE app_import_pilotos_escuderia
IS 'Tabela de apoio para carregar arquivos CSV com pilotos a serem vinculados a escuderias.';

/* ------------------------------------------------------------------------------------------------------------
   ADMIN - CADASTRAR ESCUDERIA

   Insere uma nova escuderia em constructors. A trigger trg_sync_constructor_user, criada em app_users.sql,
   cria automaticamente o usuario correspondente no padrao <constructor_ref>_c.
------------------------------------------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS app_admin_cadastrar_escuderia(TEXT, TEXT, INTEGER, TEXT);

CREATE OR REPLACE FUNCTION app_admin_cadastrar_escuderia(
    p_constructor_ref TEXT,
    p_name TEXT,
    p_country_id INTEGER,
    p_wikipedia_url TEXT DEFAULT NULL
)
RETURNS TABLE (
    escuderia_id INTEGER,
    escuderia_nome TEXT,
    login_usuario TEXT
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM countries co WHERE co.id = p_country_id) THEN
        RAISE EXCEPTION 'Pais com id % nao encontrado', p_country_id;
    END IF;

    RETURN QUERY
    WITH nova_escuderia AS (
        INSERT INTO constructors (
            constructor_ref,
            name,
            country_id,
            wikipedia_url
        )
        VALUES (
            p_constructor_ref,
            p_name,
            p_country_id,
            p_wikipedia_url
        )
        RETURNING id, name, constructor_ref
    )
    SELECT
        ne.id AS escuderia_id,
        ne.name::TEXT AS escuderia_nome,
        (ne.constructor_ref || '_c')::TEXT AS login_usuario
    FROM nova_escuderia ne;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_cadastrar_escuderia(TEXT, TEXT, INTEGER, TEXT)
IS 'Acao Admin: cadastra uma escuderia e permite que a trigger crie o usuario correspondente.';


/* ------------------------------------------------------------------------------------------------------------
   ADMIN - CADASTRAR PILOTO

   Insere um novo piloto em drivers. A trigger trg_sync_driver_user, criada em app_users.sql,
   cria automaticamente o usuario correspondente no padrao <driver_ref>_d.
------------------------------------------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS app_admin_cadastrar_piloto(TEXT, TEXT, TEXT, DATE, INTEGER);

CREATE OR REPLACE FUNCTION app_admin_cadastrar_piloto(
    p_driver_ref TEXT,
    p_given_name TEXT,
    p_family_name TEXT,
    p_date_of_birth DATE,
    p_country_id INTEGER
)
RETURNS TABLE (
    piloto_id INTEGER,
    nome_completo TEXT,
    login_usuario TEXT
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM countries co WHERE co.id = p_country_id) THEN
        RAISE EXCEPTION 'Pais com id % nao encontrado', p_country_id;
    END IF;

    RETURN QUERY
    WITH novo_piloto AS (
        INSERT INTO drivers (
            driver_ref,
            given_name,
            family_name,
            date_of_birth,
            country_id
        )
        VALUES (
            p_driver_ref,
            p_given_name,
            p_family_name,
            p_date_of_birth,
            p_country_id
        )
        RETURNING id, driver_ref, given_name, family_name
    )
    SELECT
        np.id AS piloto_id,
        (np.given_name || ' ' || np.family_name)::TEXT AS nome_completo,
        (np.driver_ref || '_d')::TEXT AS login_usuario
    FROM novo_piloto np;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_admin_cadastrar_piloto(TEXT, TEXT, TEXT, DATE, INTEGER)
IS 'Acao Admin: cadastra um piloto e permite que a trigger crie o usuario correspondente.';


/* ------------------------------------------------------------------------------------------------------------
   ESCUDERIA - PROCESSAR IMPORTACAO DE PILOTOS POR ARQUIVO

   Processa as linhas pendentes carregadas em app_import_pilotos_escuderia para a escuderia informada.
   Para carregar o arquivo pelo psql, use por exemplo:

   \copy app_import_pilotos_escuderia(escuderia_id, driver_ref, given_name, family_name, date_of_birth, country_id)
   FROM 'data/novos_pilotos.csv'
   WITH (FORMAT csv, HEADER true);

   Se ja existir outro piloto com o mesmo nome e sobrenome, a linha e rejeitada (ver comentario
   acima da tabela de staging).
------------------------------------------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS app_escuderia_processar_importacao_pilotos(INTEGER);

CREATE OR REPLACE FUNCTION app_escuderia_processar_importacao_pilotos(
    p_escuderia_id INTEGER
)
RETURNS TABLE (
    total_linhas INTEGER,
    pilotos_inseridos INTEGER,
    vinculos_criados INTEGER,
    linhas_invalidas INTEGER
) AS $$
DECLARE
    v_linha app_import_pilotos_escuderia%ROWTYPE;
    v_piloto_id INTEGER;
    v_rows INTEGER;
    v_total_linhas INTEGER := 0;
    v_pilotos_inseridos INTEGER := 0;
    v_vinculos_criados INTEGER := 0;
    v_linhas_invalidas INTEGER := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM constructors c WHERE c.id = p_escuderia_id) THEN
        RAISE EXCEPTION 'Escuderia com id % nao encontrada', p_escuderia_id;
    END IF;

    FOR v_linha IN
        SELECT *
        FROM app_import_pilotos_escuderia imp
        WHERE imp.escuderia_id = p_escuderia_id
          AND imp.importado = FALSE
        ORDER BY imp.import_id
    LOOP
        v_total_linhas := v_total_linhas + 1;
        v_piloto_id := NULL;

        IF NOT EXISTS (SELECT 1 FROM countries co WHERE co.id = v_linha.country_id) THEN
            v_linhas_invalidas := v_linhas_invalidas + 1;

            UPDATE app_import_pilotos_escuderia
            SET mensagem = 'Pais informado nao encontrado',
                processed_at = CURRENT_TIMESTAMP
            WHERE import_id = v_linha.import_id;

            CONTINUE;
        END IF;

        -- Verificacao exigida pela especificacao: nao pode existir outro piloto com o mesmo
        -- nome e sobrenome. Se existir, a linha e rejeitada e nao cria piloto nem vinculo.
        SELECT d.id
        INTO v_piloto_id
        FROM drivers d
        WHERE lower(d.given_name) = lower(v_linha.given_name)
          AND lower(d.family_name) = lower(v_linha.family_name);

        IF v_piloto_id IS NOT NULL THEN
            v_linhas_invalidas := v_linhas_invalidas + 1;

            UPDATE app_import_pilotos_escuderia
            SET mensagem = format('Piloto ja cadastrado com esse nome (id %s)', v_piloto_id),
                processed_at = CURRENT_TIMESTAMP
            WHERE import_id = v_linha.import_id;

            CONTINUE;
        END IF;

        INSERT INTO drivers (
            driver_ref,
            given_name,
            family_name,
            date_of_birth,
            country_id
        )
        VALUES (
            v_linha.driver_ref,
            v_linha.given_name,
            v_linha.family_name,
            v_linha.date_of_birth,
            v_linha.country_id
        )
        RETURNING id INTO v_piloto_id;

        v_pilotos_inseridos := v_pilotos_inseridos + 1;

        INSERT INTO app_escuderia_pilotos (
            escuderia_id,
            piloto_id,
            origem
        )
        VALUES (
            p_escuderia_id,
            v_piloto_id,
            'importacao_arquivo'
        )
        ON CONFLICT (escuderia_id, piloto_id) DO NOTHING;

        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_vinculos_criados := v_vinculos_criados + v_rows;

        UPDATE app_import_pilotos_escuderia
        SET importado = TRUE,
            mensagem = 'Processado com sucesso',
            processed_at = CURRENT_TIMESTAMP
        WHERE import_id = v_linha.import_id;
    END LOOP;

    RETURN QUERY
    SELECT
        v_total_linhas,
        v_pilotos_inseridos,
        v_vinculos_criados,
        v_linhas_invalidas;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_processar_importacao_pilotos(INTEGER)
IS 'Acao Escuderia: processa pilotos carregados por arquivo e cria vinculos com a escuderia.';


/* ------------------------------------------------------------------------------------------------------------
   ESCUDERIA - LISTAR PILOTOS VINCULADOS

   Lista os pilotos vinculados a escuderia no escopo cadastral da aplicacao. Diferentemente dos
   relatorios de desempenho, esta funcao considera tambem pilotos importados por arquivo que ainda
   nao possuem resultados de corrida.
------------------------------------------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS app_escuderia_listar_pilotos(INTEGER);

CREATE OR REPLACE FUNCTION app_escuderia_listar_pilotos(
    p_escuderia_id INTEGER
)
RETURNS TABLE (
    piloto_id INTEGER,
    nome_completo TEXT,
    data_nascimento DATE,
    pais TEXT,
    origem TEXT,
    vinculo_criado_em TIMESTAMP
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM constructors c WHERE c.id = p_escuderia_id) THEN
        RAISE EXCEPTION 'Escuderia com id % nao encontrada', p_escuderia_id;
    END IF;

    RETURN QUERY
    SELECT
        d.id AS piloto_id,
        (d.given_name || ' ' || d.family_name)::TEXT AS nome_completo,
        d.date_of_birth AS data_nascimento,
        co.name::TEXT AS pais,
        ep.origem::TEXT AS origem,
        ep.created_at AS vinculo_criado_em
    FROM app_escuderia_pilotos ep
    JOIN drivers d
      ON d.id = ep.piloto_id
    JOIN countries co
      ON co.id = d.country_id
    WHERE ep.escuderia_id = p_escuderia_id
    ORDER BY nome_completo;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_listar_pilotos(INTEGER)
IS 'Acao Escuderia: lista pilotos vinculados a escuderia, incluindo importados sem resultado de corrida.';


/* ------------------------------------------------------------------------------------------------------------
   ESCUDERIA - CONSULTAR PILOTO POR SOBRENOME

   Busca pilotos com o sobrenome informado que estejam vinculados a escuderia logada.
   O vinculo pode vir do historico de results ou de importacao por arquivo.
------------------------------------------------------------------------------------------------------------ */
DROP FUNCTION IF EXISTS app_escuderia_consultar_piloto_por_sobrenome(INTEGER, TEXT);

CREATE OR REPLACE FUNCTION app_escuderia_consultar_piloto_por_sobrenome(
    p_escuderia_id INTEGER,
    p_sobrenome TEXT
)
RETURNS TABLE (
    piloto_id INTEGER,
    nome_completo TEXT,
    data_nascimento DATE,
    pais TEXT
) AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM constructors c WHERE c.id = p_escuderia_id) THEN
        RAISE EXCEPTION 'Escuderia com id % nao encontrada', p_escuderia_id;
    END IF;

    RETURN QUERY
    SELECT DISTINCT
        d.id AS piloto_id,
        (d.given_name || ' ' || d.family_name)::TEXT AS nome_completo,
        d.date_of_birth AS data_nascimento,
        co.name::TEXT AS pais
    FROM app_escuderia_pilotos ep
    JOIN drivers d
      ON d.id = ep.piloto_id
    JOIN countries co
      ON co.id = d.country_id
    WHERE ep.escuderia_id = p_escuderia_id
      AND lower(d.family_name) = lower(p_sobrenome)
    ORDER BY nome_completo;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION app_escuderia_consultar_piloto_por_sobrenome(INTEGER, TEXT)
IS 'Acao Escuderia: consulta pilotos por sobrenome no escopo da escuderia logada.';

COMMIT;
