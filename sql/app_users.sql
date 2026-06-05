/* ============================================================================================================
   P4 - USUARIOS, AUTENTICACAO E AUDITORIA

   Deve ser executado depois de:
   1) create_table.sql
   2) insert_table.sql
   3) clean_data.sql

   Observacao:
   - A coluna password armazena HASH da senha, nao texto puro.
   - Usa pgcrypto para crypt()/gen_salt().
============================================================================================================ */

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

/* ------------------------------------------------------------------------------------------------------------
   1. TABELA DE USUARIOS

   id_original aponta para:
   - drivers.id, quando tipo = 'Piloto'
   - constructors.id, quando tipo = 'Escuderia'
   - NULL, quando tipo = 'Admin'
------------------------------------------------------------------------------------------------------------ */
CREATE TABLE IF NOT EXISTS users (
    userid      SERIAL PRIMARY KEY,
    login       VARCHAR(255) NOT NULL UNIQUE,
    password    TEXT NOT NULL,
    tipo        VARCHAR(20) NOT NULL,
    id_original INTEGER,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT ck_users_tipo
        CHECK (tipo IN ('Admin', 'Escuderia', 'Piloto')),

    CONSTRAINT ck_users_id_original
        CHECK (
            (tipo = 'Admin' AND id_original IS NULL)
            OR
            (tipo IN ('Escuderia', 'Piloto') AND id_original IS NOT NULL)
        )
);

COMMENT ON TABLE users IS 'Usuarios da aplicacao: pode ser admin, piloto ou escuderia';
COMMENT ON COLUMN users.password IS 'Hash da senha gerado com pgcrypto -> não é texto puro';
COMMENT ON COLUMN users.id_original IS 'ID do piloto ou escuderia associado ao usuario';

/* Garante que nao existam dois usuarios para o mesmo piloto/escuderia. */
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_tipo_id_original
ON users (tipo, id_original)
WHERE id_original IS NOT NULL;

/* ------------------------------------------------------------------------------------------------------------
   2. LOG DE ACESSO
------------------------------------------------------------------------------------------------------------ */
CREATE TABLE IF NOT EXISTS users_log (
    log_id     SERIAL PRIMARY KEY,
    userid     INTEGER NOT NULL,
    action     VARCHAR(20) NOT NULL,
    action_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_users_log_user
        FOREIGN KEY (userid) REFERENCES users(userid),

    CONSTRAINT ck_users_log_action
        CHECK (action IN ('LOGIN', 'LOGOUT'))
);

COMMENT ON TABLE users_log IS 'Auditoria de login e logout dos usuarios';

/* ------------------------------------------------------------------------------------------------------------
   3. FUNCOES DE APOIO PARA SENHA E LOGIN
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_hash_password(p_plain_password TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN crypt(p_plain_password, gen_salt('bf')); -- usa bcrypt para gerar o hash da senha: como não é usuario de fato do postgres, não precisa ser configurada com SCRAM-SHA-256
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION app_check_password(p_plain_password TEXT, p_password_hash TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN p_password_hash = crypt(p_plain_password, p_password_hash);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_users_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_set_updated_at ON users;

CREATE TRIGGER trg_users_set_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION trg_users_set_updated_at();

/* ------------------------------------------------------------------------------------------------------------
   4. CARGA INICIAL DOS USUARIOS

   Padroes exigidos:
   - admin / admin
   - <constructor_ref>_c / <constructor_ref>
   - <driver_ref>_d / <driver_ref>
------------------------------------------------------------------------------------------------------------ */
INSERT INTO users (login, password, tipo, id_original)
VALUES ('admin', app_hash_password('admin'), 'Admin', NULL)
ON CONFLICT (login) DO NOTHING;

INSERT INTO users (login, password, tipo, id_original)
SELECT
    c.constructor_ref || '_c' AS login,
    app_hash_password(c.constructor_ref) AS password,
    'Escuderia' AS tipo,
    c.id AS id_original
FROM constructors c
ON CONFLICT (login) DO NOTHING;

INSERT INTO users (login, password, tipo, id_original)
SELECT
    d.driver_ref || '_d' AS login,
    app_hash_password(d.driver_ref) AS password,
    'Piloto' AS tipo,
    d.id AS id_original
FROM drivers d
ON CONFLICT (login) DO NOTHING;

