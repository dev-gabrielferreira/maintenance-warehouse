-- Os dois fatos tem que concordar sobre o que e' falha.
--
-- E' a regra "falha exige modo" que o plano da Semana 3 pede, escrita nas duas
-- direcoes, porque ela pode quebrar dos dois lados:
--
--   1. Leitura marcada com falha em fct_leituras e sem nenhuma linha em fct_falhas.
--      Seria uma parada sem causa nenhuma registrada, nem mesmo INDETERMINADO. O
--      left join do fct_falhas existe justamente para isso nao acontecer, e um inner
--      join no lugar dele derrubaria as 9 falhas sem modo em silencio.
--
--   2. Linha em fct_falhas vinda de leitura que fct_leituras nao considera falha.
--      Seria modo de falha em ciclo normal, e significaria que as duas definicoes de
--      falha do warehouse divergiram.
--
-- Hoje as duas direcoes fecham em zero: 357 leituras com falha, 357 udis distintos em
-- fct_falhas. A coluna `direcao` existe para a linha que falhar dizer qual dos dois
-- lados quebrou, em vez de deixar quem for investigar adivinhar.

with sem_modo as (

    select
        'leitura com falha e sem modo' as direcao,
        l.udi
    from {{ ref('fct_leituras') }} l
    left join {{ ref('fct_falhas') }} f using (udi)
    where l.houve_falha
      and f.udi is null

),

modo_sem_falha as (

    select
        'modo em leitura sem falha' as direcao,
        f.udi
    from {{ ref('fct_falhas') }} f
    join {{ ref('fct_leituras') }} l using (udi)
    where not l.houve_falha

)

select * from sem_modo
union all
select * from modo_sem_falha
