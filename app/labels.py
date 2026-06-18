"""
Traducao dos aliases de coluna retornados pelas funcoes SQL para rotulos legiveis em
portugues, usados nas tabelas de dashboard e relatorios.
"""
from decimal import Decimal

import pandas as pd

COLUMN_LABELS = {
    "total_pilotos": "Total de Pilotos",
    "total_escuderias": "Total de Escuderias",
    "total_temporadas": "Total de Temporadas",
    "temporada_mais_recente": "Temporada Mais Recente",
    "temporada": "Temporada",
    "rodada": "Rodada",
    "corrida": "Corrida",
    "circuito": "Circuito",
    "data_corrida": "Data",
    "horario_corrida": "Horário",
    "voltas_registradas": "Voltas Registradas",
    "escuderia": "Escuderia",
    "piloto": "Piloto",
    "total_pontos": "Total de Pontos",
    "piloto_nome": "Nome",
    "piloto_sobrenome": "Sobrenome",
    "primeiro_ano": "Primeiro Ano",
    "ultimo_ano": "Último Ano",
    "ano": "Ano",
    "pontos": "Pontos",
    "vitorias": "Vitórias",
    "corridas_disputadas": "Corridas Disputadas",
    "escuderia_nome": "Escuderia",
    "quantidade_pilotos": "Quantidade de Pilotos",
    "quantidade_vitorias": "Vitórias",
    "status_corrida": "Status",
    "quantidade_resultados": "Quantidade de Resultados",
    "nome_cidade": "Cidade Pesquisada",
    "codigo_iata": "Código IATA",
    "nome_aeroporto": "Aeroporto",
    "cidade_aeroporto": "Cidade do Aeroporto",
    "distancia_km": "Distância (km)",
    "tipo_aeroporto": "Tipo de Aeroporto",
    "nivel": "Nível",
    "descricao_nivel": "Descrição",
    "quantidade_corridas": "Quantidade de Corridas",
    "minimo_voltas": "Mín. Voltas",
    "media_voltas": "Média de Voltas",
    "maximo_voltas": "Máx. Voltas",
    "nome_piloto": "Piloto",
    "ano_participacao": "Ano",
    "quantidade_total_pontos": "Pontos no Ano",
    "corridas_pontuadas": "Corridas com Pontos",
    "piloto_id": "ID do Piloto",
    "nome_completo": "Nome Completo",
    "data_nascimento": "Data de Nascimento",
    "pais": "País",
    "origem": "Origem do Vínculo",
    "vinculo_criado_em": "Vínculo Criado em",
    "escuderia_id": "ID da Escuderia",
    "login_usuario": "Login Criado",
    "total_linhas": "Linhas no Arquivo",
    "pilotos_inseridos": "Pilotos Inseridos",
    "vinculos_criados": "Vínculos Criados",
    "linhas_invalidas": "Linhas Rejeitadas",
}


def to_dataframe(rows):
    """Converte uma lista de dicts (retorno de db.run_query/run_function) em DataFrame com
    colunas renomeadas para rótulos em português, prontos para st.dataframe."""
    df = pd.DataFrame(rows)
    if df.empty:
        return df

    # NUMERIC(10,2) do Postgres chega como Decimal; convertido para float para que
    # st.bar_chart/st.line_chart (Altair) consigam plotar a coluna como eixo numérico.
    for col in df.columns:
        if df[col].map(lambda v: isinstance(v, Decimal)).any():
            df[col] = df[col].astype(float)

    return df.rename(columns=lambda col: COLUMN_LABELS.get(col, col.replace("_", " ").title()))
