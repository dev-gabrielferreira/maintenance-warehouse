-- dim_tecnico: quem executou a ordem de servico. Grain: um tecnico. 13 linhas, sendo
-- 12 reais e o membro desconhecido, que recebe as 5 OS de matricula inexistente.
--
-- SCD1: se um tecnico mudar de especialidade, o cadastro passa a valer para o passado
-- inteiro e o valor antigo se perde. Isso e' escolha, nao esquecimento. O custo real de
-- manter SCD2 e' uma versao por mudanca, o join de todo fato passando a depender da
-- data do evento, e um teste de sobreposicao para manter de pe'. Vale a pena quando
-- alguma pergunta depende do passado, e nenhuma das cinco perguntas deste warehouse
-- pergunta o que o tecnico era antes. Para o ativo pergunta, e por isso so' ele e' SCD2.
--
-- Sobre o turno: ele fica aqui como texto, e NAO como turno_sk apontando para a
-- dim_turno. Dimensao apontando para dimensao e' outrigger, que e' snowflake entrando
-- pela porta dos fundos, e o projeto rejeitou snowflake de proposito. A conformidade
-- entre os dois turnos e' garantida pelo accepted_values dos dois lados valendo sobre
-- os mesmos tres valores, e nao por uma chave estrangeira.

with fonte as (

    select * from {{ ref('stg_tecnicos') }}

),

vestido as (

    select
        row_number() over (order by matricula) as tecnico_sk,
        matricula,
        nome,
        especialidade,
        turno,
        custo_hora

    from fonte

),

desconhecido as (

    select
        -1              as tecnico_sk,
        'DESCONHECIDO'  as matricula,
        'desconhecido'  as nome,
        'desconhecido'  as especialidade,
        'desconhecido'  as turno,
        -- Nulo, e nao zero. As 5 OS orfas de tecnico tem custo de mao de obra proprio,
        -- gravado na ordem, entao este campo nao entra em soma nenhuma. Zero aqui
        -- afirmaria que a hora daquele tecnico custa nada, que e' diferente de nao se
        -- saber quanto custa.
        null::numeric   as custo_hora

)

select * from desconhecido
union all
select * from vestido
order by tecnico_sk
