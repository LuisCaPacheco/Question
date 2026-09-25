"""Valida y explora el árbol de diálogo de un caso (mismas reglas que GameManager.gd).
Uso: python simular_arbol.py ../data/caso_vehl.json
"""
import json, sys
from collections import deque, Counter

ruta = sys.argv[1] if len(sys.argv) > 1 else "../data/caso_vehl.json"
C = json.load(open(ruta, encoding="utf-8"))
A = C["arbol"]
N = A["nodos"]
FIN = A["finales"]
TURNOS = C.get("turnos", 16)
errores = []

# ---------------------------------------------------------------- referencias
def refs_opcion(o):
    r = []
    if "ir" in o: r.append(("n", o["ir"]))
    for c in o.get("ir_si", []): r.append(("n", c["ir"]))
    if "fin" in o: r.append(("f", o["fin"]))
    return r

for nid, n in N.items():
    for o in n.get("opciones", []):
        for t, x in refs_opcion(o):
            if t == "n" and x not in N: errores.append(f"{nid}: nodo inexistente {x}")
            if t == "f" and x not in FIN: errores.append(f"{nid}: final inexistente {x}")
        if "prueba" in o and o["prueba"] not in [e["id"] for e in C["evidencias"]]:
            errores.append(f"{nid}: prueba desconocida {o['prueba']}")
        if "testigo" in o and o["testigo"] not in [t["id"] for t in C["testigos"]]:
            errores.append(f"{nid}: testigo desconocido {o['testigo']}")
        if len(o["texto"]) > 120: errores.append(f"{nid}: texto largo ({len(o['texto'])}) {o['texto'][:40]}")
    for k, r in n.get("grabadora", {}).items():
        if "ir" in r and r["ir"] not in N: errores.append(f"{nid}: grabadora->{r['ir']}")
        if "fin" in r and r["fin"] not in FIN: errores.append(f"{nid}: grabadora fin {r['fin']}")
    if "fin" in n and n["fin"] not in FIN: errores.append(f"{nid}: fin {n['fin']}")
    if not n.get("opciones") and "fin" not in n: errores.append(f"{nid}: sin opciones ni fin")

# ---------------------------------------------------------------- reglas
def lista(x):
    return x if isinstance(x, list) else ([x] if x else [])

def cumple(si, st):
    if not si: return True
    fl = st["flags"]
    if "flag" in si and si["flag"] not in fl: return False
    for f in si.get("flags", []):
        if f not in fl: return False
    if "no_flag" in si and si["no_flag"] in fl: return False
    if "grabadora" in si and si["grabadora"] != st["grab"]: return False
    if "confianza_min" in si and st["conf"] < si["confianza_min"]: return False
    if "tension_max" in si and st["ten"] > si["tension_max"]: return False
    if "prueba_usada" in si and si["prueba_usada"] not in st["pru"]: return False
    return True

def aplicar(ef, st):
    if not ef: return
    st["conf"] = max(0, min(100, st["conf"] + ef.get("confianza", 0)))
    st["ten"] = max(0, min(100, st["ten"] + ef.get("tension", 0)))
    st["ver"] = max(0, min(100, st["ver"] + ef.get("verdad", 0)))
    for f in lista(ef.get("flag")): st["flags"] = st["flags"] | {f}
    for f in lista(ef.get("quitar_flag")): st["flags"] = st["flags"] - {f}

def entrar(nid, st):
    st["nodo"] = nid
    n = N[nid]
    aplicar(n.get("al_entrar"), st)
    if n.get("revela") and not st["grab"]:
        st["flags"] = st["flags"] | {"hablo_off"}
    if "fin" in n: return n["fin"]
    return None

def comprobar(st, fin):
    if fin: return fin
    if st["ten"] >= 100:
        tm = A.get("tension_max", {})
        for f, e in tm.get("con_flag", {}).items():
            if f in st["flags"]: return e
        return tm.get("fin", "d_abogado")
    if st["tur"] <= 0: return "d_amanecer"
    return None

def visibles(st):
    n = N[st["nodo"]]
    out = []
    for o in n.get("opciones", []):
        if not cumple(o.get("si"), st): continue
        if "prueba" in o and o["prueba"] in st["pru"]: continue
        if "testigo" in o and o["testigo"] in st["tes"]: continue
        out.append(o)
    return out

