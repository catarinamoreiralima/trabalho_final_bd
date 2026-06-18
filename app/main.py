"""
Ponto de entrada da aplicacao.

Tela 1 (Login): autentica via app_login (sql/app_users.sql), que valida a senha com pgcrypto
e registra o LOGIN em users_log. Depois do login, o roteador alterna entre Tela 2 (Dashboard)
e Tela 3 (Relatorios) usando st.session_state["screen"], conforme o fluxo do enunciado.
"""
import streamlit as st

import auth
import dashboard
import reports

st.set_page_config(page_title="F1 - Painel da Aplicação", layout="wide")


def render_login():
    st.title("Fórmula 1 — Login")
    with st.form("form_login"):
        login_input = st.text_input("Login")
        senha_input = st.text_input("Senha", type="password")
        submitted = st.form_submit_button("Entrar")

    if not submitted:
        return

    usuario = auth.login(login_input, senha_input)
    if usuario is None:
        st.error("Login ou senha inválidos.")
        return

    st.session_state["user"] = usuario
    st.session_state["screen"] = "dashboard"
    st.rerun()


def main():
    if not auth.is_logged_in():
        render_login()
        return

    user = auth.current_user()
    st.sidebar.markdown(f"**Usuário:** {user['login']}")
    st.sidebar.markdown(f"**Tipo:** {user['tipo']}")

    screen = st.session_state.get("screen", "dashboard")
    if screen == "relatorios":
        reports.render_reports(user)
    else:
        dashboard.render_dashboard(user)


if __name__ == "__main__":
    main()
