"""Construye modelos/ilvari.glb: Vehl Iskaar (ilvari) sentado, con túnica, collar traductor,
cabeza esculpida (mandíbula, saco vocal y arcos superciliares con hueso propio), ojos negros
y manos de cuatro dedos. Esqueleto + pesos + texturas horneadas (modelos/tex/ilv_*).
Uso: blender --background --factory-startup --python construir_ilvari.py [-- previa]
Variables: CALIDAD (1 = final, 2 = rápido), PREVIA_DIR
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bl, sdf, mano_ilvari as M, cuerpo_ilvari as V

PROY = os.path.dirname(AQUI)
OUT = os.path.join(PROY, "modelos", "ilvari.glb")
TEX = os.path.join(PROY, "modelos", "tex")
Q = float(os.environ.get("CALIDAD", "1"))
PREVIA = "previa" in sys.argv
SAL_PREVIA = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))
T0 = time.time()


def log(*a):
    print("[ilv %5.1fs]" % (time.time() - T0), *a, flush=True)


bl.limpiar()
import bpy


def borrar(ob):
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)


def normales_de(v, q):
    tmp = bl.malla("tmp_n", v, q)
    n = bl.normales_np(tmp)
    borrar(tmp)
    return n


# ------------------------------------------------------------------ manos
S_mano, A = M.esculpir(flex=V.FLEX_REPOSO)
vl, ql = sdf.malla(S_mano, (-0.095, -0.09, -0.04), (0.05, 0.28, 0.032), 0.0006 * Q)
log("mano local", len(vl))
Wz = V.altura_muneca(vl[vl[:, 1] > -0.01]) + 0.003
W_R = V.a_mundo(np.zeros((1, 3)), -1, Wz)[0]
W_L = V.a_mundo(np.zeros((1, 3)), 1, Wz)[0]
log("muñeca", W_R)

# ------------------------------------------------------------------ esqueleto
huesos = V.huesos_cuerpo(W_R, W_L)
R_m = V.mano_transform(-1)
for lado, s in ((-1, "_R"), (1, "_L")):
    for hb in M.huesos(A, sufijo=s):
        hb = dict(hb)
        hb["cabeza"] = tuple(V.a_mundo(np.array([hb["cabeza"]]), lado, Wz)[0])
        hb["cola"] = tuple(V.a_mundo(np.array([hb["cola"]]), lado, Wz)[0])
        up = np.array(hb["arriba"], np.float32) @ R_m.T
        if lado > 0:
            up = up * np.array([-1, 1, 1], np.float32)
        hb["arriba"] = tuple(up)
        if hb["padre"] is None:
            hb["padre"] = "antebrazo" + s
        huesos.append(hb)
seg = {hb["nombre"]: (np.array(hb["cabeza"], np.float32), np.array(hb["cola"], np.float32)) for hb in huesos}
arm = bl.armadura("Ilvari", huesos)
log("huesos", len(huesos))
bajas = []
texturas = {}


def dist_seg(v):
    return lambda n: bl.dist_segmento(v, *seg[n])[0]


def procesar(nombre, v, q, caras, material, tam=1024, dist=0.004, color=None, ao=False, base=(0.5, 0.5, 0.5)):
    alta = bl.malla("alta_" + nombre, v, q)
    if color is not None:
        bl.color_vertices(alta, color)
    baja = bl.copia(alta, "m_" + nombre)
    bl.decimar(baja, int(caras / Q))
    for a in list(baja.data.color_attributes):
        baja.data.color_attributes.remove(a)
    bl.uv_auto(baja)
    tex = bl.hornear(alta, baja, TEX, "ilv_" + nombre, tam=int(tam / (2 if Q > 1 else 1)), distancia=dist, ao=ao, color=color is not None)
    texturas[nombre] = (baja, tex)
    bl.material_simple(baja, material, base)
    borrar(alta)
    bajas.append(baja)
    log(nombre, "alta", len(v), "baja", len(baja.data.polygons))
    return baja


# ---- piel de las manos (se hornea la derecha; la izquierda es su reflejo)
n_loc = normales_de(vl, ql)
col = M.colores(vl, n_loc, A, V.PIEL, V.VENA, V.PUNTA)
mano_R = procesar("mano_R", V.a_mundo(vl, -1, Wz), ql, 7000, "piel", dist=0.0025, color=col, ao=True)


def cand_mano(sufijo, lado):
    def fn(vb):
        p = vb.copy()
        if lado > 0:
            p = p * np.array([-1, 1, 1], np.float32)
        loc = (p - np.array([-V.MUNECA_XY[0], V.MUNECA_XY[1], Wz], np.float32)) @ R_m
        reg = S_mano.regiones(loc)
        return [M.candidatos(int(r), sufijo) for r in reg]
    return fn


def pesos_por_candidatos(ob, cands):
    bl.pesos(ob, {n: seg[n] for n in set(sum([list(c) for c in cands], []))}, cands)
    bl.emparentar(ob, arm)


pesos_por_candidatos(mano_R, cand_mano("_R", -1)(bl.verts_np(mano_R)))
mano_L = bl.copia(mano_R, "m_mano_L")
mano_L.parent = None
mano_L.vertex_groups.clear()
for m in list(mano_L.modifiers):
    mano_L.modifiers.remove(m)
vL = bl.verts_np(mano_L) * np.array([-1, 1, 1], np.float32)
bl.set_verts(mano_L, vL)
bl.normales_fuera(mano_L)
pesos_por_candidatos(mano_L, cand_mano("_L", 1)(vL))
bajas.append(mano_L)
log("manos")

# ------------------------------------------------------------------ cabeza y cuello
S_cab = V.cabeza()
v, q = sdf.malla(S_cab, (-0.11, V.H[1] - 0.15, 0.99), (0.11, 0.14, 1.55), 0.0011 * Q)
n = normales_de(v, q)
cab = procesar("cabeza", v, q, 12000, "piel_cara", tam=2048, dist=0.004, color=V.colores_cabeza(v, n), ao=True)
vb = bl.verts_np(cab)
nombres, W = V.pesos_cabeza(vb, dist_seg(vb))
bl.pesos_matriz(cab, nombres, W)
bl.emparentar(cab, arm)
log("cabeza")

# ---- ojos
v, q = sdf.malla(V.ojos(), (-0.07, V.H[1] - 0.13, V.H[2] - 0.03), (0.07, V.H[1] - 0.06, V.H[2] + 0.035), 0.0005 * Q)
ob = bl.malla("m_ojos", v, q)
bl.decimar(ob, int(1600 / Q))
bl.uv_auto(ob)
bl.material_simple(ob, "ojo", (0.01, 0.01, 0.012), rug=0.05)
bl.pesos_fijos(ob, "cabeza")
bl.emparentar(ob, arm)
bajas.append(ob)

# ---- collar traductor y su lente
S_col, pos_lente = V.collar()
C = (V.P_CUELLO + V.P_CRANEO) * 0.5
v, q = sdf.malla(S_col, C - 0.075, C + 0.075, 0.0005 * Q)
ob = bl.malla("m_collar", v, q)
bl.decimar(ob, int(2500 / Q))
bl.uv_auto(ob)
bl.material_simple(ob, "collar", (0.5, 0.5, 0.52), rug=0.3, metal=1.0)
bl.pesos_fijos(ob, "cuello")
bl.emparentar(ob, arm)
bajas.append(ob)
v, q = sdf.malla(V.lente(pos_lente), pos_lente - 0.006, pos_lente + 0.006, 0.0004)
ob = bl.malla("m_lente", v, q)
bl.material_simple(ob, "lente", (0.3, 0.8, 1.0), rug=0.1)
bl.pesos_fijos(ob, "cuello")
bl.emparentar(ob, arm)
bajas.append(ob)
log("ojos y collar")

# ------------------------------------------------------------------ túnica
S_t = V.tunica(W_R, W_L)
v, q = sdf.malla(S_t, (-0.42, -0.72, 0.0), (0.42, 0.3, 1.2), 0.003 * Q)
tun = procesar("tunica", v, q, 16000, "tunica", tam=2048, dist=0.012, color=V.colores_tunica(v))


def cand_ropa(vb):
    reg = S_t.regiones(vb)
    out = []
    for r, x in zip(reg, vb[:, 0]):
        s = "_R" if x < 0 else "_L"
        r = int(r)
        if r == V.R_TORSO_B:
            out.append(["raiz", "cadera", "columna"])
        elif r == V.R_TORSO_A:
            out.append(["columna", "pecho"])
        elif r == V.R_HOMBRO:
            out.append(["pecho", "clavicula" + s, "brazo" + s])
        elif r == V.R_BRAZO:
            out.append(["clavicula" + s, "brazo" + s, "antebrazo" + s])
        elif r == V.R_ANTEBRAZO:
            out.append(["brazo" + s, "antebrazo" + s])
        elif r == V.R_CUELLO_T:
            out.append(["pecho", "cuello"])
        else:
            out.append(["raiz"])
    return out


pesos_por_candidatos(tun, cand_ropa(bl.verts_np(tun)))
log("túnica")

# ------------------------------------------------------------------ exportar
bl.exportar(OUT, [arm] + bajas)
log("exportado", OUT)

if PREVIA:
    os.makedirs(SAL_PREVIA, exist_ok=True)
    mesa = bl.malla("mesa", np.array([[-0.75, -0.35, 0.795], [0.75, -0.35, 0.795], [0.75, -1.3, 0.795], [-0.75, -1.3, 0.795]]), np.array([[0, 1, 2, 3]]))
    bl.material_simple(mesa, "mesa", (0.25, 0.25, 0.26), rug=0.35, metal=0.7)
    # la previa usa las texturas horneadas (el glb ya está exportado sin ellas)
    texturas["mano_L"] = (mano_L, texturas["mano_R"][1])
    for nombre, (ob, tex) in texturas.items():
        bl.material_pbr(ob, "prev_" + nombre, color=tex.get("color"), normal=tex.get("normal"),
                        rug=0.45 if nombre != "tunica" else 0.85)
    bl.render_previa(os.path.join(SAL_PREVIA, "ilv_a.png"), objetivo=(0, -0.3, 1.05), dist=2.0, elev=12, azim=0, lente=45)
    bl.render_previa(os.path.join(SAL_PREVIA, "ilv_cara.png"), objetivo=tuple(V.H + np.array([0, -0.02, -0.02])), dist=0.55, elev=5, azim=0, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "ilv_perfil.png"), objetivo=tuple(V.H + np.array([0, 0.0, -0.04])), dist=0.65, elev=5, azim=75, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "ilv_manos.png"), objetivo=(0, -0.7, 0.82), dist=0.9, elev=40, azim=10, lente=45)
    log("previa")
