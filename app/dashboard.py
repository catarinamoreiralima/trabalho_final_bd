"""
Tela 2 - Dashboard.

Mostra as informacoes resumidas do tipo de usuario logado e, na mesma tela, as acoes
disponiveis para esse tipo (cadastro, consulta, importacao) dentro de expanders. O enunciado
pede "botoes ou links para as acoes disponiveis ao tipo de usuario autenticado" na Tela 2, sem
exigir uma 4a tela dedicada para isso.
"""
import streamlit as st

import actions
import auth
from db import run_function
from labels import to_dataframe


def render_dashboard(user):
    st.subheader("Dashboard")

    if user["tipo"] == "Admin":
        _render_admin(user)
    elif user["tipo"] == "Escuderia":
        _render_escuderia(user)
    else:
        _render_piloto(user)

    st.divider()
    col1, col2 = st.columns(2)
    with col1:
        if st.button("Ver Relatórios", width="stretch"):
            st.session_state["screen"] = "relatorios"
            st.rerun()
    with col2:
        if st.button("Sair", width="stretch"):
            auth.logout()
            st.rerun()


def _render_admin(user):
    st.markdown(f"**Administrador:** {user['login']}")

    # FUNCAO: app_admin_dashboard_resumo() - agregacoes (COUNT/MAX) sobre drivers/constructors/seasons
    resumo = run_function("app_admin_dashboard_resumo")[0]
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Pilotos", resumo["total_pilotos"])
    c2.metric("Escuderias", resumo["total_escuderias"])
    c3.metric("Temporadas", resumo["total_temporadas"])
    c4.metric("Temporada Mais Recente", resumo["temporada_mais_recente"])

    st.markdown("##### Corridas da Temporada Mais Recente")
    corridas = run_function("app_admin_corridas_temporada_mais_recente")
    st.dataframe(to_dataframe(corridas), hide_index=True, width="stretch")

    col1, col2 = st.columns(2)
    with col1:
        st.markdown("##### Escuderias - Pontos na Temporada")
        df_esc = to_dataframe(run_function("app_admin_escuderias_temporada_mais_recente"))
        st.dataframe(df_esc, hide_index=True, width="stretch")
        if not df_esc.empty:
            st.bar_chart(df_esc.set_index("Escuderia")["Total de Pontos"])
    with col2:
        st.markdown("##### Pilotos - Pontos na Temporada")
        df_pil = to_dataframe(run_function("app_admin_pilotos_temporada_mais_recente"))
        st.dataframe(df_pil, hide_index=True, width="stretch")
        if not df_pil.empty:
            st.bar_chart(df_pil.set_index("Piloto")["Total de Pontos"])

    with st.expander("➕ Cadastrar Escuderia"):
        actions.form_cadastrar_escuderia()
    with st.expander("➕ Cadastrar Piloto"):
        actions.form_cadastrar_piloto()


def _render_escuderia(user):
    escuderia_id = user["id_original"]

    qtd = run_function("app_escuderia_quantidade_pilotos", (escuderia_id,))[0]
    st.markdown(
        f"**Escuderia:** {qtd['escuderia_nome']}  |  **Pilotos:** {qtd['quantidade_pilotos']}"
    )

    vitorias = run_function("app_escuderia_quantidade_vitorias", (escuderia_id,))[0]
    anos = run_function("app_escuderia_anos", (escuderia_id,))

    c1, c2, c3 = st.columns(3)
    c1.metric("Vitórias", vitorias["quantidade_vitorias"])
    c2.metric("Primeiro Ano", anos[0]["primeiro_ano"] if anos else "-")
    c3.metric("Último Ano", anos[0]["ultimo_ano"] if anos else "-")

    with st.expander("🔍 Consultar Piloto por Sobrenome"):
        actions.form_consultar_piloto_por_sobrenome(escuderia_id)
    with st.expander("📂 Importar Pilotos por Arquivo"):
        actions.form_importar_pilotos(escuderia_id)


def _render_piloto(user):
    piloto_id = user["id_original"]

    anos_rows = run_function("app_piloto_anos", (piloto_id,))
    escuderia_rows = run_function("app_piloto_escuderia_atual", (piloto_id,))

    nome = (
        f"{anos_rows[0]['piloto_nome']} {anos_rows[0]['piloto_sobrenome']}"
        if anos_rows
        else user["login"]
    )
    escuderia_nome = escuderia_rows[0]["escuderia_nome"] if escuderia_rows else "Sem corridas registradas"

    st.markdown(f"**Piloto:** {nome}  |  **Escuderia:** {escuderia_nome}")

    if anos_rows:
        c1, c2 = st.columns(2)
        c1.metric("Primeiro Ano", anos_rows[0]["primeiro_ano"])
        c2.metric("Último Ano", anos_rows[0]["ultimo_ano"])

    st.markdown("##### Desempenho por Ano e Circuito")
    df = to_dataframe(run_function("app_piloto_resumo", (piloto_id,)))
    st.dataframe(df, hide_index=True, width="stretch")

    if not df.empty:
        st.markdown("##### Pontos por Ano")
        st.line_chart(df.groupby("Ano")["Pontos"].sum())
