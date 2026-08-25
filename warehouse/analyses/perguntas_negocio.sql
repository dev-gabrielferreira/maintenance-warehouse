-- AS CINCO PERGUNTAS DE NEGOCIO
--
-- Este arquivo esta' em analyses/: o dbt compila e nao materializa nada. E' o consumo
-- da gold, e o criterio de aceite do projeto. Cada bloco tem a pergunta, o SQL, e o
-- resultado real colado logo abaixo.
--
-- Para rodar:
--
--   uv run --env-file .env dbt compile --project-dir warehouse --profiles-dir warehouse \
--     --select perguntas_negocio
--   docker exec -i maintenance-postgres psql -U ... \
--     < warehouse/target/compiled/warehouse/analyses/perguntas_negocio.sql
--
-- O dbt resolve os ref() para o nome real da tabela, e o arquivo compilado roda no
-- psql como esta'.
--
-- UMA COISA QUE VALE LER ANTES DE QUALQUER RESPOSTA AQUI. O gerador atribui os
-- instantes em ordem estrita de UDI: a correlacao entre udi e instante e' 1,0000. O
-- AI4I concentra 134 falhas entre os UDI 4000 e 4999, e esse bloco cai inteiro no 4o
-- trimestre de 2024, que fica com 11,56% de falha contra ~2,5% nos outros sete. Toda
-- tendencia temporal deste warehouse carrega junto a ordem das linhas do CSV. Isso
-- afeta a pergunta 4 diretamente, e esta' tratado la'.


-- ============================================================================
-- PERGUNTA 1: MTBF e MTTR por criticidade
-- ============================================================================
--
-- MTBF e' tempo exposto dividido por numero de falhas. As duas metades dessa conta
-- precisam de uma decisao neste warehouse.
--
-- 1. O TEMPO E' EM DIAS DE CALENDARIO, e nao em horas de maquina ligada. A fonte tem
--    uma linha por ciclo e nenhuma duracao de ciclo, entao hora de maquina nao existe
--    neste dado. Um MTBF de manutencao de verdade seria em horas de operacao. Este
--    esta' em dias corridos, e a diferenca precisa estar escrita ao lado do numero.
--
-- 2. A EXPOSICAO E' POR VERSAO DE MAQUINA, e nao por maquina. Cinco maquinas foram
--    reclassificadas de criticidade no periodo, entao uma mesma maquina contribui para
--    dois grupos diferentes, cada um com o pedaco da janela em que aquela versao
--    esteve vigente. E' a SCD2 aparecendo numa pergunta que nao e' a de numero 5: com
--    SCD1 essas maquinas iriam inteiras para a criticidade de hoje, e o passado delas
--    entraria no balde errado.
--
-- MTTR e' a media de duracao_horas das corretivas, agrupada pela criticidade da versao
-- vigente na ABERTURA da ordem, que e' como o fct_ordens_servico ja' resolveu a chave.

with janela as (

    -- A janela observada e' a das leituras, e nao o intervalo da dim_tempo. A dim_tempo
    -- vai ate 2026 de proposito, com folga, e usar aquele fim inflaria a exposicao de
    -- todo mundo com um ano em que nao houve producao nenhuma.
    select min(instante) as inicio, max(instante) as fim
    from {{ ref('fct_leituras') }}

),

exposicao as (

    -- Quanto tempo cada versao esteve vigente DENTRO da janela observada. A versao 1
    -- comeca em -infinity e a vigente termina em infinity, entao os dois lados sao
    -- cortados pela janela antes da subtracao.
    select
        a.ativo_sk,
        a.criticidade,
        case
            when a.ativo_sk = -1 then null
            else extract(epoch from (
                     least(a.valido_ate, j.fim) - greatest(a.valido_de, j.inicio)
                 )) / 86400.0
        end as dias_expostos

    from {{ ref('dim_ativo') }} a
    cross join janela j

    -- O membro desconhecido entra na saida, mas sem exposicao: a vigencia dele vai de
    -- -infinity a infinity e nao mede tempo de maquina nenhuma. Ele esta' aqui para as
    -- 4 corretivas orfas aparecerem no MTTR em vez de sumirem do total.
    where a.ativo_sk = -1
       or greatest(a.valido_de, j.inicio) < least(a.valido_ate, j.fim)

),

falhas as (

    select ativo_sk, count(*) as falhas
    from {{ ref('fct_leituras') }}
    where houve_falha
    group by 1

),

reparos as (

    select
        ativo_sk,
        count(*)            as corretivas,
        sum(duracao_horas)  as horas
    from {{ ref('fct_ordens_servico') }}
    where tipo_os = 'corretiva'
    group by 1

)

