# O modelo dimensional

Desenho fechado no fim da Semana 2, para ser executado na Semana 3. O que está aqui
saiu da silver que já existe, não do plano original: onde os dois divergem, quem manda
é o dado, e a divergência está marcada.

Documento de decisão, não de implementação. As cinco decisões que este arquivo tinha
deixado em aberto foram tomadas no primeiro dia da Semana 3, e o registro de cada uma,
com a alternativa rejeitada, está em [`decisions.md`](decisions.md). Aqui fica o
desenho que saiu delas.

## O star

```
                    dim_tempo     dim_turno
                            \       /
      dim_local ---------- fct_leituras ---------- dim_ativo (SCD2)
                                 |
                                 |  mesmo UDI, grain mais fino
                                 |
      dim_local ---------- fct_falhas ------------ dim_ativo (SCD2)
                            /    |    \
                   dim_tempo dim_turno dim_modo_falha


                    dim_tempo (abertura e conclusão)
                                 |
      dim_local ------- fct_ordens_servico -------- dim_ativo (SCD2)
                            /         \
                   dim_tecnico       dim_modo_falha
```

Três fatos, seis dimensões, nenhuma dimensão pendurada em outra. `dim_local` é
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

### fct_falhas

**Uma linha é um modo de falha de uma leitura.** 382 linhas, contra 357 leituras com
falha: as 23 leituras com dois modos entram duas vezes e a de três modos entra três.

Ele existe porque a FK simples `modo_falha_sk` que o `PLANO.md` desenhou em
`fct_leituras` não comporta o multivalorado. Com o fato próprio, contar parada por modo
é um `group by`, e `fct_leituras` fica sem FK de modo nenhuma.

É um **fato sem medida**: não há coluna para somar, e a medida é a própria contagem de
linhas. Isso tem nome em Kimball, é o factless fact table, e serve exatamente para
registrar que um evento aconteceu.

Ele carrega as próprias FKs (ativo, local, tempo, turno, modo) em vez de obrigar quem
consulta a passar por `fct_leituras` para chegar no setor ou na data. Fato que depende
de join com outro fato para ser útil não é fato, é tabela auxiliar.

O que este grain **impede** de responder:

- Quanto custou cada modo. Custo mora na OS, e a OS tem um modo só, o de maior duração
  de reparo. Somar custo por aqui contaria a mesma parada duas vezes.

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

| | dim_tempo | dim_turno | dim_ativo | dim_local | dim_modo_falha | dim_tecnico |
|---|---|---|---|---|---|---|
| **fct_leituras** | sim | sim | sim, SCD2 | sim | não, é o `fct_falhas` | não |
| **fct_falhas** | sim | sim | sim, SCD2 | sim | sim | não |
| **fct_ordens_servico** | sim, duas vezes | não | sim, SCD2 | sim | sim, com NAO_APLICA | sim |

`dim_tempo` aparece duas vezes em `fct_ordens_servico`, como abertura e como conclusão.
É dimensão role-playing: a mesma tabela cumprindo dois papéis no mesmo fato, e cada
papel com a própria FK. As 36 preventivas que não aconteceram apontam a conclusão para
o membro desconhecido, e não para NULL.

`dim_modo_falha` em `fct_ordens_servico` recebe a linha NAO_APLICA nas 651 preventivas.
Fato com FK nula quebra o join e some da contagem sem avisar, então o "não se aplica"
precisa ser uma linha da dimensão, com chave própria.

`dim_turno` não toca `fct_ordens_servico`. A hora de abertura existe e daria para
derivar o turno dela, mas o gerador não atribuiu turno a ordem de serviço: derivar aqui
seria acrescentar uma precisão que a fonte não tem. `dim_tecnico` não toca
`fct_leituras` porque leitura de sensor não tem quem a fez. Célula vazia na bus matrix é
informação, não buraco.

### As dimensões

| Dimensão | Tipo | Grain | Origem |
|---|---|---|---|
| `dim_ativo` | SCD2 | uma versão de uma máquina num intervalo de validade | `stg_ativos` mais `stg_mudancas_ativo`, via `dbt snapshot` |
| `dim_local` | SCD1 | uma linha de produção | `stg_locais` |
| `dim_tempo` | SCD0 | um dia | gerada em SQL, `generate_series` |
| `dim_turno` | SCD0 | um turno de trabalho | escrita em SQL, três linhas |
| `dim_modo_falha` | SCD1 | um modo de falha | seed do dbt, escrito à mão |
| `dim_tecnico` | SCD1 | um técnico | `stg_tecnicos` |

