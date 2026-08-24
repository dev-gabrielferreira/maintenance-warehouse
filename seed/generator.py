"""Gera o mundo sintetico em volta do AI4I: parque, locais, tempo, equipe e OS.

O AI4I tem sensor e falha, e mais nada: nem maquina, nem data, nem manutencao
(ver docs/fonte-ai4i.md). Sem esse mundo em volta nao existe dimensao, nao existe
MTBF e nao existe SCD2 para capturar.

Duas regras que este modulo respeita e que vale nao quebrar depois:

1. O CSV do AI4I nao e' tocado. A atribuicao de leitura a maquina e a instante sai
   em leitura_contexto.csv, chaveada pelo UDI. O join entre a fonte publica e a
   invencao nossa acontece em SQL, na silver, onde da' para auditar. Carimbar
   coluna no arquivo original apagaria a fronteira entre dado e suposicao.

2. Tudo sai de um unico random.Random(SEMENTE). Nada de random global, nada de
   datetime.now(). Rodar duas vezes tem que dar byte a byte o mesmo arquivo, senao
   o "reproduzivel em qualquer maquina" do criterio de aceite e' so' uma frase.
"""

import random
from datetime import date, datetime, timedelta
from pathlib import Path

import pandas as pd

from seed import download

SEMENTE = 20200101

RAIZ = Path(__file__).resolve().parent.parent
DIR_SAIDA = RAIZ / "data" / "sintetico"

# --- parque -----------------------------------------------------------------
# 80 maquinas, com a mesma proporcao de tipo que o AI4I tem de pecas: L 60%,
# M 30%, H 10%. Maquina tem tipo fixo, e leitura de um tipo so' cai em maquina
# daquele tipo. Uma fresadora H nao passa a produzir peca L no meio do arquivo.
N_MAQUINAS = {"L": 48, "M": 24, "H": 8}

FABRICANTES = ["Romi", "Mazak", "DMG Mori", "Haas", "Okuma"]

SETORES = [
    ("USI", "Usinagem"),
    ("MON", "Montagem"),
    ("ACB", "Acabamento"),
    ("FER", "Ferramentaria"),
    ("EXP", "Expedicao"),
]
LINHAS_POR_SETOR = {"USI": 4, "MON": 3, "ACB": 2, "FER": 2, "EXP": 1}

# Criticidade segue o tipo, mas nao de forma rigida: maquina H tende a ser critica
# porque roda peca de tolerancia apertada, e L tende a ser media ou baixa.
PESO_CRITICIDADE = {
    "H": {"alta": 0.75, "media": 0.20, "baixa": 0.05},
    "M": {"alta": 0.30, "media": 0.55, "baixa": 0.15},
    "L": {"alta": 0.10, "media": 0.45, "baixa": 0.45},
}

# --- tempo ------------------------------------------------------------------
DATA_INICIO = date(2024, 1, 1)
MESES_OPERACAO = 24
# Tres turnos de 8 horas. Domingo nao tem producao, e e' o que faz "dia util"
# virar coluna com significado na dim_tempo em vez de enfeite.
TURNOS = [(6, "manha"), (14, "tarde"), (22, "noite")]

# --- equipe -----------------------------------------------------------------
ESPECIALIDADES = ["mecanica", "eletrica", "preditiva"]
# Custo hora por especialidade, em reais. Preditiva custa mais porque envolve
# instrumento e laudo.
CUSTO_HORA = {"mecanica": 62.0, "eletrica": 71.0, "preditiva": 88.0}
N_TECNICOS = 12

# --- manutencao -------------------------------------------------------------
# Duracao do reparo por modo, em horas, calibrada com o Gabriel: HDF e PWF sao
# limpeza de trocador e reset de acionamento, resolvem no turno. OSF e TWF
# envolvem troca de componente e espera de peca.
DURACAO_POR_MODO = {
    "HDF": (2.0, 6.0),
    "PWF": (2.0, 6.0),
    "OSF": (4.0, 16.0),
    "TWF": (4.0, 16.0),
    "RNF": (1.0, 3.0),
    # Falha declarada pelo AI4I sem nenhum modo marcado: 9 linhas reais da fonte.
    # Sem diagnostico, a equipe investiga, e investigacao demora.
    "INDETERMINADO": (3.0, 12.0),
}

# Custo de peca por modo, em reais.
PECAS_POR_MODO = {
    "HDF": (120.0, 1200.0),
    "PWF": (150.0, 1400.0),
    "OSF": (800.0, 5200.0),
    "TWF": (600.0, 3800.0),
    "RNF": (50.0, 420.0),
    "INDETERMINADO": (100.0, 2000.0),
}

