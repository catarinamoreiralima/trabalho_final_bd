"""
Acoes disponiveis por tipo de usuario (cadastro, consulta, importacao).

Cada formulario apenas coleta os dados pedidos pelo enunciado e chama a funcao SQL
correspondente, ja criada em sql/app_actions.sql. Erros do banco (ex: RAISE EXCEPTION das
triggers de sincronizacao de usuario) sao capturados e mostrados ao usuario.
"""
from datetime import date

import pandas as pd
import psycopg2
import streamlit as st

from db import db_error_message, get_countries, run_command_many, run_function, run_query
from labels import to_dataframe


def _country_selectbox(label, key):
    countries = get_countries()
    return st.selectbox(label, options=countries, format_func=lambda c: c["name"], key=key)


def form_cadastrar_escuderia():
    """Admin: cadastra escuderia (constructor_ref, name, country_id, wikipedia_url)."""
    with st.form("form_cadastrar_escuderia"):
        constructor_ref = st.text_input("Referência (constructor_ref)")
        name = st.text_input("Nome da Escuderia")
        country = _country_selectbox("País", "escuderia_country")
        wikipedia_url = st.text_input("URL da Wikipedia (opcional)")
        submitted = st.form_submit_button("Cadastrar Escuderia")

    if not submitted:
        return
    if not constructor_ref or not name:
        st.error("Informe a referência e o nome da escuderia.")
        return

    try:
        # FUNCAO: app_admin_cadastrar_escuderia - INSERT em constructors; a trigger
        # trg_sync_constructor_user (app_users.sql) cria o usuario <constructor_ref>_c e
        # cancela a operacao (RAISE EXCEPTION) se o login ja existir.
        resultado = run_function(
            "app_admin_cadastrar_escuderia",
            (constructor_ref, name, country["id"], wikipedia_url or None),
        )[0]
        st.success(
            f"Escuderia '{resultado['escuderia_nome']}' cadastrada. "
            f"Login criado: {resultado['login_usuario']}"
        )
    except psycopg2.Error as exc:
        st.error(db_error_message(exc))


def form_cadastrar_piloto():
    """Admin: cadastra piloto (driver_ref, given_name, family_name, date_of_birth, country_id)."""
    with st.form("form_cadastrar_piloto"):
        driver_ref = st.text_input("Referência (driver_ref)")
        given_name = st.text_input("Nome")
        family_name = st.text_input("Sobrenome")
        date_of_birth = st.date_input(
            "Data de Nascimento", value=date(2000, 1, 1), min_value=date(1900, 1, 1), max_value=date.today()
        )
        country = _country_selectbox("País", "piloto_country")
        submitted = st.form_submit_button("Cadastrar Piloto")

    if not submitted:
        return
    if not driver_ref or not given_name or not family_name:
        st.error("Informe referência, nome e sobrenome do piloto.")
        return

    try:
        # FUNCAO: app_admin_cadastrar_piloto - INSERT em drivers; a trigger
        # trg_sync_driver_user (app_users.sql) cria o usuario <driver_ref>_d e cancela a
        # operacao (RAISE EXCEPTION) se o login ja existir.
        resultado = run_function(
            "app_admin_cadastrar_piloto",
            (driver_ref, given_name, family_name, date_of_birth, country["id"]),
        )[0]
        st.success(
            f"Piloto '{resultado['nome_completo']}' cadastrado. "
            f"Login criado: {resultado['login_usuario']}"
        )
    except psycopg2.Error as exc:
        st.error(db_error_message(exc))


def form_consultar_piloto_por_sobrenome(escuderia_id):
    """Escuderia: busca piloto por sobrenome no escopo da escuderia logada."""
    with st.form("form_consultar_sobrenome"):
        sobrenome = st.text_input("Sobrenome do Piloto")
        submitted = st.form_submit_button("Consultar")

    if not submitted:
        return
    if not sobrenome:
        st.error("Informe um sobrenome.")
        return

    # FUNCAO: app_escuderia_consultar_piloto_por_sobrenome - filtra por escuderia logada
    resultado = run_function("app_escuderia_consultar_piloto_por_sobrenome", (escuderia_id, sobrenome))
    if not resultado:
        st.info("Nenhum piloto com esse sobrenome correu por esta escuderia.")
    else:
        st.dataframe(to_dataframe(resultado), hide_index=True, width="stretch")


def form_importar_pilotos(escuderia_id):
    """Escuderia: importa pilotos por arquivo CSV (upload pelo navegador)."""
    st.caption("Arquivo CSV com colunas: driver_ref, given_name, family_name, date_of_birth, country_id")
    arquivo = st.file_uploader("Selecione o arquivo de pilotos", type=["csv"], key="upload_pilotos")

    if arquivo is None:
        return

    try:
        df = pd.read_csv(arquivo)
    except Exception as exc:
        st.error(f"Não foi possível ler o arquivo: {exc}")
        return

    colunas_esperadas = {"driver_ref", "given_name", "family_name", "date_of_birth", "country_id"}
    if not colunas_esperadas.issubset(df.columns):
        st.error(f"O arquivo precisa conter as colunas: {', '.join(sorted(colunas_esperadas))}")
        return

    df["date_of_birth"] = pd.to_datetime(df["date_of_birth"], errors="coerce").dt.date
    st.dataframe(df, hide_index=True, width="stretch")

    if not st.button("Processar Importação", key="processar_importacao"):
        return

    try:
        linhas = [
            (
                escuderia_id,
                str(row["driver_ref"]),
                str(row["given_name"]),
                str(row["family_name"]),
                row["date_of_birth"] if pd.notna(row["date_of_birth"]) else None,
                int(row["country_id"]),
            )
            for _, row in df.iterrows()
        ]

        # Staging: grava as linhas do arquivo em app_import_pilotos_escuderia antes de processar
        run_command_many(
            """
            INSERT INTO app_import_pilotos_escuderia
                (escuderia_id, driver_ref, given_name, family_name, date_of_birth, country_id)
            VALUES %s
            """,
            linhas,
        )

        # FUNCAO: app_escuderia_processar_importacao_pilotos - rejeita linhas com piloto
        # ja cadastrado com o mesmo nome+sobrenome, e cria piloto+vinculo para as demais.
        resumo = run_function("app_escuderia_processar_importacao_pilotos", (escuderia_id,))[0]
    except (psycopg2.Error, ValueError) as exc:
        st.error(db_error_message(exc) if isinstance(exc, psycopg2.Error) else str(exc))
        return

    st.success(
        f"{resumo['pilotos_inseridos']} piloto(s) inserido(s), "
        f"{resumo['vinculos_criados']} vínculo(s) criado(s), "
        f"{resumo['linhas_invalidas']} linha(s) rejeitada(s)."
    )

    rejeitadas = run_query(
        """
        SELECT driver_ref, given_name, family_name, mensagem
        FROM app_import_pilotos_escuderia
        WHERE escuderia_id = %s AND importado = FALSE
        ORDER BY import_id DESC
        LIMIT %s
        """,
        (escuderia_id, len(linhas)),
    )
    if rejeitadas:
        st.warning("Linhas rejeitadas:")
        st.dataframe(to_dataframe(rejeitadas), hide_index=True, width="stretch")
