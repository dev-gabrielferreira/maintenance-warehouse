-- Silver da costura entre a fonte publica e o mundo sintetico: em qual maquina e em
-- qual instante cada UDI aconteceu.
--
-- E' o unico modelo da semana que joga linha fora, e por isso o unico onde "1:1 com
-- a origem" nao vale: entram 10.200 linhas, saem 10.000. As 200 a mais sao
-- duplicatas injetadas de proposito pelo gerador, e o `where _versao = 1` la' embaixo
-- e' toda a limpeza. Comentar aquela linha faz o unique de udi quebrar o build, e
-- essa demonstracao esta' colada em docs/decisions.md.
--
-- Por que row_number e nao `select distinct`. Aqui as 200 copias sao identicas em
-- todas as colunas, entao o distinct daria o mesmo resultado. Mas ele so' funciona
-- enquanto a duplicata for identica: no dia em que a mesma chave chegar duas vezes
-- com um campo diferente, o distinct devolve as duas e o unique quebra do mesmo
-- jeito. A janela obriga a responder a pergunta que o distinct deixa em aberto,
-- que e' qual das copias vence, e a resposta fica escrita no `order by`.

with fonte as (

    select * from {{ source('bronze', 'leitura_contexto') }}

),

tipado as (

    select
        udi::int            as udi,
        codigo_ativo,
        instante::timestamp as instante,
        turno,

        _carregado_em,
        _arquivo_origem

    from fonte

),

numerado as (

    select
        *,
        -- Vence a copia mais antiga a chegar. Com duplicata identica o criterio nao
        -- muda o resultado, mas ele precisa existir e ser deterministico, senao o
        -- modelo devolve linha diferente a cada execucao sem ninguem perceber.
        row_number() over (
            partition by udi
            order by _carregado_em, codigo_ativo, instante
        ) as _versao

    from tipado

),

deduplicado as (

    select
        udi,
        codigo_ativo,
        instante,
        turno,
        _carregado_em,
        _arquivo_origem

    from numerado
    where _versao = 1

)

select * from deduplicado