MODOS = ["TWF", "HDF", "PWF", "OSF", "RNF"]

# Plano preventivo: uma parada a cada 90 dias por maquina. A aderencia nao e' de
# 100% de proposito: sem preventiva atrasada nao ha' o que comparar na pergunta
# "preventiva em dia reduz corretiva no trimestre seguinte".
INTERVALO_PREVENTIVA_DIAS = 90
ADERENCIA_PREVENTIVA = 0.85

# --- sujeira ----------------------------------------------------------------
# Quantidades pequenas e conhecidas. Cada uma existe para um teste especifico da
# semana 2 ter o que pegar. O numero fica aqui, no topo, para o README poder dizer
# "sao 200 duplicatas" sem ninguem precisar contar.
FRACAO_LEITURAS_DUPLICADAS = 0.02
N_OS_ORFAS = 8
N_OS_TECNICO_INEXISTENTE = 5
N_OS_CUSTO_NEGATIVO = 10
N_OS_DATAS_INVERTIDAS = 10
N_ATIVOS_INSTALACAO_FUTURA = 5


def _dias_uteis(inicio: date, meses: int) -> list[date]:
    """Todos os dias do periodo menos domingo."""
    fim = inicio + timedelta(days=int(meses * 30.44))
    dias = []
    d = inicio
    while d < fim:
        if d.weekday() != 6:
            dias.append(d)
        d += timedelta(days=1)
    return dias


def gerar_locais() -> pd.DataFrame:
    linhas = []
    for cod_setor, nome_setor in SETORES:
        for i in range(1, LINHAS_POR_SETOR[cod_setor] + 1):
            linhas.append(
                {
                    "codigo_linha": f"{cod_setor}-L{i:02d}",
                    "codigo_setor": cod_setor,
                    "nome_setor": nome_setor,
                    "planta": "Planta Sorocaba",
                }
            )
    return pd.DataFrame(linhas)


def gerar_ativos(rng: random.Random, locais: pd.DataFrame) -> pd.DataFrame:
    codigos_linha = locais["codigo_linha"].tolist()
    ativos = []
    n = 0
    for tipo, quantidade in N_MAQUINAS.items():
        for _ in range(quantidade):
            n += 1
            pesos = PESO_CRITICIDADE[tipo]
            criticidade = rng.choices(
                list(pesos.keys()), weights=list(pesos.values()), k=1
            )[0]
            # Instalacao entre 8 e 1 anos antes do inicio da operacao observada.
            dias_antes = rng.randint(365, 365 * 8)
            ativos.append(
                {
                    "codigo_ativo": f"MAQ-{n:03d}",
                    "tipo": tipo,
                    "fabricante": rng.choice(FABRICANTES),
                    "codigo_linha": rng.choice(codigos_linha),
                    "criticidade": criticidade,
                    "data_instalacao": (DATA_INICIO - timedelta(days=dias_antes)).isoformat(),
                    "estado": "operando",
                }
            )
    rng.shuffle(ativos)
    return pd.DataFrame(ativos)


def gerar_tecnicos(rng: random.Random) -> pd.DataFrame:
    nomes = [
        "Adriano Souza", "Beatriz Lima", "Carlos Menezes", "Daniela Rocha",
        "Eduardo Prado", "Fernanda Alves", "Gilberto Nunes", "Helena Castro",
        "Igor Ramalho", "Juliana Barros", "Kleber Antunes", "Larissa Pinto",
    ]
    turnos = [t[1] for t in TURNOS]
    tecnicos = []
    for i, nome in enumerate(nomes[:N_TECNICOS], start=1):
        especialidade = ESPECIALIDADES[i % len(ESPECIALIDADES)]
        tecnicos.append(
            {
                "matricula": f"TEC-{i:03d}",
                "nome": nome,
                "especialidade": especialidade,
                "turno": turnos[i % len(turnos)],
                "custo_hora": CUSTO_HORA[especialidade],
            }
        )
    return pd.DataFrame(tecnicos)


def _pesos_desbalanceados(rng: random.Random, n: int) -> list[float]:
    """Carga de uso concentrada numa minoria, como em chao de fabrica de verdade.

    Uma curva 1/rank: a maquina gargalo roda direto, a ultima da fila complementa.
    Sem isso o MTBF sai igual em todas e as perguntas por setor ficam sem contraste.
    """
    pesos = [1.0 / ((i + 1) ** 0.8) for i in range(n)]
    rng.shuffle(pesos)
    return pesos


