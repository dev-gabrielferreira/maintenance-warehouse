-- Silver da equipe: 12 tecnicos, uma linha por matricula.
--
-- Unico cast do modelo e' custo_hora, que vira numeric. Ele e' insumo de calculo de
-- custo de mao de obra na gold, e numero que chega como texto em coluna de calculo
-- e' o comeco de uma soma silenciosamente errada.

with fonte as (

    select * from {{ source('bronze', 'tecnicos') }}

),

renomeado as (

    select
        matricula,
        nome,
        especialidade,
        turno,
        custo_hora::numeric as custo_hora,

        _carregado_em,
        _arquivo_origem

    from fonte

)

select * from renomeado
