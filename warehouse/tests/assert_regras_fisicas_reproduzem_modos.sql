-- As regras fisicas documentadas tem que reproduzir exatamente os modos marcados.
--
-- O docs/fonte-ai4i.md, escrito na Semana 1, rodou cada regra do dataset contra o dado
-- e registrou que tres delas fecham na unha: HDF 115 de 115, OSF 98 de 98, PWF 95 de
-- 95. Este teste transforma aquela conferencia manual em contrato do build.
--
-- Ele nao testa a fonte, testa O WAREHOUSE. As regras sao calculadas a partir das
-- medidas derivadas de fct_leituras (diferenca_temperatura_k e potencia_w) e o
-- resultado e' comparado com os modos de fct_falhas. Se alguem mexer na formula da
-- potencia, no cast que ela precisa, ou no unpivot dos modos, as duas pontas param de
-- bater e o build para.
--
-- Nas duas direcoes, porque errar tem dois lados: regra que dispara sem o modo estar
-- marcado, e modo marcado sem a regra disparar.
--
-- O TWF FICA DE FORA, e isso e' honestidade e nao esquecimento. A documentacao do
-- dataset descreve troca de ferramenta entre 200 e 240 minutos de desgaste, e o
-- arquivo tem casos de 198 a 253. A regra publicada e o dado publicado nao coincidem,
-- entao testar contra ela acusaria um erro que e' da documentacao, nao do warehouse.
-- O RNF tambem fica: e' ruido proposital, sem causa fisica, e nao ha' regra para
-- reproduzir.

with modos as (

    select
        udi,
        bool_or(d.codigo_modo = 'HDF') as tem_hdf,
        bool_or(d.codigo_modo = 'PWF') as tem_pwf,
        bool_or(d.codigo_modo = 'OSF') as tem_osf
    from {{ ref('fct_falhas') }} f
    join {{ ref('dim_modo_falha') }} d using (modo_falha_sk)
    group by udi

),

base as (

    select
        l.udi,
        l.tipo_produto,
        l.temperatura_ar_k,
        l.temperatura_processo_k,
        l.diferenca_temperatura_k,
        l.rotacao_rpm,
        l.potencia_w,
        l.desgaste_ferramenta_min,
        l.torque_nm,
        coalesce(m.tem_hdf, false) as tem_hdf,
        coalesce(m.tem_pwf, false) as tem_pwf,
        coalesce(m.tem_osf, false) as tem_osf

    from {{ ref('fct_leituras') }} l
    left join modos m using (udi)

),

avaliado as (

    select
        *,
        -- Dissipacao de calor: pouca diferenca entre processo e ar, com rotacao baixa.
        --
        -- REPARE NO ::float8, que nao esta' aqui por acaso e custou duas tentativas.
        --
        -- Com a diferenca em numeric, que e' o que fct_leituras guarda, este teste
        -- acusou 12 linhas: HDF marcado na fonte e a regra dizendo que nao, todas com
        -- diferenca de exatamente 8.6. Trocar o < por <= "consertou" as 12 e criou 15
        -- do outro lado, o que ja' provava que nenhum limite decimal reproduzia o
        -- rotulo.
        --
        -- A causa: o AI4I calculou o rotulo em ponto flutuante binario, e ali o erro
        -- muda de direcao conforme o par de numeros.
        --
        --   309.4 - 300.8 = 8.599999999999966   abaixo de 8.6, e' HDF
        --   311.0 - 302.4 = 8.600000000000023   acima de 8.6, nao e' HDF
        --
        -- As duas contas dao 8.6 cravado em decimal exato, e mesmo assim uma e' HDF e a
        -- outra nao. Nenhum limiar decimal separa as duas, porque a diferenca entre
        -- elas nao existe em decimal: ela so' existe em binario.
        --
        -- A silver esta' certa em converter para numeric, e nao vai mudar: medicao e
        -- dinheiro pedem decimal exato, e trocar o tipo do warehouse inteiro para
        -- salvar uma comparacao seria deixar a cauda balancar o cachorro. O que muda e'
        -- o teste, que refaz a aritmetica da FONTE para conferir o rotulo DA FONTE.
        -- Registrado em docs/decisions.md.
        (
            (temperatura_processo_k::float8 - temperatura_ar_k::float8) < 8.6
            and rotacao_rpm < 1380
        )                                                      as regra_hdf,

        -- Potencia fora da faixa de trabalho, nos dois extremos.
        (potencia_w < 3500 or potencia_w > 9000)               as regra_pwf,

        -- Sobrecarga: desgaste vezes torque acima do limite do TIPO da peca. E' a unica
        -- regra do dataset em que uma coluna categorica muda um limite fisico.
        (
            desgaste_ferramenta_min * torque_nm >
            case tipo_produto
                when 'L' then 11000
                when 'M' then 12000
                when 'H' then 13000
            end
        )                                                      as regra_osf

    from base

)

select 'HDF' as modo, udi, tem_hdf as marcado_na_fonte, regra_hdf as regra_diz
from avaliado where tem_hdf <> regra_hdf

union all
select 'PWF', udi, tem_pwf, regra_pwf
from avaliado where tem_pwf <> regra_pwf

union all
select 'OSF', udi, tem_osf, regra_osf
from avaliado where tem_osf <> regra_osf
