"""Fronteira do projeto: aqui o Python baixa, gera e carrega o dado bruto na bronze.

Da bronze em diante quem transforma e' o dbt, em SQL versionado dentro do warehouse.
Nada neste pacote deve limpar, agregar ou derivar coluna: essa e' a tese do projeto,
e um transform.py aqui dentro a invalidaria.
"""
