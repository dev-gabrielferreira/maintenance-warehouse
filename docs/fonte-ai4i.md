# A fonte: AI4I 2020 Predictive Maintenance Dataset

Exploração feita em 2026-08-24, no bloco 1.3 do plano. Os números daqui saíram do
arquivo real, não da documentação do dataset, e algumas coisas não batem entre os dois.

## De onde vem

| Item | Valor |
|---|---|
| Origem | UCI Machine Learning Repository, id 601 |
| Licença | CC BY 4.0 |
| Download | `seed/download.py`, com checksum fixo |
| SHA-256 do zip | `f601f14294bcf190f9d720676b7f0aea46a26cde9ab8ebc7b4f8174d9d26b252` |
| Tamanho | 522 KB (zip), um único `ai4i2020.csv` dentro |
| Forma | 10.000 linhas, 14 colunas, nenhum nulo |

O dataset é sintético, criado para se parecer com uma fresadora real. Isso não é
demérito para este projeto: o que se está exercitando é modelagem dimensional e dbt,
e para isso importa que o dado tenha regras internas verificáveis, o que ele tem.

## As colunas

| Coluna | Tipo | Observação |
|---|---|---|
| `UDI` | inteiro | 1 a 10.000, único e sem buraco. É a ordem das leituras, e é o que o gerador vai usar para distribuir no tempo. |
| `Product ID` | texto | Letra do tipo mais 5 dígitos. **Único em todas as 10.000 linhas.** Ver achado 1. |
| `Type` | texto | Qualidade da peça: L (6.000), M (2.997), H (1.003). Sempre igual à primeira letra do `Product ID`. |
| `Air temperature [K]` | decimal | 295,3 a 304,5. Média 300,0. |
| `Process temperature [K]` | decimal | 305,7 a 313,8. Média 310,0. Sempre acima da temperatura do ar. |
| `Rotational speed [rpm]` | inteiro | 1.168 a 2.886. Média 1.539. |
| `Torque [Nm]` | decimal | 3,8 a 76,6. Média 40,0. |
| `Tool wear [min]` | inteiro | 0 a 253. Média 108. Minutos de uso acumulado da ferramenta. |
| `Machine failure` | 0/1 | 339 casos (3,39%). Ver achado 3. |
| `TWF` `HDF` `PWF` `OSF` `RNF` | 0/1 | Os cinco modos. Contagens abaixo. |

As faixas acima são a base dos testes de faixa física na silver. Valor fora delas na
bronze é sujeira, não medição.

## Os cinco modos de falha

Cada modo tem uma regra determinística. Rodei cada uma contra o dado e três delas
reproduzem a coluna exatamente, o que quer dizer que viram teste de regra de negócio
na Semana 3, com resposta conhecida.

| Modo | Casos | Regra | Confere? |
|---|---|---|---|
| **HDF** dissipação de calor | 115 (1,15%) | temperatura do processo menos a do ar abaixo de 8,6 K **e** rotação abaixo de 1.380 rpm | 115 de 115, exato |
| **OSF** sobrecarga | 98 (0,98%) | desgaste da ferramenta vezes torque acima do limite do tipo: 11.000 para L, 12.000 para M, 13.000 para H (min·Nm) | 98 de 98, exato |
| **PWF** falha de potência | 95 (0,95%) | potência (torque vezes rotação em rad/s) fora da faixa de 3.500 a 9.000 W | 95 de 95, exato |
| **TWF** desgaste de ferramenta | 46 (0,46%) | ferramenta trocada ou quebrada por desgaste acumulado | ver observação |
| **RNF** falha aleatória | 19 (0,19%) | ruído proposital, sem causa física | não reproduzível, por desenho |

**Observação sobre o TWF:** a documentação do dataset descreve a troca de ferramenta
entre 200 e 240 minutos de desgaste. No arquivo, os casos de TWF aparecem entre **198
e 253 minutos**. A regra descrita e o dado publicado não coincidem, então o TWF não
vira teste determinístico como os outros três. Isso vai para o `decisions.md`.

O `Type` entrando na regra do OSF é o detalhe mais interessante daqui: peça de melhor
qualidade aguenta mais esforço antes de falhar. É a única coluna categórica que altera
um limite físico, e é um bom argumento para ela virar atributo de dimensão e não só
rótulo.

## Três achados que mexem no plano

### 1. `Product ID` não identifica máquina, identifica peça

São **10.000 valores distintos em 10.000 linhas**. A seção 4 do `PLANO.md` previa um
"parque de ~80 máquinas mapeando os product IDs", e isso não é possível como estava
escrito: cada linha é uma peça diferente saindo da produção, não um equipamento
reaparecendo.

Consequência para o bloco 1.5: a atribuição de leituras a máquinas passa a ser
sintética, feita pelo gerador com semente fixa, e não derivada do `Product ID`. O
`Product ID` continua no fato como atributo degenerado, porque é o identificador
natural do evento e serve para rastrear até a linha de origem.

### 2. Uma leitura pode ter mais de um modo de falha

Distribuição de modos por linha:

| Modos marcados | Linhas |
|---|---|
| 0 | 9.652 |
| 1 | 324 |
| 2 | 23 |
| 3 | 1 |

Uma FK simples `modo_falha_sk` em `fct_leituras`, como a seção 5 do `PLANO.md` desenha,
não comporta as 24 linhas com mais de um modo. Isso é decisão de modelagem da Semana 3
e vai ser levantada lá, não aqui.

### 3. A própria fonte é incoerente, e isso é bom

| Situação | Linhas |
|---|---|
| `Machine failure` = 1 e nenhum dos cinco modos marcado | 9 |
| Algum modo marcado e `Machine failure` = 0 | 18 |
| Das 18 acima, quantas são só `RNF` | 18 |

Duas leituras disso:

- O **RNF não conta** para `Machine failure`. Em 18 dos 19 casos de RNF a máquina segue
  marcada como operante. Faz sentido para uma coluna que existe para ser ruído, mas
  significa que "falha" tem duas definições no mesmo arquivo, e o warehouse precisa
  escolher uma e documentar.
- Sobram **9 linhas com falha declarada e nenhuma causa**. Não há explicação na
  documentação do dataset.

Isso importa mais do que parece. O `PLANO.md` prevê o teste de regra "falha exige modo
de falha" na Semana 3, e a sujeira do projeto seria toda injetada pelo gerador. Só que
essas 9 linhas são sujeira **real**, que veio da fonte, e o teste vai pegá-las sem que
ninguém as tenha plantado. Um teste que acusa problema em dado público de verdade
defende-se melhor em entrevista do que um que acusa problema que a gente mesmo criou.

## O que a fonte não tem, e por isso existe o gerador

Nada de máquina, nada de tempo, nada de manutenção:

- **Sem equipamento.** Não há coluna de máquina, linha, setor ou planta.
- **Sem timestamp.** O `UDI` dá ordem, não data. Sem eixo temporal não há `dim_tempo`,
  não há turno e não há MTBF.
- **Sem ordem de serviço.** Há a falha, não há o que se fez com ela: nem técnico, nem
  peça, nem custo, nem tempo de reparo. Metade das perguntas de negócio do projeto
  depende disso.
- **Sem histórico de cadastro.** Nenhum atributo muda ao longo do arquivo, então não há
  o que a SCD2 capture.

O gerador do bloco 1.5 cria essas quatro coisas com semente fixa. Elas são sintéticas e
assumidas, e o README vai dizer isso na cara, porque um número inventado apresentado
como medição é pior que nenhum número.
