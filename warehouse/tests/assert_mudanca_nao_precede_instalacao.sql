-- Nenhum ativo pode ter mudanca de cadastro anterior a propria instalacao.
--
-- Parece regra de negocio obvia, e e' tambem uma protecao do mecanismo da SCD2, que e'
-- o motivo real deste teste existir.
--
-- O snapshot usa a estrategia `timestamp`, comparando a coluna atualizado_em. Para o
-- ativo que ainda nao mudou nada, atualizado_em vale a data de instalacao. Se um ativo
-- tivesse instalacao posterior a alguma mudanca dele, o atualizado_em daria um passo
-- para tras entre dois cortes, e a estrategia timestamp descarta silenciosamente o que
-- for mais antigo que o ultimo registrado: a mudanca sumiria do historico sem erro
-- nenhum aparecer.
--
-- Hoje isso nao acontece, e o teste retorna zero linhas. Ele fica aqui para o dia em
-- que a semente do gerador mudar. As 5 maquinas com instalacao posterior a primeira
-- leitura, que sao sujeira injetada, nao caem neste teste: elas nao tem mudanca
-- anterior a instalacao, e quem as acusa e' outro teste.

select
    a.codigo_ativo,
    a.data_instalacao,
    min(m.data_mudanca) as primeira_mudanca

from {{ ref('stg_ativos') }} a
join {{ ref('stg_mudancas_ativo') }} m using (codigo_ativo)

group by a.codigo_ativo, a.data_instalacao
having a.data_instalacao > min(m.data_mudanca)
