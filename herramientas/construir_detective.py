"""Construye modelos/detective.glb: el agente completo (traje, camisa, corbata, manos
realistas con uñas, reloj, cabeza y pelo), con esqueleto y pesos, y texturas horneadas.
Uso: blender --background --factory-startup --python construir_detective.py [-- previa]
Variables: VOXEL_MANO (0.0005), CALIDAD (1 = final, 2 = rapido)
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bl, sdf, mano as M, cuerpo_detective as D

PROY = os.path.dirname(AQUI)
OUT = os.path.join(PROY, "modelos", "detective.glb")
TEX = os.path.join(PROY, "modelos", "tex")
Q = float(os.environ.get("CALIDAD", "1"))
PREVIA = "previa" in sys.argv
SAL_PREVIA = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))

T0 = time.time()


def log(*a):
    print("[det %5.1fs]" % (time.time() - T0), *a, flush=True)


bl.limpiar()

# ------------------------------------------------------------------ manos (local -> mundo)
S_mano, A, unas = M.esculpir(flex=D.FLEX_REPOSO)
hm = float(os.environ.get("VOXEL_MANO", "0.0005")) * Q
vl, ql = sdf.malla(S_mano, (-0.08, -0.082, -0.04), (0.055, 0.2, 0.032), hm)
log("mano local", len(vl))
Wz = D.altura_muneca(vl[vl[:, 1] > -0.01]) + 0.003
W_R = D.muneca(1, Wz)
W_L = D.muneca(-1, Wz)
log("muñeca z", Wz)


def a_mundo(v, lado):
    return D.a_mundo(np.asarray(v, np.float32), lado, Wz)


cuff_R = a_mundo(np.array([[0, -0.05, 0.016]]), 1)[0]
cuff_L = a_mundo(np.array([[0, -0.05, 0.016]]), -1)[0]

# ------------------------------------------------------------------ huesos
huesos = D.huesos_cuerpo(W_R, W_L)
for lado, s in ((1, "_R"), (-1, "_L")):
    for h in M.huesos(A, sufijo=s):
        h = dict(h)
        h["cabeza"] = tuple(a_mundo(np.array([h["cabeza"]]), lado)[0])
        h["cola"] = tuple(a_mundo(np.array([h["cola"]]), lado)[0])
        up = np.array(h["arriba"], np.float32) @ D.mano_transform(1).T
        if lado < 0:
            up = up * np.array([-1, 1, 1], np.float32)
        h["arriba"] = tuple(up)
        if h["padre"] is None:
            h["padre"] = "antebrazo" + s
        huesos.append(h)
seg = {h["nombre"]: (np.array(h["cabeza"], np.float32), np.array(h["cola"], np.float32)) for h in huesos}
arm = bl.armadura("Agente", huesos)
log("huesos", len(huesos))

bajas = []


def lado_de(v):
    return np.where(v[:, 0] >= 0, "_R", "_L")


def procesar(nombre, v, q, caras, cand_fn, material, bake=None, tam=1024, dist=0.004, color=None, ao=False, alta_extra=None):
    alta = bl.malla("alta_" + nombre, v, q)
    if color is not None:
        bl.color_vertices(alta, color)
    baja = bl.copia(alta, "m_" + nombre)
    bl.decimar(baja, int(caras / Q))
    for a in list(baja.data.color_attributes):
        baja.data.color_attributes.remove(a)
    bl.uv_auto(baja)
    tex = {}
    if bake:
        tex = bl.hornear(alta, baja, TEX, "det_" + nombre, tam=int(tam / (2 if Q > 1 else 1)), distancia=dist, ao=ao, color=color is not None)
    bl.material_simple(baja, material, (bake or {}).get("base", (0.7, 0.6, 0.55, 1)), rug=(bake or {}).get("rug", 0.6))
    vb = bl.verts_np(baja)
    cands = cand_fn(vb)
    bl.pesos(baja, {n: seg[n] for n in set(sum([list(c) for c in cands], []))}, cands)
    bl.emparentar(baja, arm)
    bajas.append(baja)
    bpy_data_remove(alta)
    log(nombre, "alta", len(v), "baja", len(baja.data.polygons))
    return baja, tex


def bpy_data_remove(ob):
    import bpy
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)


# ------------------------------------------------------------------ piel de las manos
n_loc = None
v_R = a_mundo(vl, 1)
reg_l = S_mano.regiones(vl)
alta_tmp = bl.malla("tmp_n", vl, ql)
n_loc = bl.normales_np(alta_tmp)
bpy_data_remove(alta_tmp)
col = M.colores(vl, reg_l, n_loc, A, piel=(0.60, 0.40, 0.31))


def cand_mano(sufijo):
    def fn(vb_mundo):
        # volver a local para conocer la region
        R = D.mano_transform(1)
        p = vb_mundo.copy()
        if sufijo == "_L":
            p = p * np.array([-1, 1, 1], np.float32)
        loc = (p - np.array([D.MUNECA_XY[0], D.MUNECA_XY[1], Wz], np.float32)) @ R
        reg = S_mano.regiones(loc)
        return [M.candidatos(int(r), "", sufijo) for r in reg]
    return fn


mano_R, tex_mano = procesar("mano_R", v_R, ql, 7000, cand_mano("_R"), "piel",
                            bake=dict(rug=0.5), tam=1024, dist=0.0025, color=col, ao=True)
# izquierda = reflejo de la derecha (mismas UV y texturas)
import bpy
mano_L = bl.copia(mano_R, "m_mano_L")
mano_L.parent = None
mano_L.vertex_groups.clear()
for m in list(mano_L.modifiers):
    mano_L.modifiers.remove(m)
vL = bl.verts_np(mano_L) * np.array([-1, 1, 1], np.float32)
bl.set_verts(mano_L, vL)
bl.normales_fuera(mano_L)
cands = cand_mano("_L")(vL)
bl.pesos(mano_L, {n: seg[n] for n in set(sum([list(c) for c in cands], []))}, cands)
bl.emparentar(mano_L, arm)
bajas.append(mano_L)

# ------------------------------------------------------------------ uñas
S_unas = M.esculpir_unas(unas)
vu, qu = sdf.malla(S_unas, (-0.08, 0.04, -0.045), (0.055, 0.2, 0.035), 0.0003 * Q)
distales = lambda s: ["dedo%d_2%s" % (f, s) for f in range(5)]
for lado, s in ((1, "_R"), (-1, "_L")):
    vw = a_mundo(vu, lado)
    ob = bl.malla("m_unas" + s, vw, qu)
    bl.decimar(ob, int(1600 / Q))
    bl.material_simple(ob, "unas", (0.74, 0.56, 0.5), rug=0.28)
    vb = bl.verts_np(ob)
    bl.pesos(ob, {n: seg[n] for n in distales(s)}, [distales(s)] * len(vb), potencia=8, max_inf=1)
    bl.emparentar(ob, arm)
    bajas.append(ob)
log("uñas")

# ------------------------------------------------------------------ puños y reloj (locales a la mano)
S_puno = D.puno_local()
vp, qp = sdf.malla(S_puno, (-0.045, -0.12, -0.035), (0.045, -0.02, 0.04), 0.0012 * Q)
for lado, s in ((1, "_R"), (-1, "_L")):
    ob = bl.malla("m_puno" + s, a_mundo(vp, lado), qp)
    bl.decimar(ob, int(700 / Q))
    bl.uv_auto(ob)
    bl.material_simple(ob, "camisa", (0.8, 0.79, 0.75), rug=0.75)
    bl.pesos_fijos(ob, "antebrazo" + s)
    bl.emparentar(ob, arm)
    bajas.append(ob)
S_rel = D.reloj_local()
vr, qr = sdf.malla(S_rel, (-0.045, -0.05, -0.035), (0.045, -0.01, 0.035), 0.0006 * Q)
ob = bl.malla("m_reloj", a_mundo(vr, -1), qr)
bl.decimar(ob, int(1400 / Q))
bl.uv_auto(ob)
bl.material_simple(ob, "reloj", (0.55, 0.5, 0.42), rug=0.3, metal=1.0)
bl.pesos_fijos(ob, "antebrazo_L")
bl.emparentar(ob, arm)
bajas.append(ob)
log("puños y reloj")

# ------------------------------------------------------------------ chaqueta


def cand_ropa(S):
    def fn(vb):
        reg = S.regiones(vb)
        lados = lado_de(vb)
        out = []
        for r, s in zip(reg, lados):
            r = int(r)
            if r == D.R_TORSO_B:
                out.append(["raiz", "cadera", "columna"])
            elif r == D.R_TORSO_A:
                out.append(["columna", "pecho"])
            elif r == D.R_HOMBRO:
                out.append(["pecho", "clavicula" + s, "brazo" + s])
            elif r == D.R_BRAZO:
                out.append(["clavicula" + s, "brazo" + s, "antebrazo" + s])
            elif r == D.R_ANTEBRAZO:
                out.append(["brazo" + s, "antebrazo" + s])
            elif r == D.R_CUELLO_CH:
                out.append(["pecho", "cuello"])
            else:
                out.append(["pecho"])
        return out
    return fn


hc = 0.0025 * Q
S_ch = D.chaqueta(W_R, W_L, cuff_R, cuff_L)
v, q = sdf.malla(S_ch, (-0.36, -0.9, 0.42), (0.36, 0.02, 1.17), hc)
procesar("chaqueta", v, q, 14000, cand_ropa(S_ch), "chaqueta", bake=dict(rug=0.85, base=(0.05, 0.05, 0.06, 1)), tam=2048, dist=0.012)

S_cam = D.camisa()
v, q = sdf.malla(S_cam, (-0.3, -0.85, 0.6), (0.3, -0.4, 1.13), hc)
procesar("camisa", v, q, 4000, cand_ropa(S_cam), "camisa", bake=dict(rug=0.75, base=(0.8, 0.79, 0.75, 1)), tam=1024, dist=0.006)

S_tie = D.corbata(S_cam)
v, q = sdf.malla(S_tie, (-0.06, -0.62, 0.7), (0.06, -0.4, 1.07), 0.0012 * Q)
procesar("corbata", v, q, 1200, lambda vb: [["pecho", "columna"]] * len(vb), "corbata", bake=dict(rug=0.55, base=(0.3, 0.03, 0.04, 1)), tam=512, dist=0.003)
log("ropa superior")

# ------------------------------------------------------------------ cabeza, pelo


def cand_cabeza(S):
    def fn(vb):
        reg = S.regiones(vb)
        return [["pecho", "cuello", "cabeza"] if int(r) == D.R_CUELLO else ["cuello", "cabeza"] for r in reg]
    return fn


S_cab = D.cabeza()
v, q = sdf.malla(S_cab, (-0.1, -0.68, 0.98), (0.1, -0.39, 1.4), 0.0015 * Q)
reg = S_cab.regiones(v)
col_cab = np.tile(np.array([0.6, 0.41, 0.32], np.float32), (len(v), 1)) * (1 + sdf.fbm(v * 40.0, 3, 5)[:, None] * 0.05)
procesar("cabeza", v, q, 6000, cand_cabeza(S_cab), "piel_cara", bake=dict(rug=0.55), tam=1024, dist=0.005, color=col_cab)
S_pelo = D.pelo()
v, q = sdf.malla(S_pelo, (-0.1, -0.67, 1.16), (0.1, -0.43, 1.4), 0.0012 * Q)
procesar("pelo", v, q, 4000, lambda vb: [["cabeza"]] * len(vb), "pelo", bake=dict(rug=0.6, base=(0.035, 0.028, 0.022, 1)), tam=1024, dist=0.004)
log("cabeza")

# ------------------------------------------------------------------ pantalon y zapatos


def cand_pant(S):
    def fn(vb):
        reg = S.regiones(vb)
        lados = lado_de(vb)
        out = []
        for r, s in zip(reg, lados):
            r = int(r)
            if r == D.R_PELVIS:
                out.append(["raiz", "cadera"])
            elif r == D.R_MUSLO:
                out.append(["raiz", "muslo" + s, "pierna" + s])
            else:
                out.append(["muslo" + s, "pierna" + s])
        return out
    return fn


S_p = D.pantalon()
v, q = sdf.malla(S_p, (-0.3, -0.87, 0.08), (0.3, -0.18, 0.7), 0.003 * Q)
procesar("pantalon", v, q, 6000, cand_pant(S_p), "pantalon", bake=dict(rug=0.85, base=(0.045, 0.045, 0.055, 1)), tam=1024, dist=0.01)
S_z = D.zapatos()
v, q = sdf.malla(S_z, (-0.2, -0.32, 0.0), (0.2, -0.05, 0.17), 0.002 * Q)
procesar("zapatos", v, q, 2000, lambda vb: [["pie" + s, "pierna" + s] for s in lado_de(vb)], "zapatos", bake=None)
bajas[-1].data.materials.clear()
bl.material_simple(bajas[-1], "zapatos", (0.02, 0.016, 0.014), rug=0.22)
log("piernas")

# ------------------------------------------------------------------ exportar
bl.exportar(OUT, [arm] + bajas)
log("exportado", OUT)

if PREVIA:
    import bpy
    os.makedirs(SAL_PREVIA, exist_ok=True)
    mesa = bl.malla("mesa", np.array([[-0.75, -0.2, 0.795], [0.75, -0.2, 0.795], [0.75, 0.7, 0.795], [-0.75, 0.7, 0.795]]), np.array([[0, 1, 2, 3]]))
    bl.material_simple(mesa, "mesa", (0.25, 0.25, 0.26), rug=0.35, metal=0.7)
    bl.render_previa(os.path.join(SAL_PREVIA, "det_a.png"), objetivo=(0, -0.45, 0.8), dist=2.2, elev=18, azim=-140, lente=45)
    bl.render_previa(os.path.join(SAL_PREVIA, "det_b.png"), objetivo=(0, -0.35, 0.9), dist=1.6, elev=10, azim=160, lente=45)
    bl.render_previa(os.path.join(SAL_PREVIA, "det_c.png"), objetivo=(0.1, -0.1, 0.83), dist=0.75, elev=35, azim=-175, lente=40)
    log("previa")