`dim_modo_falha` nasce de um `seed` e não de uma staging porque a descrição de
engenharia de cada modo (o que é dissipação de calor, por que o tipo da peça muda o
limite do OSF) não existe em nenhuma fonte: é conhecimento escrito à mão. Sete linhas:
os cinco modos do AI4I, mais INDETERMINADO para as 9 falhas que a fonte declara sem
causa, mais NAO_APLICA para as 651 preventivas.

## As cinco perguntas de negócio

| # | Pergunta | Toca | Observação |
|---|---|---|---|
| 1 | MTBF e MTTR por criticidade | `fct_ordens_servico`, `fct_leituras`, `dim_ativo`, `dim_tempo` | MTBF em dias de calendário, não em horas de máquina. Limite do grain, declarado. |
| 2 | Setores que concentram custo de corretiva | `fct_ordens_servico`, `dim_local`, `dim_tempo` | Filtra `tipo_os = 'corretiva'`. Cuidado com os 10 custos negativos. |
| 3 | Modo de falha que mais para máquina por hora parada | `fct_ordens_servico`, `dim_modo_falha` | Soma `duracao_horas` por modo, pelo fato de OS e não pelo `fct_falhas`, que não tem medida de duração. |
| 4 | Preventiva em dia reduz corretiva no trimestre seguinte | `fct_ordens_servico`, `dim_tempo` | Autojoin deslocado por trimestre. As 36 preventivas não executadas são metade da resposta. |
| 5 | Evolução do custo por máquina após reforma | `fct_ordens_servico`, `dim_ativo` SCD2 | **Só existe com SCD2.** Sem histórico, a máquina sempre esteve reformada e o antes desaparece. |

A pergunta 5 é a que justifica a SCD2 no projeto inteiro. As outras quatro sobrevivem
com SCD1. É por isso que ela está no plano.

## As cinco decisões, tomadas

O porquê de cada uma, com a alternativa rejeitada e o custo aceito, está em
[`decisions.md`](decisions.md). Aqui fica só o que o desenho passou a ser.

### A. As 24 leituras com mais de um modo de falha

**Fato próprio `fct_falhas`, grain (leitura, modo).** 382 linhas. `fct_leituras` fica
sem FK de modo, e a contagem por modo vira um `group by`. Rejeitadas as cinco flags no
fato e a tabela ponte.

### B. Qual é a definição de "falha"

**A união: `falha_maquina` marcado ou algum modo marcado. 357 eventos.**

O desempate veio do dado. As 357 OS corretivas têm `udi_origem` preenchido nas 357, e
357 é exatamente o tamanho da união. Com qualquer uma das outras duas definições, um
teste do tipo "toda corretiva aponta para uma leitura com falha" acusaria 18 linhas (se
`falha_maquina` mandasse) ou 9 (se "algum modo" mandasse). Com a união ele fecha em
zero, e esse teste está no projeto.

O que precisa estar escrito no README: o warehouse conta 357 falhas onde o dataset
publica 339. A definição aqui é "evento que levou um técnico até a máquina", que é a de
um warehouse de manutenção, e não o rótulo de um dataset de classificação.

### C. Como a SCD2 vai ser construída de verdade

**Laço de `dbt snapshot`, uma rodada por data de corte.**

Um modelo de estado do ativo parametrizado por `var('data_corte')` responde "como estava
o parque nesta data", e o snapshot roda uma vez por data de mudança, em ordem crescente.
São 31 datas distintas, entre 2024-03-04 e 2025-10-23, e o resultado esperado são 111
versões: 80 máquinas mais 31 mudanças.

A estratégia do snapshot é `timestamp`, com `updated_at` apontando para a data da última
mudança aplicada. Isso não é detalhe de configuração: com a estratégia `check`, o
`dbt_valid_from` receberia a hora em que o comando rodou, e o histórico ficaria carimbado
com data de execução em vez de data de negócio.

Duas consequências que precisam estar no README:

- a ordem crescente do laço importa, porque a estratégia `timestamp` ignora em silêncio
  uma mudança mais antiga que a última registrada;
- quem rodar `dbt build` antes do laço fica com uma versão por máquina e um histórico
  errado que não aparece em lugar nenhum. Por isso existe um teste singular comparando a
  contagem de versões com o esperado: pular o laço deixa o build vermelho.

### D. `dim_tempo` não comporta turno

**Nasce `dim_turno`, três linhas, com hora de início e fim.** Ela é conformada: descreve
o turno de `fct_leituras` e o turno de `dim_tecnico`. `dim_tempo` fica com um dia por
linha, dia útil, mês, trimestre e estação.

### E. Trazer ou não o `dbt_utils`

**Entra, versão 1.4.1 fixa.** Traz `accepted_range`, `expression_is_true` e
`unique_combination_of_columns`. Os testes que são deste domínio, e que pacote nenhum
conhece, continuam escritos à mão em `tests/`.

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
