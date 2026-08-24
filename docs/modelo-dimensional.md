# O modelo dimensional

Desenho fechado no fim da Semana 2, para ser executado na Semana 3. O que está aqui
saiu da silver que já existe, não do plano original: onde os dois divergem, quem manda
é o dado, e a divergência está marcada.

Documento de decisão, não de implementação. Nenhum modelo da gold existe ainda.

## O star

```
                          dim_tempo
                              |
        dim_local ------ fct_leituras ------ dim_ativo (SCD2)
                              |
                       dim_modo_falha
                              |
        dim_local -- fct_ordens_servico --- dim_ativo (SCD2)
                         |        |
                   dim_tempo   dim_tecnico
```

Dois fatos, cinco dimensões, nenhuma dimensão pendurada em outra. `dim_local` é
alcançada direto pelo fato, e não através de `dim_ativo`, mesmo sendo o local um
atributo da máquina. Isso é a decisão de rejeitar snowflake, do `decisions.md`,
aplicada: quem quiser custo por setor faz um join, não dois.

## Os grains

O grain é a primeira coisa a declarar e a última a mudar. Declarado errado, todo o
resto sai errado, e ninguém percebe até a soma dobrar.

### fct_leituras

**Uma linha é um ciclo de operação de uma máquina.** 10.000 linhas, uma por UDI.

Chega assim porque o AI4I traz uma linha por peça produzida, e `stg_leitura_contexto`
atribui cada uma a uma máquina e a um instante.

O que este grain **impede** de responder:

- Qualquer coisa sobre o estado da máquina entre dois ciclos. Não existe medição
  contínua, existe amostra por ciclo.
- Tempo de operação em horas. Sabe-se quando cada ciclo aconteceu, não quanto durou.
  Isso tem consequência direta no MTBF, que vai ser medido em intervalo entre falhas
  no calendário, e não em horas de máquina ligada. Precisa estar escrito na resposta.
- Qualquer corte por peça produzida. O `produto_id` é único nas 10.000 linhas, então
  ele entra como atributo degenerado, serve para rastrear a linha de origem, e não
  vira dimensão.

### fct_ordens_servico

**Uma linha é uma ordem de serviço.** 1.008 linhas: 357 corretivas e 651 preventivas.

O que este grain **impede** de responder:

- Quais peças foram trocadas em cada OS. `custo_pecas` é um valor só, sem item. Um
  fato de grain (OS, item) não existe porque o gerador não inventou almoxarifado, e
  essa foi uma decisão consciente de escopo.
- Quantos técnicos atenderam uma OS. Há uma matrícula por ordem. MTTR por técnico
  funciona; rateio de esforço entre dois técnicos não.
- Qualquer coisa sobre a OS depois de encerrada: não há retrabalho, não há reabertura.

## A bus matrix

| | dim_tempo | dim_ativo | dim_local | dim_modo_falha | dim_tecnico |
|---|---|---|---|---|---|
| **fct_leituras** | sim | sim, SCD2 | sim | ver decisão A | não |
| **fct_ordens_servico** | sim | sim, SCD2 | sim | sim, opcional | sim |

`dim_modo_falha` é opcional em `fct_ordens_servico` porque as 651 preventivas não têm
modo. Na gold isso vira a linha "não se aplica" da dimensão, com chave própria, e não
um NULL na FK: fato com FK nula quebra o join e some da contagem sem avisar.

`dim_tecnico` não toca `fct_leituras` porque leitura de sensor não tem quem a fez.
Célula vazia na bus matrix é informação, não buraco.

### As dimensões

| Dimensão | Tipo | Grain | Origem |
|---|---|---|---|
| `dim_ativo` | SCD2 | uma versão de uma máquina num intervalo de validade | `stg_ativos` mais `stg_mudancas_ativo` |
| `dim_local` | SCD1 | uma linha de produção | `stg_locais` |
| `dim_tempo` | SCD0 | um dia | gerada em SQL, ver decisão D |
| `dim_modo_falha` | SCD1 | um modo de falha | seed do dbt, escrito à mão |
| `dim_tecnico` | SCD1 | um técnico | `stg_tecnicos` |