def elegir(o, st):
    st["tur"] -= 1
    if "grabadora" in o: st["grab"] = o["grabadora"]
    aplicar(o.get("ef"), st)
    if "prueba" in o: st["pru"] = st["pru"] | {o["prueba"]}
    if "testigo" in o: st["tes"] = st["tes"] | {o["testigo"]}
    for c in o.get("ir_si", []):
        if cumple(c["si"], st):
            return comprobar(st, entrar(c["ir"], st))
    if "fin" in o: return o["fin"]
    return comprobar(st, entrar(o["ir"], st))

def grabadora(st):
    st["tur"] -= 1
    nuevo = not st["grab"]
    st["grab"] = nuevo
    n = N[st["nodo"]]
    r = n.get("grabadora", {}).get("on" if nuevo else "off")
    if r and "si_no_flag" in r and r["si_no_flag"] in st["flags"]: r = None
    if r:
        aplicar(r.get("ef"), st)
        if "fin" in r: return r["fin"]
        if "ir" in r: return comprobar(st, entrar(r["ir"], st))
        return comprobar(st, None)
    d = A["grabadora_defecto"]
    orden = ["off_confia", "off_sabe", "off_sospecha"] if not nuevo else ["on_traicion", "on_formal"]
    for k in orden:
        r = d[k]
        if cumple(r.get("si"), st):
            aplicar(r.get("ef"), st)
            if "fin" in r: return r["fin"]
            return comprobar(st, None)
    return comprobar(st, None)

print("ERRORES:", len(errores))
for e in errores: print("  ", e)

# alcance estático (ignora condiciones): nodos a los que ninguna flecha llega
enlazados = {A["inicio"]}
for n in N.values():
    for o in n.get("opciones", []):
        enlazados |= {x for t, x in refs_opcion(o) if t == "n"}
    enlazados |= {r["ir"] for r in n.get("grabadora", {}).values() if "ir" in r}
print("huérfanos (sin flecha de entrada):", sorted(set(N) - enlazados), flush=True)

# ---------------------------------------------------------------- exploración
# Confianza y tensión se agrupan de 5 en 5 para deduplicar (si no, el espacio
# explota); MAX_ESTADOS corta la búsqueda si aun así crece demasiado.
MAX_ESTADOS = int(sys.argv[2]) if len(sys.argv) > 2 else 400_000

def clave(st):
    return (st["nodo"], st["ten"] // 5, st["conf"] // 5, st["flags"], st["grab"], st["pru"], st["tes"])

ini = dict(nodo=None, ten=C.get("tension_inicial", 18), conf=C.get("confianza_inicial", 15), ver=0,
           flags=frozenset(), grab=C.get("grabadora_inicial", True), pru=frozenset(), tes=frozenset(), tur=TURNOS)
entrar(A["inicio"], ini)
cola = deque([(ini, [])])
visto = {clave(ini): TURNOS}
finales = Counter()
mejor = {}
nodos_vistos = set()
estados = 0
while cola and estados < MAX_ESTADOS:
    st, camino = cola.popleft()
    estados += 1
    nodos_vistos.add(st["nodo"])
    acciones = [("op", o) for o in visibles(st)] + [("grab", None)]
    for tipo, o in acciones:
        s2 = dict(st)
        fin = elegir(o, s2) if tipo == "op" else grabadora(s2)
        paso = (st["nodo"], o["texto"][:48] if o else ("[GRABADORA " + ("ON" if s2["grab"] else "OFF") + "]"))
        if fin:
            finales[fin] += 1
            if fin not in mejor or len(camino) + 1 < len(mejor[fin]):
                mejor[fin] = camino + [paso]
            continue
        k = clave(s2)
        if k in visto and visto[k] >= s2["tur"]:
            continue
        visto[k] = s2["tur"]
        cola.append((s2, camino + [paso]))

if cola: print(f"(búsqueda cortada en {MAX_ESTADOS} estados; quedan {len(cola)} en cola)")
print("nodos:", len(N), " alcanzados:", len(nodos_vistos), " estados explorados:", estados)
print("no alcanzados:", sorted(set(N) - nodos_vistos))
opciones = sum(len(n.get("opciones", [])) for n in N.values())
print("opciones totales:", opciones)
print("FINALES (caminos que llegan):")
for f, c in finales.most_common():
    print(f"  {f:14s} {c:8d}  mínimo {len(mejor[f])} turnos")
for f in ("v_padre", "v_coro"):
    if f in mejor:
        print(f"\nCAMINO MÁS CORTO A {f}:")
        for nodo, txt in mejor[f]:
            print(f"   {nodo:22s} -> {txt}")
    else:
        print(f"\n¡{f} NO ES ALCANZABLE!")
