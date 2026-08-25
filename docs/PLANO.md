# Plano de execução — maintenance-warehouse

Projeto P2 da trilha de portfólio. Este arquivo vive em `docs/PLANO.md` e guia o desenvolvimento; o Claude Code deve segui-lo na ordem, junto com o contrato do `CLAUDE.md` na raiz. Escrito após a conclusão do P1 (energy-load-etl, em produção em energia.gabrielfdev.com).

## 1. O que vamos construir

No P1 o pipeline morava todo em Python. No P2 a transformação muda de casa: Python só carrega o dado bruto no PostgreSQL, e dali em diante tudo é SQL versionado, testado e documentado com dbt, nas três camadas do medalhão. A gold é um star schema de manutenção industrial: fatos de leituras de sensores e ordens de serviço, dimensões de ativo, local, tempo, modo de falha e técnico, com dim_ativo em SCD tipo 2 registrando como os ativos mudam no tempo.

Fluxo: `AI4I 2020 (10k leituras) + gerador sintético seedado (ativos, calendário, OS)` → `loader Python` → `bronze (Postgres)` → `dbt staging (silver)` → `dbt marts (gold: star schema)` → `consultas de negócio + dbt docs/lineage`. dbt test roda sobre silver e gold; o que não passa barra o build.

A fronteira que o projeto ensina: Python termina na bronze. A ausência de um transform.py é a tese do projeto.

## 2. Antes da semana 1: fechar o P1

Pendências do P1 vêm antes do primeiro commit do P2: doc estendida no Notion e post de lançamento em carrossel (achados prontos: 368 horas de horário de verão, blecautes, Copa, anomalia do Norte em 2020). Dois ou três dias. O primeiro commit do maintenance-warehouse só acontece com o post do P1 no ar.

## 3. Decisões já tomadas

| Decisão | Escolha | Por quê (alternativa rejeitada) |
|---|---|---|
| Warehouse | PostgreSQL em Docker | Grátis, local, conhecido. Objetivo é modelagem e dbt, não cloud (P3). Rejeitados BigQuery/Snowflake: conta e distração. |
| Transformação | dbt | Ferramenta de transformação mais pedida em vaga. Atenção: ecossistema mudou (Fusion / dbt Core v2 em Rust). Tarefa 1 da semana 1: verificar suporte estável do Fusion a Postgres; senão, dbt Core + dbt-postgres (diferença conceitual zero). Registrar em decisions.md. |
| Fonte das leituras | AI4I 2020 (UCI, CC-BY) | Escolha do Gabriel: público, reproduzível, 10k ciclos, 5 modos de falha. Rejeitado 100% sintético (menos verificável). |
| Enriquecimento | gerador seedado | AI4I não tem máquinas, tempo nem OS. Gerador cria o mundo em volta com semente fixa, calibrado pela vivência de campo do Gabriel. Limites documentados no README. |
| Modelagem | Kimball / star schema | O que vagas pedem e entrevistas cobram. Snowflake normalizado rejeitado de propósito (porquê no decisions.md). |
| Histórico | SCD2 via dbt snapshots | dim_ativo muda (setor, criticidade, reforma) e o warehouse guarda o histórico. |
| Consumo da gold | 5 perguntas de negócio em SQL + dbt docs | Metabase é extensão opcional da semana 4, fora do DoD. |
| Sujeira | injetada de propósito | ~2% duplicatas, OS órfãs, fora de faixa, datas invertidas, com semente. Teste que nunca falha não demonstra nada. |

## 4. Os dados

AI4I 2020 traz: product ID e tipo (L/M/H), temperatura do ar e do processo, rotação, torque, desgaste de ferramenta, falha com 5 modos (TWF, HDF, PWF, OSF, RNF).

O gerador cria em volta: parque de ~80 máquinas mapeando os product IDs (código, tipo, fabricante, setor, criticidade, instalação); eixo temporal distribuindo os 10k ciclos em ~2 anos de operação com turnos (o AI4I não tem timestamps: atribuição sintética e assumida); OS corretivas derivadas das falhas (técnico, peças, custo, atraso realista) + preventivas por plano; mudanças de ativo no tempo (transferência, reclassificação, reforma) para a SCD2 capturar; sujeira controlada.

## 5. O modelo dimensional (desenho de partida)

| Tabela | Grain / natureza | Conteúdo |
|---|---|---|
| fct_leituras | 1 linha = 1 ciclo de operação de uma máquina | sensores AI4I + FKs ativo, tempo, modo de falha |
| fct_ordens_servico | 1 linha = 1 OS | tipo, datas, custo, técnico, FKs ativo e tempo |
| dim_ativo | SCD2 | setor, criticidade, estado; valid_from/valid_to via snapshot |
| dim_local | SCD1 | planta → setor → linha |
| dim_tempo | 1 linha = 1 dia | turno, dia útil, mês, estação |
| dim_modo_falha | SCD1 | 5 modos AI4I + descrição de engenharia escrita pelo Gabriel |
| dim_tecnico | SCD1 | equipe sintética, especialidade, turno |

As 5 perguntas de negócio da gold: MTBF e MTTR por criticidade; setores que concentram custo de corretiva; modo de falha que mais para máquina por hora parada; preventiva em dia reduz corretiva no trimestre seguinte; evolução do custo por máquina após reforma (essa exige SCD2, de propósito).

