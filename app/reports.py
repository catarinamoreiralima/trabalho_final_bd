"""
Tela 3 - Relatorios.

Lista somente os relatorios disponiveis para o tipo de usuario logado. Ao escolher um, executa
a funcao correspondente e mostra o resultado; o botao "Voltar a lista de relatorios" retorna a
Tela 3 (lista), como pede o enunciado.
"""
import streamlit as st

from db import run_function
from labels import to_dataframe

REPORTS_BY_TYPE = {
    "Admin": ["1", "2", "3"],
    "Escuderia": ["4", "5"],
    "Piloto": ["6", "7"],
}

REPORT_TITLES = {
    "1": "Relatório 1 — Resultados por Status",
    "2": "Relatório 2 — Aeroportos Próximos a uma Cidade",
    "3": "Relatório 3 — Escuderias e Corridas (Hierárquico)",
    "4": "Relatório 4 — Vitórias por Piloto",
    "5": "Relatório 5 — Resultados por Status (Escuderia)",
    "6": "Relatório 6 — Pontos por Ano",
    "7": "Relatório 7 — Resultados por Status (Piloto)",
}


def render_reports(user):
    st.subheader("Relatórios")

    selecionado = st.session_state.get("relatorio_selecionado")
    if selecionado is None:
        _render_lista(user)
    else:
        _render_relatorio(user, selecionado)

    st.divider()
    if st.button("Voltar ao Dashboard"):
        st.session_state["relatorio_selecionado"] = None
        st.session_state["screen"] = "dashboard"
        st.rerun()


def _render_lista(user):
    for codigo in REPORTS_BY_TYPE[user["tipo"]]:
        if st.button(REPORT_TITLES[codigo], key=f"abrir_relatorio_{codigo}", width="stretch"):
            st.session_state["relatorio_selecionado"] = codigo
            st.rerun()


def _render_relatorio(user, codigo):
    st.markdown(f"### {REPORT_TITLES[codigo]}")

    if st.button("← Voltar à lista de relatórios"):
        st.session_state["relatorio_selecionado"] = None
        st.rerun()

    relatorios = {
        "1": lambda: _relatorio_1(),
        "2": lambda: _relatorio_2(),
        "3": lambda: _relatorio_3(),
        "4": lambda: _relatorio_4(user["id_original"]),
        "5": lambda: _relatorio_5(user["id_original"]),
        "6": lambda: _relatorio_6(user["id_original"]),
        "7": lambda: _relatorio_7(user["id_original"]),
    }
    relatorios[codigo]()


def _relatorio_1():
    # FUNCAO: app_admin_relatorio_status_resultados - JOIN results/status + COUNT + GROUP BY
    dados = run_function("app_admin_relatorio_status_resultados")
    st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")


def _relatorio_2():
    cidade = st.text_input("Nome da cidade brasileira", key="relatorio_2_cidade")
    if not cidade:
        st.info("Informe o nome de uma cidade para buscar aeroportos próximos (até 100 km).")
        return
    # FUNCAO: app_admin_relatorio_aeroportos_por_cidade - earth_distance/ll_to_earth (cube/earthdistance)
    dados = run_function("app_admin_relatorio_aeroportos_por_cidade", (cidade,))
    if not dados:
        st.info("Nenhum aeroporto medium/large encontrado a até 100 km dessa cidade.")
    else:
        st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")


def _relatorio_3():
    st.markdown("##### Escuderias e Quantidade de Pilotos")
    # FUNCAO: app_admin_relatorio_3_escuderias_pilotos
    parte_a = run_function("app_admin_relatorio_3_escuderias_pilotos")
    st.dataframe(to_dataframe(parte_a), hide_index=True, width="stretch")

    st.markdown("##### Relatório Hierárquico de Corridas")
    # FUNCAO: app_admin_relatorio_3_hierarquico_corridas - 3 niveis: total, por circuito, por corrida
    hierarquico = run_function("app_admin_relatorio_3_hierarquico_corridas")
    nivel1 = [r for r in hierarquico if r["nivel"] == 1]
    nivel2 = [r for r in hierarquico if r["nivel"] == 2]
    nivel3 = [r for r in hierarquico if r["nivel"] == 3]

    # Nivel 1 - total geral de corridas
    if nivel1:
        st.metric("Total de Corridas Cadastradas", nivel1[0]["quantidade_corridas"])

    # Niveis 2 e 3 em drill-down: cada circuito (nivel 2) vira um expander clicavel; ao abrir,
    # mostra embaixo as corridas daquele circuito (nivel 3). A coluna "nivel" nao e exibida -
    # ela so organiza a hierarquia internamente. Os dados do nivel 3 ja vieram na mesma consulta,
    # entao o filtro por circuito e feito em memoria, sem nova ida ao banco.
    st.markdown("**Resumo por Circuito** (clique para ver as corridas)")
    for circ in nivel2:
        titulo = (
            f"{circ['circuito']} — {circ['quantidade_corridas']} corrida(s)  ·  "
            f"voltas: mín {circ['minimo_voltas']} / méd {circ['media_voltas']} / máx {circ['maximo_voltas']}"
        )
        with st.expander(titulo):
            detalhe = [
                {
                    "ano": r["ano"],
                    "rodada": r["rodada"],
                    "corrida": r["corrida"],
                    "voltas_registradas": r["voltas_registradas"],
                    "quantidade_pilotos": r["quantidade_pilotos"],
                }
                for r in nivel3
                if r["circuito"] == circ["circuito"]
            ]
            st.dataframe(to_dataframe(detalhe), hide_index=True, width="stretch")


def _relatorio_4(escuderia_id):
    # FUNCAO: app_escuderia_relatorio_4 - vitorias por piloto, escopo da escuderia logada
    dados = run_function("app_escuderia_relatorio_4", (escuderia_id,))
    st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")


def _relatorio_5(escuderia_id):
    # FUNCAO: app_escuderia_relatorio_5 - resultados por status, escopo da escuderia logada
    dados = run_function("app_escuderia_relatorio_5", (escuderia_id,))
    st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")


def _relatorio_6(piloto_id):
    # FUNCAO: app_piloto_relatorio_6 - pontos totais por ano, escopo do piloto logado
    dados = run_function("app_piloto_relatorio_6", (piloto_id,))
    st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")


def _relatorio_7(piloto_id):
    # FUNCAO: app_piloto_relatorio_7 - resultados por status, escopo do piloto logado
    dados = run_function("app_piloto_relatorio_7", (piloto_id,))
    st.dataframe(to_dataframe(dados), hide_index=True, width="stretch")
