-- Duas macros que existem so' para servir o laco de scripts/historico_ativo.sh.
-- Elas nao transformam dado: uma le' as datas, a outra derruba a tabela do snapshot.

{% macro datas_de_mudanca() %}
    {#-
        Imprime, uma por linha, cada data distinta de mudanca de cadastro, em ordem
        crescente. O script le' esta saida para saber quantas vezes rodar o snapshot.

        Por que sair daqui e nao de um psql no script: assim o laco usa a mesma
        conexao que o dbt usa, resolvida pelo profiles.yml. Um psql no script
        precisaria descobrir host, porta e senha por conta propria, e passaria a ter
        uma segunda definicao de "onde fica o banco" para divergir da primeira.
    -#}
    {#-
        A primeira data que sai daqui nao e' uma data de mudanca: e' o dia anterior a
        primeira delas, e ela existe para o snapshot gravar a linha de base.

        Sem essa rodada, a maquina que mudou na primeira data nasce no warehouse ja'
        alterada, e o estado anterior dela nunca existiu. Foi o que aconteceu com a
        MAQ-066, que trocou de linha em 2024-03-04: o historico saiu com 110 versoes
        em vez de 111, e a unica pista era um numero um a menos.

        A data e' calculada e nao escrita a mao, para o laco continuar certo se o
        gerador mudar a semente.
    -#}
    {% set consulta %}
        select min(data_mudanca)::date - 1 as data_mudanca
        from {{ source('bronze', 'mudancas_ativo') }}

        union

        select distinct data_mudanca::date
        from {{ source('bronze', 'mudancas_ativo') }}

        order by 1
    {% endset %}

    {% set resultado = run_query(consulta) %}

    {% if execute %}
        {% for linha in resultado.rows %}
            {{ log(linha[0], info=true) }}
        {% endfor %}
    {% endif %}
{% endmacro %}


{% macro derruba_historico_ativo() %}
    {#-
        Derruba a tabela do snapshot para o historico ser reconstruido do zero.

        Sem isto o laco nao seria reproduzivel: rodar o script duas vezes seguidas
        deixaria o snapshot com o historico da primeira rodada intacto, e a segunda
        nao teria nada a acrescentar. Pior, se alguem tivesse rodado `dbt build`
        antes, a tabela ja' estaria com uma versao unica por maquina e o laco nao
        conseguiria mais inserir as datas antigas.

        O sufixo _snapshots vem do `+schema: snapshots` do dbt_project.yml, que o dbt
        cola no schema base do profiles.yml.
    -#}
    {% set esquema = target.schema ~ '_snapshots' %}
    {% set alvo = adapter.get_relation(
        database=target.database, schema=esquema, identifier='snap_ativo'
    ) %}

    {% if alvo is none %}
        {{ log("snap_ativo ainda nao existe em " ~ esquema ~ ", nada a derrubar", info=true) }}
    {% else %}
        {% do run_query("drop table " ~ alvo) %}
        {{ log("snap_ativo derrubado em " ~ esquema, info=true) }}
    {% endif %}
{% endmacro %}


{% macro confere_historico_ativo() %}
    {#-
        Le' o snapshot e imprime o resumo do historico. Serve ao script, para ele
        terminar mostrando o que construiu em vez de mostrar o que o dbt achou que
        fez. O teste de verdade e' o assert_historico_ativo_completo, que roda no
        dbt build; isto aqui e' so' para quem esta' olhando a tela.
    -#}
    {% set esquema = target.schema ~ '_snapshots' %}
    {% set consulta %}
        select
            count(*)                                          as versoes,
            count(distinct codigo_ativo)                      as maquinas,
            count(*) filter (where dbt_valid_to is null)      as vigentes,
            count(distinct codigo_ativo) filter (
                where dbt_valid_to is not null
            )                                                 as maquinas_com_passado
        from {{ target.database }}.{{ esquema }}.snap_ativo
    {% endset %}

    {% set r = run_query(consulta) %}
    {% if execute %}
        {% set linha = r.rows[0] %}
        {{ log("    versoes: " ~ linha[0] ~ "   vigentes: " ~ linha[2], info=true) }}
        {{ log("    maquinas: " ~ linha[1] ~ "   maquinas com passado: " ~ linha[3], info=true) }}
    {% endif %}
{% endmacro %}
