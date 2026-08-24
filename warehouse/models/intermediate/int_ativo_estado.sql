-- Como estava o parque na data de corte.
--
-- Este modelo responde uma pergunta so': dado um dia, qual era o cadastro de cada
-- uma das 80 maquinas naquele dia. Ele e' o insumo do snapshot, e nao um modelo de
-- consumo: ninguem deveria consultar isto direto.
--
-- Por que ele existe. `bronze.ativos` e' estatico depois da carga: as 80 maquinas
-- tem um estado so', e `estado` vale 'operando' nas 80 mesmo havendo 6 reformas
-- registradas. Um `dbt snapshot` grava o que enxerga na hora em que roda, entao
-- rodar dez vezes sobre a bronze produziria dez vezes a mesma versao. As 31 linhas
-- de stg_mudancas_ativo nao viram historico sozinhas. Este modelo e' o que
-- transforma "log de eventos" em "estado numa data", e o laco de
-- scripts/historico_ativo.sh e' o que roda o snapshot uma vez por data.
--
-- E' ephemeral de proposito, e isso nao e' detalhe de performance: ele depende de
-- var('data_corte'), e o snapshot precisa resolver esse var no momento em que o
-- snapshot roda. Materializado como view, o valor ficaria congelado no ultimo
-- `dbt run`.
--
-- `atualizado_em` e' a coluna que o snapshot usa como updated_at. Ela carrega a data
-- da ultima mudanca aplicada ao ativo, e nao a hora da execucao: e' isso que faz o
-- dbt_valid_from nascer com data de negocio em vez de com carimbo de quando alguem
-- rodou o comando.

with ativos as (

    select * from {{ ref('stg_ativos') }}

),

mudancas as (

    select *
    from {{ ref('stg_mudancas_ativo') }}
    where data_mudanca <= '{{ var("data_corte") }}'::date

),

-- O log e' longo: uma linha por (ativo, campo, data). O que vale numa data e' o
-- ultimo valor de cada campo ate' ali, e nao o ultimo valor de qualquer campo.
-- Maquina que trocou de linha em marco e de criticidade em agosto tem que carregar
-- as duas mudancas, nao so' a mais recente.
ultimo_por_campo as (

    select distinct on (codigo_ativo, campo)
        codigo_ativo,
        campo,
        valor_novo,
        data_mudanca
    from mudancas
    order by codigo_ativo, campo, data_mudanca desc

),

-- Formato longo vira coluna. Sao tres campos possiveis, e o accepted_values de
-- stg_mudancas_ativo e' quem garante que nao aparece um quarto sem ninguem ver.
aplicado as (

    select
        codigo_ativo,
        max(valor_novo) filter (where campo = 'codigo_linha') as codigo_linha,
        max(valor_novo) filter (where campo = 'criticidade')  as criticidade,
        max(valor_novo) filter (where campo = 'estado')       as estado,
        max(data_mudanca)                                     as ultima_mudanca
    from ultimo_por_campo
    group by codigo_ativo

),

estado_na_data as (

    select
        a.codigo_ativo,
        a.tipo,
        a.fabricante,
        a.data_instalacao,

        -- coalesce e' o coracao do modelo: campo que nunca mudou continua com o valor
        -- do cadastro, campo que mudou passa a valer o ultimo valor ate' a data.
        coalesce(m.codigo_linha, a.codigo_linha) as codigo_linha,
        coalesce(m.criticidade,  a.criticidade)  as criticidade,
        coalesce(m.estado,       a.estado)       as estado,

        -- Ativo que ainda nao mudou nada tem como data de atualizacao a propria
        -- instalacao. Sem isso o snapshot nao teria o que comparar na primeira rodada.
        coalesce(m.ultima_mudanca, a.data_instalacao)::timestamp as atualizado_em

    from ativos a
    left join aplicado m using (codigo_ativo)

)

select * from estado_na_data
