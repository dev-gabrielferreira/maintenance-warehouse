#!/usr/bin/env bash
#
# Constroi o historico SCD2 de dim_ativo.
#
# Por que este script existe. Um `dbt snapshot` grava o que enxerga na hora em que
# roda, e bronze.ativos e' estatico depois da carga: rodar o snapshot dez vezes
# produziria dez vezes a mesma versao. O historico esta' em outra tabela, o log de 31
# mudancas de cadastro. Este laco roda o snapshot uma vez por data de mudanca,
# mostrando ao dbt o parque como ele estava naquele dia, e o dbt faz o que ele sabe
# fazer: perceber o que mudou e abrir uma versao nova.
#
# A ordem crescente e' obrigatoria. A estrategia `timestamp` ignora, sem reclamar,
# uma linha cujo updated_at seja anterior ao ultimo ja' registrado. Rodar fora de
# ordem nao da' erro: da' historico errado.
#
# Roda depois de `uv run seed` e antes de `dbt build`.

set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

dbt_() { uv run --env-file .env dbt "$@" --project-dir warehouse --profiles-dir warehouse; }

echo "==> lendo as datas de corte"
# Sao as 31 datas de mudanca mais uma: o dia anterior a primeira delas, que grava a
# linha de base. Sem ela a maquina que muda na primeira data nasce ja' alterada.
# ISO ordena igual em ordem alfabetica e cronologica, entao o sort -u serve de rede
# de seguranca da ordem sem precisar entender data.
datas=$(dbt_ run-operation datas_de_mudanca | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -u)
total=$(echo "$datas" | wc -l | tr -d ' ')
echo "    $total datas, de $(echo "$datas" | head -1) a $(echo "$datas" | tail -1)"

echo "==> derrubando o snapshot para reconstruir do zero"
dbt_ run-operation derruba_historico_ativo | grep -E 'snap_ativo' || true

i=0
for data in $datas; do
    i=$((i + 1))
    printf '    [%2d/%2d] corte %s ... ' "$i" "$total" "$data"
    if ! saida=$(dbt_ snapshot --vars "{data_corte: $data}" 2>&1); then
        printf 'falhou\n'
        echo "$saida"
        exit 1
    fi
    printf 'ok\n'
done

# A contagem vem do banco, e nao da saida do dbt. O status que o dbt imprime na linha
# do snapshot e' o retorno do ultimo comando que ele mandou ao Postgres, e a partir da
# segunda rodada isso vira "INSERT 0 0" mesmo quando versao nova foi aberta. Numero
# que parece contagem e nao e' contagem e' pior que numero nenhum.
echo "==> conferindo o historico no banco"
dbt_ run-operation confere_historico_ativo | grep -E 'versoes|maquinas' || true

echo "==> pronto. O teste assert_historico_ativo_completo, no dbt build, quebra se"
echo "    este laco tiver sido pulado."
