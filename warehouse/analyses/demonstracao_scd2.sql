-- DEMONSTRACAO DA SCD2, DE PONTA A PONTA
--
-- Este arquivo esta' em analyses/: o dbt compila, e nao materializa nada. E' consulta
-- para ler e rodar a mao, nao modelo.
--
-- A pergunta: o custo de manutencao da MAQ-060 mudou depois da reforma dela, em
-- 2025-05-05?
--
-- Ela e' a unica das cinco perguntas de negocio do projeto que NAO EXISTE sem SCD2, e
-- este arquivo mostra por que, comparando as duas respostas lado a lado.
--
-- ============================================================================
-- 1. AS VERSOES DA MAQUINA
-- ============================================================================
--
-- select ... from dim_ativo where codigo_ativo = 'MAQ-060'
--
--  versao |  estado   | criticidade | codigo_linha |     de     |    ate
-- --------+-----------+-------------+--------------+------------+------------
--       1 | operando  | alta        | MON-L02      | -infinity  | 2025-05-05
--       2 | reformado | alta        | MON-L02      | 2025-05-05 | infinity
--
-- Duas linhas na dimensao para uma maquina. A versao 1 comeca em -infinity, e nao na
-- data de instalacao, para nenhum evento anterior ao cadastro ficar orfao.

select
    a.versao,
    a.estado,
    a.valido_de::date                                                as vigente_de,
    a.valido_ate::date                                               as vigente_ate,
    count(*) filter (where o.tipo_os = 'corretiva')                  as corretivas,
    round(sum(o.custo_total) filter (where o.tipo_os = 'corretiva'), 2) as custo_corretiva,
    round(sum(o.duracao_horas) filter (where o.tipo_os = 'corretiva'), 1) as horas_paradas

from {{ ref('dim_ativo') }} a
left join {{ ref('fct_ordens_servico') }} o using (ativo_sk)

where a.codigo_ativo = 'MAQ-060'
group by a.versao, a.estado, a.valido_de, a.valido_ate
order by a.versao

-- RESULTADO:
--
--  versao |  estado   | vigente_de | vigente_ate | corretivas | custo_corretiva | horas
-- --------+-----------+------------+-------------+------------+-----------------+-------
--       1 | operando  | -infinity  | 2025-05-05  |          4 |         4849.95 |  15.0
--       2 | reformado | 2025-05-05 | infinity    |          1 |          579.71 |   3.2
--
-- A pergunta foi respondida: quatro corretivas e R$ 4.849,95 antes, uma corretiva e
-- R$ 579,71 depois.
--
-- ============================================================================
-- 2. O QUE A MESMA PERGUNTA RESPONDERIA COM SCD1
-- ============================================================================
--
-- Com SCD1 a dimensao guarda um estado so' por maquina, o de hoje, e hoje a MAQ-060
-- esta' reformada. Trocando o join pela versao vigente, que e' o que uma SCD1 seria:
--
--   join dim_ativo a on a.codigo_ativo = 'MAQ-060' and a.versao_atual
--
--  estado    | corretivas | custo_corretiva | horas
-- -----------+------------+-----------------+-------
--  reformado |          5 |         5429.66 |  18.2
--
-- Uma linha so'. As cinco corretivas aparecem todas como "da maquina reformada",
-- porque a maquina, na dimensao, sempre esteve reformada. O antes nao ficou errado:
-- ele DESAPARECEU. Nao ha' o que comparar, e a pergunta deixa de ter resposta possivel.
--
-- Repare que nenhum numero fica marcado como suspeito. O total de R$ 5.429,66 esta'
-- certo, e e' a soma dos dois periodos. So' que ele responde outra pergunta.
--
-- ============================================================================
-- 3. A HONESTIDADE QUE PRECISA ESTAR JUNTO
-- ============================================================================
--
-- A queda de R$ 4.850 para R$ 580 na MAQ-060 NAO e' prova de que reforma reduz custo.
-- Olhando as seis maquinas reformadas do parque:
--
--  codigo_ativo | corr_antes | corr_depois | custo_antes | custo_depois
-- --------------+------------+-------------+-------------+--------------
--  MAQ-005      |          0 |           6 |             |         5604
--  MAQ-008      |          1 |           1 |        4757 |         2309
--  MAQ-017      |          3 |           0 |        3092 |
--  MAQ-025      |          2 |           0 |        4780 |
--  MAQ-060      |          4 |           1 |        4850 |          580
--  MAQ-075      |          1 |           2 |         564 |         3328
--
-- Duas sobem, duas descem, duas nao tem os dois lados. Nao ha' padrao, e nao deveria
-- haver: o gerador sintetico distribui falha por carga de uso e nao por estado do
-- equipamento, entao reforma nao reduz falha neste dado. Isso esta' declarado nos
-- limites do gerador.
--
-- O QUE ESTA DEMONSTRADO AQUI E' OUTRA COISA, e ela e' a que vale: a pergunta pode ser
-- FEITA. O warehouse consegue separar o antes do depois de uma mudanca de cadastro,
-- com o custo de cada periodo atribuido a versao certa da maquina. Se o dado tivesse
-- um padrao, ele apareceria. Sem SCD2 nem essa frase seria possivel escrever, porque o
-- antes nao existiria para ser olhado.
