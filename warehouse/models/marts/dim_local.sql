-- dim_local: onde a maquina esta'. Grain: uma linha de producao. 13 linhas, sendo 12
-- reais e o membro desconhecido.
--
-- Hierarquia planta > setor > linha, achatada numa tabela so'. Isso e' a decisao de
-- rejeitar snowflake, aplicada: setor poderia ser uma dimensao propria com a linha
-- apontando para ela, e nao e', porque economizaria espaco que nao falta e cobraria um
-- join a mais em toda consulta por setor.
--
-- O fato alcanca esta dimensao direto, e nao atraves da dim_ativo, mesmo o local sendo
-- um atributo da maquina. Quem quiser custo por setor faz um join, nao dois.
--
-- O membro desconhecido tem codigo_linha = 'DESCONHECIDO', que e' o mesmo valor que a
-- linha desconhecida da dim_ativo carrega. Isso nao e' coincidencia: o fato resolve o
-- local a partir do codigo_linha da versao do ativo, entao a OS orfa de ativo cai no
-- ativo desconhecido, que aponta para a linha desconhecida, e o caminho se fecha
-- sozinho sem coalesce nenhum na consulta.

with fonte as (

    select * from {{ ref('stg_locais') }}

),

vestido as (

    select
        row_number() over (order by codigo_linha) as local_sk,
        codigo_linha,
        codigo_setor,
        nome_setor,
        planta

    from fonte

),

desconhecido as (

    select
        -1              as local_sk,
        'DESCONHECIDO'  as codigo_linha,
        'DESCONHECIDO'  as codigo_setor,
        'desconhecido'  as nome_setor,
        'desconhecido'  as planta

)

select * from desconhecido
union all
select * from vestido
order by local_sk