`dim_modo_falha` nasce de um `seed` e não de uma staging porque a descrição de
engenharia de cada modo (o que é dissipação de calor, por que o tipo da peça muda o
limite do OSF) não existe em nenhuma fonte: é conhecimento escrito à mão. Seis linhas,
contando o INDETERMINADO.

## As cinco perguntas de negócio

| # | Pergunta | Toca | Observação |
|---|---|---|---|
| 1 | MTBF e MTTR por criticidade | `fct_ordens_servico`, `fct_leituras`, `dim_ativo`, `dim_tempo` | MTBF em dias de calendário, não em horas de máquina. Limite do grain, declarado. |
| 2 | Setores que concentram custo de corretiva | `fct_ordens_servico`, `dim_local`, `dim_tempo` | Filtra `tipo_os = 'corretiva'`. Cuidado com os 10 custos negativos. |
| 3 | Modo de falha que mais para máquina por hora parada | `fct_ordens_servico`, `dim_modo_falha` | Soma `duracao_horas` por modo. Depende da decisão A. |
| 4 | Preventiva em dia reduz corretiva no trimestre seguinte | `fct_ordens_servico`, `dim_tempo` | Autojoin deslocado por trimestre. As 36 preventivas não executadas são metade da resposta. |
| 5 | Evolução do custo por máquina após reforma | `fct_ordens_servico`, `dim_ativo` SCD2 | **Só existe com SCD2.** Sem histórico, a máquina sempre esteve reformada e o antes desaparece. |

A pergunta 5 é a que justifica a SCD2 no projeto inteiro. As outras quatro sobrevivem
com SCD1. É por isso que ela está no plano.

## Cinco decisões que a Semana 3 precisa tomar

Levantadas aqui para serem decididas no primeiro dia, não descobertas no meio.

### A. As 24 leituras com mais de um modo de falha

O `PLANO.md` desenhou `fct_leituras` com uma FK simples `modo_falha_sk`. Não cabe: 23
leituras têm dois modos marcados e 1 tem três.

| Saída | A favor | Contra |
|---|---|---|
| Manter as cinco flags booleanas no fato | Nada se perde, e já está pronto na silver | Não é dimensional. Contar falha por modo vira cinco somas separadas, e um modo novo vira coluna nova |
| Tabela ponte (leitura, modo) | Kimball clássico para multivalorado | Traz o problema de peso: somar custo por modo conta a mesma parada duas vezes se ninguém ratear |
| Fato próprio `fct_falhas`, grain (leitura, modo) | Grain honesto, contagem por modo trivial, 348 linhas | Duas tabelas de fato para o mesmo evento, e quem consulta precisa saber qual usar |

Inclinação: o fato próprio. As 24 linhas viram 373 em vez de 348, o grain fica
declarável em uma frase, e `fct_leituras` fica sem FK de modo nenhuma.

### B. Qual é a definição de "falha"

A fonte discorda de si mesma em 27 linhas: 9 têm `Machine failure` sem nenhum modo
marcado, e 18 têm modo marcado (todas RNF) sem `Machine failure`.

O warehouse precisa de uma definição só, escolhida e escrita. As duas candidatas:

- **`falha_maquina` manda.** 339 eventos. Simples, é a coluna que o dataset publica
  como rótulo. Custo: as 18 RNF somem, e o INDETERMINADO cobre 9 falhas sem causa.
- **Algum modo marcado manda.** 348 eventos. Toda falha tem causa por construção.
  Custo: as 9 linhas sem modo somem, e entram 18 RNF que a própria fonte não considera
  parada de máquina.

Seja qual for, as 357 OS corretivas já existem pela união das duas, e isso não muda: a
OS registra que alguém foi lá. A decisão é sobre o que `fct_leituras` chama de falha.

