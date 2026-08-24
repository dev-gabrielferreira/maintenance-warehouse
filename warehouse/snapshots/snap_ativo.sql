-- SCD2 do cadastro de ativo.
--
-- A estrategia e' `timestamp`, e a escolha nao e' cosmetica. Com `check`, o dbt
-- compara colunas e carimba dbt_valid_from com a hora em que o comando rodou: o
-- historico ficaria com data de execucao, e duas pessoas rodando o projeto em dias
-- diferentes teriam warehouses diferentes. Com `timestamp` apontando para
-- atualizado_em, o dbt_valid_from nasce com a data real da mudanca de cadastro.
--
-- Como este snapshot e' alimentado: scripts/historico_ativo.sh roda um `dbt snapshot`
-- por data de mudanca, em ordem crescente, passando cada data em var('data_corte').
-- A ordem crescente e' obrigatoria: a estrategia timestamp ignora, em silencio, uma
-- linha cujo updated_at seja anterior ao ultimo registrado. Rodar fora de ordem nao
-- da' erro, da' historico errado.
--
-- Quem rodar `dbt build` sem ter rodado o laco fica com uma versao por maquina e um
-- passado que nunca existiu. E' um erro que nao aparece sozinho, entao existe um
-- teste singular contando as versoes para ele aparecer.

{% snapshot snap_ativo %}

{{
    config(
        unique_key='codigo_ativo',
        strategy='timestamp',
        updated_at='atualizado_em'
    )
}}

select * from {{ ref('int_ativo_estado') }}

{% endsnapshot %}
