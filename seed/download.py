"""Baixa o AI4I 2020 do UCI e deixa o CSV pronto em data/raw/.

Nao le, nao valida e nao transforma o conteudo: isso e' trabalho do loader e,
depois dele, do dbt. Aqui so' se resolve o problema de "o arquivo certo esta' no
disco, inteiro, e sem baixar duas vezes".
"""

import hashlib
import os
import shutil
import zipfile
from pathlib import Path

import requests

URL = (
    "https://archive.ics.uci.edu/static/public/601/"
    "ai4i+2020+predictive+maintenance+dataset.zip"
)

# Checksum do zip publicado pelo UCI, conferido em 2026-08-24. Ele nao esta' aqui
# para pegar download corrompido (o HTTPS ja' faz isso): esta' para pegar o dia em
# que o UCI republicar o dataset com outro conteudo. Fonte que muda em silencio e'
# como o warehouse fica errado sem ninguem notar. Se este valor deixar de bater, a
# carga para e alguem vai olhar, que e' exatamente o que se quer.
SHA256_ZIP = "f601f14294bcf190f9d720676b7f0aea46a26cde9ab8ebc7b4f8174d9d26b252"

NOME_CSV = "ai4i2020.csv"

RAIZ = Path(__file__).resolve().parent.parent
DIR_RAW = RAIZ / "data" / "raw"


def _sha256(caminho: Path) -> str:
    """Le em blocos porque um dia a fonte pode nao caber na memoria."""
    h = hashlib.sha256()
    with caminho.open("rb") as f:
        for bloco in iter(lambda: f.read(1024 * 1024), b""):
            h.update(bloco)
    return h.hexdigest()


def _baixar_zip(destino: Path) -> None:
    """Baixa para um .parte e so' entao renomeia.

    Download interrompido no meio deixa arquivo truncado. Se ele ficasse com o nome
    final, a execucao seguinte veria o arquivo, acharia que ja' tem tudo e leria
    lixo. O temporario fica na mesma pasta do destino porque rename entre sistemas
    de arquivos diferentes nao e' atomico.
    """
    parcial = destino.with_suffix(destino.suffix + ".parte")
    with requests.get(URL, stream=True, timeout=120) as r:
        r.raise_for_status()
        with parcial.open("wb") as f:
            shutil.copyfileobj(r.raw, f)
    os.replace(parcial, destino)


def garantir_zip() -> Path:
    """Devolve o caminho do zip integro, baixando so' se precisar."""
    DIR_RAW.mkdir(parents=True, exist_ok=True)
    destino = DIR_RAW / "ai4i2020.zip"

    if destino.exists() and _sha256(destino) == SHA256_ZIP:
        print(f"zip ja' esta' em cache e integro: {destino.relative_to(RAIZ)}")
        return destino

    print(f"baixando {URL}")
    _baixar_zip(destino)

    obtido = _sha256(destino)
    if obtido != SHA256_ZIP:
        raise RuntimeError(
            "checksum do AI4I nao confere. O UCI pode ter republicado o dataset.\n"
            f"  esperado: {SHA256_ZIP}\n"
            f"  obtido:   {obtido}\n"
            "Confira o que mudou na fonte antes de atualizar a constante SHA256_ZIP."
        )
    print(f"baixado e conferido: {destino.relative_to(RAIZ)}")
    return destino


def garantir_csv() -> Path:
    """Extrai o CSV de dentro do zip. Idempotente."""
    caminho_zip = garantir_zip()
    destino = DIR_RAW / NOME_CSV

    if destino.exists():
        print(f"csv ja' extraido: {destino.relative_to(RAIZ)}")
        return destino

    with zipfile.ZipFile(caminho_zip) as z:
        nomes = [n for n in z.namelist() if n.endswith(".csv")]
        if nomes != [NOME_CSV]:
            raise RuntimeError(
                f"esperava um unico {NOME_CSV} dentro do zip, achei: {nomes}"
            )
        # Extrai para .parte pelo mesmo motivo do download: zip corrompido nao pode
        # deixar meio CSV com o nome definitivo.
        parcial = destino.with_suffix(".parte")
        with z.open(NOME_CSV) as origem, parcial.open("wb") as f:
            shutil.copyfileobj(origem, f)
        os.replace(parcial, destino)

    print(f"csv extraido: {destino.relative_to(RAIZ)}")
    return destino


def main() -> int:
    garantir_csv()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
