"""Roda os cenarios do simulador e compara com a referencia gravada.

Uso (na raiz do repositorio):
  py ferramentas/sim/testar.py                   compara todos os cenarios
  py ferramentas/sim/testar.py orbita_velocity   so um cenario
  py ferramentas/sim/testar.py --gravar          regrava a referencia
Precisa de Python 3 com lupa (pip install lupa).
"""
import difflib
import glob
import os
import sys

import lupa

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
REF = os.path.join(AQUI, "referencia")
CEN = os.path.join(AQUI, "cenarios")


def ler(p):
    with open(p, encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def arquivos_do_repo():
    caminhos = glob.glob(os.path.join(RAIZ, "*.lua")) + glob.glob(os.path.join(RAIZ, "*.txt"))
    caminhos += glob.glob(os.path.join(RAIZ, "lib", "**", "*.lua"), recursive=True)
    out = {}
    for p in caminhos:
        out[os.path.relpath(p, RAIZ).replace(os.sep, "/")] = ler(p)
    return out


def rodar(nome):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    A = L.execute(ler(os.path.join(AQUI, "ambiente.lua")))
    criar = L.execute(ler(os.path.join(AQUI, "mundo.lua")))
    rodar_lua = L.execute(ler(os.path.join(AQUI, "rodar.lua")))
    cen = L.execute(ler(os.path.join(CEN, nome + ".lua")))
    saida = rodar_lua(A, criar, cen, L.table_from(arquivos_do_repo()))
    return saida, bool(cen["semReferencia"])


def main():
    gravar = "--gravar" in sys.argv
    nomes = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not nomes:
        nomes = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(CEN, "*.lua")))
    falhas = 0
    for nome in nomes:
        saida, sem_ref = rodar(nome)
        quebrou = "SCRIPT ERRO" in saida or "SIM ERRO" in saida or "VERIFICACAO FALHOU" in saida
        if sem_ref:
            print(("FALHOU    " if quebrou else "ok        ") + nome)
            if quebrou:
                falhas += 1
                print("\n".join("    " + l for l in saida.splitlines() if "ERRO" in l or "FALHOU" in l))
            continue
        ref = os.path.join(REF, nome + ".txt")
        if gravar:
            os.makedirs(REF, exist_ok=True)
            with open(ref, "w", encoding="utf-8", newline="\n") as f:
                f.write(saida)
            print("gravado   " + nome + ("  (ATENCAO: tem ERRO no rastro)" if quebrou else ""))
            continue
        if not os.path.exists(ref):
            print("SEM REF   " + nome)
            falhas += 1
            continue
        esperado = ler(ref)
        if esperado == saida:
            print("ok        " + nome)
        else:
            falhas += 1
            print("DIFERENTE " + nome)
            diff = difflib.unified_diff(esperado.splitlines(), saida.splitlines(), "referencia", "atual", lineterm="", n=2)
            for linha in list(diff)[:80]:
                print("    " + linha)
    sys.exit(1 if falhas else 0)


if __name__ == "__main__":
    main()
