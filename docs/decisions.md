# Decisões

Cada linha aqui é uma pergunta que já apareceu, ou que vai aparecer, em entrevista.
Documento vivo: decisão nova entra aqui no mesmo commit em que entra no código.

## Arquitetura

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Warehouse | PostgreSQL em Docker | Grátis, local e já conhecido. O assunto do projeto é modelagem e dbt, não infraestrutura. Rejeitados BigQuery e Snowflake: exigem conta, cartão e desviam o foco. Cloud é escopo do P3. |
| Transformação | dbt | É a ferramenta de transformação mais pedida em vaga de dados hoje, e o projeto existe para exercitar SQL versionado, testado e documentado. |
| Onde o Python para | Na bronze | `seed/` baixa, gera e carrega. Nada além disso. A ausência de um `transform.py` é a tese do projeto: no P1 a transformação morava em pandas, aqui ela mora no warehouse, em SQL que dá para versionar, testar e desenhar lineage. |
| Fonte das leituras | AI4I 2020 (UCI, CC BY 4.0) | Público, reproduzível, 10 mil linhas e cinco modos de falha com regra física verificável. Rejeitado gerar 100% sintético: ninguém consegue conferir o resultado contra nada. |
| O mundo em volta | Gerador com semente fixa | O AI4I não tem máquina, tempo nem ordem de serviço (ver `fonte-ai4i.md`). Sem esse mundo não há dimensão, não há MTBF e não há SCD2. Limites documentados no README, porque número inventado apresentado como medição é pior que número nenhum. |
| Modelagem | Kimball, star schema | É o que a vaga pede e o que a entrevista cobra. Rejeitado snowflake normalizado: economiza espaço que não falta e cobra join em toda consulta. |
| Histórico de cadastro | SCD2 via dbt snapshots | Ativo muda de setor, de criticidade e passa por reforma. Sem SCD2, a pergunta "o custo caiu depois da reforma?" não tem como ser respondida, porque o passado teria sido reescrito. |
| Sujeira nos dados | Injetada de propósito, com semente | Teste que nunca falha não demonstra nada. Desligar a limpeza da silver tem que quebrar o build, e isso vira parágrafo no README com a saída colada. |
| Ambiente Python | uv | Lockfile reprodutível e `uv sync` deixa qualquer pessoa rodando. Mesma escolha do P1, pelos mesmos motivos. |
| Idioma do código | Português | Alinhado ao domínio (ordem de serviço, criticidade, setor). README principal continua em inglês, com versão PT linkada. |

## Semana 1