select
    e.criticidade,
    count(*)                                        as versoes,
    round(sum(e.dias_expostos)::numeric, 0)         as dias_expostos,
    coalesce(sum(f.falhas), 0)                      as falhas,

    -- MTBF: dias expostos somados divididos por falhas somadas. E' a forma agrupada, e
    -- nao a media das medias: maquina com uma falha so' nao pesa igual a uma com dez.
    round((sum(e.dias_expostos) / nullif(sum(f.falhas), 0))::numeric, 1) as mtbf_dias,

    coalesce(sum(r.corretivas), 0)                  as corretivas,
    round((sum(r.horas) / nullif(sum(r.corretivas), 0))::numeric, 2)     as mttr_horas

from exposicao e
left join falhas  f using (ativo_sk)
left join reparos r using (ativo_sk)

group by 1
order by mtbf_dias nulls last;

-- RESULTADO:
--
--  criticidade  | versoes | dias_expostos | falhas | mtbf_dias | corretivas | mttr_horas
-- --------------+---------+---------------+--------+-----------+------------+------------
--  baixa        |      38 |         19922 |    136 |     146.5 |        135 |       6.07
--  media        |      43 |         22970 |    137 |     167.7 |        135 |       6.58
--  alta         |      30 |         15504 |     84 |     184.6 |         83 |       6.59
--  desconhecido |       1 |               |      0 |           |          4 |       8.81
--
-- As contas fecham: 38+43+30 = 111 versoes, 136+137+84 = 357 falhas, e
-- 135+135+83+4 = 357 corretivas.
--
-- ----------------------------------------------------------------------------
-- A LEITURA, QUE E' O QUE VALE AQUI
-- ----------------------------------------------------------------------------
--
-- O numero esta' invertido em relacao ao que a intuicao pede: maquina de criticidade
-- ALTA falha MENOS. 184,6 dias entre falhas contra 146,5 da criticidade baixa, que e'
-- 26% a mais de tempo em pe'.
--
-- A leitura errada, e tentadora, seria "as maquinas criticas sao mais bem cuidadas".
-- Nao ha' nada neste dado que sustente isso, e a causa e' outra: sao duas decisoes
-- tomadas em lugares diferentes, que ninguem ligou uma na outra de proposito.
--
--   1. O AI4I faz o limite do OSF depender do tipo da peca. Peca H aguenta mais esforco
--      que L antes da sobrecarga, e a consequencia esta' no dado: das 98 ocorrencias de
--      OSF, 87 sao de maquina tipo L, 9 de M e 2 de H. Por tipo de maquina, a taxa de
--      falha e' 4,12% no L, 2,84% no M e 2,49% no H.
--
--   2. O gerador sorteia a criticidade A PARTIR do tipo da maquina: H tem 75% de chance
--      de nascer "alta", e L tem 45% de nascer "baixa".
--
-- Junte as duas e o resultado sai sozinho: o grupo "alta" concentra maquina H e M, que
-- falham menos porque a REGRA FISICA DA FONTE as poupa. O MTBF por criticidade esta'
-- medindo tipo de peca com outro nome.
--
-- Isso e' um limite deste dado sintetico, e nao um achado sobre manutencao industrial.
-- Num parque de verdade a criticidade e' uma classificacao de consequencia da parada,
-- e nao uma propriedade fisica do equipamento, entao ela nao teria por que se
-- correlacionar com taxa de falha em direcao nenhuma.
--
-- O MTTR, esse, nao tem gradiente: 6,07, 6,58 e 6,59 horas nas tres criticidades. Faz
-- sentido, porque o gerador tira a duracao do reparo do MODO de falha e nunca olha a
-- criticidade da maquina. Celula sem padrao com o motivo escrito e' informacao.
--
-- As 4 corretivas orfas de ativo aparecem na linha "desconhecido" com MTTR de 8,81
-- horas. Elas nao tem MTBF porque nao ha' maquina a que atribuir exposicao, e continuam
-- visiveis em vez de filtradas: sao ordens com custo real, e a decisao da Semana 2 foi
-- que nenhuma delas some do warehouse sem alguem ver.


-- ============================================================================
-- PERGUNTA 2: quais setores concentram custo de corretiva
-- ============================================================================
--
-- "Concentra" e' uma palavra perigosa numa pergunta de custo, porque a resposta obvia
-- e' uma tabela de TAMANHO DE SETOR com nome de custo: o setor que tem mais maquina
-- gasta mais, e isso nao informa nada a quem decide onde mexer.
--
-- Entao a resposta sai com as duas colunas lado a lado: quanto o setor pesa no custo
-- total, e quanto ele pesa na producao. A diferenca entre as duas e' o que separa "e'
-- grande" de "e' caro".
--
-- O DENOMINADOR E' CICLO PRODUZIDO, e nao numero de maquinas. E' o que o fct_leituras
-- mede de verdade, e o parque tem carga desbalanceada de proposito (de 32 a 933
-- leituras por maquina): contar maquina daria peso igual para o gargalo e para a que
-- roda uma vez por semana.
--
-- dim_local tem grain de LINHA DE PRODUCAO, e sao 13 linhas em 5 setores. O group by
-- e' pelo codigo_setor, e nao pelo local_sk.
--
-- O setor desconhecido FICA NA SAIDA. Sao as 4 corretivas orfas de ativo, com
-- R$ 12.679,33 de custo real, e a decisao da Semana 2 foi que ordem com dinheiro dentro
-- nao some do warehouse sem alguem ver. Filtrar aqui seria fazer exatamente isso.

