-- fct_leituras: 10.000 linhas, uma por ciclo de operacao de uma maquina.
--
-- Costura a fonte publica (stg_ai4i_leituras, os sensores) com o mundo sintetico
-- (stg_leitura_contexto, em que maquina e em que instante), pelo UDI. As duas tem
-- 10.000 linhas e o join e' 1:1.
--
-- O QUE ESTE GRAIN IMPEDE DE RESPONDER, e que precisa estar na resposta de quem
-- consultar: nao ha' medicao continua, ha' amostra por ciclo, entao nada se sabe sobre
-- a maquina entre dois ciclos. E nao ha' duracao de ciclo, so' o instante em que ele
-- aconteceu, e por isso o MTBF deste warehouse e' medido em dias de calendario e nao
-- em horas de maquina ligada.
--
-- COMO O FATO ACHA O ATIVO, que e' o assunto da semana:
--
--   join dim_ativo a
--     on  l.codigo_ativo = a.codigo_ativo
--     and l.instante >= a.valido_de
--     and l.instante <  a.valido_ate
--
-- As tres condicoes juntas, nunca so' a primeira. Com SCD2, MAQ-066 identifica quatro
-- linhas da dimensao, e o join pelo codigo natural sozinho casaria com as quatro:
-- cada leitura dela viraria quatro, o fato passaria de 10.000 para mais de 10.000
-- linhas, e toda soma sairia multiplicada pelo numero de mudancas que a maquina teve.
-- E' o erro mais caro que uma SCD2 permite cometer, e ele nao da' erro nenhum: da'
-- numero maior.
--
-- Resolver a chave aqui, e nao na consulta, e' o que impede quem consulta de errar.
--
-- O LOCAL VEM DA VERSAO DO ATIVO, e nao do cadastro de hoje. Maquina transferida de
-- linha em 2025 tem as leituras de 2024 no setor antigo. Isso e' o ponto inteiro de
-- existir SCD2: sem ela, uma transferencia reescreveria o passado e o setor de origem
-- perderia leituras que aconteceram nele.
--
-- SOBRE AS DUAS COLUNAS DE FALHA. `houve_falha` e' a definicao deste warehouse: a
-- uniao entre a falha declarada pela fonte e a marcacao de qualquer modo. Sao 357, e
-- 357 e' exatamente o numero de OS corretivas, todas com udi_origem preenchido.
-- `falha_declarada_fonte` guarda o rotulo original, 339. As duas ficam lado a lado de
-- proposito: a divergencia de 18 linhas passa a ser auditavel dentro do dado, e nao
-- so' descrita em documento que ninguem abre.

with leituras as (

    select * from {{ ref('stg_ai4i_leituras') }}

),

contexto as (

    select * from {{ ref('stg_leitura_contexto') }}

),

ativos as (

    select * from {{ ref('dim_ativo') }}

),

locais as (

    select * from {{ ref('dim_local') }}

),

turnos as (

    select * from {{ ref('dim_turno') }}

),

costurado as (

    select
        c.udi,
        c.instante,
        c.turno,
        c.codigo_ativo,
        l.produto_id,
        l.tipo_produto,
        l.temperatura_ar_k,
        l.temperatura_processo_k,
        l.rotacao_rpm,
        l.torque_nm,
        l.desgaste_ferramenta_min,
        l.falha_maquina,
        (
            l.falha_twf or l.falha_hdf or l.falha_pwf or l.falha_osf or l.falha_rnf
        ) as algum_modo_marcado

    from contexto c
    join leituras l using (udi)

),

com_chaves as (

    select
        -- Chaves. O coalesce para -1 existe para o fato nunca carregar FK nula, que
        -- quebraria o join de quem consulta e sumiria da contagem sem avisar. Aqui ele
        -- nao deveria acionar nunca, porque toda leitura aponta para ativo existente e
        -- a vigencia da primeira versao comeca em -infinity: o teste ao lado cobra isso.
        coalesce(a.ativo_sk, -1)                        as ativo_sk,
        coalesce(loc.local_sk, -1)                      as local_sk,
        to_char(f.instante, 'YYYYMMDD')::int            as tempo_sk,
        t.turno_sk,

        -- Degenerados. Ficam no fato porque sao unicos por linha e nao descrevem nada
        -- que se repita: produto_id tem 10.000 valores distintos em 10.000 linhas, e
        -- dimensao de 10.000 linhas para um fato de 10.000 linhas nao e' dimensao.
        f.udi,
        f.produto_id,
        f.tipo_produto,
        f.instante,

        -- Medidas cruas, como o sensor entregou.
        f.temperatura_ar_k,
        f.temperatura_processo_k,
        f.rotacao_rpm,
        f.torque_nm,
        f.desgaste_ferramenta_min,

        -- Medidas derivadas. Sao grandezas fisicas com significado proprio, e sao o
        -- que duas das tres regras verificadas do AI4I usam: HDF olha a diferenca de
        -- temperatura junto com a rotacao, PWF olha a potencia. Calculadas aqui, uma
        -- vez, em vez de reescritas em cada consulta e em cada teste.
        f.temperatura_processo_k - f.temperatura_ar_k   as diferenca_temperatura_k,
        -- O cast para numeric nao e' enfeite: pi() devolve double precision, o
        -- produto inteiro sobe para double, e o round de duas casas do Postgres so'
        -- existe para numeric. Sem o cast o modelo nem compila.
        round((f.torque_nm * f.rotacao_rpm * 2 * pi() / 60)::numeric, 2) as potencia_w,

        -- As duas definicoes de falha, lado a lado.
        (f.falha_maquina or f.algum_modo_marcado)       as houve_falha,
        f.falha_maquina                                 as falha_declarada_fonte

    from costurado f

    left join ativos a
      on  f.codigo_ativo = a.codigo_ativo
      and f.instante     >= a.valido_de
      and f.instante     <  a.valido_ate

    left join locais loc on a.codigo_linha = loc.codigo_linha
    left join turnos t   on f.turno        = t.nome_turno

)

select * from com_chaves
