-- dim_ativo: SCD tipo 2. Grain: uma versao de uma maquina num intervalo de validade.
--
-- 111 linhas para 80 maquinas. 53 tem uma versao so', porque nunca mudaram de
-- cadastro; 27 tem duas ou mais. A MAQ-066 tem quatro.
--
-- O insumo e' o snap_ativo, construido por scripts/historico_ativo.sh. Este modelo
-- nao inventa historico: ele veste o snapshot de dimensao, gerando a chave e
-- arrumando as bordas da vigencia.
--
-- As duas bordas, que sao o que vale ler com atencao:
--
-- 1. A PRIMEIRA VERSAO COMECA EM -infinity, e nao na data de instalacao. Existem 365
--    leituras anteriores a data de instalacao do proprio ativo, em 5 maquinas, e isso
--    e' sujeira injetada de proposito. Se a versao 1 comecasse na instalacao, essas
--    365 leituras nao achariam versao nenhuma, cairiam no ativo desconhecido, e o
--    fato perderia dado de verdade por causa de um erro de cadastro. Quem acusa a
--    instalacao futura e' teste, nao descarte silencioso. A data de instalacao
--    continua na dimensao como atributo, para o teste ter o que comparar.
--
-- 2. A VERSAO VIGENTE TERMINA EM infinity, e nao em NULL. Com infinity, o join do
--    fato e' `evento >= valido_de and evento < valido_ate` e acabou. Com NULL, toda
--    consulta precisaria lembrar do caso especial, e quem esquecesse perderia
--    exatamente as linhas da versao atual, sem erro nenhum aparecer. Borda que exige
--    ser lembrada e' borda que um dia sera' esquecida.
--
-- O intervalo e' fechado na esquerda e aberto na direita: [valido_de, valido_ate).
-- Evento que cai exatamente na data da mudanca pertence a versao nova. Isso precisa
-- ser uma regra escrita, porque as duas escolhas sao defensaveis e so' uma delas nao
-- conta o mesmo evento duas vezes.

with versoes as (

    select * from {{ ref('snap_ativo') }}

),

numerado as (

    select
        *,
        row_number() over (
            partition by codigo_ativo
            order by dbt_valid_from
        ) as versao

    from versoes

),

vestido as (

    select
        -- Chave por versao, e nao por maquina. Com SCD2, MAQ-017 deixa de identificar
        -- uma linha e passa a identificar um conjunto delas: e' por isso que o fato
        -- guarda a surrogate da versao e nao o codigo natural.
        row_number() over (order by codigo_ativo, dbt_valid_from) as ativo_sk,

        codigo_ativo,
        versao,

        tipo,
        fabricante,
        codigo_linha,
        criticidade,
        estado,
        data_instalacao,

        case
            when versao = 1 then '-infinity'::timestamp
            else dbt_valid_from
        end                                     as valido_de,
        coalesce(dbt_valid_to, 'infinity')      as valido_ate,
        dbt_valid_to is null                    as versao_atual

    from numerado

),

desconhecido as (

    select
        -1                          as ativo_sk,
        'DESCONHECIDO'              as codigo_ativo,
        0                           as versao,
        'desconhecido'              as tipo,
        'desconhecido'              as fabricante,
        'DESCONHECIDO'              as codigo_linha,
        'desconhecido'              as criticidade,
        'desconhecido'              as estado,
        null::date                  as data_instalacao,
        '-infinity'::timestamp      as valido_de,
        'infinity'::timestamp       as valido_ate,
        true                        as versao_atual

)

-- O membro desconhecido recebe as 8 OS orfas de ativo. Elas tem custo real e ficam no
-- warehouse; o que elas nao podem e' carregar FK nula, que quebra o join e some da
-- contagem sem avisar. A vigencia dele vai de -infinity a infinity para o join por
-- data continuar funcionando sem caso especial.
select * from desconhecido
union all
select * from vestido
order by ativo_sk
