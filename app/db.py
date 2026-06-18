"""
Camada de acesso ao banco.

Toda consulta feita pela aplicacao chama uma VIEW ou FUNCTION ja criada em sql/app_*.sql.
Nao ha logica de negocio em Python: este modulo apenas abre a conexao e executa o SQL,
que fica sempre explicito (visivel) em cada ponto de chamada.
"""
import os

import psycopg2
import psycopg2.extras
import streamlit as st
from dotenv import load_dotenv

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5433"),
    "dbname": os.getenv("DB_NAME", "f1db"),
    "user": os.getenv("DB_USER", "f1user"),
    "password": os.getenv("DB_PASSWORD", "f1pass"),
}


@st.cache_resource
def get_connection():
    """Conexao reaproveitada entre reruns do Streamlit.

    autocommit=True porque cada chamada da aplicacao e uma unica instrucao (um SELECT em uma
    view/funcao, ou uma funcao que faz o INSERT internamente), entao a propria instrucao já é
    atomica e nao precisamos controlar BEGIN/COMMIT/ROLLBACK manualmente no lado Python.
    """
    conn = psycopg2.connect(**DB_CONFIG)
    conn.autocommit = True
    return conn


def run_query(sql, params=None):
    """Executa um SELECT explicito e retorna uma lista de dicts (uma entrada por linha)."""
    conn = get_connection()
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]


def run_function(function_name, params=()):
    """Chama 'SELECT * FROM <function_name>(%s, %s, ...)' com os parametros informados.

    function_name e sempre uma constante escrita no codigo (nunca vem de input do usuario),
    entao apenas evita repetir o boilerplate de cursor/execute em cada chamada; o SQL efetivo
    continua explicito e visivel em cada ponto de uso.
    """
    placeholders = ", ".join(["%s"] * len(params))
    sql = f"SELECT * FROM {function_name}({placeholders})"
    return run_query(sql, params)


def run_command(sql, params=None):
    """Executa um INSERT/UPDATE/chamada de funcao que nao retorna linhas."""
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(sql, params)


def run_command_many(sql, rows):
    """Executa um INSERT em lote (ex: linhas de um CSV importado) com execute_values."""
    conn = get_connection()
    with conn.cursor() as cur:
        psycopg2.extras.execute_values(cur, sql, rows)


def db_error_message(exc):
    """Extrai a mensagem primaria de um erro do PostgreSQL (ex: RAISE EXCEPTION de uma trigger)."""
    diag = getattr(exc, "diag", None)
    message = getattr(diag, "message_primary", None) if diag else None
    return message or str(exc)


@st.cache_data(ttl=300)
def get_countries():
    """Lista de paises (id, name) usada nos selectbox de cadastro em actions.py."""
    return run_query("SELECT id, name FROM countries ORDER BY name")
