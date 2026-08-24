-- Silver do AI4I 2020: renomeia, tipa, e nada mais.
--
-- Um por um, o que muda em relacao a bronze e por que:
--
-- 1. Nome. "Air temperature [K]" vira temperatura_ar_k. A unidade continua no nome
--    da coluna de proposito: quem escreve `where temperatura_ar_k > 30` erra na hora
--    e ve' o erro, porque a escala e' Kelvin. Coluna chamada so' `temperatura` deixa
--    a unidade viver na cabeca de quem escreveu, e um dia essa pessoa sai do time.
--
-- 2. Tipo. Tudo chega text e sai int, numeric ou boolean. E' aqui que a tipagem
--    acontece, em SQL versionado, e nao no loader: se o Python tivesse tipado, a
--    sujeira teria explodido na carga em vez de chegar ate' o teste do dbt.
--
-- 3. Booleano em vez de 0/1. `where falha_maquina` le' melhor que `where "Machine
--    failure" = '1'`, e o tipo passa a impedir um terceiro valor de existir. O cast
--    intermediario para int e' proposital: se a coluna algum dia trouxer texto que
--    nao e' numero, o modelo quebra alto em vez de virar false em silencio.
--
-- O que este modelo NAO faz: nao junta com leitura_contexto (staging e' 1:1 com a
-- origem, join e' da gold), nao calcula nada, nao decide o que e' "falha". As 9
-- linhas com falha declarada e nenhum modo, e as 18 de RNF que nao contam como
-- falha, passam por aqui intactas. Escolher entre as duas definicoes e' assunto da
-- Semana 3, e esta' registrado em docs/modelo-dimensional.md.

with fonte as (

    select * from {{ source('bronze', 'ai4i_leituras') }}

),

renomeado as (

    select
        -- chaves
        "UDI"::int                          as udi,
        "Product ID"                        as produto_id,
        "Type"                              as tipo_produto,

        -- sensores
        "Air temperature [K]"::numeric      as temperatura_ar_k,
        "Process temperature [K]"::numeric  as temperatura_processo_k,
        "Rotational speed [rpm]"::int       as rotacao_rpm,
        "Torque [Nm]"::numeric              as torque_nm,
        "Tool wear [min]"::int              as desgaste_ferramenta_min,

        -- falha declarada e os cinco modos
        "Machine failure"::int = 1          as falha_maquina,
        "TWF"::int = 1                      as falha_twf,
        "HDF"::int = 1                      as falha_hdf,
        "PWF"::int = 1                      as falha_pwf,
        "OSF"::int = 1                      as falha_osf,
        "RNF"::int = 1                      as falha_rnf,

        -- rastreio, herdado do loader
        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
