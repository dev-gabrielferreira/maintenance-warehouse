-- fct_falhas: 382 linhas. Grain: um modo de falha de uma leitura.
--
-- POR QUE ELE EXISTE. 23 leituras tem dois modos marcados e 1 tem tres. Uma FK simples
-- modo_falha_sk em fct_leituras nao comporta isso: ou perde modo, ou escolhe um deles
-- por criterio arbitrario. Com o fato proprio, o grain fica declaravel numa frase e
-- contar parada por modo vira um group by, em vez das cinco somas separadas que as
-- flags booleanas exigiriam.
--
-- A CONTA, para ninguem precisar confiar: 357 leituras com falha pela definicao do
-- warehouse. Dessas, 348 tem pelo menos um modo marcado e produzem 373 linhas (324 com
-- um modo, 23 com dois, 1 com tres). As outras 9 sao as que a fonte declara como falha
-- sem marcar modo nenhum, e viram uma linha de INDETERMINADO cada. 373 mais 9 da' 382.
--
-- E' um FATO SEM MEDIDA. Nao ha' coluna para somar: a medida e' a propria contagem de
-- linhas. Kimball chama isso de factless fact table, e serve exatamente para registrar
-- que um evento aconteceu. Duracao e custo NAO entram aqui, e a razao e' de grain: eles
-- vivem na ordem de servico, que tem um modo so', e soma-los por modo aqui contaria a
-- mesma parada duas vezes nas 24 leituras multimodo.
--
-- POR QUE ELE LE fct_leituras E NAO A STAGING. As chaves de ativo, local, tempo e turno
-- ja' foram resolvidas la', inclusive a resolucao da versao do ativo pela data. Refazer
-- aquele join aqui criaria duas copias da mesma logica, e duas copias divergem um dia
-- sem ninguem ver. Lendo o fato pronto, a mesma leitura tem obrigatoriamente a mesma
-- versao de ativo nos dois fatos.
--
-- Isso e' diferente de CONSUMIR um fato atraves do outro: fct_falhas carrega as
-- proprias FKs, e responder "falhas por setor" nao exige passar por fct_leituras.

with leituras_com_falha as (

    select
        udi,
        ativo_sk,
        local_sk,
        tempo_sk,
        turno_sk,
        instante
    from {{ ref('fct_leituras') }}
    where houve_falha

),

flags as (

    select
        udi,
        falha_twf,
        falha_hdf,
        falha_pwf,
        falha_osf,
        falha_rnf
    from {{ ref('stg_ai4i_leituras') }}

),

-- Formato largo vira longo. Cinco colunas booleanas viram ate' cinco linhas por
-- leitura. E' o unpivot escrito a mao: sao cinco modos fixos, publicados pela fonte, e
-- um union all de cinco ramos e' mais legivel aqui do que qualquer macro.
modos_marcados as (

    select udi, 'TWF' as codigo_modo from flags where falha_twf
    union all
    select udi, 'HDF' from flags where falha_hdf
    union all
    select udi, 'PWF' from flags where falha_pwf
    union all
    select udi, 'OSF' from flags where falha_osf
    union all
    select udi, 'RNF' from flags where falha_rnf

),

-- O left join e' o que faz a conta fechar. Leitura com um modo devolve uma linha, com
-- dois devolve duas, e leitura sem modo nenhum devolve uma linha com codigo nulo, que
-- vira INDETERMINADO. Um inner join aqui perderia as 9 falhas sem causa, que sao
-- justamente as que o membro INDETERMINADO existe para representar.
expandido as (

    select
        l.udi,
        l.ativo_sk,
        l.local_sk,
        l.tempo_sk,
        l.turno_sk,
        l.instante,
        coalesce(m.codigo_modo, 'INDETERMINADO') as codigo_modo

    from leituras_com_falha l
    left join modos_marcados m using (udi)

)

select
    -- Chaves.
    e.ativo_sk,
    e.local_sk,
    e.tempo_sk,
    e.turno_sk,
    d.modo_falha_sk,

    -- Degenerados. O udi liga de volta a leitura de origem, e sozinho nao e' chave
    -- aqui: o grain e' o par (udi, modo).
    e.udi,
    e.instante

    -- Sem medida, de proposito. Ver o cabecalho.

from expandido e
join {{ ref('dim_modo_falha') }} d on e.codigo_modo = d.codigo_modo
