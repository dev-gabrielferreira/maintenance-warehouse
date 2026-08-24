"""Ponto de entrada do `uv run seed`.

Amarra as tres etapas que levam o dado ate' a bronze, nesta ordem: baixar a fonte
publica, gerar o mundo sintetico em volta dela, carregar os dois no Postgres.
Generator e loader entram nos blocos 1.5 e 1.6 do plano.
"""

from seed import download


def main() -> int:
    download.main()

    print("\nfalta implementar:")
    print("  1.5 generator do mundo sintetico")
    print("  1.6 loader da bronze")
    return 0
