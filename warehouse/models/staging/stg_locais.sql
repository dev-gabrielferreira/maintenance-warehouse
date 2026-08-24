-- Silver dos locais: 12 linhas de producao, 5 setores, uma planta.
--
-- Nao ha' nada para converter aqui: todas as colunas sao texto na origem e texto no
-- destino. O modelo existe assim mesmo, e nao e' cerimonia. Duas razoes concretas:
-- a gold vai referenciar `ref('stg_locais')` e nao `bronze.locais`, o que mantem a
-- regra de que nenhum modelo de negocio toca a bronze direto; e o dia em que a
-- origem ganhar coluna nova ou trocar de nome, quem absorve o impacto e' este
-- arquivo, num lugar so', em vez de todo modelo que usa local.

with fonte as (

    select * from {{ source('bronze', 'locais') }}

),

renomeado as (

    select
        codigo_linha,
        codigo_setor,
        nome_setor,
        planta,

        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