with producao as (

    select
        l.codigo_setor,
        count(*) as ciclos

    from {{ ref('fct_leituras') }} f
    join {{ ref('dim_local') }} l using (local_sk)
    group by 1

),

corretivas as (

    select
        l.codigo_setor,
        l.nome_setor,
        count(*)                as ordens,
        sum(o.custo_total)      as custo,
        sum(o.duracao_horas)    as horas

    from {{ ref('fct_ordens_servico') }} o
    join {{ ref('dim_local') }} l using (local_sk)
    where o.tipo_os = 'corretiva'
    group by 1, 2

)

select
    c.nome_setor,
    p.ciclos,
    c.ordens,
    round(c.custo, 2)                                       as custo,

    -- As duas colunas que fazem a pergunta valer: peso no custo contra peso na producao.
    round(100.0 * c.custo  / sum(c.custo)  over (), 1)      as pct_custo,
    round(100.0 * p.ciclos / sum(p.ciclos) over (), 1)      as pct_ciclos,

    round(c.custo / c.ordens, 2)                            as custo_medio_os,
    round(c.custo * 1000 / p.ciclos, 2)                     as por_1k_ciclos

from corretivas c
left join producao p using (codigo_setor)
order by c.custo desc;

-- RESULTADO:
--
--   nome_setor   | ciclos | ordens |   custo   | pct_custo | pct_ciclos | custo_medio_os | por_1k_ciclos
-- ---------------+--------+--------+-----------+-----------+------------+----------------+---------------
--  Usinagem      |   3992 |    141 | 284857.16 |      40.8 |       39.9 |        2020.26 |      71357.00
--  Montagem      |   2482 |    100 | 208583.95 |      29.9 |       24.8 |        2085.84 |      84038.66
--  Acabamento    |   2024 |     52 |  93287.02 |      13.4 |       20.2 |        1793.98 |      46090.42
--  Ferramentaria |   1135 |     45 |  74325.70 |      10.7 |       11.4 |        1651.68 |      65485.20
--  Expedicao     |    367 |     15 |  23706.56 |       3.4 |        3.7 |        1580.44 |      64595.53
--  desconhecido  |        |      4 |  12679.33 |       1.8 |            |        3169.83 |
--
-- ----------------------------------------------------------------------------
-- A LEITURA
-- ----------------------------------------------------------------------------
--
-- A resposta de uma coluna so' seria "Usinagem, com 40,8% do custo". Ela esta' certa e
-- e' quase inutil: a Usinagem tambem roda 39,9% dos ciclos do parque. Ela concentra
-- custo porque concentra producao, e a R$ 71.357 por mil ciclos ela esta' praticamente
-- na media da fabrica, que e' R$ 69.744.
--
-- QUEM DESTOA E' A MONTAGEM: 29,9% do custo sobre 24,8% dos ciclos, e R$ 84.039 por mil
-- ciclos, 20% acima da media. E o inverso tambem existe, e e' igual de util: o
-- Acabamento roda 20,2% dos ciclos e responde por 13,4% do custo, a R$ 46.090 por mil,
-- um terco abaixo da media.
--
-- Entre o setor mais intenso e o menos intenso ha' 82% de diferenca por ciclo
-- produzido, e nenhuma das duas pontas e' a que a coluna de custo total apontaria.
--
-- E DE ONDE VEM A DIFERENCA. Nao e' qualidade de manutencao, e o dado diz de onde e':
--
--   setor          | % dos ciclos em maquina tipo L | taxa de falha
--   Montagem       |                          72,4% |         4,07%
--   Ferramentaria  |                          60,3% |         4,14%
--   Usinagem       |                          70,3% |         3,53%
--   Expedicao      |                          59,7% |         4,09%
--   Acabamento     |                          24,5% |         2,62%
--
-- E' a mesma cadeia da pergunta 1, chegando por outro caminho. O limite do OSF no AI4I
-- depende do tipo da peca, 87 das 98 ocorrencias de OSF sao de maquina tipo L, e o OSF
-- e' de longe o reparo mais caro do parque: R$ 2.967,64 de peca em media, contra
-- R$ 643,26 do HDF. O Acabamento e' barato porque tem 24,5% de tipo L; a Montagem e'
-- cara porque tem 72,4%.
--
-- O gerador espalhou as maquinas pelas linhas com rng.choice, sem olhar tipo nem setor.
-- Entao a intensidade de custo por setor deste warehouse e' uma regra fisica da fonte
-- passando por um sorteio, e nao uma diferenca de gestao. Num parque real a conclusao
-- seria "va' olhar a Montagem"; aqui a conclusao honesta e' "va' olhar o mix de tipo de
-- maquina, que e' o que a Montagem tem de diferente".
--
-- SOBRE A SUJEIRA NA SOMA. Das 10 ordens com custo de peca negativo injetadas, 5 sao
-- corretivas, e elas somam -R$ 7.476,19, ou 1,07% do custo total de R$ 697.439,72. Em
-- 4 delas o negativo arrasta a ordem inteira para baixo de zero. Elas ficam na conta,
-- porque tira-las aqui em silencio deixaria esta resposta em desacordo com o teste que
-- guarda o limiar delas no build. O numero para saber e': a resposta erra 1% para
-- menos, e o erro tem dono.


