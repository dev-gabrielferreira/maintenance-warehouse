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
| Aderência do plano preventivo | 85% dentro de 7 dias | Os 15% restantes atrasam de 15 a 60 dias, e um terço deles não acontece (conclusão vazia). Sem preventiva atrasada, a pergunta "preventiva em dia reduz corretiva no trimestre seguinte" não teria os dois lados para comparar. Resultado: 651 preventivas, 44 não executadas. |
| Quantidade de sujeira | Fixa e declarada em constante no topo do módulo | 200 leituras duplicadas, 8 OS órfãs de ativo, 5 de técnico, 10 com custo negativo, 10 com datas invertidas, 5 ativos instalados depois da primeira leitura. Números conferidos um a um, e todos vão a zero com `--sem-sujeira`. O README pode dizer "são 200 duplicatas" sem ninguém precisar contar. |
| Bug encontrado pela própria conferência | Conclusão da preventiva passou a sair da abertura | A conferência acusou 32 OS concluídas antes de abrir, quando só 10 tinham sido injetadas. As outras 22 vinham de sortear a hora da abertura e a da conclusão de forma independente: preventiva realizada no mesmo dia podia abrir às 22h e concluir às 6h. Corrigido somando atraso e duração à abertura. Sujeira que ninguém escolheu injetar é sujeira que o README descreveria errado. |

### Achados da fonte que viraram decisão

Detalhamento em [`fonte-ai4i.md`](fonte-ai4i.md).

| Decisão | Escolha | Por quê, e o que foi rejeitado |
|---|---|---|
| Mapeamento leitura para máquina | Sintético, feito pelo gerador | A seção 4 do `PLANO.md` previa derivar as máquinas dos `Product ID`. Não é possível: são 10.000 valores distintos em 10.000 linhas, porque o campo identifica a peça produzida, não o equipamento. O `Product ID` continua no fato como atributo degenerado, que é o que ele é. |
| `TWF` como teste determinístico | Não | As regras de HDF, PWF e OSF reproduzem as colunas exatamente contra o dado (115/115, 95/95, 98/98) e viram teste com resposta conhecida. O TWF não fecha: a documentação do dataset fala em troca de ferramenta entre 200 e 240 minutos de desgaste, e o arquivo tem casos de 198 a 253. Testar contra a regra documentada acusaria erro que é da documentação, não do warehouse. |
| Sujeira real da fonte | Mantida, não corrigida na bronze | O AI4I traz 9 linhas com `Machine failure = 1` e nenhum modo marcado, e 18 linhas de `RNF` que não contam como falha de máquina. Bronze guarda o dado como veio. A decisão de o que fazer com essas linhas é da silver, em SQL, e o teste que as encontra vale mais que a sujeira injetada por nós, porque está em dado público que qualquer um pode conferir. |

## Pendentes

Decisões que o plano ainda vai cobrar, registradas aqui para não se perderem:

| Assunto | Quando | O que está em jogo |
|---|---|---|
| Onde mora o `profiles.yml` | Bloco 1.7 | Fora do repositório em `~/.dbt/`, ou dentro do repositório contendo só chamadas `env_var()`. A segunda é mais reprodutível para quem clona e não coloca segredo no git. |
| Leitura com mais de um modo de falha | Semana 3 | 24 leituras têm dois ou três modos marcados. A FK simples `modo_falha_sk` da seção 5 do `PLANO.md` não comporta. Saídas possíveis: manter as cinco flags no fato, criar tabela ponte, ou criar um fato próprio de falhas com grain (leitura, modo). |
| Qual definição de "falha" a gold adota | Semana 3 | `Machine failure` e "algum modo marcado" discordam em 27 linhas. O warehouse precisa escolher uma, documentar, e não deixar as duas circulando. |