### C. Como a SCD2 vai ser construída de verdade

**O problema não é óbvio e vale ler duas vezes.** Um `dbt snapshot` grava o que enxerga
na hora em que roda. `bronze.ativos` é estático depois da carga: as 80 máquinas têm um
estado só, e `estado` vale `operando` nas 80 mesmo havendo 6 reformas registradas. Rodar
`dbt snapshot` dez vezes seguidas produz uma versão por máquina, com um `valid_from` só.
As 31 linhas de `stg_mudancas_ativo` não viram histórico sozinhas.

| Caminho | A favor | Contra |
|---|---|---|
| Montar o histórico em SQL, num modelo que já sai com `valid_from` e `valid_to` | Determinístico, reproduz igual em qualquer máquina, roda num comando | Não usa `dbt snapshot`, que é o que o plano pede e o que a entrevista pergunta |
| View de estado do ativo parametrizada por data de corte, e rodar `dbt snapshot --vars` uma vez por data de mudança | Usa a ferramenta de verdade, e a tabela de snapshot fica com versões reais, `dbt_valid_from` e `dbt_valid_to` preenchidos pelo dbt | Precisa de um laço no shell com as 31 datas distintas de mudança, e "roda em qualquer máquina" passa a depender desse laço estar no README |

Inclinação: o segundo. O ponto do projeto é saber operar snapshot, e o laço vira três
linhas documentadas. O primeiro caminho fica registrado como alternativa rejeitada.

### D. `dim_tempo` não comporta turno

O `PLANO.md` desenhou `dim_tempo` com grain de um dia e listou `turno` entre os
atributos. Não fecha: há três turnos por dia, e uma dimensão de grain diário não
consegue guardar um atributo que muda três vezes dentro da própria linha.

Saídas: `turno` vira atributo degenerado no fato (barato, e some da lista de dimensões);
ou nasce uma `dim_turno` de três linhas com hora de início e fim. A segunda tem um
argumento a mais: `dim_tecnico` também tem turno, então ela seria dimensão conformada,
usada por um fato e por uma dimensão, o que é exatamente o que a bus matrix existe para
mostrar.

Inclinação: `dim_turno`, pela conformidade. `dim_tempo` fica com um dia por linha, dia
útil, mês, trimestre e estação, que é o clássico.

### E. Trazer ou não o `dbt_utils`

Três coisas da Semana 3 pedem teste que o dbt nativo não tem:

- chave composta em `stg_mudancas_ativo`, grain (ativo, data, campo): `unique_combination_of_columns`
- faixa física dos sensores, documentada em `fonte-ai4i.md`: `accepted_range`
- regras de negócio como "custo não negativo": `expression_is_true`

Sem o pacote, as três viram teste singular em SQL na pasta `tests/`, o que funciona e
é mais explícito, ao custo de escrever à mão o que já existe pronto. O `CLAUDE.md`
manda perguntar antes de trazer dependência, então isso é pergunta para o Gabriel no
começo da Semana 3, não decisão minha.

## Chaves

Toda dimensão ganha surrogate key inteira, gerada na gold. O código natural
(`MAQ-017`, `TEC-003`) continua na dimensão como atributo, para conferência, mas o
fato guarda a surrogate.

Isso não é cerimônia, e a razão é a `dim_ativo`: com SCD2, `MAQ-017` deixa de
identificar uma linha e passa a identificar um conjunto de versões. Um fato que faça
join por `codigo_ativo` sozinho casa com todas as versões da máquina de uma vez e
multiplica o custo pelo número de reformas que ela teve. O join correto é pela
surrogate da versão vigente **na data do evento**:

```sql
from fct_ordens_servico f
join dim_ativo a
  on  f.ativo_sk = a.ativo_sk
```

com `ativo_sk` já resolvido na construção do fato, comparando `data_abertura` contra o
intervalo `valid_from` e `valid_to` da versão. Resolver no fato, e não na consulta, é o
que faz a gold responder rápido e o que impede quem consulta de errar o join.