## 6. Estrutura do repositório

```
maintenance-warehouse/
├── README.md                  ← diagrama + lineage no topo, EN com versão PT
├── CLAUDE.md
├── pyproject.toml / uv.lock   ← só gerador e loader
├── .env.example
├── docker-compose.yml         ← PostgreSQL (Metabase opcional, semana 4)
├── docs/
│   ├── PLANO.md
│   ├── decisions.md
│   └── modelo-dimensional.md  ← grains, bus matrix, perguntas de negócio
├── seed/
│   ├── generator.py           ← mundo sintético, semente fixa
│   └── loader.py              ← AI4I + sintéticos → bronze
├── warehouse/                 ← projeto dbt
│   ├── dbt_project.yml
│   ├── models/staging/        ← silver
│   ├── models/marts/          ← gold: fct_*, dim_*
│   ├── snapshots/             ← SCD2 dim_ativo
│   ├── tests/                 ← testes singulares
│   └── seeds/                 ← dim_modo_falha e afins
└── analyses/perguntas_negocio.sql
```

## 7. As semanas

### Semana 1 · Fundação: Postgres, dbt e o mundo sintético (~15h)

Entregável: Postgres via docker-compose; decisão Fusion vs dbt Core verificada e registrada; exploração do AI4I documentada; generator.py e loader.py com bronze carregada (AI4I + cadastros + OS + sujeira); projeto dbt inicializado com primeiro modelo trivial rodando.

Checkpoint (perguntar e esperar resposta em texto):
1. Por que o Python para na bronze, e o que se ganha movendo a transformação para dentro do warehouse?
2. O que é o profiles.yml do dbt e por que credencial não entra no repositório?
3. Por que o gerador precisa de semente fixa?

### Semana 2 · Silver: staging e a gramática do dbt (~15h)

Entregável: staging para todas as fontes (renomes, tipos, dedup, 1:1 com a origem); testes genéricos (unique, not_null, accepted_values, relationships) pegando a sujeira injetada; desenho final do star revisado em docs/modelo-dimensional.md. Exercício de reescrita: uma staging model do zero, com testes.

Checkpoint:
1. Diferença entre materializar como view e como table, e por que staging costuma ser view?
2. O que o ref() faz além de substituir o nome da tabela?
3. Por que testar na staging se a gold vai testar de novo?

### Semana 3 · Gold: o star schema e a história dos ativos (~15h)

Entregável: fatos e dimensões materializados e testados; snapshot SCD2 de dim_ativo com um caso demonstrado de ponta a ponta; testes singulares de regra de negócio (OS não conclui antes de abrir, custo não negativo, falha exige modo); dbt docs com lineage completo, print no README. Exercício de reescrita: surrogate key + join de fato com dimensão SCD2 na data certa.

Checkpoint:
1. Qual o grain de fct_ordens_servico e que pergunta ele impede de responder?
2. Como um fato acha a versão certa de um ativo na SCD2, e o que acontece se fizer join pelo código natural?
3. Quando SCD1 basta, e qual o custo real de manter SCD2?

### Semana 4 · Análise, documentação e lançamento (~15h)

Entregável: analyses/perguntas_negocio.sql com as 5 respostas comentadas; README padrão trilha + decisions.md fechado + falha real documentada; doc Notion, repo público, post carrossel (lineage rende slide ótimo). Opcional: Metabase lendo a gold.

Checkpoint:
1. Por que warehouse dimensional em vez de responder as 5 perguntas direto no Parquet do P1 com pandas?
2. O que o dbt não resolve neste projeto, e qual ferramenta da trilha entra nesse buraco no P3?

## 8. Pronto quando

- Do zero: clone, docker compose up, uv run seed, dbt build, tudo verde em qualquer máquina
- Testes comprovadamente pegam a sujeira injetada (desligar a limpeza faz o build falhar)
- Lineage no README e dbt docs navegável
- 5 perguntas respondidas com SQL comentado, incluindo a que exige SCD2
- Um caso de mudança de ativo demonstrado de ponta a ponta na SCD2
- Gabriel responde qualquer checkpoint sem consultar
- Doc no Notion e post publicados, repo no primeiro comentário

## 9. Riscos e plano B

| Risco | Chance | Plano |
|---|---|---|
| Fusion sem suporte estável a Postgres | média | dbt Core + dbt-postgres; verificação vira parágrafo em decisions.md |
| Gerador virar projeto paralelo | alta | Timebox: versão simples que carrega bronze até o dia 4 |
| Modelagem travar em discussão de grain | média | Desenho da seção 5 é o default; divergência vira nota e segue |
| Pendências do P1 escorregarem | média | São a porta de entrada: primeiro commit do P2 só com post do P1 no ar |
| Semana estourar | alta em alguma | Cada semana fecha algo utilizável; corte da semana 4 é o Metabase, nunca as perguntas |

## 10. Status

- [ ] Fechamento do P1: doc Notion + post de lançamento
- [x] Semana 1 · fundação
- [x] Semana 2 · silver
- [x] Semana 3 · gold + SCD2
- [ ] Semana 4 · análise + lançamento
