-- dim_tempo: um dia por linha, de 2024-01-01 a 2026-12-31.
--
-- O intervalo cobre o que os fatos precisam com folga: as leituras vao de 2024-01-01
-- a 2025-12-31 e a ultima conclusao de OS e' 2026-02-12. Dimensao de data se gera
-- com folga de proposito, porque estender depois obriga a recarregar quem aponta
-- para ela.
--
-- Tres coisas neste modelo merecem atencao.
--
-- 1. A chave e' YYYYMMDD como inteiro, e nao um row_number como nas outras
--    dimensoes. E' a excecao classica do Kimball: chave de data legivel deixa
--    `where tempo_sk between 20240101 and 20241231` funcionar sem join, e o
--    resultado continua ordenavel. A coerencia entre a chave e a data e' testada,
--    para ninguem confiar num numero que ninguem confere.
--
-- 2. Nome de mes e de dia saem de `case`, e nao de `to_char(data, 'TMMonth')`. O
--    to_char localizado devolve o nome no idioma do lc_time do servidor: aqui sairia
--    uma coisa e na maquina de quem clonar sairia outra, e a gold passaria a
--    depender de configuracao de container. E' o mesmo motivo pelo qual a Semana 1
--    recusou a imagem alpine.
--
-- 3. A linha -1 existe para as 36 preventivas que nunca foram concluidas. Elas
--    precisam apontar para alguma linha da dimensao, porque FK nula quebra o join e
--    some da contagem sem avisar. As colunas de texto dizem 'nao se aplica' para
--    nenhum relatorio sair em branco, e `data` fica nula porque data ali nao existe.
--    Pelo mesmo motivo, `data`, `ano` e `dia_util` nao tem not_null no .yml.

with dias as (

    select
        generate_series(
            date '2024-01-01',
            date '2026-12-31',
            interval '1 day'
        )::date as data

),

atributos as (

    select
        to_char(data, 'YYYYMMDD')::int          as tempo_sk,
        data,

        extract(year from data)::int            as ano,
        extract(month from data)::int           as mes,
        extract(quarter from data)::int         as trimestre,
        extract(day from data)::int             as dia_do_mes,
        to_char(data, 'YYYY-MM')                as ano_mes,

        case extract(month from data)
            when 1 then 'janeiro'   when 2 then 'fevereiro' when 3 then 'marco'
            when 4 then 'abril'     when 5 then 'maio'      when 6 then 'junho'
            when 7 then 'julho'     when 8 then 'agosto'    when 9 then 'setembro'
            when 10 then 'outubro'  when 11 then 'novembro' when 12 then 'dezembro'
        end                                     as nome_mes,

        -- extract(dow) devolve 0 para domingo.
        extract(dow from data)::int             as dia_semana,
        case extract(dow from data)
            when 0 then 'domingo' when 1 then 'segunda' when 2 then 'terca'
            when 3 then 'quarta'  when 4 then 'quinta'  when 5 then 'sexta'
            when 6 then 'sabado'
        end                                     as nome_dia,

        -- Domingo nao tem producao, e essa e' exatamente a regra que o gerador usou
        -- para distribuir as 10 mil leituras. Se as duas divergissem, um dia sem
        -- leitura nenhuma apareceria como dia util e ninguem entenderia o buraco.
        extract(dow from data) <> 0             as dia_util,

        -- Hemisferio sul: a planta e' em Sorocaba. Datas de virada pelo calendario
        -- astronomico, aproximadas para o dia fixo de cada ano.
        case
            when to_char(data, 'MMDD')::int >= 1221
              or to_char(data, 'MMDD')::int <= 320  then 'verao'
            when to_char(data, 'MMDD')::int <= 620  then 'outono'
            when to_char(data, 'MMDD')::int <= 922  then 'inverno'
            else                                         'primavera'
        end                                     as estacao

    from dias

),

desconhecido as (

    select
        -1                  as tempo_sk,
        null::date          as data,
        null::int           as ano,
        null::int           as mes,
        null::int           as trimestre,
        null::int           as dia_do_mes,
        'nao se aplica'     as ano_mes,
        'nao se aplica'     as nome_mes,
        null::int           as dia_semana,
        'nao se aplica'     as nome_dia,
        null::boolean       as dia_util,
        'nao se aplica'     as estacao

)

select * from desconhecido
union all
select * from atributos
order by tempo_sk
