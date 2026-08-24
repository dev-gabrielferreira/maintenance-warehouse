-- dim_turno: tres linhas, os turnos de 8 horas que o gerador usou para distribuir as
-- leituras no tempo.
--
-- Por que ela existe em vez de o turno ser uma coluna de texto no fato: dim_tecnico
-- tambem tem turno. Com a dimensao propria, as duas passam a falar do mesmo turno,
-- com a mesma chave, e isso e' o que a bus matrix chama de dimensao conformada. Com
-- turno solto como texto em cada tabela, "manha" no fato e "manha" no tecnico sao
-- duas strings que ninguem garante serem a mesma coisa.
--
-- Ela tambem resolve o que a dim_tempo nao consegue: dimensao de grain diario nao
-- guarda um atributo que muda tres vezes dentro da propria linha.
--
-- Nao tem membro desconhecido, e isso e' escolha com fundamento: stg_leitura_contexto
-- tem not_null e accepted_values em turno, entao os tres valores estao garantidos por
-- teste antes de chegar aqui. Membro -1 numa dimensao que nao pode receber
-- desconhecido seria linha morta.
--
-- Os valores estao escritos aqui em vez de virem de select sobre a staging porque
-- turno e' regra da operacao, nao dado observado: sao tres, comecam em hora fixa, e
-- nao mudam porque um arquivo mudou.

with turnos as (

    select * from (
        values
            (1, 'manha',  6, 14),
            (2, 'tarde', 14, 22),
            (3, 'noite', 22,  6)
    ) as t (turno_sk, nome_turno, hora_inicio, hora_fim)

)

select
    turno_sk,
    nome_turno,
    hora_inicio,
    hora_fim,

    -- O turno da noite comeca num dia e termina no outro. Quem for cruzar turno com
    -- data precisa saber disso, e um booleano na dimensao resolve melhor do que cada
    -- consulta redescobrir a regra.
    hora_fim < hora_inicio as vira_o_dia

from turnos
