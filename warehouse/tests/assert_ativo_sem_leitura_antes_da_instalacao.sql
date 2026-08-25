{{ config(severity='error', error_if='>5', warn_if='>0') }}

-- Maquina nao produz antes de ser instalada.
--
-- Sao 5 maquinas com data de instalacao posterior a primeira leitura delas, e isso e'
-- sujeira injetada de proposito pelo gerador. O limiar e' 5, no grain de MAQUINA e nao
-- de leitura: as 5 maquinas concentram 365 leituras anteriores a instalacao, e um
-- limiar de 365 seria fragil, porque muda com a distribuicao de carga sem o problema
-- ter mudado. Cinco maquinas com cadastro errado continuam sendo cinco.
--
-- Estas 365 leituras NAO sao descartadas do fato, e nao caem no ativo desconhecido: a
-- vigencia da primeira versao de cada ativo comeca em -infinity exatamente para elas
-- continuarem ligadas a maquina certa. O erro esta' no cadastro, nao na leitura, e
-- quem o acusa e' este teste. Descartar seria apagar 365 ciclos de producao reais para
-- esconder uma data errada.

select
    a.codigo_ativo,
    a.data_instalacao,
    min(f.instante)     as primeira_leitura,
    count(*)            as leituras_anteriores

from {{ ref('fct_leituras') }} f
join {{ ref('dim_ativo') }} a using (ativo_sk)

where a.data_instalacao is not null
  and f.instante < a.data_instalacao

group by a.codigo_ativo, a.data_instalacao
