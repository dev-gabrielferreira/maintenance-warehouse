-- Modelo descartavel do bloco 1.7. Existe para provar uma coisa so': que o dbt
-- fecha conexao com o Postgres, enxerga a bronze e consegue materializar. Ele sai
-- do projeto na semana 2, quando os staging de verdade nascerem.
--
-- Repare que ele le' a bronze por nome cru. Isso e' justamente o que a semana 2
-- vai consertar: com a bronze declarada como source e lida por source(), o dbt
-- passa a saber que este modelo depende dela, e o lineage deixa de ter buracos.

select
    'ai4i_leituras'    as tabela,
    count(*)           as linhas
from bronze.ai4i_leituras

union all

select
    'leitura_contexto',
    count(*)
from bronze.leitura_contexto

union all

select
    'ordens_servico',
    count(*)
from bronze.ordens_servico
