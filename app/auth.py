"""
Autenticacao e auditoria de acesso.

Toda a regra (validar senha com pgcrypto, registrar LOGIN/LOGOUT em users_log) ja existe em
sql/app_users.sql (app_login/app_logout). Este modulo so chama essas funcoes e guarda o
usuario autenticado em st.session_state.
"""
import streamlit as st

from db import run_command, run_function, run_query


def _nome_exibicao(user):
    """Nome amigavel do usuario, conforme o tipo (em vez de mostrar o login/credencial).

    - Admin: rotulo fixo;
    - Escuderia: nome em constructors (id_original);
    - Piloto: nome completo em drivers (id_original).
    """
    if user["tipo"] == "Admin":
        return "Administrador"
    if user["tipo"] == "Escuderia":
        rows = run_query("SELECT name FROM constructors WHERE id = %s", (user["id_original"],))
        return rows[0]["name"] if rows else user["login"]
    rows = run_query(
        "SELECT given_name || ' ' || family_name AS nome FROM drivers WHERE id = %s",
        (user["id_original"],),
    )
    return rows[0]["nome"] if rows else user["login"]


def login(login_input, senha_input):
    """Chama app_login(login, senha). Retorna o dict do usuario autenticado, ou None."""
    rows = run_function("app_login", (login_input, senha_input))
    if not rows:
        return None
    user = rows[0]
    user["nome_exibicao"] = _nome_exibicao(user)  # guardado na sessao para uso na barra lateral
    return user


def logout():
    """Chama app_logout(userid) para registrar o LOGOUT em users_log e encerra a sessao."""
    user = st.session_state.get("user")
    if user is not None:
        run_command("SELECT app_logout(%s)", (user["userid"],))
    # Limpa o usuario e o estado de navegacao.
    for chave in ("user", "pagina", "relatorio_selecionado"):
        st.session_state.pop(chave, None)


def current_user():
    return st.session_state.get("user")


def is_logged_in():
    return "user" in st.session_state