### A verificação que o plano pediu primeiro

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| dbt Fusion ou dbt Core | **dbt Core 1.12.3 + dbt-postgres 1.11.0** | Verificado em 2026-08-24: o Fusion continua sem suporte a Postgres. O [issue #31 do dbt-fusion](https://github.com/dbt-labs/dbt-fusion/issues/31) segue aberto e a [página de plataformas suportadas](https://docs.getdbt.com/docs/fusion/supported-features) não lista Postgres. A confirmação prática é o `dbt --version`, que responde `Core:`. Isso executa o plano B previsto na seção 9 do PLANO, e a diferença conceitual para o projeto é zero: modelo, teste, snapshot e docs são os mesmos. |
| Versão do `dbt-core` no `pyproject.toml` | `>=1.10,<2.0` | Sem o teto, o resolvedor pode puxar o `dbt-core 2.0.0-alpha`, que é o motor do Fusion, e a instalação passa a responder "the postgres adapter is not yet supported by dbt Fusion" ([issue #1992](https://github.com/dbt-labs/dbt-adapters/issues/1992)). O `dbt-postgres` já declara `<2.0` por conta própria, mas deixar explícito documenta a intenção para quem ler o arquivo. |

### Banco e container

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Imagem do Postgres | `postgres:17`, não `17-alpine` | A alpine usa musl, que não tem suporte completo a locale. Os dados deste projeto têm texto em português com acento (setor, nome de técnico), e `ORDER BY` sobre eles ordena diferente em musl. Rejeitada a alpine: 150 MB a menos não paga uma ordenação errada. |
| Publicação da porta | `127.0.0.1:5432`, não `5432` | Sem o `127.0.0.1` na frente o Docker abre a porta em `0.0.0.0`, e o banco passa a aceitar conexão de qualquer máquina da rede local. Quem precisa falar com ele de dentro do compose (o Metabase, se entrar na semana 4) usa a rede interna e não depende dessa publicação. |
| Porta como variável | `POSTGRES_PORT`, padrão 5432 | Quem clonar o projeto pode já ter um Postgres na 5432. Trocar no `.env` resolve sem editar o compose. |
| Persistência | Volume nomeado `pgdata` | Rejeitado bind mount para uma pasta do repositório: deixaria os arquivos internos do Postgres dentro do projeto, com dono root. O `data/` do `.gitignore` existe para o dado bruto, não para o banco. |
| Healthcheck | `pg_isready` com `start_period` de 10s | `docker compose up -d` devolve o controle antes do Postgres aceitar conexão. Sem healthcheck, um `uv run seed` logo em seguida falharia com "connection refused" de forma intermitente, que é o pior tipo de erro: some quando alguém vai investigar. |
| Credenciais | Só no `.env`, nunca no repositório | O `.env.example` versionado lista quais variáveis existem, com valores de exemplo. Uma fonte só para compose, loader e dbt, porque credencial repetida em dois arquivos é credencial que um dia diverge. |

### Ambiente Python

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Versão do Python | 3.12 fixa no `.python-version`, teto `<3.14` no `pyproject.toml` | A máquina tem 3.14, e o dbt-core tem [issue aberta](https://github.com/dbt-labs/dbt-core/issues/12098) com ela por causa de mashumaro e pydantic v1, que é end-of-life. Mesmo raciocínio do P1, onde o 3.12 foi fixado por causa do pyarrow. O teto permite 3.13 para quem clonar com ela, e barra só a versão problemática. |
| pandas no caminho do dado | Sim, em `seed/` | **Decisão consciente, com custo.** O caminho alternativo era `csv` da stdlib, que manteria a pasta `seed/` sem nenhuma ferramenta de transformação dentro dela. Escolhido pandas por familiaridade vinda do P1 e por deixar a exploração da fonte direta. O custo aceito: um `import pandas` dentro de `seed/` deixa um `df.assign` a um passo de distância, e a regra de que o Python para na bronze passa a depender de disciplina em vez de depender da ausência da ferramenta. |
| Carga para o Postgres | `COPY` via psycopg 3 | Rejeitado o `to_sql` do pandas: puxaria SQLAlchemy como dependência e faz INSERT por baixo do pano. O `COPY` é o caminho nativo de carga em massa do Postgres, e deixa visível no código o que está acontecendo. |
| Driver | psycopg 3 no loader | O 3 tem `COPY` nativo com context manager. O `psycopg2-binary` que aparece no `uv.lock` não é escolha nossa: é dependência do adapter `dbt-postgres`. Dois drivers no lock, com consumidores diferentes, sem conflito porque são pacotes de nomes distintos. |
| Layout do pacote | `seed/` na raiz, não `src/seed/` | É como a seção 6 do `PLANO.md` desenha o repositório. Custa duas linhas de `[tool.uv.build-backend]` (`module-root = ""`), porque o uv_build procura em `src/` por padrão. |

### Download da fonte

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Como o dado chega | `seed/download.py` baixa do UCI | O critério de aceite do projeto é "clone, `docker compose up`, `uv run seed`, `dbt build`, tudo verde em qualquer máquina". Download manual documentado quebraria isso. Rejeitada também a dependência `ucimlrepo`: seria um pacote a mais para um download só, e esconderia o cache e o checksum, que são justamente o que vale mostrar. |
| Cache | Por SHA-256, não por existência do arquivo | Arquivo existir não quer dizer arquivo íntegro. Com checksum, zip truncado por download interrompido rebaixa sozinho na execução seguinte. |
| Checksum fixo no código | Sim | Não está lá contra corrupção de download, que o HTTPS já resolve. Está contra o dia em que o UCI republicar o dataset com outro conteúdo: a carga para com mensagem em vez de contaminar o warehouse em silêncio. Testado forçando um SHA falso, e o `RuntimeError` diz o que conferir. |
| Escrita do arquivo | Temporário `.parte` e depois `os.replace` | Download interrompido não pode deixar arquivo truncado com o nome definitivo, senão a execução seguinte lê lixo achando que tem tudo. O temporário fica na mesma pasta porque rename entre sistemas de arquivos diferentes não é atômico. Mesmo padrão do `extract.py` do P1. |
| CSV extraído ou lido de dentro do zip | Extraído para `data/raw/` | Custa 522 KB de disco em pasta que não é versionada, e em troca dá para abrir o arquivo e olhar. Transparência vale mais que o disco aqui. |

### O gerador do mundo sintético

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Onde entra a atribuição de máquina e instante | Tabela própria, `leitura_contexto`, chaveada pelo `UDI` | Rejeitado carimbar colunas no CSV do AI4I. A fonte pública entra na bronze como veio, e a invenção nossa entra separada, para que o join entre as duas aconteça em SQL, na silver, onde dá para auditar. Misturar os dois no mesmo arquivo apagaria a fronteira entre dado e suposição, que é justamente o que o README precisa declarar. |
| Semente | `random.Random(20200101)`, instância própria | Rejeitado o `random` global e qualquer `datetime.now()`. Com instância própria, nenhuma biblioteca que também use random consegue mexer na sequência. Verificado: duas execuções seguidas produzem os seis CSVs idênticos byte a byte. |
| Tamanho do parque | 80 máquinas, na proporção de tipo do AI4I (48 L, 24 M, 8 H) | Máquina tem tipo fixo, e leitura de um tipo só cai em máquina daquele tipo. Uma fresadora H que passasse a produzir peça L no meio do arquivo quebraria a regra do OSF, que usa o tipo como limite físico. |
| Carga de uso entre máquinas | Desbalanceada, curva `1/rank^0.8` | Escolha do Gabriel, pela vivência de campo: gargalo roda direto e o resto complementa. O resultado é de 32 a 933 leituras por máquina, com 20% do parque concentrando 52% dos ciclos. Rejeitada a distribuição uniforme: 125 leituras para todo mundo achataria o MTBF e deixaria as respostas por setor parecidas demais entre si. |
| Duração do reparo por modo | 2h a 16h, conforme o modo | Calibrado pelo Gabriel: HDF e PWF são limpeza de trocador e reset de acionamento, resolvem dentro do turno (2h a 6h). OSF e TWF envolvem troca de componente e espera de peça (4h a 16h). RNF, 1h a 3h. Rejeitada a faixa de 4h a 72h: realista para equipamento sem estoque, mas transformaria o projeto numa discussão sobre almoxarifado. |
| Quais leituras viram ordem corretiva | União: `Machine failure = 1` **ou** algum modo marcado | 357 corretivas. Rejeitado escolher uma das duas definições aqui, porque isso esconderia na origem as duas incoerências da fonte. Elas seguem para a bronze, e a escolha é da gold, documentada. |
| Modo atribuído quando há mais de um | O de maior duração de reparo | Vale só para dar duração e custo à OS, já que é o modo mais demorado que determina quanto tempo a máquina fica parada. As 24 leituras com dois ou três modos continuam com todos eles no fato: a modelagem do múltiplo é assunto da Semana 3. |
| Aderência do plano preventivo | 85% dentro de 7 dias | Os 15% restantes atrasam de 15 a 60 dias, e um terço deles não acontece (conclusão vazia). Sem preventiva atrasada, a pergunta "preventiva em dia reduz corretiva no trimestre seguinte" não teria os dois lados para comparar. Resultado: 651 preventivas, 36 não executadas (o 44 esteve escrito aqui por engano até a Semana 2; conferido no banco, são 36, com data de conclusão nula, duração zero e custo zero batendo entre si). |
| Quantidade de sujeira | Fixa e declarada em constante no topo do módulo | 200 leituras duplicadas, 8 OS órfãs de ativo, 5 de técnico, 10 com custo negativo, 10 com datas invertidas, 5 ativos instalados depois da primeira leitura. Números conferidos um a um, e todos vão a zero com `--sem-sujeira`. O README pode dizer "são 200 duplicatas" sem ninguém precisar contar. |
| Bug encontrado pela própria conferência | Conclusão da preventiva passou a sair da abertura | A conferência acusou 32 OS concluídas antes de abrir, quando só 10 tinham sido injetadas. As outras 22 vinham de sortear a hora da abertura e a da conclusão de forma independente: preventiva realizada no mesmo dia podia abrir às 22h e concluir às 6h. Corrigido somando atraso e duração à abertura. Sujeira que ninguém escolheu injetar é sujeira que o README descreveria errado. |

### A camada bronze

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Tipo das colunas | Tudo `text` | Rejeitado tipar na carga. Se o loader convertesse, a sujeira plantada pelo gerador explodiria dentro do Python em vez de chegar na bronze para o teste do dbt encontrar, e o projeto teria movido a validação de volta para onde ele promete tirá-la. Tipagem é da silver, em SQL. |
| Nomes de coluna | Preservados como vieram, inclusive `"Air temperature [K]"` | Feio de consultar, e de propósito. A Semana 2 do plano define renome como trabalho da staging. Normalizar aqui seria resolver em Python o que o projeto se propõe a resolver em dbt, e ninguém veria o `select ... as temperatura_ar_k` que é justamente o que se quer mostrar. |
| Encoding na leitura do cabeçalho | `utf-8-sig` | O CSV do UCI começa com BOM (`EF BB BF`). Com `utf-8` puro esses bytes grudam no nome da primeira coluna, e a tabela nascia com uma coluna `"﻿UDI"`, invisível na tela e obrigatória em todo `select` da silver. Achado pela conferência de schema depois da primeira carga. Isso é consertar leitura de arquivo, não transformar dado: o conteúdo das linhas continua intocado. |
| Colunas de rastreio | `_carregado_em` e `_arquivo_origem`, com `DEFAULT` no DDL | Com o default no SQL, o `COPY` não precisa fornecer esses valores e o arquivo entra exatamente como está, sem ninguém montar linha em Python. |
| Recarga | `DROP TABLE ... CASCADE` e `CREATE` a cada execução | Rodar `uv run seed` duas vezes não dobra linha nenhuma. Rejeitado `TRUNCATE`: manteria a estrutura antiga quando o gerador ganhasse coluna nova. O `CASCADE` derruba as views que a silver tiver criado em cima, e o `dbt run` seguinte as reconstrói, que é o fluxo normal do projeto. |
| Transação | Uma só para as sete tabelas | Ou a bronze inteira troca, ou nada troca. Bronze meio velha e meio nova daria resultado que ninguém consegue reproduzir depois. |
| Leitura do arquivo na carga | `COPY` em blocos de 64 KB, direto do arquivo | Sem pandas no meio. O pandas está no gerador, que é onde ele ajuda; aqui ele só repassaria bytes, ao custo de carregar tudo na memória. Hoje são 522 KB e caberiam com folga, mas o dia em que a fonte crescer não deveria exigir reescrever o loader. |

### O projeto dbt

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Onde mora o `profiles.yml` | Versionado em `warehouse/`, contendo só `env_var()` | A regra do `CLAUDE.md` proíbe credencial no repositório, não o arquivo. Sem nenhum valor literal dentro, versionar não vaza nada e deixa quem clona com a conexão pronta: copia o `.env` e roda. Rejeitado `~/.dbt/profiles.yml`: é o caminho que a documentação mostra primeiro, mas obriga cada pessoa a criar o arquivo à mão antes do primeiro `dbt run`, e isso é um passo a mais no "roda em qualquer máquina". Conferido com `grep`: fora da estrutura YAML, o arquivo não tem um único valor. |
| Como as variáveis chegam ao dbt | `uv run --env-file .env dbt ...` | O dbt lê variável de ambiente do processo, e o `.env` é arquivo. O `--env-file` do uv resolve sem exportar nada na shell e sem dependência nova (`direnv` e afins). Quem quiser encurtar exporta `UV_ENV_FILE=.env` no shell. |
| `[tool.uv] env-file` no `pyproject.toml` | Removido | Testado e **ignorado em silêncio** pelo uv 0.12.5: a chave é aceita no arquivo e a variável não chega ao processo. Chave que não faz nada e parece que faz é pior que chave nenhuma, porque o próximo a ler o arquivo acredita nela. |
| Materialização da staging | `view` | A silver renomeia, converte tipo e limpa, e nada disso precisa ficar em disco. Reprocessar um select sobre 10 mil linhas é barato, e em troca a silver nunca fica velha em relação à bronze. |
| Materialização dos marts | `table` | O fato faz join com várias dimensões e quem consulta o star quer resposta rápida. Aqui a materialização se paga. |

### Achados da fonte que viraram decisão

Detalhamento em [`fonte-ai4i.md`](fonte-ai4i.md).

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Mapeamento leitura para máquina | Sintético, feito pelo gerador | A seção 4 do `PLANO.md` previa derivar as máquinas dos `Product ID`. Não é possível: são 10.000 valores distintos em 10.000 linhas, porque o campo identifica a peça produzida, não o equipamento. O `Product ID` continua no fato como atributo degenerado, que é o que ele é. |
| `TWF` como teste determinístico | Não | As regras de HDF, PWF e OSF reproduzem as colunas exatamente contra o dado (115/115, 95/95, 98/98) e viram teste com resposta conhecida. O TWF não fecha: a documentação do dataset fala em troca de ferramenta entre 200 e 240 minutos de desgaste, e o arquivo tem casos de 198 a 253. Testar contra a regra documentada acusaria erro que é da documentação, não do warehouse. |
| Sujeira real da fonte | Mantida, não corrigida na bronze | O AI4I traz 9 linhas com `Machine failure = 1` e nenhum modo marcado, e 18 linhas de `RNF` que não contam como falha de máquina. Bronze guarda o dado como veio. A decisão de o que fazer com essas linhas é da silver, em SQL, e o teste que as encontra vale mais que a sujeira injetada por nós, porque está em dado público que qualquer um pode conferir. |

## Semana 2

### Onde mora cada teste

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Camada onde os testes vivem | Nos dois: fonte em `warn`, staging em `error` | São duas perguntas diferentes com a mesma sintaxe. O teste na bronze responde "quanta sujeira chegou?" e não pode barrar nada, porque a bronze é o dado como veio. O teste na staging responde "o que sai daqui está limpo?" e barra. Rejeitado testar só na staging: economizaria a repetição no YAML, mas a sujeira deixaria de aparecer na tela em toda execução e a prova de que os testes valem algo dependeria de alguém lembrar de rodar um passo manual. |
| As 13 OS órfãs (8 de ativo, 5 de técnico) | Ficam na staging, com `relationships` em `warn` | São ordens com custo real. Rejeitado descartar com anti-join: o build ficaria verde e 13 ordens sumiriam do warehouse sem ninguém ver, que é o pior desfecho possível. Rejeitado `error` desde já: deixaria o build vermelho e quebraria o critério de aceite. Na Semana 3 elas passam a apontar para o membro "desconhecido" da dimensão e o teste sobe para `error`. Severidade é decisão de contrato, com prazo, não botão de mudo. |
| Nome dos schemas do dbt | Padrão: `analytics_staging` e `analytics_marts` | Rejeitado sobrescrever o macro `generate_schema_name` para gerar `silver` e `gold` literais no banco. Ficaria bonito num `\dn` do psql ao lado da `bronze`, mas custa um macro que muda comportamento global do projeto, e qualquer pessoa que já usou dbt espera encontrar o padrão. Medalhão é vocabulário do README, não do catálogo. |
| Pacote `dbt_utils` | Fora da Semana 2 | Os quatro testes que o plano pede são nativos. O pacote entra na conversa na Semana 3, quando `accepted_range`, `expression_is_true` e `unique_combination_of_columns` aparecerem juntos, e aí vira pergunta em vez de hábito. |
| Um `.yml` por modelo | Sim | Rejeitado o `_stg__models.yml` único que o guia da dbt Labs sugere: com um arquivo por modelo, cada bloco de trabalho fecha sozinho e o diff do commit mostra o modelo e o contrato dele lado a lado. |
| Sintaxe dos testes genéricos | `arguments:` separado de `config:` | A primeira execução acusou `MissingArgumentsPropertyInGenericTestDeprecation`. A partir do dbt 1.12, `to`, `field` e `values` moram num bloco `arguments:` próprio, e `severity` fica em `config:`. A forma antiga ainda roda, mas escrever certo agora evita uma migração inteira depois. |

### O que a silver faz e o que ela recusa a fazer

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| O que a staging transforma | Renome, tipo e deduplicação. Nada mais | Rejeitado somar `custo_mao_obra` com `custo_pecas` em `stg_ordens_servico`. É cálculo, e cálculo mora na gold: se a soma nascesse na silver, dois modelos poderiam somar de formas diferentes mais adiante e não haveria uma versão canônica. |
| Sujeira que é regra de negócio | Passa intacta pela silver | Os 10 custos negativos, as 10 conclusões anteriores à abertura e os 5 ativos instalados depois da primeira leitura continuam lá. Não são erro de estrutura, são violação de regra, e quem as acusa é o teste singular da Semana 3. Corrigir em silêncio na staging apagaria a prova. |
| Dedup por `row_number` e não por `distinct` | `row_number` | As 200 cópias de `leitura_contexto` são idênticas em todas as colunas, então o `distinct` daria o mesmo resultado hoje. Ele para de funcionar no dia em que a mesma chave chegar duas vezes com um campo diferente. A janela obriga a responder qual cópia vence, e a resposta fica escrita no `order by`. |
| `not_null` em `data_conclusao` | Não existe | 36 preventivas foram planejadas e não aconteceram. O nulo ali é a resposta, não a ausência dela, e é metade da pergunta de aderência ao plano. Teste que exigisse valor estaria errado sobre o negócio, não sobre o dado. |
| `relationships` em `udi_origem` | Não existe | O teste genérico do dbt trata nulo como violação, e `udi_origem` é nulo nas 651 preventivas por construção. A checagem certa é um teste singular filtrando `tipo_os = 'corretiva'`, e ele é da Semana 3. |
| `quote: true` nas colunas do AI4I | Obrigatório no `sources.yml` | A bronze guardou `"UDI"` e `"Air temperature [K]"` com aspas, então o nome real tem maiúscula e espaço. Sem `quote: true` o dbt compila `select UDI`, o Postgres rebaixa para `udi` e o teste quebra por coluna inexistente. É o preço concreto de ter mantido os nomes feios na bronze, e ele termina aqui. |

### A prova de que os testes pegam a sujeira

O critério de aceite do projeto diz que desligar a limpeza tem que quebrar o build.
Foram duas verificações, nesta ordem.

**1. Comentar o filtro do dedup em `stg_leitura_contexto`.** Uma linha, `where _versao = 1`:

```
9 of 9 FAIL 200 unique_stg_leitura_contexto_udi ........... [FAIL 200 in 0.07s]
  Got 200 results, configured to fail if != 0
Done. PASS=8 WARN=0 ERROR=1 SKIP=0 NO-OP=0 REUSED=0 TOTAL=9
```

Repare que os outros 8 testes do modelo continuaram passando. Quebrou exatamente o
teste que guarda aquela linha, e nenhum outro.

**2. Recarregar a bronze sem sujeira nenhuma**, com `uv run seed --sem-sujeira`, e
rodar o build inteiro:

```
Done. PASS=97 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=97
```

Zero avisos. Isso fecha a outra ponta do argumento: os 5 avisos do build normal vêm da
sujeira injetada, e não de um modelo mal escrito que avisaria de qualquer jeito.

**O build normal, com a sujeira no lugar**, tem 97 nós e este desenho:

```
Done. PASS=92 WARN=5 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=97
```

Os 5 avisos, e o que cada um significa:

| Onde | Aviso | Leitura |
|---|---|---|
| fonte | `unique` em `leitura_contexto.udi`, 200 | Chegaram 200 duplicatas na bronze |
| fonte | `relationships` de `ordens_servico.codigo_ativo`, 8 | 8 OS apontam para máquina que não existe |
| fonte | `relationships` de `ordens_servico.matricula_tecnico`, 5 | 5 OS apontam para técnico que não existe |
| staging | `relationships` de `stg_ordens_servico.codigo_ativo`, 8 | As mesmas 8, que a silver não descarta de propósito |
| staging | `relationships` de `stg_ordens_servico.matricula_tecnico`, 5 | As mesmas 5 |

A lista inteira cabe num parágrafo: **a fonte tem três avisos e a staging tem dois.** O
que desapareceu no caminho foram as 200 duplicatas, e o que sobrou foram as órfãs, que
a silver preserva de propósito. A diferença entre as duas listas é o trabalho que a
camada silver fez, medido em vez de afirmado.

### Achado sobre o comando

O comentário do `profiles.yml` documentava `dbt build --project-dir warehouse`, que
falha quando rodado da raiz:

```
Error: Invalid value for '--profiles-dir': Path '/home/gabriel/.dbt' does not exist.
```

`--project-dir` diz onde está o projeto, e não onde está o `profiles.yml`: sem
`--profiles-dir`, o dbt procura em `~/.dbt`. Na Semana 1 isso passou porque os comandos
foram rodados de dentro de `warehouse/`, onde o dbt acha o arquivo no diretório
corrente. Comentário corrigido.

### Aviso que fica até a Semana 3

Todo build imprime `Configuration paths exist in your dbt_project.yml file which do not
apply to any resources: models.warehouse.marts`. Está certo: o bloco `marts` existe no
`dbt_project.yml` desde a Semana 1, com a decisão de materializar como `table`, e a
pasta `models/marts/` ainda não tem nenhum modelo. Some sozinho quando o primeiro fato
nascer. Rejeitado tirar o bloco para calar o aviso: perderia o comentário que explica
por que a gold é `table` e a silver é `view`.

## Semana 3

### As cinco decisões que o desenho tinha deixado em aberto

Levantadas com opções e custos no fim da Semana 2, em
[`modelo-dimensional.md`](modelo-dimensional.md), e fechadas no primeiro dia da Semana 3
com os números conferidos no banco antes de escolher.

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Leitura com mais de um modo de falha | Fato próprio `fct_falhas`, grain (leitura, modo) | 324 leituras têm um modo marcado, 23 têm dois e 1 tem três. Com a definição de falha adotada abaixo, o fato tem 382 linhas e a pergunta "quantas paradas por modo" vira um `group by`. Rejeitado manter as cinco flags booleanas no fato: funciona, já estava pronto na silver, e não é dimensional, porque contar por modo viraria cinco somas separadas e um modo novo viraria coluna nova. Rejeitada a tabela ponte: é o Kimball clássico para multivalorado, mas traz o problema de peso, e somar custo por modo contaria a mesma parada duas vezes se ninguém ratear. O preço da escolha: duas tabelas de fato para o mesmo evento, e quem consulta precisa saber qual usar. |
| O que a gold chama de "falha" | União: `falha_maquina` ou algum modo marcado, 357 eventos | A fonte discorda de si mesma em 27 linhas, e o desempate veio do dado e não do gosto: as 357 OS corretivas têm `udi_origem` preenchido nas 357, e 357 é exatamente o tamanho da união. Com ela, o teste "toda corretiva aponta para uma leitura com falha" fecha em zero. Rejeitado `falha_maquina` manda (339): 18 corretivas ficariam apontando para leitura que a gold não considera falha. Rejeitado "algum modo marcado" manda (348): 9 ficariam, e o membro INDETERMINADO perderia a razão de existir. O custo aceito, e que precisa estar escrito no README: o warehouse conta 357 falhas onde o dataset publica 339, porque a definição aqui é "evento que levou um técnico até a máquina", que é a definição de um warehouse de manutenção, e não o rótulo de um dataset de classificação. |
| Como a SCD2 é construída | Laço de `dbt snapshot`, uma rodada por data de corte | São 31 datas distintas de mudança, entre 2024-03-04 e 2025-10-23, sobre 27 das 80 máquinas. Um modelo de estado do ativo parametrizado por `var` responde "como estava o parque nesta data", e o snapshot roda uma vez por data, em ordem crescente. Resultado esperado: 111 versões, que são 80 mais 31. Rejeitado montar o histórico direto em SQL com window function: é determinístico, roda num comando e não tem armadilha de ordem, mas não usa `dbt snapshot`, que é o que a seção 3 do plano decidiu e o que a entrevista pergunta. O custo aceito: o README ganha um passo entre o `uv run seed` e o `dbt build`, e a ordem crescente do laço passa a importar. |
| Onde mora o turno | `dim_turno`, três linhas | O plano tinha listado `turno` como atributo de uma dimensão de grain diário, e há três turnos por dia: não cabe. Escolhida a dimensão própria em vez do atributo degenerado no fato porque `dim_tecnico` também tem turno, então ela nasce conformada, usada por um fato e descrevendo uma dimensão, que é exatamente o que a bus matrix existe para mostrar. `dim_tempo` fica com o clássico: um dia por linha, dia útil, mês, trimestre e estação. |
| Pacote `dbt_utils` | Entra, versão 1.4.1 fixa | Três testes da semana não existem no dbt: `accepted_range` para a faixa física dos sensores, `expression_is_true` para regra de negócio e `unique_combination_of_columns` para provar o grain de `fct_falhas` e de `dim_ativo`. Escrever os três à mão funcionaria, e custaria uma dúzia de consultas de boilerplate só para faixa de sensor. Gerenciar pacote é parte do ofício, e o projeto passa a mostrar `packages.yml`, `dbt deps` e `package-lock.yml`. Os testes que são de verdade deste domínio (sobreposição de vigência na SCD2, histórico completo, corretiva sem leitura) continuam escritos à mão em `tests/`, porque pacote nenhum conhece essa regra. |

Sobre a versão do pacote: fixa em `1.4.1`, não em faixa. Com `>=1.3.0` o `dbt deps` de
amanhã pode trazer outra versão e mudar o resultado de um teste sem ninguém ter tocado
no projeto. O `package-lock.yml` que o `dbt deps` gera é versionado, pela mesma razão do
`uv.lock`, e o `dbt_packages/` fica no `.gitignore`, porque se refaz sozinho.

### O que fazer quando o teste encontra a sujeira que nós mesmos plantamos

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Severidade dos testes de regra de negócio | `severity: error` com `error_if` no limiar auditado | Os 10 custos negativos, as 10 conclusões anteriores à abertura e as 5 instalações posteriores à primeira leitura são sujeira injetada, e continuam no warehouse por decisão da Semana 2. Com `error_if: '>10'` e `warn_if: '>0'`, os casos conhecidos pintam amarelo, o build passa, e o 11º caso pinta vermelho e barra. O teste deixa de ser "existe problema?" e passa a ser "o problema é maior do que a linha de base que auditamos?". Rejeitado deixar tudo em `warn`, como a Semana 2 fez com as órfãs: seria consistente e simples, e o teste nunca barraria nada, nem quando a sujeira dobrasse. Rejeitado tirar as linhas suspeitas do fato para uma quarentena: contraria a decisão da Semana 2 de que ordem com custo real não some do warehouse sem ninguém ver. O custo aceito: o número no `error_if` precisa ser mantido em dia se o gerador mudar, e por isso o comentário do `.yml` diz de onde ele veio. |

### As convenções que valem para a gold inteira

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Surrogate key | Inteira, gerada com `row_number()` sobre ordem determinística | O código natural continua na dimensão como atributo, para conferência, e o fato guarda a surrogate. A razão é a `dim_ativo`: com SCD2, `MAQ-017` deixa de identificar uma linha e passa a identificar um conjunto de versões, e um fato que faça join por `codigo_ativo` sozinho casa com todas as versões de uma vez e multiplica o custo pelo número de reformas. O custo aceito, e declarado: como os marts são `table` reconstruída a cada build, a chave é estável dentro de um build e não entre builds. No dia em que um mart virar `incremental`, ela precisa passar a ser hash (`dbt_utils.generate_surrogate_key`). |
| Chave de `dim_tempo` | `YYYYMMDD` como inteiro | É a exceção clássica do Kimball: a chave da dimensão de data é legível, ordenável e dispensa join para filtrar por período. Rejeitado usar `row_number()` aqui por consistência com as outras: consistência que custa legibilidade em toda consulta do warehouse não vale. |
| Fato que não acha a dimensão | Membro desconhecido fixo em `-1`, nunca FK nula | As 8 OS órfãs de ativo e as 5 de técnico continuam no warehouse com custo real, e passam a apontar para o membro desconhecido. Fato com FK nula quebra o `inner join` e some da contagem sem avisar, que é o pior desfecho: o número fica errado e ninguém vê. Com o membro `-1`, os `relationships` que a Semana 2 deixou em `warn` sobem para `error` na gold, e a promessa registrada lá é cumprida. |
| Início de vigência da primeira versão de cada ativo | `-infinity`, não a data de instalação | Achado que muda o modelo: 365 leituras acontecem antes da data de instalação do próprio ativo, em 5 máquinas, e isso é sujeira injetada de propósito. Se a versão 1 começasse na instalação, essas 365 leituras não achariam versão nenhuma e cairiam no ativo desconhecido, e o fato perderia dado por causa de um erro de cadastro. Quem acusa a instalação futura é teste singular, não descarte silencioso. |
| Tamanho de `dim_modo_falha` | Sete linhas, não seis | O `modelo-dimensional.md` tinha escrito seis, contando os cinco modos do AI4I mais o INDETERMINADO. Faltava uma: as 651 preventivas não têm modo, e precisam do membro NAO_APLICA, senão volta a FK nula que a linha acima proíbe. A surrogate de cada modo vai escrita no próprio CSV do seed, para a chave não depender de ordem de carga. |

### As tres dimensoes que nao dependem de ninguem

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Nome de mês e de dia em `dim_tempo` | Escritos em `case`, não em `to_char` | `to_char(data, 'TMMonth')` devolve o nome no idioma do `lc_time` do servidor. A gold passaria a depender de configuração de container, e o mesmo modelo daria "janeiro" aqui e "January" na máquina de quem clonasse. É o mesmo problema de locale que fez a Semana 1 recusar a imagem alpine, aparecendo do outro lado. Rejeitado também fixar `lc_time` no compose: resolveria, e escondendo a dependência em vez de eliminá-la. |
| Intervalo de `dim_tempo` | 2024-01-01 a 2026-12-31, 1.096 dias | As leituras vão até 2025-12-31 e a última conclusão de OS é 2026-02-12. A folga é de propósito: estender uma dimensão de data depois obriga a recarregar todo fato que aponta para ela, e o custo de guardar dia que ninguém usa é uma linha. |
| Membro desconhecido em `dim_turno` | Não existe | `stg_leitura_contexto` já tem `not_null` e `accepted_values` em `turno`, então os três valores estão garantidos por teste antes de chegar na gold. Membro `-1` numa dimensão que não pode receber desconhecido seria linha morta, e linha morta em dimensão vira `where` defensivo em toda consulta. |
| Chave de `dim_modo_falha` | Escrita no próprio CSV do seed | Rejeitado gerar com `row_number()` sobre o seed: funcionaria hoje, e no dia em que alguém inserisse uma linha no meio do arquivo, todas as chaves abaixo dela mudariam e os fatos passariam a apontar para o modo errado, sem erro nenhum aparecer. Chave que depende de ordem de arquivo não é chave. |
| Coluna `origem` em `dim_modo_falha` | Existe, com valores `AI4I` e `warehouse` | Separa os cinco modos que a fonte publica das duas linhas que este projeto inventou (INDETERMINADO e NAO_APLICA). O README precisa declarar o que é dado e o que é suposição, e aqui a declaração fica dentro da própria dimensão, onde quem consulta vê sem ler documento nenhum. |

O aviso `Configuration paths exist in your dbt_project.yml file which do not apply to
any resources: models.warehouse.marts`, que a Semana 2 registrou como pendente, sumiu
com o nascimento da `dim_tempo`, exatamente como estava previsto.

### A SCD2, e o erro de um a menos que quase passou

O laço de `dbt snapshot` funcionou na primeira tentativa e produziu **110 versões**,
onde a conta dizia 111. A diferença de uma linha era o projeto inteiro:

| Achado | O que era |
|---|---|
| A `MAQ-066` tinha 3 mudanças e só 3 versões, quando deveria ter 4 | Ela trocou de linha em 2024-03-04, que é **a primeira data de mudança do parque**, e portanto a primeira data de corte do laço. A primeira rodada do snapshot já a viu alterada, então o estado anterior dela nunca foi gravado. |

A correção não foi cravar uma data no script, e sim o laço passar a rodar **32 vezes em
vez de 31**: o dia anterior à primeira mudança, que grava a linha de base, mais as 31
datas de mudança. A data da linha de base é calculada (`min(data_mudanca) - 1`), para o
laço continuar certo se a semente do gerador mudar.

Vale registrar como o erro apareceu, porque é o tipo que não aparece: nada falhou, nada
ficou vermelho, e a única pista era um número um a menos numa conferência que só existia
porque alguém decidiu conferir. Sem a contagem esperada escrita em algum lugar, a
`MAQ-066` teria entrado no warehouse tendo nascido na linha USI-L04, e a resposta sobre
o passado dela estaria errada com toda a confiança do mundo.

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Estratégia do snapshot | `timestamp`, com `updated_at` na data da mudança | Rejeitada a `check`, que compara colunas: ela carimba o `dbt_valid_from` com a hora em que o comando rodou, e o histórico ficaria com data de execução em vez de data de negócio. Duas pessoas rodando o projeto em dias diferentes teriam warehouses diferentes. |
| Materialização do `int_ativo_estado` | `ephemeral` | Não é economia de disco, é requisito. O modelo depende de `var('data_corte')`, e o snapshot precisa resolver esse var na hora em que o snapshot roda. Como view, o valor ficaria congelado no último `dbt run` e o laço custaria dois comandos por data em vez de um. Verificado na 1.12.3: `ref()` de modelo ephemeral dentro de snapshot é inlinado como CTE, e funciona. |
| Onde o laço lê as datas | Macro `datas_de_mudanca`, no dbt | Rejeitado um `psql` dentro do script: ele precisaria descobrir host, porta e senha por conta própria, e o projeto passaria a ter duas definições de "onde fica o banco" para divergir uma da outra. Pela macro, o laço usa a mesma conexão do `profiles.yml`. |
| Como o script conta o que gravou | Consulta ao banco no fim, não a saída do dbt | Primeira versão do script lia `SELECT 80` da linha do snapshot. A partir da segunda rodada aquilo vira `INSERT 0 0`, que é o retorno do último comando enviado ao Postgres e não a contagem de versões abertas. Número que parece contagem e não é contagem é pior que número nenhum. De quebra, o `grep` que não achava nada matava o script pelo `set -e`, em silêncio, na segunda data. |
| Teste de mudança anterior à instalação | Existe, e hoje retorna zero | Não está lá por regra de negócio, está lá protegendo o mecanismo. Se um ativo tivesse instalação posterior a alguma mudança dele, o `atualizado_em` daria um passo para trás entre dois cortes, e a estratégia `timestamp` descartaria a mudança em silêncio. Zero linhas hoje, e o teste fica para o dia em que a semente mudar. |

**A prova de que o teste de completude pega o erro.** Derrubando o snapshot e rodando
`dbt snapshot` uma vez só, que é o que acontece com quem clona o projeto e roda `dbt
build` sem o laço:

```
1 of 1 FAIL 1 assert_historico_ativo_completo .................... [FAIL 1 in 0.05s]
  Got 1 result, configured to fail if != 0
Done. PASS=0 WARN=0 ERROR=1 SKIP=0 NO-OP=0 REUSED=0 TOTAL=1
```

São 80 versões onde deveriam ser 111. O build fica vermelho e a linha que o teste
devolve diz o comando a rodar.

### As duas bordas da vigencia em dim_ativo

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Início da vigência da primeira versão | `-infinity` | Já registrado nas convenções da gold, e vale repetir o número: são 365 leituras anteriores à data de instalação do próprio ativo, em 5 máquinas. Com a vigência começando na instalação, essas leituras não achariam versão e cairiam no ativo desconhecido. A `data_instalacao` continua na dimensão como atributo, para o teste ter o que comparar. |
| Fim da vigência da versão atual | `infinity`, não `NULL` | Com `infinity`, o join do fato é `evento >= valido_de and evento < valido_ate` e acabou. Com `NULL`, toda consulta precisaria de `coalesce` ou de `is null` na condição, e quem esquecesse perderia exatamente as linhas da versão vigente, sem erro nenhum aparecer. Rejeitado o `NULL` que o dbt entrega por padrão no `dbt_valid_to`: é a convenção do snapshot, não a da dimensão, e a dimensão é quem tem que ser fácil de consultar. |
| Intervalo aberto ou fechado | `[valido_de, valido_ate)`, fechado na esquerda | Evento que cai exatamente na data da mudança pertence à versão nova. As duas escolhas são defensáveis, e só uma delas não conta o mesmo evento duas vezes. Está escrito no modelo e no teste de sobreposição, que por isso compara com `<` estrito. |
| Chave da dimensão | Por versão, não por máquina | 111 versões para 80 máquinas. `MAQ-066` sozinha tem quatro, porque trocou de linha três vezes. É o que torna errado o join de fato por `codigo_ativo`: ele casaria com as quatro de uma vez. |

**A prova de que o teste de sobreposição pega o defeito.** Trocando o
`coalesce(dbt_valid_to, 'infinity')` por `'infinity'` fixo, que faz toda versão parecer
vigente:

```
5 of 19 FAIL 36 assert_dim_ativo_sem_sobreposicao ............... [FAIL 36 in 0.07s]
  Got 36 results, configured to fail if != 0
```

São 36 pares, e o número fecha com a estrutura do parque: 24 máquinas de duas versões
dão um par cada, 2 máquinas de três versões dão três pares cada, e a `MAQ-066` com
quatro versões dá seis. Sem o teste, o defeito apareceria como custo dobrado em relatório,
que é o erro que ninguém estranha porque parece que a máquina gastou muito.

### As duas SCD1

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Turno em `dim_tecnico` | Texto, não FK para `dim_turno` | Dimensão apontando para dimensão é outrigger, e outrigger é snowflake entrando pela porta dos fundos numa modelagem que o rejeitou pela porta da frente. A conformidade entre os dois turnos é sustentada pelo `accepted_values` dos dois lados valendo sobre os mesmos três valores. O que `dim_turno` conforma de verdade são os dois fatos de leitura. |
| `custo_hora` no técnico desconhecido | `NULL`, não zero | Zero afirmaria que a hora daquele técnico custa nada, o que é diferente de não se saber quanto custa. As 5 OS órfãs de técnico têm custo de mão de obra gravado na própria ordem, então este campo não entra em soma nenhuma. |
| `codigo_linha` do ativo desconhecido | `'DESCONHECIDO'`, igual ao da linha desconhecida | Não é coincidência de nome, é o que fecha o caminho: o fato resolve o local pelo `codigo_linha` da versão do ativo, então a OS órfã cai no ativo desconhecido, que aponta para a linha desconhecida, sem `coalesce` nenhum na consulta. Membro desconhecido que não se encadeia com o da dimensão vizinha obriga cada fato a tratar o caso à mão. |
| `dim_tecnico` e `dim_local` como SCD1 | Sim | O custo real de manter SCD2 é uma versão por mudança, o join de todo fato passando a depender da data do evento, e um teste de sobreposição para manter de pé. Isso se paga quando alguma pergunta depende do passado. Nenhuma das cinco pergunta o que o técnico era antes, e a de número 5 pergunta exatamente isso sobre o ativo. Por isso só ele é SCD2. |

### fct_leituras, e a prova do join errado

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Duas medidas derivadas no fato | `diferenca_temperatura_k` e `potencia_w` | São grandezas físicas com significado próprio, e são o que duas das três regras verificadas do AI4I usam: HDF olha a diferença de temperatura com a rotação, PWF olha a potência. Calculadas uma vez na gold em vez de reescritas em cada consulta e em cada teste. O produto desgaste vezes torque, do OSF, **não** entrou: aquilo é intermediário de uma regra, não grandeza física, e o lugar dele é dentro do teste. |
| Duas colunas de falha lado a lado | `houve_falha` (357) e `falha_declarada_fonte` (339) | A decisão B escolheu a união, e manter o rótulo original ao lado torna a divergência de 18 linhas auditável dentro do próprio dado. Mesmo espírito da coluna `origem` em `dim_modo_falha`: quem consulta vê a diferença sem abrir documento nenhum. |
| `codigo_ativo` no fato | Não existe | Com SCD2, o código natural identifica um conjunto de versões, e deixá-lo no fato seria oferecer a quem consulta exatamente a coluna com que se erra o join. O código natural mora na dimensão, para conferência. |
| Cast de `pi()` para numeric | Obrigatório | `pi()` devolve `double precision`, o produto inteiro sobe para double, e o `round` de duas casas do Postgres só existe para `numeric`. Sem o cast o modelo não compila. Vale registrar porque parece detalhe e é o tipo de coisa que trava um build às onze da noite. |

**Quanto custa errar o join, medido.** As duas formas de ligar as 10.000 leituras à
`dim_ativo`:

```
            forma            | linhas
-----------------------------+--------
 join so pelo codigo natural |  14329
 join com a vigencia         |  10000
```

São 43% de linhas a mais, e nenhum erro aparece. Onde dói mais:

| Máquina | Versões | Leituras que viram |
|---|---|---|
| `MAQ-066` | 4 | 58 viram 232 |
| `MAQ-060` | 2 | 137 viram 274 |

O fato multiplica cada leitura pelo número de versões que a máquina teve, e o resultado
é um custo maior, não um erro. É o defeito mais caro que uma SCD2 permite cometer,
porque quem lê o relatório conclui que a máquina gastou muito, e não que a consulta está
errada. É por isso que a chave é resolvida na construção do fato, e não deixada para
quem consulta.

### fct_falhas, o fato sem medida

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| De onde `fct_falhas` lê as chaves | De `fct_leituras`, não da staging | A resolução da versão do ativo pela data já aconteceu lá. Refazer aquele join aqui criaria duas cópias da mesma lógica, e duas cópias divergem um dia sem ninguém ver. Lendo o fato pronto, a mesma leitura tem obrigatoriamente a mesma versão de ativo nos dois fatos. Isso é diferente de **consumir** um fato através do outro: `fct_falhas` carrega as próprias FKs, e "falhas por setor" é um join só. |
| Medidas em `fct_falhas` | Nenhuma | Fato sem medida, o factless fact table do Kimball: a medida é a contagem de linhas. Rejeitado trazer `duracao_horas` e custo da OS: eles vivem num grain onde a falha tem um modo só, e somá-los por modo aqui contaria a mesma parada duas vezes nas 24 leituras multimodo. Quem quiser hora parada por modo usa `fct_ordens_servico`, e isso está escrito na pergunta 3 do modelo dimensional. |
| Como o unpivot é escrito | `union all` de cinco ramos, à mão | Rejeitada macro de unpivot: são cinco modos fixos, publicados pela fonte, e o `union all` explícito se lê de cima a baixo sem abrir outro arquivo. Macro se paga quando o número de colunas é grande ou variável, e aqui ele é cinco e não muda. |

**A conferência que vale mais que a contagem de linhas.** As ocorrências por modo saíram
assim:

| Modo | `fct_falhas` | `docs/fonte-ai4i.md` |
|---|---|---|
| HDF | 115 | 115 |
| OSF | 98 | 98 |
| PWF | 95 | 95 |
| TWF | 46 | 46 |
| RNF | 19 | 19 |
| INDETERMINADO | 9 | as 9 sem causa |

O documento da fonte foi escrito na Semana 1, antes de existir qualquer modelo da gold.
O fato reproduzir aqueles números agora é conferência contra um valor que já estava
escrito, e não contra um número que o próprio modelo produziu.

**A prova de que o teste `falha exige modo` pega o erro.** Trocando o `left join` por
`join` na montagem dos modos, que é o engano natural de quem escreve o modelo:

```
2 of 17 FAIL 9 assert_falha_tem_modo ........................ [FAIL 9 in 0.17s]
  Got 9 results, configured to fail if != 0
```

São exatamente as 9 leituras que a fonte declara como falha sem marcar modo nenhum. Com
o inner join elas sumiriam do fato, o total cairia de 382 para 373, e nenhum erro
apareceria: só um número menor que ninguém tem com o que comparar.

### fct_ordens_servico, e uma promessa da Semana 2 corrigida

**A correção primeiro.** A Semana 2 registrou, sobre as 13 OS órfãs, que "na Semana 3
elas passam a apontar para o membro desconhecido da dimensão e o teste sobe para
`error`". A primeira metade aconteceu. A segunda estava errada como escrita, e só ficou
claro na implementação:

O teste que estava em `warn` é o `relationships` da **staging**, e ele não pode subir
para `error`. A staging é 1:1 com a origem, as 8 ordens continuam apontando para máquina
que não existe, e subir a severidade lá só deixaria o build vermelho sem consertar nada.
Quem sobe para `error` é o `relationships` **da gold**, que é um teste novo, sobre uma
coluna nova (`ativo_sk`), e que passa porque o fato roteia as órfãs para o membro `-1`.

O aviso da staging continua no lugar, e continua sendo a medição de quanta sujeira
chegou. A diferença entre as duas camadas é o trabalho que a gold fez, medido em vez de
afirmado, do mesmo jeito que a Semana 2 mediu o trabalho da silver.

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Versão do ativo resolvida por qual data | Pela **abertura** da ordem | Não pela conclusão e não pelo cadastro de hoje. Ordem aberta antes de uma reforma pertence à máquina como ela era antes, e é isso que permite comparar custo antes e depois. Pela conclusão, uma ordem aberta antes e fechada depois da reforma migraria de versão e a comparação perderia o caso mais interessante. |
| `dim_tempo` em dois papéis | `tempo_sk_abertura` e `tempo_sk_conclusao` | Role-playing: a mesma tabela cumprindo dois papéis no mesmo fato. Rejeitado criar uma `dim_data_conclusao` separada: seria a mesma tabela duplicada, com dois lugares para corrigir quando um atributo mudasse. |
| As 36 preventivas sem conclusão | `tempo_sk_conclusao = -1` | O nulo ali é a resposta, não a ausência dela: elas foram planejadas e não aconteceram, e isso é metade da pergunta sobre aderência ao plano. Com FK nula, exatamente essas 36 sumiriam de qualquer join com `dim_tempo`, que são as linhas que mais importam naquela pergunta. |
| Datas mantidas no fato além das FKs | Sim | `data_abertura` e `data_conclusao` continuam como timestamp ao lado das chaves, porque a diferença entre elas é medida em horas e uma dimensão de grain diário não responde isso. Redundância deliberada, e barata. |
| Caminho do local para a ordem órfã | `coalesce(codigo_linha, 'DESCONHECIDO')` antes do join | É o que faz a ordem sem ativo cair também no local desconhecido pelo mesmo caminho, em vez de cada fato tratar o caso à mão. Conferido: as 8 órfãs de ativo são exatamente as 8 com `local_sk = -1`. |

**A prova do limiar conhecido.** Com o limiar em `>8`, as 8 órfãs pintam amarelo e o
build passa. Baixando para `>7`, que simula uma nona órfã aparecendo:

```
  Got 8 results, configured to fail if >7
Done. PASS=21 WARN=1 ERROR=1 SKIP=0 NO-OP=0 REUSED=0 TOTAL=23
```

O teste deixa de perguntar "existe problema?" e passa a perguntar "o problema cresceu?".
É a diferença entre um aviso que todo mundo aprende a ignorar e um contrato com a linha
de base escrita dentro dele.

## Pendentes

As cinco decisões que este bloco listava foram todas fechadas na seção da Semana 3
acima. O que sobra é da Semana 4.

| Assunto | Quando | O que está em jogo |
|---|---|---|
| As 5 perguntas de negócio em SQL comentado | Semana 4 | São o consumo da gold e o critério de aceite do projeto. A de número 5, custo por máquina depois da reforma, é a que só existe com SCD2. |
| A falha real do projeto, documentada | Semana 4 | O padrão da trilha pede um erro de verdade contado por inteiro. Candidatos até aqui: as 22 OS concluídas antes de abrir que ninguém injetou, achadas pela conferência da Semana 1, e o `[tool.uv] env-file` que o uv ignora em silêncio. |
| Metabase lendo a gold | Semana 4, opcional | É o corte previsto se a semana estourar. Nunca as perguntas. |
