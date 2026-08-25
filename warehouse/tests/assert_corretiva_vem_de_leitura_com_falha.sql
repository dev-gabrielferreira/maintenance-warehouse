-- Toda ordem corretiva tem que apontar para uma leitura que o warehouse considera
-- falha. Este teste tem que fechar em ZERO, e ele e' a prova pratica da decisao B.
--
-- A Semana 2 registrou por que udi_origem nao tem relationships generico: aquele teste
-- trata nulo como violacao, e udi_origem e' nulo nas 651 preventivas por construcao. A
-- checagem certa e' esta, filtrando tipo_os = 'corretiva'.
--
-- POR QUE ELE PROVA A ESCOLHA. A fonte discorda de si mesma em 27 linhas: 9 tem falha
-- declarada sem modo marcado, e 18 tem modo marcado (todas RNF) sem falha declarada. A
-- gold precisava escolher uma definicao, e as tres candidatas davam:
--
--   falha_maquina manda ............ 339 falhas, e este teste acusaria 18 linhas
--   algum modo marcado manda ....... 348 falhas, e este teste acusaria  9 linhas
--   a uniao das duas ............... 357 falhas, e este teste fecha em  0
--
-- As 357 OS corretivas tem udi_origem preenchido nas 357, porque o gerador as criou
-- pela uniao. Escolher qualquer outra definicao deixaria corretivas apontando para
-- leituras que a propria gold nao considera falha, o que seria o warehouse discordando
-- de si mesmo no lugar da fonte.

select
    o.numero_os,
    o.udi_origem,
    l.houve_falha,
    l.falha_declarada_fonte

from {{ ref('fct_ordens_servico') }} o
join {{ ref('fct_leituras') }} l on o.udi_origem = l.udi

where o.tipo_os = 'corretiva'
  and not l.houve_falha
