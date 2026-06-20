"""
Ponto de entrada da aplicacao.

Tela 1 (Login): autentica via app_login (sql/app_users.sql), que valida a senha com pgcrypto
e registra o LOGIN em users_log. Depois do login, a navegacao entre as telas (Visao Geral,
Cadastros/Acoes e Relatorios) e feita por um menu de itens clicaveis na barra lateral, que
tambem concentra a identificacao do usuario e o botao de logout.
"""
import os

import streamlit as st

import auth
import dashboard
import reports

st.set_page_config(page_title="F1 - Painel da Aplicação", layout="wide")

LOGO_PATH = os.path.join(os.path.dirname(__file__), "Formula_One_logo.png")


def render_login():
    # Centraliza logo e formulario na coluna do meio.
    _, col_meio, _ = st.columns([1, 2, 1])
    with col_meio:
        st.image(LOGO_PATH, width="stretch")
        st.title("Login")
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
    st.rerun()


def _menu_opcoes(tipo):
    """Opcoes do menu lateral por tipo de usuario.

    O piloto e somente leitura (enunciado), entao nao tem a pagina de cadastros/acoes.
    """
    if tipo == "Admin":
        return ["Visão Geral", "Cadastros", "Relatórios"]
    if tipo == "Escuderia":
        return ["Visão Geral", "Ações", "Relatórios"]
    return ["Visão Geral", "Relatórios"]  # Piloto


def _sidebar_nav(user):
    """Desenha o menu lateral como itens de texto clicaveis e devolve a pagina atual.

    O item ativo aparece destacado. O estado da pagina fica em st.session_state["pagina"].
    """
    opcoes = _menu_opcoes(user["tipo"])

    pagina = st.session_state.get("pagina", opcoes[0])
    if pagina not in opcoes:  # protege quando o tipo de usuario muda (login diferente)
        pagina = opcoes[0]
        st.session_state["pagina"] = pagina

    with st.sidebar:
        _, col_logo, _ = st.columns([1, 3, 1])
        col_logo.image(LOGO_PATH, width="stretch")
        st.markdown(
            f"<div style='text-align:center'>{user.get('nome_exibicao', user['login'])} · {user['tipo']}</div>",
            unsafe_allow_html=True,
        )
        st.divider()

        for op in opcoes:
            ativo = op == pagina
            if st.button(
                op,
                key=f"nav_{op}",
                width="stretch",
                type="primary" if ativo else "tertiary",
            ):
                st.session_state["pagina"] = op
                st.rerun()

        st.divider()
        if st.button("🚪 Sair", key="nav_sair", width="stretch"):
            auth.logout()
            st.rerun()

    return st.session_state.get("pagina", opcoes[0])


def main():
    if not auth.is_logged_in():
        render_login()
        return

    user = auth.current_user()
    pagina = _sidebar_nav(user)

    # Roteamento conforme a pagina escolhida no menu lateral.
    if pagina == "Visão Geral":
        dashboard.render_dashboard(user)
    elif pagina in ("Cadastros", "Ações"):
        dashboard.render_acoes(user)
    else:
        reports.render_reports(user)


if __name__ == "__main__":
    main()
