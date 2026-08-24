# maintenance-warehouse — contrato de trabalho com o Claude

Este arquivo orienta como o Claude Code deve trabalhar neste repositório. Leia antes de qualquer tarefa.

## Contexto

Projeto P2 da trilha de portfólio de Engenharia de Dados do Gabriel (o P1, energy-load-etl, está em produção em energia.gabrielfdev.com). Warehouse dimensional de manutenção industrial: leituras do dataset AI4I 2020 (UCI) + mundo sintético seedado (ativos, calendário, ordens de serviço) carregados em PostgreSQL, transformados com dbt em medalhão bronze/silver/gold, com star schema, SCD2 via snapshots, testes e docs.

O plano completo está em `docs/PLANO.md`. Siga a ordem das semanas de lá. Não pule etapas nem antecipe trabalho de semanas futuras.

## O objetivo real deste projeto

Projeto de PORTFÓLIO e de APRENDIZADO. O Gabriel precisa defender cada decisão em entrevista. Código que funciona mas que ele não entende é fracasso. Portanto:

1. **Explique antes de implementar.** Antes de cada bloco, o que vai fazer e por quê; depois, as duas ou três linhas que merecem atenção.
2. **Passos pequenos.** Um modelo dbt ou um módulo por vez. Espere o Gabriel rodar e confirmar antes de seguir.
3. **Pergunte quando houver escolha real.** Dois caminhos defensáveis = apresentar prós e contras e deixar o Gabriel decidir.
4. **Checkpoints.** Ao fechar cada semana, faça as perguntas de checkpoint do `docs/PLANO.md` e espere respostas em texto. Resposta errada ou vaga = explicar de novo por outro ângulo antes de avançar.
5. **Exercícios de reescrita.** Quando o plano mandar, crie arquivo paralelo para o Gabriel refazer do zero sem olhar o original, depois compare com ele.
6. **Commits são dele.** Nunca commite automaticamente. Sugira a mensagem e deixe o Gabriel rodar o git.

## Regras técnicas

- A fronteira do projeto: Python (seed/generator.py, seed/loader.py) termina na camada bronze. Da bronze em diante, TODA transformação é modelo dbt. Nada de pandas transformando dado depois da carga.
- Python gerenciado com uv. PostgreSQL via docker-compose.
- dbt: verificar na semana 1 se o Fusion suporta Postgres de forma estável; caso contrário, dbt Core + dbt-postgres. Registrar a verificação em docs/decisions.md.
- O gerador sintético usa semente fixa (reprodutível) e injeta sujeira controlada de propósito. Os testes dbt DEVEM pegar essa sujeira: teste que nunca falha não demonstra nada.
- SCD2 de dim_ativo via dbt snapshots. Fatos fazem join com a versão vigente na data do evento, nunca pelo código natural sozinho.
- Credenciais só via variáveis de ambiente / profiles fora do repo. `.env.example` sempre atualizado.
- `data/` e artefatos de build não são commitados.
- Toda regra de negócio nova vira teste (genérico ou singular) no projeto dbt.

## Estilo de comunicação e documentação

- Conversa em português brasileiro, direto, sem jargão desnecessário.
- README e docs: sem travessão (—), escrever como pessoa, concreto, sem palavras infladas. README principal em inglês com versão em português linkada.
- docs/decisions.md registra cada decisão com alternativa rejeitada e porquê.

## O que NÃO fazer

- Não gerar o projeto dbt inteiro de uma vez "para adiantar".
- Não adicionar dependência sem justificar e perguntar.
- Não trazer orquestrador (Airflow é escopo do P3) nem cloud (idem).
- Não deixar o gerador sintético virar projeto paralelo: ele é meio, não fim (timebox do plano).
- Não commitar profiles.yml com credencial.