-- ============================================================================
-- PERGUNTA 3: qual modo de falha mais para maquina, por hora parada
-- ============================================================================
--
-- A pergunta ja' vem com a armadilha embutida: "qual modo mais para maquina" tem duas
-- respostas diferentes, e a diferenca entre elas e' a pergunta inteira. Contar
-- OCORRENCIA responde qual acontece mais; somar HORA PARADA responde qual custa mais
-- tempo de fabrica. As duas colunas saem lado a lado.
--
-- A SOMA E' PELO fct_ordens_servico, E NAO PELO fct_falhas. Isso esta' escrito no
-- modelo-dimensional.md e vale repetir, porque e' o erro natural: o fct_falhas tem
-- grain (leitura, modo) e 382 linhas, mas e' um fato SEM MEDIDA, e nao tem duracao para
-- somar. Quem tem duracao e' a ordem de servico.
--
-- A consequencia disso aparece na propria tabela: aqui o HDF tem 109 ordens, e no
-- fct_falhas ele tem 115 ocorrencias. Nao ha' erro nos dois numeros. As 24 leituras com
-- mais de um modo geram UMA ordem so', e o gerador a atribui ao modo de maior duracao
-- de reparo. Somar hora parada pelo fct_falhas contaria a mesma parada duas ou tres
-- vezes nessas 24 leituras.

select
    m.codigo_modo,
    m.nome_modo,
    count(*)                                                            as ordens,
    round(sum(o.duracao_horas), 1)                                      as horas_paradas,

    -- As duas participacoes lado a lado. E' a comparacao delas que responde.
    round(100.0 * sum(o.duracao_horas) / sum(sum(o.duracao_horas)) over (), 1) as pct_horas,
    round(100.0 * count(*) / sum(count(*)) over (), 1)                  as pct_ordens,

    round(avg(o.duracao_horas), 2)                                      as horas_por_os,
    round(sum(o.custo_total), 2)                                        as custo

from {{ ref('fct_ordens_servico') }} o
join {{ ref('dim_modo_falha') }} m using (modo_falha_sk)

where o.tipo_os = 'corretiva'
group by 1, 2
order by horas_paradas desc;

-- RESULTADO:
--
--   codigo_modo  |          nome_modo           | ordens | horas_paradas | pct_horas | pct_ordens | horas_por_os |   custo
-- ---------------+------------------------------+--------+---------------+-----------+------------+--------------+-----------
--  OSF           | Sobrecarga                   |     95 |         915.4 |      40.0 |       26.6 |         9.64 | 349421.40
--  TWF           | Desgaste de ferramenta       |     46 |         508.4 |      22.2 |       12.9 |        11.05 | 140388.35
--  HDF           | Dissipacao de calor          |    109 |         444.0 |      19.4 |       30.5 |         4.07 | 102713.74
--  PWF           | Falha de potencia            |     80 |         306.1 |      13.4 |       22.4 |         3.83 |  82093.47
--  INDETERMINADO | Falha sem causa identificada |      9 |          79.4 |       3.5 |        2.5 |         8.83 |  16056.17
--  RNF           | Falha aleatoria              |     18 |          37.0 |       1.6 |        5.0 |         2.05 |   6766.59
--
-- ----------------------------------------------------------------------------
-- A LEITURA
-- ----------------------------------------------------------------------------
--
-- OS DOIS RANQUEAMENTOS SAO QUASE INVERSOS.
--
--   por ocorrencia:   HDF (30,5%), OSF (26,6%), PWF (22,4%), TWF (12,9%)
--   por hora parada:  OSF (40,0%), TWF (22,2%), HDF (19,4%), PWF (13,4%)
--
-- O HDF e' o modo que MAIS ACONTECE e o terceiro em hora parada. O TWF e' o penultimo
-- em ocorrencia e o segundo em hora parada. Quem olhasse so' a contagem de falhas iria
-- atras do HDF, que e' quase um terco das ordens e menos de um quinto do tempo perdido.
--
-- A explicacao esta' na coluna horas_por_os, e ela e' de manutencao, nao de estatistica:
-- HDF e PWF resolvem dentro do turno (4,07 e 3,83 horas), porque sao limpeza de
-- trocador e reset de acionamento, sem troca de peca. OSF e TWF param a maquina por 9,64
-- e 11,05 horas, porque envolvem trocar componente e esperar a peca chegar. E' o que
-- esta' escrito na descricao de engenharia de cada modo, dentro da propria
-- dim_modo_falha, e o dado reproduz.
--
-- O CUSTO SEGUE A HORA, E NAO A OCORRENCIA: o OSF sozinho responde por R$ 349.421 dos
-- R$ 697.440 de corretiva do parque, metade do total, com 26,6% das ordens.
--
-- Vale reparar no RNF, que e' o menor de todos em hora e em custo, e nao por acaso: ele
-- e' o ruido que o proprio AI4I injetou de proposito, sem causa fisica, e o gerador deu
-- a ele 1 a 3 horas de "abre, confere e fecha sem achar nada". A dimensao carrega isso
-- escrito, e a tabela concorda com o texto.


