"""Ponto de entrada do `uv run seed`.

Amarra as etapas que levam o dado ate' a bronze, nesta ordem: baixar a fonte
publica, gerar o mundo sintetico em volta dela, carregar os dois no Postgres.
O loader entra no bloco 1.6 do plano.
"""

import argparse

from seed import download, generator


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="seed",
        description="Baixa o AI4I, gera o mundo sintetico e carrega a bronze.",
    )
    parser.add_argument(
        "--sem-sujeira",
        action="store_true",
        help=(
            "gera o mundo sem a sujeira injetada. Serve para provar que os testes "
            "da silver acusam a sujeira, e nao um erro do modelo."
        ),
    )
    args = parser.parse_args()

    download.main()
    print()
    generator.main(sem_sujeira=args.sem_sujeira)

    print("\nfalta implementar:")
    print("  1.6 loader da bronze")
    return 0
