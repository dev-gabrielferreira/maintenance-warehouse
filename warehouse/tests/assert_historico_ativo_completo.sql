-- O snapshot tem que ter uma versao por maquina mais uma por mudanca de cadastro.
--
-- Este teste existe por causa de um erro que nao se denuncia sozinho. O historico da
-- SCD2 nao nasce do `dbt build`: ele nasce do laco de scripts/historico_ativo.sh, que
-- roda o snapshot uma vez por data de corte. Quem clonar o projeto e rodar `dbt build`
-- direto fica com uma versao por maquina, o build todo verde, e um passado que nunca
-- existiu. A pergunta "o custo caiu depois da reforma?" passaria a responder que a
-- maquina sempre esteve reformada, com toda a confianca do mundo.
--
-- O esperado conta pares distintos de (ativo, data) e nao linhas do log, porque duas
-- mudancas do mesmo ativo no mesmo dia entram numa rodada so' do snapshot e abrem uma
-- versao so'. Hoje as 31 mudancas caem em 31 datas distintas e os dois numeros
-- coincidem, mas o teste continua certo se o gerador mudar.
--
-- Falhou? Rode `bash scripts/historico_ativo.sh` e depois o build de novo.

with esperado as (

    select
        (select count(*) from {{ ref('stg_ativos') }})
        + (
            select count(*) from (
                select distinct codigo_ativo, data_mudanca
                from {{ ref('stg_mudancas_ativo') }}
            ) as pares
        ) as versoes

),

encontrado as (

    select count(*) as versoes from {{ ref('snap_ativo') }}

)

select
    esperado.versoes    as versoes_esperadas,
    encontrado.versoes  as versoes_encontradas,
    'rode bash scripts/historico_ativo.sh' as o_que_fazer
from esperado
cross join encontrado
where esperado.versoes <> encontrado.versoes