-- ============================================================================
-- PERGUNTA 4: preventiva em dia reduz corretiva no trimestre seguinte?
-- ============================================================================
--
-- Esta e' a pergunta que mais precisa de definicao antes de virar SQL, e sao tres.
--
-- 1. O QUE E' "EM DIA", SEM COLUNA DE DATA PLANEJADA. O fato nao tem data de plano, e
--    nao precisa ter: para preventiva, a data_abertura E' a data do plano, porque a
--    ordem nasce quando o plano manda. O atraso e' entao a espera entre abrir e ficar
--    pronta, descontado o tempo de reparo:
--
--        atraso = (data_conclusao - data_abertura) - duracao_horas
--
--    A distribuicao cai limpa em 0 a 7 dias, 14 a 60 dias, e sem conclusao. Isso
--    reproduz a regra de aderencia do gerador sem ninguem ter contado a ela qual era,
--    o que e' a melhor conferencia possivel de uma definicao derivada.
--
-- 2. QUAL FAIXA VALE QUANDO O TRIMESTRE TEM DUAS PREVENTIVAS. Sao 11 pares
--    (maquina, trimestre) com duas ordens, contra 625 com uma. A pior faixa vence:
--    quem fez uma no prazo e outra com 40 dias de atraso nao aderiu ao plano. As 4
--    preventivas de atraso negativo, que sao a sujeira das datas invertidas, ganham
--    faixa propria e vencem qualquer desempate, para nao se esconderem dentro de outra.
--
-- 3. POR QUE AQUI O AGRUPAMENTO E' PELO CODIGO NATURAL, e nao pela surrogate. O resto
--    do projeto repete que fato nao casa com dimensao por codigo_ativo. Aqui a serie e'
--    a mesma MAQUINA FISICA ao longo de oito trimestres, e uma maquina que trocou de
--    versao no meio tem ativo_sk diferente antes e depois: agrupar pela surrogate
--    partiria a serie dela em duas no meio da janela. Nao e' a mesma coisa que o erro
--    de join: la' o codigo natural casava uma linha de fato com VARIAS versoes e
--    multiplicava o valor; aqui a chave ja' esta' resolvida no fato, e o codigo natural
--    so' esta' costurando de volta as versoes da mesma maquina, que e' para isso que
--    ele existe na dimensao. Medido, em vez de afirmado: sao 636 pares, e casar a
--    serie pela surrogate em vez do codigo natural perde 12 pares e 22 corretivas,
--    de 318 para 296. Sete por cento das corretivas sumiriam da resposta, sem erro
--    nenhum aparecer, e justamente nas maquinas que mudaram de cadastro no periodo.
--
-- As 8 ordens orfas de ativo ficam de fora, porque nao ha' maquina a que atribuir a
-- serie. E' a unica pergunta do arquivo em que o desconhecido nao aparece na saida, e
-- o motivo e' esse.

with preventivas as (

    select
        a.codigo_ativo,
        t.ano * 4 + t.trimestre  as tri,
        t.ano,
        t.trimestre,
        case
            when o.data_conclusao is null then 'nao executada'
            when floor(extract(epoch from (o.data_conclusao - o.data_abertura)) / 86400.0
                       - o.duracao_horas / 24.0) <  0 then 'data invertida'
            when floor(extract(epoch from (o.data_conclusao - o.data_abertura)) / 86400.0
                       - o.duracao_horas / 24.0) <= 7 then 'em dia'
            else 'atrasada'
        end as faixa

    from {{ ref('fct_ordens_servico') }} o
    join {{ ref('dim_ativo') }}  a using (ativo_sk)
    join {{ ref('dim_tempo') }}  t on o.tempo_sk_abertura = t.tempo_sk
    where o.tipo_os = 'preventiva'
      and a.ativo_sk <> -1

),

aderencia as (

    -- Uma linha por (maquina, trimestre), com a pior faixa do trimestre.
    select distinct on (codigo_ativo, tri)
        codigo_ativo, tri, ano, trimestre, faixa
    from preventivas
    order by
        codigo_ativo, tri,
        case faixa
            when 'data invertida' then 4
            when 'nao executada'  then 3
            when 'atrasada'       then 2
            else 1
        end desc

),

