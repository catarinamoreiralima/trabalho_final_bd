"""
Autenticacao e auditoria de acesso.

Toda a regra (validar senha com pgcrypto, registrar LOGIN/LOGOUT em users_log) ja existe em
sql/app_users.sql (app_login/app_logout). Este modulo so chama essas funcoes e guarda o
usuario autenticado em st.session_state.
"""
import streamlit as st

from db import run_command, run_function


def login(login_input, senha_input):
    """Chama app_login(login, senha). Retorna o dict do usuario autenticado, ou None."""
    rows = run_function("app_login", (login_input, senha_input))
    return rows[0] if rows else None


def logout():
    """Chama app_logout(userid) para registrar o LOGOUT em users_log e encerra a sessao."""
    user = st.session_state.get("user")
    if user is not None:
        run_command("SELECT app_logout(%s)", (user["userid"],))
    st.session_state.pop("user", None)
    st.session_state["screen"] = "dashboard"


def current_user():
    return st.session_state.get("user")


def is_logged_in():
    return "user" in st.session_state
