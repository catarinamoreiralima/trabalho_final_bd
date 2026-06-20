"""
Telas de Visao Geral (dashboard) e de Acoes/Cadastros.

- render_dashboard: informacoes resumidas do tipo de usuario logado (a "Visao Geral" do menu).
- render_acoes: formularios de cadastro/consulta/importacao (a pagina "Cadastros"/"Acoes" do menu).

A navegacao entre essas paginas e o logout ficam no menu lateral, em main.py.
"""
import altair as alt
import streamlit as st

import actions
from db import run_function
from labels import to_dataframe


# ============================================================================================
# GRAFICOS ESTATICOS
#
# Os graficos nativos (st.bar_chart / st.line_chart) permitem zoom e arraste pelo usuario.
# Para evitar esse comportamento, montamos os graficos com Altair SEM chamar .interactive():
# por padrao um grafico Altair nao tem pan/zoom. Mantemos so o tooltip ao passar o mouse.
# ============================================================================================
def _grafico_barras(df, coluna_categoria, coluna_valor):
    chart = (
        alt.Chart(df)
        .mark_bar()
        .encode(
            x=alt.X(f"{coluna_categoria}:N", sort="-y", title=coluna_categoria),
            y=alt.Y(f"{coluna_valor}:Q", title=coluna_valor),
            tooltip=list(df.columns),
        )
        .properties(width="container", height=300)
    )
    st.altair_chart(chart)


def _grafico_linha(df, coluna_x, coluna_y):
    chart = (
        alt.Chart(df)
        .mark_line(point=True)
        .encode(
            x=alt.X(f"{coluna_x}:O", title=coluna_x),
            y=alt.Y(f"{coluna_y}:Q", title=coluna_y),
            tooltip=[coluna_x, coluna_y],
        )
        .properties(width="container", height=300)
    )
    st.altair_chart(chart)


# ============================================================================================
# VISAO GERAL (dashboard)
# ============================================================================================
def render_dashboard(user):
    st.subheader("Visão Geral")

    if user["tipo"] == "Admin":
        _render_admin(user)
    elif user["tipo"] == "Escuderia":
        _render_escuderia(user)
    else:
        _render_piloto(user)


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
            _grafico_barras(df_esc, "Escuderia", "Total de Pontos")
    with col2:
        st.markdown("##### Pilotos - Pontos na Temporada")
        df_pil = to_dataframe(run_function("app_admin_pilotos_temporada_mais_recente"))
        st.dataframe(df_pil, hide_index=True, width="stretch")
        if not df_pil.empty:
            _grafico_barras(df_pil, "Piloto", "Total de Pontos")


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
        pontos_ano = df.groupby("Ano", as_index=False)["Pontos"].sum()
        _grafico_linha(pontos_ano, "Ano", "Pontos")


# ============================================================================================
# ACOES / CADASTROS
# ============================================================================================
def render_acoes(user):
    if user["tipo"] == "Admin":
        st.subheader("Cadastros")
        st.markdown("##### ➕ Cadastrar Escuderia")
        actions.form_cadastrar_escuderia()
        st.divider()
        st.markdown("##### ➕ Cadastrar Piloto")
        actions.form_cadastrar_piloto()

    elif user["tipo"] == "Escuderia":
        st.subheader("Ações")
        escuderia_id = user["id_original"]
        st.markdown("##### 🔍 Consultar Piloto por Sobrenome")
        actions.form_consultar_piloto_por_sobrenome(escuderia_id)
        st.divider()
        st.markdown("##### 📂 Importar Pilotos por Arquivo")
        actions.form_importar_pilotos(escuderia_id)

    else:
        # Piloto e somente leitura: nao deveria chegar aqui (sem opcao no menu), mas garantimos.
        st.info("Usuários do tipo Piloto não possuem ações de cadastro.")
