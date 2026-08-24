-- Nenhuma maquina pode ter duas versoes vigentes no mesmo instante.
--
-- E' o teste que prova que a SCD2 esta' bem formada, e o unico que pega o pior defeito
-- possivel numa dimensao historica: se duas versoes se sobrepusessem, o join do fato
-- por data casaria com as duas e o custo da maquina apareceria dobrado. O numero
-- ficaria errado para mais, que e' o erro que ninguem estranha, porque parece que a
-- maquina gastou muito.
--
-- Ele tambem cobre, de graca, o caso de duas versoes vigentes ao mesmo tempo: duas
-- linhas com valido_ate = infinity se sobrepoem por definicao.
--
-- O intervalo e' [valido_de, valido_ate), fechado na esquerda e aberto na direita,
-- entao versao que termina exatamente onde a proxima comeca NAO e' sobreposicao. E'
-- por isso que a comparacao usa < e > estritos.

select
    a.codigo_ativo,
    a.versao        as versao_a,
    b.versao        as versao_b,
    a.valido_de     as de_a,
    a.valido_ate    as ate_a,
    b.valido_de     as de_b,
    b.valido_ate    as ate_b

from {{ ref('dim_ativo') }} a
join {{ ref('dim_ativo') }} b
  on  a.codigo_ativo = b.codigo_ativo
  and a.ativo_sk < b.ativo_sk
  and a.valido_de  < b.valido_ate
  and b.valido_de  < a.valido_ate