corretivas as (

    select
        a.codigo_ativo,
        t.ano * 4 + t.trimestre  as tri,
        count(*)                 as n

    from {{ ref('fct_ordens_servico') }} o
    join {{ ref('dim_ativo') }}  a using (ativo_sk)
    join {{ ref('dim_tempo') }}  t on o.tempo_sk_abertura = t.tempo_sk
    where o.tipo_os = 'corretiva'
      and a.ativo_sk <> -1
    group by 1, 2

),

pares as (

    -- O deslocamento de um trimestre. O left join com coalesce e' obrigatorio: trimestre
    -- seguinte SEM corretiva nenhuma e' zero, e e' o caso que mais interessa a pergunta.
    -- Com inner join essas maquinas sumiriam e a media subiria em todas as faixas.
    select
        ad.*,
        coalesce(c.n, 0) as corretivas_seguinte

    from aderencia ad
    left join corretivas c
      on  c.codigo_ativo = ad.codigo_ativo
      and c.tri          = ad.tri + 1

    -- O ultimo trimestre da janela nao tem seguinte, e vira par sem resposta possivel.
    where ad.tri + 1 <= (select max(tri) from corretivas)

)

select
    faixa,
    count(*)                                as pares,
    sum(corretivas_seguinte)                as corretivas_no_seguinte,
    round(avg(corretivas_seguinte), 3)      as media,

    -- As mesmas duas colunas, tirando os pares cujo trimestre seguinte e' 2024Q4. Ver a
    -- leitura abaixo: aquele trimestre nao mede manutencao, mede a ordem das linhas do
    -- arquivo do AI4I.
    count(*) filter (where not (ano = 2024 and trimestre = 3))                   as pares_limpos,
    round(avg(corretivas_seguinte) filter (where not (ano = 2024 and trimestre = 3)), 3) as media_limpa

from pares
group by 1
order by media desc;

-- RESULTADO:
--
--      faixa      | pares | corretivas_no_seguinte | media | pares_limpos | media_limpa
-- ----------------+-------+------------------------+-------+--------------+-------------
--  data invertida |     4 |                      5 | 1.250 |            2 |       1.500
--  nao executada  |    33 |                     25 | 0.758 |           26 |       0.231
--  atrasada       |    62 |                     41 | 0.661 |           52 |       0.500
--  em dia         |   457 |                    247 | 0.540 |          397 |       0.350
--
-- ----------------------------------------------------------------------------
-- A LEITURA, E ELA E' O CONTRARIO DO QUE A PRIMEIRA COLUNA SUGERE
-- ----------------------------------------------------------------------------
--
-- A coluna "media" e' uma armadilha perfeita, porque ela sai na direcao que a pergunta
-- espera, e em ordem: 0,540 corretiva no trimestre seguinte para quem fez a preventiva
-- em dia, 0,661 para quem atrasou, 0,758 para quem nao fez. Escrito assim, vira "fazer
-- preventiva em dia reduz corretiva em 29%", e o numero e' verdadeiro.
--
-- A coluna "media_limpa" desmancha isso. Tirando UM par de trimestres, a ordem quebra:
-- quem NAO FEZ a preventiva passa a ter a MENOR taxa de corretiva depois (0,231),
-- abaixo de quem fez em dia (0,350).
--
-- O par retirado e' 2024Q3 -> 2024Q4, e aqui esta' o porque, aberto por trimestre:
--
--   trimestre  | seguinte | pares | em dia | atrasada | nao exec | media geral
--  ------------+----------+-------+--------+----------+----------+-------------
--   2024Q1     | 2024Q2   |    80 |  0.348 |    1.143 |    0.286 |       0.413
--   2024Q2     | 2024Q3   |    78 |  0.349 |    0.250 |    0.400 |       0.372
--   2024Q3     | 2024Q4   |    79 |  1.800 |    1.500 |    2.714 |       1.823
--   2024Q4     | 2025Q1   |    80 |  0.391 |    0.600 |    0.167 |       0.400
--   2025Q1     | 2025Q2   |    80 |  0.324 |    0.143 |    0.000 |       0.300
--   2025Q2     | 2025Q3   |    79 |  0.369 |    0.700 |    0.250 |       0.405
--   2025Q3     | 2025Q4   |    80 |  0.324 |    0.200 |    0.000 |       0.300
--
-- Uma linha e' cinco vezes as outras, nas tres faixas ao mesmo tempo. Ela e' o achado
-- que abre este arquivo: o gerador atribui os instantes em ordem estrita de UDI, o AI4I
-- concentra 134 falhas entre os UDI 4000 e 4999, e esse bloco cai inteiro no 4o
-- trimestre de 2024. Aquele trimestre tem 146 corretivas contra ~30 dos outros sete, e
-- a razao nao tem nada a ver com manutencao: e' a ordem das linhas de um CSV.
--
-- Como a faixa "nao executada" tem 33 pares no total e 7 deles caem justamente ali,
-- aquele unico trimestre carrega quase toda a diferenca que a coluna "media" mostrava.
--
-- ENTAO A RESPOSTA E' NAO: neste dado, preventiva em dia nao reduz corretiva no
-- trimestre seguinte. E ela nao poderia reduzir, o que e' a parte que fecha o
-- argumento. O gerador deriva as corretivas das falhas do AI4I, indexadas por UDI, e
-- gera as preventivas de um plano fixo de 90 dias. Os dois nunca se olham. Nao existe
-- mecanismo pelo qual uma preventiva atrasada cause uma falha aqui, entao qualquer
-- gradiente que aparecesse teria que ser ruido ou contaminacao, e foi as duas coisas.
--
-- O que sustenta isso na tabela por trimestre e' a estabilidade da coluna "em dia":
-- 0,348, 0,349, 0,391, 0,324, 0,369, 0,324 nos seis trimestres limpos. Ela tem 457
-- pares e quase nao se move. As outras duas colunas pulam de 0,000 a 1,143 porque tem
-- 62 e 33 pares no total, uns 9 e uns 5 por trimestre, e com essa amostra a media anda
-- sozinha.
--
-- O VALOR DESTA PERGUNTA NAO E' A RESPOSTA, E' O CAMINHO. O warehouse formulou a
-- pergunta certa, com a definicao de "em dia" derivada do dado, o deslocamento de
-- trimestre montado e a serie por maquina costurada atraves das versoes da SCD2. O
-- resultado agregado apontava para a resposta que se queria ouvir, e foi olhar o corte
-- por trimestre que mostrou que ela vinha de um artefato da fonte. Num projeto de
-- verdade e' exatamente esse o momento em que se ganha ou se perde a confianca no
-- numero, e ele so' existe porque a resposta veio com o corte junto.


