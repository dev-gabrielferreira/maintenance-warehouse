-- Silver das ordens de servico: 1.008 linhas, 1:1 com a origem.
--
-- Sobre os nulos. As 651 preventivas nao tem modo de falha nem UDI de origem, e 36
-- delas tambem nao tem data de conclusao porque simplesmente nao foram executadas.
-- Isso nao e' dado faltando: e' o significado da linha. Campo vazio no CSV chega na
-- bronze como NULL de verdade (o COPY do Postgres converte campo vazio nao aspado),
-- entao nao ha' string vazia para tratar aqui, e foi conferido no banco em vez de
-- assumido. O not_null de data_conclusao seria um teste errado, e por isso ele nao
-- existe no .yml ao lado.
--
-- O que este modelo NAO faz, de proposito:
--
-- - Nao soma custo_mao_obra com custo_pecas. Custo total e' calculo, e calculo mora
--   na gold. Se a soma nascesse aqui, dois modelos poderiam somar de formas
--   diferentes mais adiante e ninguem saberia qual e' a versao boa.
-- - Nao corrige os 10 custos negativos nem as 10 conclusoes anteriores a abertura.
--   Sao sujeira injetada, sao violacao de regra de negocio, e quem as acusa e' o
--   teste singular da Semana 3. Consertar em silencio aqui seria apagar a prova.
-- - Nao descarta as 13 OS orfas (8 de ativo, 5 de tecnico). Sao ordens com custo
--   real; joga-las fora tiraria dinheiro do warehouse sem ninguem ver. Elas ficam,
--   os relationships do .yml ficam em warn, e na Semana 3 elas passam a apontar
--   para o membro "desconhecido" da dimensao e o teste sobe para error.

with fonte as (

    select * from {{ source('bronze', 'ordens_servico') }}

),

renomeado as (

    select
        -- chave e classificacao
        numero_os,
        tipo_os,
        modo_falha,

        -- de onde a OS veio
        codigo_ativo,
        matricula_tecnico,
        udi_origem::int             as udi_origem,

        -- quando
        data_abertura::timestamp    as data_abertura,
        data_conclusao::timestamp   as data_conclusao,

        -- quanto
        duracao_horas::numeric      as duracao_horas,
        custo_mao_obra::numeric     as custo_mao_obra,
        custo_pecas::numeric        as custo_pecas,

        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
