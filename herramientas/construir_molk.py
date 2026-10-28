"""Construye modelos/molk.glb: Gruul, el molk, sentado y encorvado; roca viva con grietas de
magma, mono del penal sin mangas, losa en la frente, ojos de brasa, colmillos y manos de tres
dedos. Mismo esqueleto que el ilvari, así que lo anima Ilvari.gd.
Esqueleto + pesos + texturas horneadas (modelos/tex/mlk_*): color, normal, AO y, en la piel,
la máscara de las grietas (<prefijo>_emi.png) que Ilvari.gd hace brillar.
Uso: blender --background --factory-startup --python construir_molk.py [-- previa]
Variables: CALIDAD (1 = final, 2 = rápido), PREVIA_DIR
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bl, sdf, mano_molk as M, cuerpo_molk as K

PROY = os.path.dirname(AQUI)
OUT = os.path.join(PROY, "modelos", "molk.glb")
TEX = os.path.join(PROY, "modelos", "tex")
Q = float(os.environ.get("CALIDAD", "1"))
PREVIA = "previa" in sys.argv
SAL_PREVIA = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))
T0 = time.time()


def log(*a):
    print("[mlk %5.1fs]" % (time.time() - T0), *a, flush=True)


bl.limpiar()
import bpy
F = K.ficha("gruul")


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
vl, ql = sdf.malla(S_mano, (-0.1, -0.11, -0.05), (0.075, 0.27, 0.05), 0.0008 * Q)
log("mano local", len(vl))
Wz = K.altura_muneca(vl[vl[:, 1] > -0.01]) + 0.003
W_R = K.a_mundo(np.zeros((1, 3)), -1, Wz)[0]
W_L = K.a_mundo(np.zeros((1, 3)), 1, Wz)[0]
log("muñeca", W_R)

# ------------------------------------------------------------------ mono (la placa sale de él)
S_m = K.mono()
placa = K.placa_pos(S_m)

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
arm = bl.armadura("Molk", huesos)
log("huesos", len(huesos))
bajas = []
texturas = {}


def dist_seg(v):
    return lambda n: bl.dist_segmento(v, *seg[n])[0]


def procesar(nombre, v, q, caras, material, tam=1024, dist=0.004, color=None, ao=False, base=(0.5, 0.5, 0.5), emi=None):
    """Como en construir_kthar.py; con emi (0..1 por vértice) hornea además la máscara de grietas."""
    alta = bl.malla("alta_" + nombre, v, q)
    if color is not None:
        bl.color_vertices(alta, color)
    if emi is not None:
        bl.color_vertices(alta, np.repeat(np.asarray(emi, np.float32)[:, None], 3, axis=1), "Emi")
    baja = bl.copia(alta, "m_" + nombre)
    bl.decimar(baja, int(caras / Q))
    for a in list(baja.data.color_attributes):
        baja.data.color_attributes.remove(a)
    bl.uv_auto(baja)
    t = int(tam / (2 if Q > 1 else 1))
    tex = bl.hornear(alta, baja, TEX, "mlk_" + nombre, tam=t, distancia=dist, ao=ao, color=color is not None)
    if emi is not None:
        tex["emi"] = bl.hornear_mascara(alta, baja, TEX, "mlk_" + nombre + "_emi", "Emi", tam=t, distancia=dist)
    texturas[nombre] = (baja, tex)
    bl.material_simple(baja, material, base)
    borrar(alta)
    bajas.append(baja)
    log(nombre, "alta", len(v), "baja", len(baja.data.polygons))
    return baja


def pesos_por_candidatos(ob, cands):
    bl.pesos(ob, {n: seg[n] for n in set(sum([list(c) for c in cands], []))}, cands)
    bl.emparentar(ob, arm)


# ---- manos (se hornea la derecha; la izquierda es su reflejo)
n_loc = normales_de(vl, ql)
col = M.colores(vl, n_loc, A, F["PIEL"], F["MANCHA"], F["suciedad"])
mano_R = procesar("mano_R", K.a_mundo(vl, -1, Wz), ql, 9000, "piel", dist=0.003, color=col, ao=True, emi=M.emision(vl))


def cand_mano(sufijo, lado):
    def fn(vb):
        p = vb.copy()
        if lado > 0:
            p = p * np.array([-1, 1, 1], np.float32)
        loc = (p - np.array([-K.MUNECA_XY[0], K.MUNECA_XY[1], Wz], np.float32)) @ R_m
        reg = S_mano.regiones(loc)
        return [M.candidatos(int(r), sufijo) for r in reg]
    return fn


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

# ------------------------------------------------------------------ cabeza
H = K.H
S_cab = K.cabeza()
v, q = sdf.malla(S_cab, (-0.15, H[1] - 0.2, 1.08), (0.15, H[1] + 0.15, H[2] + 0.16), 0.0012 * Q)
n = normales_de(v, q)
cab = procesar("cabeza", v, q, 14000, "piel_cara", tam=2048, dist=0.005, color=K.colores_cabeza(F, v, n), ao=True, emi=K.emision_cabeza(v))
vb = bl.verts_np(cab)
nombres, W = K.pesos_cabeza(vb, dist_seg(vb))
bl.pesos_matriz(cab, nombres, W)
bl.emparentar(cab, arm)
log("cabeza")

# ---- ojos de brasa (UV frontal para Ilvari.SHADER_OJO_UV)
v, q = sdf.malla(K.ojos(), (-0.07, H[1] - 0.12, H[2] - 0.02), (0.07, H[1] - 0.07, H[2] + 0.025), 0.0004 * Q)
ob = bl.malla("m_ojos", v, q)
bl.decimar(ob, int(2000 / Q))
bl.uv_desde(ob, K.uv_ojos)
bl.material_simple(ob, "ojo", (1.0, 0.4, 0.05), rug=0.2)
bl.pesos_fijos(ob, "cabeza")
bl.emparentar(ob, arm)
bajas.append(ob)

# ---- colmillos y muelas (con la mandíbula)
v, q = sdf.malla(K.colmillos(), H + np.array([-0.08, -0.16, K.BOCA_Z - 0.03]), H + np.array([0.08, -0.11, K.BOCA_Z + 0.04]), 0.0004 * Q)
ob = bl.malla("m_colmillos", v, q)
bl.decimar(ob, int(2500 / Q))
bl.uv_auto(ob)
bl.material_simple(ob, "diente", (0.62, 0.57, 0.46), rug=0.5)
bl.pesos_fijos(ob, "mandibula")
bl.emparentar(ob, arm)
bajas.append(ob)
log("ojos y colmillos")

# ------------------------------------------------------------------ cuerpo de piedra (hombros y brazos)
S_c = K.cuerpo(W_R, W_L)
v, q = sdf.malla(S_c, (-0.48, -0.75, 0.4), (0.48, 0.32, 1.36), 0.0028 * Q)
n = normales_de(v, q)
cu = procesar("cuerpo", v, q, 18000, "piel_cuerpo", tam=2048, dist=0.01, color=K.colores_roca(F, v, n), ao=True, emi=M.emision(v, 2.0))


def cand_cuerpo(S):
    def fn(vb):
        reg = S.regiones(vb)
        out = []
        for r, x in zip(reg, vb[:, 0]):
            s = "_R" if x < 0 else "_L"
            r = int(r)
            if r == K.R_TORSO_B:
                out.append(["raiz", "cadera", "columna"])
            elif r == K.R_TORSO_A:
                out.append(["columna", "pecho", "cuello"])
            elif r == K.R_HOMBRO:
                out.append(["pecho", "clavicula" + s, "brazo" + s])
            elif r == K.R_BRAZO:
                out.append(["clavicula" + s, "brazo" + s, "antebrazo" + s])
            elif r == K.R_ANTEBRAZO:
                out.append(["brazo" + s, "antebrazo" + s])
            else:
                out.append(["raiz", "cadera"])
        return out
    return fn


pesos_por_candidatos(cu, cand_cuerpo(S_c)(bl.verts_np(cu)))
log("cuerpo")

# ------------------------------------------------------------------ mono
v, q = sdf.malla(S_m, (-0.42, -0.7, 0.0), (0.42, 0.35, 1.3), 0.003 * Q)
mono = procesar("mono", v, q, 14000, "ropa", tam=2048, dist=0.012, color=K.colores_mono(F, v))
pesos_por_candidatos(mono, cand_cuerpo(S_m)(bl.verts_np(mono)))
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
        bl.material_pbr(ob, "prev_" + nombre, color=tex.get("color"), normal=tex.get("normal"), rug=0.8)
    bl.render_previa(os.path.join(SAL_PREVIA, "mlk_a.png"), objetivo=(0, -0.3, 1.05), dist=2.4, elev=12, azim=0, lente=45)
    bl.render_previa(os.path.join(SAL_PREVIA, "mlk_cara.png"), objetivo=tuple(H + np.array([0, -0.04, -0.03])), dist=0.75, elev=5, azim=0, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "mlk_perfil.png"), objetivo=tuple(H + np.array([0, 0.0, -0.02])), dist=0.9, elev=8, azim=75, lente=50)
    bl.render_previa(os.path.join(SAL_PREVIA, "mlk_manos.png"), objetivo=(0, -0.75, 0.84), dist=1.0, elev=40, azim=10, lente=45)
    log("previa")