-- ============================================================================
-- PERGUNTA 5: o custo de manutencao muda depois da reforma?
-- ============================================================================
--
-- E' a unica das cinco que NAO EXISTE sem SCD2, e por isso ela e' a razao de a SCD2
-- estar no projeto. Sem historico, a maquina sempre esteve reformada, e o periodo
-- anterior nao fica errado: ele desaparece.
--
-- O caso unico, com a comparacao lado a lado contra o que uma SCD1 responderia, esta'
-- em analyses/demonstracao_scd2.sql, com a MAQ-060. Aqui a pergunta e' feita para o
-- parque inteiro, e o que este arquivo acrescenta aquele e' o DENOMINADOR.
--
-- POR QUE O TOTAL CRU NAO SERVE. A demonstracao mostra o custo somado de cada periodo,
-- e aquilo basta para provar que os dois periodos existem separados. Mas comparar os
-- dois totais e' comparar um ano com dois meses: a MAQ-017 tem 661 dias antes da
-- reforma e 69 depois, e a MAQ-005 tem 148 antes e 582 depois. "Zero antes, seis
-- depois" na MAQ-005 nao quer dizer que a reforma piorou a maquina; quer dizer que o
-- antes dela e' um quarto do depois.
--
-- Entao o custo sai por mes de vigencia, com o tempo de cada versao cortado pela janela
-- observada, do mesmo jeito que a pergunta 1 fez com a exposicao.

with janela as (

    select min(instante) as inicio, max(instante) as fim
    from {{ ref('fct_leituras') }}

),

reformadas as (

    -- Uma maquina esta' aqui se ALGUMA versao dela chegou a 'reformado'. Sao 6 das 80.
    select distinct codigo_ativo
    from {{ ref('dim_ativo') }}
    where estado = 'reformado'

),

versoes as (

    -- O 'antes' pode ter mais de uma versao: maquina que foi transferida e depois
    -- reformada tem duas versoes antes da reforma. Por isso o periodo agrega versoes,
    -- em vez de assumir uma de cada lado.
    select
        a.codigo_ativo,
        a.ativo_sk,
        case when a.estado = 'reformado' then 'depois' else 'antes' end as periodo,
        extract(epoch from (
            least(a.valido_ate, j.fim) - greatest(a.valido_de, j.inicio)
        )) / 86400.0 as dias

    from {{ ref('dim_ativo') }} a
    join reformadas r using (codigo_ativo)
    cross join janela j
    where greatest(a.valido_de, j.inicio) < least(a.valido_ate, j.fim)

),

ordens as (

    -- A chave ja' esta' resolvida pela data de ABERTURA da ordem no fct_ordens_servico,
    -- entao a ordem aberta antes da reforma pertence a versao antiga mesmo que tenha
    -- sido concluida depois. E' a decisao registrada no proprio modelo, e e' ela que
    -- faz esta pergunta ter resposta.
    select
        ativo_sk,
        count(*)            as corretivas,
        sum(custo_total)    as custo
    from {{ ref('fct_ordens_servico') }}
    where tipo_os = 'corretiva'
    group by 1

)

