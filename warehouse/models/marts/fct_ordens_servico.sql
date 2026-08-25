-- fct_ordens_servico: 1.008 linhas, uma por ordem de servico. 357 corretivas e 651
-- preventivas.
--
-- O QUE ESTE GRAIN IMPEDE DE RESPONDER: quais pecas foram trocadas (custo_pecas e' um
-- valor so', sem item), quantos tecnicos atenderam (ha' uma matricula por ordem), e
-- qualquer coisa depois do encerramento, porque nao existe reabertura nem retrabalho.
--
-- dim_tempo APARECE DUAS VEZES, como abertura e como conclusao. Isso e' dimensao
-- role-playing: a mesma tabela cumprindo dois papeis no mesmo fato, cada papel com a
-- propria FK. As 36 preventivas que nunca foram executadas apontam a conclusao para o
-- membro -1, e nao para NULL: FK nula quebraria o join e sumiria da contagem sem
-- avisar, justamente nas linhas que respondem metade da pergunta sobre aderencia ao
-- plano preventivo.
--
-- custo_total NASCE AQUI, e nao na silver. A Semana 2 recusou somar mao de obra com
-- peca na staging exatamente para a soma ter uma versao canonica, num lugar so'. Se
-- ela tivesse nascido la', dois modelos poderiam somar de formas diferentes mais
-- adiante e ninguem saberia qual e' a versao boa.
--
-- AS 13 ORFAS. 8 ordens apontam para maquina que nao existe e 5 para tecnico que nao
-- existe. Elas tem custo real e ficam no warehouse: descarta-las tiraria dinheiro do
-- fato sem ninguem ver, que e' o pior desfecho possivel. Aqui elas passam a apontar
-- para o membro desconhecido de cada dimensao. Note o coalesce do codigo_linha para
-- 'DESCONHECIDO' antes do join com a dim_local: e' ele que faz a ordem sem ativo cair
-- tambem no local desconhecido, seguindo o mesmo caminho, em vez de cada fato tratar o
-- caso a mao.

with ordens as (

    select * from {{ ref('stg_ordens_servico') }}

),

ativos as (

    select * from {{ ref('dim_ativo') }}

),

-- A versao do ativo e' resolvida pela DATA DE ABERTURA da ordem, e nao pela conclusao
-- nem pelo cadastro de hoje. Ordem aberta antes de uma reforma pertence a maquina como
-- ela era antes: e' isso que permite comparar o custo de manutencao antes e depois, que
-- e' a unica pergunta do projeto que nao existe sem SCD2.
resolvido as (

    select
        o.*,
        coalesce(a.ativo_sk, -1)                        as ativo_sk,
        coalesce(a.codigo_linha, 'DESCONHECIDO')        as codigo_linha_na_abertura

    from ordens o
    left join ativos a
      on  o.codigo_ativo   = a.codigo_ativo
      and o.data_abertura >= a.valido_de
      and o.data_abertura <  a.valido_ate

)

select
    -- Chaves.
    r.ativo_sk,
    coalesce(loc.local_sk, -1)                          as local_sk,
    coalesce(tec.tecnico_sk, -1)                        as tecnico_sk,
    modo.modo_falha_sk,

    -- Os dois papeis da dimensao de tempo.
    to_char(r.data_abertura, 'YYYYMMDD')::int           as tempo_sk_abertura,
    coalesce(
        to_char(r.data_conclusao, 'YYYYMMDD')::int, -1
    )                                                   as tempo_sk_conclusao,

    -- Degenerados.
    r.numero_os,
    r.tipo_os,
    r.udi_origem,

    -- Quando, no relogio. As datas continuam no fato alem das FKs porque a diferenca
    -- entre elas e' medida em horas, e dimensao de grain diario nao responde isso.
    r.data_abertura,
    r.data_conclusao,

    -- Medidas.
    r.duracao_horas,
    r.custo_mao_obra,
    r.custo_pecas,
    r.custo_mao_obra + r.custo_pecas                    as custo_total

from resolvido r

left join {{ ref('dim_local') }} loc
  on r.codigo_linha_na_abertura = loc.codigo_linha

left join {{ ref('dim_tecnico') }} tec
  on r.matricula_tecnico = tec.matricula

-- Preventiva nao tem modo, e vira NAO_APLICA. O coalesce acontece antes do join, para
-- o resultado ser um join comum que nunca falha, e nao um left join com FK nula.
join {{ ref('dim_modo_falha') }} modo
  on coalesce(r.modo_falha, 'NAO_APLICA') = modo.codigo_modo
