"""Carrega os CSVs na camada bronze do Postgres. E' aqui que o Python termina.

Tres regras que definem esta camada, e que valem mais que qualquer linha de codigo
deste arquivo:

1. Toda coluna entra como text. Nenhuma conversao, nenhuma validacao, nenhum
   descarte. Se o loader tipasse, a sujeira plantada pelo gerador (custo negativo,
   data invertida, FK orfa) explodiria na carga em vez de chegar na bronze para o
   teste do dbt encontrar. Tipagem e' trabalho da silver, em SQL.

2. Os nomes de coluna ficam como vieram, inclusive os do AI4I com espaco e
   colchete ("Air temperature [K]"). Renomear e' trabalho da staging, segundo a
   semana 2 do plano. Fazer isso aqui seria resolver em Python o que o projeto se
   propoe a resolver em dbt.

3. Recarregar e' idempotente: DROP e CREATE a cada execucao. Rodar duas vezes nao
   dobra linha nenhuma. O CASCADE derruba as views que a silver tiver criado em
   cima, e o `dbt run` seguinte as reconstroi, que e' o fluxo normal do projeto.
"""

import csv
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv
from psycopg import sql

RAIZ = Path(__file__).resolve().parent.parent
DIR_RAW = RAIZ / "data" / "raw"
DIR_SINTETICO = RAIZ / "data" / "sintetico"

SCHEMA = "bronze"

# Nome da tabela na bronze -> arquivo de origem. A fonte publica e o mundo
# sintetico entram lado a lado, em tabelas separadas, e so' se encontram na silver.
TABELAS = {
    "ai4i_leituras": DIR_RAW / "ai4i2020.csv",
    "leitura_contexto": DIR_SINTETICO / "leitura_contexto.csv",
    "ativos": DIR_SINTETICO / "ativos.csv",
    "locais": DIR_SINTETICO / "locais.csv",
    "tecnicos": DIR_SINTETICO / "tecnicos.csv",
    "ordens_servico": DIR_SINTETICO / "ordens_servico.csv",
    "mudancas_ativo": DIR_SINTETICO / "mudancas_ativo.csv",
}


def conectar() -> psycopg.Connection:
    """Conexao montada a partir do .env, nunca de credencial no codigo."""
    load_dotenv(RAIZ / ".env")
    faltando = [
        v
        for v in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD")
        if not os.getenv(v)
    ]
    if faltando:
        raise RuntimeError(
            f"faltam variaveis no .env: {', '.join(faltando)}.\n"
            "Copie o .env.example para .env e preencha."
        )
    return psycopg.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )


def _colunas(caminho: Path) -> list[str]:
    """Le so' o cabecalho. O conteudo quem le e' o COPY, direto do arquivo.

    O encoding e' utf-8-sig, e nao utf-8, por causa do BOM: o CSV do UCI comeca
    com os tres bytes EF BB BF, e com utf-8 puro eles grudam no nome da primeira
    coluna. A tabela nascia com uma coluna chamada "﻿UDI", invisivel na tela
    e obrigatoria em todo select da silver. Isso e' consertar leitura de arquivo,
    nao transformar dado: o conteudo das linhas continua intocado.
    """
    with caminho.open(newline="", encoding="utf-8-sig") as f:
        cabecalho = next(csv.reader(f))
    if not cabecalho:
        raise RuntimeError(f"{caminho.name} nao tem cabecalho")
    return cabecalho


def carregar_tabela(conn: psycopg.Connection, nome: str, caminho: Path) -> int:
    if not caminho.exists():
        raise RuntimeError(
            f"{caminho.relative_to(RAIZ)} nao existe. Rode `uv run seed` inteiro."
        )

    colunas = _colunas(caminho)
    ident = sql.Identifier(SCHEMA, nome)

    # Todas as colunas como text, mais duas de rastreio com DEFAULT. Com o DEFAULT
    # no DDL, o COPY nao precisa fornecer esses valores e o arquivo entra do jeito
    # que esta', sem ninguem montar linha em Python.
    definicao = sql.SQL(", ").join(
        sql.SQL("{} text").format(sql.Identifier(c)) for c in colunas
    )

    with conn.cursor() as cur:
        cur.execute(sql.SQL("DROP TABLE IF EXISTS {} CASCADE").format(ident))
        cur.execute(
            sql.SQL(
                "CREATE TABLE {} ({}, "
                "_carregado_em timestamptz NOT NULL DEFAULT now(), "
                "_arquivo_origem text NOT NULL DEFAULT {})"
            ).format(ident, definicao, sql.Literal(caminho.name))
        )

        copia = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT CSV, HEADER)").format(
            ident,
            sql.SQL(", ").join(sql.Identifier(c) for c in colunas),
        )
        # Streaming em blocos: o arquivo nunca e' carregado inteiro na memoria.
        # Hoje sao 522 KB e caberia com folga, mas o dia em que a fonte crescer
        # nao deveria exigir reescrever o loader.
        with cur.copy(copia) as copy, caminho.open("rb") as f:
            while bloco := f.read(1024 * 64):
                copy.write(bloco)

        cur.execute(sql.SQL("SELECT count(*) FROM {}").format(ident))
        return cur.fetchone()[0]


def carregar_tudo() -> dict[str, int]:
    contagens = {}
    with conectar() as conn:
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("CREATE SCHEMA IF NOT EXISTS {}").format(sql.Identifier(SCHEMA))
            )
        for nome, caminho in TABELAS.items():
            contagens[nome] = carregar_tabela(conn, nome, caminho)
            print(f"  {SCHEMA}.{nome:20} {contagens[nome]:6} linhas")
        # Uma transacao so' para as sete tabelas: ou a bronze inteira troca, ou
        # nada troca. Bronze meio velha e meio nova daria resultado que ninguem
        # consegue reproduzir depois.
        conn.commit()
    return contagens


def main() -> int:
    print("carregando a bronze:")
    carregar_tudo()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
