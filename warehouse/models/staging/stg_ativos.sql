-- Silver do parque: 80 maquinas, uma linha por maquina.
--
-- Atencao no que este modelo NAO faz: ele nao aplica as 31 mudancas de
-- bronze.mudancas_ativo. O que sai daqui e' o cadastro num estado so', e por isso
-- `estado` vale 'operando' nas 80 linhas mesmo havendo 6 reformas registradas no
-- log. Montar a versao vigente em cada data e' trabalho da SCD2, na Semana 3.
--
-- As 5 maquinas com data_instalacao posterior a primeira leitura delas passam
-- intactas. Isso e' sujeira injetada, e de propriedade da regra de negocio, nao da
-- estrutura: o teste singular que a pega e' da Semana 3. Filtrar aqui esconderia o
-- problema em vez de mostra-lo.

with fonte as (

    select * from {{ source('bronze', 'ativos') }}

),

renomeado as (

    select
        codigo_ativo,
        tipo,
        fabricante,
        codigo_linha,
        criticidade,
        data_instalacao::date as data_instalacao,
        estado,

        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
