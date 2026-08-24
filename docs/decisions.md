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

## Pendentes

Decisões que o plano ainda vai cobrar, registradas aqui para não se perderem. As cinco
da Semana 3 estão desenvolvidas, com opções e custos, em
[`modelo-dimensional.md`](modelo-dimensional.md).

| Assunto | Quando | O que está em jogo |
|---|---|---|
| Leitura com mais de um modo de falha | Semana 3 | 24 leituras têm dois ou três modos marcados, e a FK simples `modo_falha_sk` do `PLANO.md` não comporta. Saídas: manter as cinco flags no fato, tabela ponte, ou um `fct_falhas` próprio de grain (leitura, modo), que teria 373 linhas contra 348 leituras com falha. |
| Qual definição de "falha" a gold adota | Semana 3 | `Machine failure` e "algum modo marcado" discordam em 27 linhas. O warehouse precisa escolher uma, documentar, e não deixar as duas circulando. |
| Como a SCD2 vai ser construída | Semana 3 | `dbt snapshot` grava o que enxerga na hora em que roda, e `bronze.ativos` é estático depois da carga: as 31 mudanças não viram histórico sozinhas. Ou o histórico é montado em SQL, ou o snapshot roda uma vez por data de corte. |
| `dim_tempo` e o turno | Semana 3 | O `PLANO.md` listou `turno` como atributo de uma dimensão de grain diário, e há três turnos por dia. Vira atributo degenerado no fato ou uma `dim_turno` conformada com `dim_tecnico`. |
| Trazer o `dbt_utils` | Semana 3 | Três testes da gold pedem `accepted_range`, `expression_is_true` e `unique_combination_of_columns`. Sem o pacote, viram teste singular escrito à mão. O `CLAUDE.md` manda perguntar antes de adicionar dependência. |
