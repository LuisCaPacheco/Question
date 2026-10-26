"""Construye modelos/kthar.glb: Vex'ahl (kthar) sentado, con el mono del penal, cabeza con
crestas, ojos rasgados, pinzas y dientes de aguja, y manos de cuatro dedos con garras.
Usa el mismo esqueleto que el ilvari (más pinza_R/L y placa), así que lo anima Ilvari.gd.
Esqueleto + pesos + texturas horneadas (modelos/tex/kth_*).
Uso: blender --background --factory-startup --python construir_kthar.py [-- previa]
Variables: CALIDAD (1 = final, 2 = rápido), PREVIA_DIR
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bl, sdf, mano_kthar as M, cuerpo_kthar as K

PROY = os.path.dirname(AQUI)
OUT = os.path.join(PROY, "modelos", "kthar.glb")
TEX = os.path.join(PROY, "modelos", "tex")
Q = float(os.environ.get("CALIDAD", "1"))
PREVIA = "previa" in sys.argv
SAL_PREVIA = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))
T0 = time.time()


def log(*a):
    print("[kth %5.1fs]" % (time.time() - T0), *a, flush=True)


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
S_mano, A = M.esculpir(flex=K.FLEX_REPOSO)
vl, ql = sdf.malla(S_mano, (-0.095, -0.09, -0.04), (0.05, 0.3, 0.036), 0.0006 * Q)
log("mano local", len(vl))
Wz = K.altura_muneca(vl[vl[:, 1] > -0.01]) + 0.003
W_R = K.a_mundo(np.zeros((1, 3)), -1, Wz)[0]
W_L = K.a_mundo(np.zeros((1, 3)), 1, Wz)[0]
log("muñeca", W_R)

# ------------------------------------------------------------------ mono (antes que el esqueleto: la placa sale de él)
S_m = K.mono(W_R, W_L)
placa = K.placa_pos(S_m)
log("placa", placa)

# ------------------------------------------------------------------ esqueleto
huesos = K.huesos_cuerpo(W_R, W_L, placa)
R_m = K.mano_transform(-1)
for lado, s in ((-1, "_R"), (1, "_L")):
    for hb in M.huesos(A, sufijo=s):
        hb = dict(hb)
        hb["cabeza"] = tuple(K.a_mundo(np.array([hb["cabeza"]]), lado, Wz)[0])
        hb["cola"] = tuple(K.a_mundo(np.array([hb["cola"]]), lado, Wz)[0])
        up = np.array(hb["arriba"], np.float32) @ R_m.T
        if lado > 0:
            up = up * np.array([-1, 1, 1], np.float32)
        hb["arriba"] = tuple(up)
        if hb["padre"] is None:
            hb["padre"] = "antebrazo" + s
        huesos.append(hb)
seg = {hb["nombre"]: (np.array(hb["cabeza"], np.float32), np.array(hb["cola"], np.float32)) for hb in huesos}
arm = bl.armadura("Kthar", huesos)
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
    tex = bl.hornear(alta, baja, TEX, "kth_" + nombre, tam=int(tam / (2 if Q > 1 else 1)), distancia=dist, ao=ao, color=color is not None)
    texturas[nombre] = (baja, tex)
    bl.material_simple(baja, material, base)
    borrar(alta)
    bajas.append(baja)
    log(nombre, "alta", len(v), "baja", len(baja.data.polygons))
    return baja


# ---- manos (se hornea la derecha; la izquierda es su reflejo)
n_loc = normales_de(vl, ql)
col = M.colores(vl, n_loc, A, K.PIEL, K.MANCHA, (0.05, 0.07, 0.05), K.QUITINA)
mano_R = procesar("mano_R", K.a_mundo(vl, -1, Wz), ql, 7500, "piel", dist=0.0025, color=col, ao=True)


def cand_mano(sufijo, lado):
    def fn(vb):
        p = vb.copy()
        if lado > 0:
            p = p * np.array([-1, 1, 1], np.float32)
        loc = (p - np.array([-K.MUNECA_XY[0], K.MUNECA_XY[1], Wz], np.float32)) @ R_m
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
S_cab = K.cabeza()
v, q = sdf.malla(S_cab, (-0.115, K.H[1] - 0.15, 0.99), (0.115, K.H[1] + 0.25, 1.56), 0.0011 * Q)
n = normales_de(v, q)
cab = procesar("cabeza", v, q, 14000, "piel_cara", tam=2048, dist=0.004, color=K.colores_cabeza(v, n), ao=True)
vb = bl.verts_np(cab)
nombres, W = K.pesos_cabeza(vb, dist_seg(vb))
bl.pesos_matriz(cab, nombres, W)
bl.emparentar(cab, arm)
log("cabeza")

# ---- ojos
v, q = sdf.malla(K.ojos(), (-0.07, K.H[1] - 0.13, K.H[2] - 0.035), (0.07, K.H[1] - 0.05, K.H[2] + 0.04), 0.0005 * Q)
ob = bl.malla("m_ojos", v, q)
bl.decimar(ob, int(1600 / Q))
bl.uv_auto(ob)
bl.material_simple(ob, "ojo", (0.01, 0.01, 0.012), rug=0.05)
bl.pesos_fijos(ob, "cabeza")
bl.emparentar(ob, arm)
bajas.append(ob)

# ---- pinzas (cada una con su hueso)
S_p = K.pinzas()
v, q = sdf.malla(S_p, K.H + np.array([-0.075, -0.14, -0.155]), K.H + np.array([0.075, -0.045, -0.045]), 0.0004 * Q)
pz = procesar("pinzas", v, q, 3000, "quitina", tam=512, dist=0.002, color=K.colores_pinza(v))
vb = bl.verts_np(pz)
Wp = np.stack([(vb[:, 0] < 0).astype(np.float32), (vb[:, 0] >= 0).astype(np.float32)], axis=1)
bl.pesos_matriz(pz, ["pinza_R", "pinza_L"], Wp)
bl.emparentar(pz, arm)

# ---- dientes de aguja
sup, inf = K.dientes()
for nombre, S, hueso in (("dientes_sup", sup, "cabeza"), ("dientes_inf", inf, "mandibula")):
    v, q = sdf.malla(S, K.H + np.array([-0.03, -0.11, K.BOCA_Z - 0.02]), K.H + np.array([0.03, -0.08, K.BOCA_Z + 0.01]), 0.00025 * Q)
    ob = bl.malla("m_" + nombre, v, q)
    bl.decimar(ob, int(1500 / Q))
    bl.uv_auto(ob)
    bl.material_simple(ob, "diente", K.DIENTE, rug=0.3)
    bl.pesos_fijos(ob, hueso)
    bl.emparentar(ob, arm)
    bajas.append(ob)
log("ojos, pinzas y dientes")

# ------------------------------------------------------------------ mono
v, q = sdf.malla(S_m, (-0.42, -0.72, 0.0), (0.42, 0.3, 1.2), 0.003 * Q)
mono = procesar("mono", v, q, 16000, "ropa", tam=2048, dist=0.012, color=K.colores_mono(v))


def cand_ropa(vb):
    reg = S_m.regiones(vb)
    out = []
    for r, x in zip(reg, vb[:, 0]):
        s = "_R" if x < 0 else "_L"
        r = int(r)
        if r == K.R_TORSO_B:
            out.append(["raiz", "cadera", "columna"])
        elif r == K.R_TORSO_A:
            out.append(["columna", "pecho"])
        elif r == K.R_HOMBRO:
            out.append(["pecho", "clavicula" + s, "brazo" + s])
        elif r == K.R_BRAZO:
            out.append(["clavicula" + s, "brazo" + s, "antebrazo" + s])
        elif r == K.R_ANTEBRAZO:
            out.append(["brazo" + s, "antebrazo" + s])
        elif r == K.R_CUELLO_T:
            out.append(["pecho", "cuello"])
        else:
            out.append(["raiz"])
    return out


pesos_por_candidatos(mono, cand_ropa(bl.verts_np(mono)))
log("mono")

# ------------------------------------------------------------------ exportar
bl.exportar(OUT, [arm] + bajas)
log("exportado", OUT)

if PREVIA:
    os.makedirs(SAL_PREVIA, exist_ok=True)
    mesa = bl.malla("mesa", np.array([[-0.75, -0.35, 0.795], [0.75, -0.35, 0.795], [0.75, -1.3, 0.795], [-0.75, -1.3, 0.795]]), np.array([[0, 1, 2, 3]]))
    bl.material_simple(mesa, "mesa", (0.25, 0.25, 0.26), rug=0.35, metal=0.7)
    texturas["mano_L"] = (mano_L, texturas["mano_R"][1])
    for nombre, (ob, tex) in texturas.items():
        bl.material_pbr(ob, "prev_" + nombre, color=tex.get("color"), normal=tex.get("normal"),
                        rug=0.45 if nombre != "mono" else 0.85)
    bl.render_previa(os.path.join(SAL_PREVIA, "kth_a.png"), objetivo=(0, -0.3, 1.05), dist=2.0, elev=12, azim=0, lente=45)
    bl.render_previa(os.path.join(SAL_PREVIA, "kth_cara.png"), objetivo=tuple(K.H + np.array([0, -0.02, -0.03])), dist=0.6, elev=5, azim=0, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "kth_perfil.png"), objetivo=tuple(K.H + np.array([0, 0.03, -0.02])), dist=0.75, elev=8, azim=75, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "kth_manos.png"), objetivo=(0, -0.7, 0.82), dist=0.9, elev=40, azim=10, lente=45)
    log("previa")