select
    v.codigo_ativo,
    v.periodo,
    round(sum(v.dias))                                          as dias,
    coalesce(sum(o.corretivas), 0)                              as corretivas,
    round(coalesce(sum(o.custo), 0), 2)                         as custo,

    -- A coluna que torna os dois lados comparaveis.
    round(coalesce(sum(o.custo), 0) * 30 / sum(v.dias), 2)      as custo_por_mes,

    round(sum(v.dias) / nullif(sum(o.corretivas), 0), 0)        as dias_entre_corretivas

from versoes v
left join ordens o using (ativo_sk)
group by 1, 2
order by 1, 2 desc;

-- RESULTADO:
--
--  codigo_ativo | periodo | dias | corretivas |  custo  | custo_por_mes | dias_entre_corretivas
-- --------------+---------+------+------------+---------+---------------+-----------------------
--  MAQ-005      | depois  |  582 |          6 | 5604.36 |        288.78 |                    97
--  MAQ-005      | antes   |  148 |          0 |    0.00 |          0.00 |
--  MAQ-008      | depois  |  213 |          1 | 2308.89 |        324.88 |                   213
--  MAQ-008      | antes   |  517 |          1 | 4756.58 |        276.15 |                   517
--  MAQ-017      | depois  |   69 |          0 |    0.00 |          0.00 |
--  MAQ-017      | antes   |  661 |          3 | 3092.39 |        140.40 |                   220
--  MAQ-025      | depois  |  349 |          0 |    0.00 |          0.00 |
--  MAQ-025      | antes   |  381 |          2 | 4780.06 |        376.63 |                   190
--  MAQ-060      | depois  |  240 |          1 |  579.71 |         72.40 |                   240
--  MAQ-060      | antes   |  490 |          4 | 4849.95 |        297.09 |                   122
--  MAQ-075      | depois  |  583 |          2 | 3328.29 |        171.21 |                   292
--  MAQ-075      | antes   |  147 |          1 |  564.06 |        115.31 |                   147
--
-- Confere: os dois periodos de cada maquina somam 730 dias, que e' a janela observada
-- inteira. Nenhum pedaco de vigencia se perdeu no caminho.
--
-- ----------------------------------------------------------------------------
-- A LEITURA
-- ----------------------------------------------------------------------------
--
-- Pelo custo por mes de vigencia, TRES SOBEM E TRES DESCEM:
--
--   MAQ-060   R$ 297 -> R$  72     desceu
--   MAQ-025   R$ 377 -> R$   0     desceu
--   MAQ-017   R$ 140 -> R$   0     desceu
--   MAQ-075   R$ 115 -> R$ 171     subiu
--   MAQ-008   R$ 276 -> R$ 325     subiu
--   MAQ-005   R$   0 -> R$ 289     subiu
--
-- Nao ha' padrao, e nao deveria haver. O gerador distribui falha por CARGA DE USO,
-- seguindo a curva 1/rank^0.8, e nunca olha o estado do equipamento. Reforma nao reduz
-- falha neste dado porque nada no gerador liga uma coisa na outra, e isso esta'
-- declarado nos limites do README.
--
-- A NORMALIZACAO INVERTEU UMA DAS SEIS, e vale saber qual. A MAQ-008 gastou
-- R$ 4.756,58 antes da reforma e R$ 2.308,89 depois: pelo total cru, o custo dela caiu
-- pela metade, e a demonstracao_scd2.sql a lista assim. Por mes de vigencia ela vai de
-- R$ 276,15 para R$ 324,88, ou seja, SUBIU 18%. As duas contas estao certas, e o que
-- muda entre elas e' que o periodo depois da reforma tem 213 dias contra 517 do
-- periodo anterior. Ela gastou menos dinheiro porque foi observada menos tempo.
--
-- E' por isso que a contagem muda de lugar para lugar neste projeto: a Semana 3 escreveu
-- "duas sobem, duas descem e duas nao tem os dois lados", contando totais crus, e aqui
-- sao tres e tres, contando taxa. Nenhuma das duas frases esta' errada, e as duas
-- precisam dizer de que sao feitas.
--
-- As tres maquinas com R$ 0 de um lado tem 69, 148 e 349 dias naquele lado: com zero ou
-- uma ordem, a taxa por mes anda muito, e isso precisa estar dito ao lado da tabela em
-- vez de virar conclusao.
--
-- O QUE ESTA DEMONSTRADO, E E' O QUE IMPORTA. Nao e' que reforma reduz custo. E' que o
-- warehouse SEPARA o antes do depois de uma mudanca de cadastro, com cada ordem de
-- servico atribuida a versao da maquina que estava valendo no dia em que ela abriu. Se
-- o dado tivesse padrao, ele apareceria nesta tabela.
--
-- Com SCD1 esta consulta devolveria seis linhas em vez de doze, todas marcadas
-- 'reformado', e o custo dos dois periodos somado numa so'. O numero nao ficaria
-- errado: ele responderia outra pergunta, e ninguem notaria a troca. E' esse o custo
-- real de nao guardar historico, e e' por isso que so' a dim_ativo e' SCD2 neste
-- projeto: nenhuma das outras quatro perguntas precisa do passado, e esta nao existe
-- sem ele.
