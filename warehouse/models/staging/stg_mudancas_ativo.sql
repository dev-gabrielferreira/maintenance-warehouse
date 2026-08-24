-- Silver do log de mudancas de cadastro: 31 eventos, o insumo da SCD2.
--
-- Formato longo, campo/valor_novo: cada linha diz que um atributo de uma maquina
-- passou a valer outra coisa a partir de uma data. Nao e' estado, e' evento. O
-- gerador escreveu 15 transferencias de linha, 10 reclassificacoes de criticidade e
-- 6 reformas, espalhadas por 27 das 80 maquinas.
--
-- Fica registrado aqui o problema que a Semana 3 vai ter que resolver, porque ele
-- nao e' obvio: um `dbt snapshot` grava o que enxerga na hora em que roda. Como
-- bronze.ativos e' estatico depois da carga, rodar o snapshot dez vezes produz uma
-- versao so' por maquina, e estas 31 linhas nao viram historico sozinhas. Os dois
-- caminhos possiveis estao em docs/modelo-dimensional.md.

with fonte as (

    select * from {{ source('bronze', 'mudancas_ativo') }}

),

renomeado as (

    select
        codigo_ativo,
        data_mudanca::date as data_mudanca,
        campo,
        valor_novo,
        motivo,

        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