def gerar_leitura_contexto(
    rng: random.Random, ai4i: pd.DataFrame, ativos: pd.DataFrame
) -> pd.DataFrame:
    """Para cada UDI do AI4I, diz em qual maquina e em qual instante ele aconteceu.

    E' a tabela que costura a fonte publica ao mundo sintetico, e o motivo de ela
    existir separada esta' no docstring do modulo.
    """
    dias = _dias_uteis(DATA_INICIO, MESES_OPERACAO)
    slots = [(d, h, nome) for d in dias for h, nome in TURNOS]

    # Uma fila de maquinas por tipo, com peso desbalanceado dentro de cada tipo.
    por_tipo = {}
    for tipo in N_MAQUINAS:
        candidatos = ativos.loc[ativos["tipo"] == tipo, "codigo_ativo"].tolist()
        por_tipo[tipo] = (candidatos, _pesos_desbalanceados(rng, len(candidatos)))

    total = len(ai4i)
    linhas = []
    for pos, (udi, tipo) in enumerate(zip(ai4i["UDI"], ai4i["Type"])):
        # O UDI e' sequencial e sem buraco, entao ele vira a ordem cronologica:
        # leitura 1 e' a mais antiga, leitura 10000 a mais recente.
        dia, hora_turno, nome_turno = slots[pos * len(slots) // total]
        instante = datetime(dia.year, dia.month, dia.day, hora_turno) + timedelta(
            minutes=rng.randint(0, 479)
        )
        candidatos, pesos = por_tipo[tipo]
        linhas.append(
            {
                "udi": int(udi),
                "codigo_ativo": rng.choices(candidatos, weights=pesos, k=1)[0],
                "instante": instante.isoformat(sep=" "),
                "turno": nome_turno,
            }
        )
    return pd.DataFrame(linhas)


def _modo_da_linha(linha) -> str:
    """Qual modo explica a falha desta leitura.

    Quando mais de um esta' marcado, vence o de maior duracao de reparo, porque e'
    ele que determina quanto tempo a maquina fica parada. As 24 leituras com mais
    de um modo continuam com todos eles no fato: esta escolha e' so' para dar
    duracao e custo a OS. A modelagem do multiplo e' assunto da semana 3.
    """
    marcados = [m for m in MODOS if linha[m] == 1]
    if not marcados:
        return "INDETERMINADO"
    return max(marcados, key=lambda m: DURACAO_POR_MODO[m][1])


def gerar_ordens_servico(
    rng: random.Random,
    ai4i: pd.DataFrame,
    contexto: pd.DataFrame,
    ativos: pd.DataFrame,
    tecnicos: pd.DataFrame,
) -> pd.DataFrame:
    ctx = contexto.set_index("udi")
    matriculas = tecnicos["matricula"].tolist()
    custo_hora = dict(zip(tecnicos["matricula"], tecnicos["custo_hora"]))

    ordens = []
    n = 0

    # --- corretivas: nascem das falhas do AI4I ---
    # O criterio e' a uniao: Machine failure ligada OU algum modo marcado. Isso
    # preserva as duas incoerencias da fonte (9 falhas sem modo, 18 RNF que nao
    # contam como falha) em vez de escolher uma definicao aqui. Escolher e' assunto
    # da gold, e a bronze nao e' lugar de esconder divergencia da fonte.
    falhou = (ai4i["Machine failure"] == 1) | (ai4i[MODOS].sum(axis=1) > 0)
    for _, linha in ai4i[falhou].iterrows():
        n += 1
        udi = int(linha["UDI"])
        modo = _modo_da_linha(linha)
        instante = datetime.fromisoformat(ctx.loc[udi, "instante"])

        dur_min, dur_max = DURACAO_POR_MODO[modo]
        duracao_h = round(rng.uniform(dur_min, dur_max), 2)
        # A equipe nao chega no instante da falha: ha' deteccao, chamado e
        # deslocamento pelo meio.
        abertura = instante + timedelta(minutes=rng.randint(5, 180))
        conclusao = abertura + timedelta(hours=duracao_h)

        matricula = rng.choice(matriculas)
        peca_min, peca_max = PECAS_POR_MODO[modo]
        custo_pecas = round(rng.uniform(peca_min, peca_max), 2)
        custo_mo = round(duracao_h * custo_hora[matricula], 2)

        ordens.append(
            {
                "numero_os": f"OS-{n:05d}",
                "codigo_ativo": ctx.loc[udi, "codigo_ativo"],
                "tipo_os": "corretiva",
                "modo_falha": modo,
                "udi_origem": udi,
                "data_abertura": abertura.isoformat(sep=" "),
                "data_conclusao": conclusao.isoformat(sep=" "),
                "matricula_tecnico": matricula,
                "duracao_horas": duracao_h,
                "custo_mao_obra": custo_mo,
                "custo_pecas": custo_pecas,
            }
        )

    # --- preventivas: por plano, a cada 90 dias ---
    fim = DATA_INICIO + timedelta(days=int(MESES_OPERACAO * 30.44))
    for codigo in ativos["codigo_ativo"]:
        # Primeira parada em ponto aleatorio do primeiro ciclo, senao o parque
        # inteiro para no mesmo dia.
        planejada = DATA_INICIO + timedelta(days=rng.randint(0, INTERVALO_PREVENTIVA_DIAS))
        while planejada < fim:
            n += 1
            if rng.random() < ADERENCIA_PREVENTIVA:
                atraso = rng.randint(0, 7)
                realizada = planejada + timedelta(days=atraso)
            else:
                # Fora da aderencia: ou atrasa muito, ou nao acontece. Preventiva
                # nao executada fica com conclusao vazia, e e' isso que a pergunta
                # de negocio da semana 4 vai medir.
                if rng.random() < 0.35:
                    realizada = None
                else:
                    realizada = planejada + timedelta(days=rng.randint(15, 60))

            duracao_h = round(rng.uniform(1.5, 5.0), 2)
            matricula = rng.choice(matriculas)
            abertura = datetime(
                planejada.year, planejada.month, planejada.day, rng.choice([6, 14, 22])
            )
            if realizada is None:
                conclusao_txt = ""
                custo_mo = 0.0
                custo_pecas = 0.0
                duracao_h = 0.0
            else:
                # A conclusao sai da abertura mais o atraso, e nunca de um horario
                # sorteado por conta propria. Sorteando os dois lados em separado,
                # uma preventiva realizada no mesmo dia podia abrir 22h e concluir
                # 6h, terminando antes de comecar. Eram 22 OS assim, sujeira que
                # ninguem escolheu injetar e que o README descreveria errado.
                dias_atraso = (realizada - planejada).days
                conclusao = abertura + timedelta(days=dias_atraso, hours=duracao_h)
                conclusao_txt = conclusao.isoformat(sep=" ")
                custo_mo = round(duracao_h * custo_hora[matricula], 2)
                custo_pecas = round(rng.uniform(80.0, 900.0), 2)

            ordens.append(
                {
                    "numero_os": f"OS-{n:05d}",
                    "codigo_ativo": codigo,
                    "tipo_os": "preventiva",
                    "modo_falha": "",
                    "udi_origem": "",
                    "data_abertura": abertura.isoformat(sep=" "),
                    "data_conclusao": conclusao_txt,
                    "matricula_tecnico": matricula,
                    "duracao_horas": duracao_h,
                    "custo_mao_obra": custo_mo,
                    "custo_pecas": custo_pecas,
                }
            )
            planejada += timedelta(days=INTERVALO_PREVENTIVA_DIAS)

    return pd.DataFrame(ordens).sort_values("data_abertura").reset_index(drop=True)


def gerar_mudancas_ativo(rng: random.Random, ativos: pd.DataFrame, locais: pd.DataFrame) -> pd.DataFrame:
    """O que a SCD2 vai capturar.

    Sem estas linhas o snapshot rodaria e nao acharia nada para versionar, e a
    pergunta "o custo caiu depois da reforma?" nao teria como ser respondida.
    """
    fim = DATA_INICIO + timedelta(days=int(MESES_OPERACAO * 30.44))
    total_dias = (fim - DATA_INICIO).days
    codigos = ativos["codigo_ativo"].tolist()
    codigos_linha = locais["codigo_linha"].tolist()

    mudancas = []
    plano = (
        [("transferencia", 15)] + [("reclassificacao", 10)] + [("reforma", 6)]
    )
    for tipo, quantidade in plano:
        for _ in range(quantidade):
            codigo = rng.choice(codigos)
            # Nunca no primeiro nem no ultimo mes: a mudanca precisa ter passado e
            # futuro dentro da janela observada para o antes e depois existir.
            dia = DATA_INICIO + timedelta(days=rng.randint(60, total_dias - 60))
            if tipo == "transferencia":
                campo, valor = "codigo_linha", rng.choice(codigos_linha)
            elif tipo == "reclassificacao":
                campo, valor = "criticidade", rng.choice(["alta", "media", "baixa"])
            else:
                campo, valor = "estado", "reformado"
            mudancas.append(
                {
                    "codigo_ativo": codigo,
                    "data_mudanca": dia.isoformat(),
                    "campo": campo,
                    "valor_novo": valor,
                    "motivo": tipo,
                }
            )
    return pd.DataFrame(mudancas).sort_values("data_mudanca").reset_index(drop=True)


def injetar_sujeira(
    rng: random.Random,
    contexto: pd.DataFrame,
    ordens: pd.DataFrame,
    ativos: pd.DataFrame,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Estraga o dado de proposito, em quantidade conhecida.

    Cada item aqui existe para um teste da semana 2 ter o que pegar. Teste que
    nunca falha nao demonstra nada, e a prova de que estes pegam e' desligar a
    limpeza da silver e ver o build quebrar.
    """
    # 1. Leituras duplicadas: o mesmo UDI aparecendo duas vezes quebra o unique.
    n_dup = int(len(contexto) * FRACAO_LEITURAS_DUPLICADAS)
    idx = rng.sample(range(len(contexto)), n_dup)
    contexto = pd.concat([contexto, contexto.iloc[idx]], ignore_index=True)

    ordens = ordens.copy()
    disponiveis = list(range(len(ordens)))

    def _sortear(quantidade: int) -> list[int]:
        escolhidos = rng.sample(disponiveis, quantidade)
        for i in escolhidos:
            disponiveis.remove(i)
        return escolhidos

    # 2. OS orfa: aponta para ativo que nao existe. Quebra o relationships.
    for i in _sortear(N_OS_ORFAS):
        ordens.loc[i, "codigo_ativo"] = f"MAQ-{rng.randint(900, 999)}"

    # 3. OS com tecnico inexistente: mesma ideia, outra FK.
    for i in _sortear(N_OS_TECNICO_INEXISTENTE):
        ordens.loc[i, "matricula_tecnico"] = f"TEC-{rng.randint(900, 999)}"

    # 4. Custo negativo: quebra o teste de regra de negocio da semana 3.
    for i in _sortear(N_OS_CUSTO_NEGATIVO):
        ordens.loc[i, "custo_pecas"] = -abs(ordens.loc[i, "custo_pecas"])

    # 5. Conclusao antes da abertura: idem, e e' o erro de digitacao mais comum
    #    em sistema de manutencao de verdade.
    for i in _sortear(N_OS_DATAS_INVERTIDAS):
        abertura = ordens.loc[i, "data_abertura"]
        conclusao = ordens.loc[i, "data_conclusao"]
        if conclusao:
            ordens.loc[i, "data_abertura"] = conclusao
            ordens.loc[i, "data_conclusao"] = abertura

    # 6. Ativo instalado depois da primeira leitura dele.
    ativos = ativos.copy()
    for i in rng.sample(range(len(ativos)), N_ATIVOS_INSTALACAO_FUTURA):
        ativos.loc[i, "data_instalacao"] = (
            DATA_INICIO + timedelta(days=rng.randint(30, 400))
        ).isoformat()

    return contexto, ordens, ativos


def gerar(sem_sujeira: bool = False) -> dict[str, Path]:
    rng = random.Random(SEMENTE)
    DIR_SAIDA.mkdir(parents=True, exist_ok=True)

    ai4i = pd.read_csv(download.garantir_csv())

    locais = gerar_locais()
    ativos = gerar_ativos(rng, locais)
    tecnicos = gerar_tecnicos(rng)
    contexto = gerar_leitura_contexto(rng, ai4i, ativos)
    ordens = gerar_ordens_servico(rng, ai4i, contexto, ativos, tecnicos)
    mudancas = gerar_mudancas_ativo(rng, ativos, locais)

    if not sem_sujeira:
        contexto, ordens, ativos = injetar_sujeira(rng, contexto, ordens, ativos)

    tabelas = {
        "locais": locais,
        "ativos": ativos,
        "tecnicos": tecnicos,
        "leitura_contexto": contexto,
        "ordens_servico": ordens,
        "mudancas_ativo": mudancas,
    }

    escritos = {}
    for nome, df in tabelas.items():
        caminho = DIR_SAIDA / f"{nome}.csv"
        df.to_csv(caminho, index=False)
        escritos[nome] = caminho
        print(f"  {nome:20} {len(df):6} linhas -> {caminho.relative_to(RAIZ)}")

    if sem_sujeira:
        print("  (gerado sem sujeira injetada)")
    return escritos


def main(sem_sujeira: bool = False) -> int:
    print("gerando o mundo sintetico:")
    gerar(sem_sujeira=sem_sujeira)
    return 0


if __name__ == "__main__":
    import sys

    raise SystemExit(main(sem_sujeira="--sem-sujeira" in sys.argv))
