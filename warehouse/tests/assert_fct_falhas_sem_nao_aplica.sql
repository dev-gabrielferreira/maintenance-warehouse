-- O membro NAO_APLICA nao pode aparecer em fct_falhas.
--
-- Ele existe para as 651 preventivas de fct_ordens_servico, que nao tem modo porque
-- nao houve falha. Uma linha dele aqui seria uma falha que nao se aplica, e a
-- contradicao passaria despercebida numa contagem por modo: apareceria como mais uma
-- categoria com numero ao lado, igual as outras.

select
    f.udi,
    d.codigo_modo

from {{ ref('fct_falhas') }} f
join {{ ref('dim_modo_falha') }} d using (modo_falha_sk)
where d.codigo_modo = 'NAO_APLICA'