/* ------------------------------------------------------------------------------------------------------------
   5. TRIGGERS PARA SINCRONIZAR CONSTRUCTORS -> USERS

   Se o login gerado ja existir para outro usuario, a operacao na tabela de origem e cancelada.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION trg_sync_constructor_user()
RETURNS TRIGGER AS $$
DECLARE
    v_login TEXT;
    v_existing_userid INTEGER; -- declara variaveis pra guardar o login gerado e o userid do usuario existente (se houver)
BEGIN
    v_login := NEW.constructor_ref || '_c'; -- gera o login padrao para a escuderia

    SELECT userid -- tenta encontrar um usuario com o mesmo login, mas que nao seja o mesmo da escuderia atual (isso permite atualizar o login se o constructor_ref mudar, sem criar conflito com ele mesmo)
    INTO v_existing_userid
    FROM users
    WHERE login = v_login
      AND NOT (tipo = 'Escuderia' AND id_original = NEW.id);

    IF v_existing_userid IS NOT NULL THEN -- se encontrar um usuario diferente com o mesmo login, gera um erro e cancela a operacao
        RAISE EXCEPTION 'Login % ja existe para outro usuario', v_login;
    END IF;

    INSERT INTO users (login, password, tipo, id_original) -- insere ou atualiza o usuario correspondente a escuderia
    VALUES (v_login, app_hash_password(NEW.constructor_ref), 'Escuderia', NEW.id)
    ON CONFLICT (tipo, id_original) WHERE id_original IS NOT NULL
    DO UPDATE -- se ja existir um usuario para essa escuderia, atualiza o login e a senha (isso permite manter o mesmo usuario atualizado se o constructor_ref mudar)
    SET login = EXCLUDED.login,
        password = EXCLUDED.password;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_constructor_user ON constructors;

CREATE TRIGGER trg_sync_constructor_user
AFTER INSERT OR UPDATE ON constructors
FOR EACH ROW
EXECUTE FUNCTION trg_sync_constructor_user();

/* ------------------------------------------------------------------------------------------------------------
   6. TRIGGERS PARA SINCRONIZAR DRIVERS -> USERS - MESMA LOGICA DOS CONSTRUCTORS
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION trg_sync_driver_user()
RETURNS TRIGGER AS $$
DECLARE
    v_login TEXT;
    v_existing_userid INTEGER; -- declara variaveis pra guardar o login gerado e o userid do usuario existente (se houver)
BEGIN
    v_login := NEW.driver_ref || '_d';

    SELECT userid
    INTO v_existing_userid
    FROM users
    WHERE login = v_login
      AND NOT (tipo = 'Piloto' AND id_original = NEW.id);

    IF v_existing_userid IS NOT NULL THEN
        RAISE EXCEPTION 'Login % ja existe para outro usuario', v_login;
    END IF;

    INSERT INTO users (login, password, tipo, id_original)
    VALUES (v_login, app_hash_password(NEW.driver_ref), 'Piloto', NEW.id)
    ON CONFLICT (tipo, id_original) WHERE id_original IS NOT NULL
    DO UPDATE
    SET login = EXCLUDED.login,
        password = EXCLUDED.password;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_driver_user ON drivers;

CREATE TRIGGER trg_sync_driver_user
AFTER INSERT OR UPDATE ON drivers
FOR EACH ROW
EXECUTE FUNCTION trg_sync_driver_user();

/* ------------------------------------------------------------------------------------------------------------
   7. FUNCOES PARA LOGIN E LOGOUT DA APLICACAO

   A aplicacao pode chamar app_login(login, senha). Se autenticar, a funcao registra LOGIN
   em users_log e retorna os dados do usuario.
------------------------------------------------------------------------------------------------------------ */
CREATE OR REPLACE FUNCTION app_login(p_login TEXT, p_password TEXT)
RETURNS TABLE (
    userid INTEGER,
    login VARCHAR,
    tipo VARCHAR,
    id_original INTEGER
) AS $$
BEGIN
    RETURN QUERY
    WITH authenticated_user AS (
        SELECT u.userid, u.login, u.tipo, u.id_original
        FROM users u
        WHERE u.login = p_login
          AND app_check_password(p_password, u.password)
    ),
    log_insert AS (
        INSERT INTO users_log (userid, action)
        SELECT au.userid, 'LOGIN'
        FROM authenticated_user au
        RETURNING users_log.userid AS logged_userid
    )
    SELECT au.userid, au.login, au.tipo, au.id_original
    FROM authenticated_user au
    JOIN log_insert li
      ON li.logged_userid = au.userid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION app_logout(p_userid INTEGER)
RETURNS VOID AS $$
BEGIN
    INSERT INTO users_log (userid, action)
    VALUES (p_userid, 'LOGOUT');
END;
$$ LANGUAGE plpgsql;

COMMIT;
