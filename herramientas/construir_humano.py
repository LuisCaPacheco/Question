"""Construye los sospechosos humanos esculpidos: modelos/humano_<id>.glb (danner, sara, elena).
Cada uno sentado con el mono del penal, cabeza con su peinado, cicatriz y dientes, ojos de
esclera (UV frontal para Ilvari.SHADER_OJO_UV), manos humanas de cinco dedos con uñas.
Mismo esqueleto que el ilvari (+ comisura_R/L), así que lo anima Ilvari.gd.
Esqueleto + pesos + texturas horneadas (modelos/tex/hum_<id>_*). Colores: data/sospechosos.json.
Uso: blender --background --factory-startup --python construir_humano.py [-- danner sara elena] [previa]
     (sin nombres construye los tres)
Variables: CALIDAD (1 = final, 2 = rápido), PREVIA_DIR
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bl, sdf, mano as M, cuerpo_humano as C

PROY = os.path.dirname(AQUI)
TEX = os.path.join(PROY, "modelos", "tex")
Q = float(os.environ.get("CALIDAD", "1"))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIA = "previa" in ARGS
IDS = [a for a in ARGS if a in C.VARIANTES] or list(C.VARIANTES)
SAL_PREVIA = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))
T0 = time.time()


def log(*a):
    print("[hum %5.1fs]" % (time.time() - T0), *a, flush=True)


def construir(ident):
    V = C.variante(ident)
    pre = "hum_" + ident
    out = os.path.join(PROY, "modelos", "humano_%s.glb" % ident)
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

    # -------------------------------------------------------------- manos
    e = V["mano"]
    S_mano, A, unas = M.esculpir(escala=e, flex=C.FLEX_REPOSO)
    vl, ql = sdf.malla(S_mano, (-0.08 * e, -0.082 * e, -0.04 * e), (0.055 * e, 0.2 * e, 0.032 * e), 0.0005 * Q)
    log(ident, "mano local", len(vl))
    Wz = C.altura_muneca(vl[vl[:, 1] > -0.01]) + 0.003
    W_R = C.a_mundo(np.zeros((1, 3)), -1, Wz)[0]
    W_L = C.a_mundo(np.zeros((1, 3)), 1, Wz)[0]

    # -------------------------------------------------------------- mono (antes que el esqueleto: la placa sale de él)
    S_m = C.mono(V, W_R, W_L)
    placa = C.placa_pos(S_m)

    # -------------------------------------------------------------- esqueleto
    huesos = C.huesos_cuerpo(V, W_R, W_L, placa)
    R_m = C.mano_transform(-1)
    for lado, s in ((-1, "_R"), (1, "_L")):
        for hb in M.huesos(A, sufijo=s):
            hb = dict(hb)
            hb["cabeza"] = tuple(C.a_mundo(np.array([hb["cabeza"]]), lado, Wz)[0])
            hb["cola"] = tuple(C.a_mundo(np.array([hb["cola"]]), lado, Wz)[0])
            up = np.array(hb["arriba"], np.float32) @ R_m.T
            if lado > 0:
                up = up * np.array([-1, 1, 1], np.float32)
            hb["arriba"] = tuple(up)
            if hb["padre"] is None:
                hb["padre"] = "antebrazo" + s
            huesos.append(hb)
    seg = {hb["nombre"]: (np.array(hb["cabeza"], np.float32), np.array(hb["cola"], np.float32)) for hb in huesos}
    arm = bl.armadura("Humano", huesos)
    log(ident, "huesos", len(huesos))
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
        tex = bl.hornear(alta, baja, TEX, pre + "_" + nombre, tam=int(tam / (2 if Q > 1 else 1)), distancia=dist, ao=ao, color=color is not None)
        texturas[nombre] = (baja, tex)
        bl.material_simple(baja, material, base)
        borrar(alta)
        bajas.append(baja)
        log(ident, nombre, "alta", len(v), "baja", len(baja.data.polygons))
        return baja

    def pesos_por_candidatos(ob, cands):
        bl.pesos(ob, {n: seg[n] for n in set(sum([list(c) for c in cands], []))}, cands)
        bl.emparentar(ob, arm)

    # ---- manos (se hornea la derecha; la izquierda es su reflejo)
    n_loc = normales_de(vl, ql)
    col = C.colores_mano(V, vl, S_mano.regiones(vl), n_loc, A)
    mano_R = procesar("mano_R", C.a_mundo(vl, -1, Wz), ql, 7500, "piel", dist=0.0025, color=col, ao=True)

    def cand_mano(sufijo, lado):
        def fn(vb):
            p = vb.copy()
            if lado > 0:
                p = p * np.array([-1, 1, 1], np.float32)
            loc = (p - np.array([-C.MUNECA_XY[0], C.MUNECA_XY[1], Wz], np.float32)) @ R_m
            reg = S_mano.regiones(loc)
            return [M.candidatos(int(r), "", sufijo) for r in reg]
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

    # ---- uñas (material "una": Ilvari.gd le pone el color de la ficha)
    S_u = M.esculpir_unas(unas)
    vu, qu = sdf.malla(S_u, (-0.08 * e, 0.04 * e, -0.045 * e), (0.055 * e, 0.2 * e, 0.035 * e), 0.0003 * Q)
    for lado, s in ((-1, "_R"), (1, "_L")):
        ob = bl.malla("m_unas" + s, C.a_mundo(vu, lado, Wz), qu)
        bl.decimar(ob, int(1600 / Q))
        bl.uv_auto(ob)
        bl.material_simple(ob, "una", tuple(V["UNA"]), rug=0.3)
        distales = ["dedo%d_2%s" % (f, s) for f in range(5)]
        vb = bl.verts_np(ob)
        bl.pesos(ob, {n: seg[n] for n in distales}, [distales] * len(vb), potencia=8, max_inf=1)
        bl.emparentar(ob, arm)
        bajas.append(ob)
    log(ident, "manos y uñas")

    # -------------------------------------------------------------- cabeza y cuello
    H = C.H
    S_cab = C.cabeza(V)
    v, q = sdf.malla(S_cab, (-0.105, H[1] - 0.145, 0.98), (0.105, H[1] + 0.13, H[2] + 0.13), 0.0008 * Q)
    n = normales_de(v, q)
    cab = procesar("cabeza", v, q, 24000, "piel_cara", tam=2048, dist=0.004, color=C.colores_cabeza(V, v, n), ao=True)
    vb = bl.verts_np(cab)
    nombres, W = C.pesos_cabeza(vb, dist_seg(vb))
    bl.pesos_matriz(cab, nombres, W)
    bl.emparentar(cab, arm)
    log(ident, "cabeza")

    # ---- ojos: UV frontal (centro = iris)
    v, q = sdf.malla(C.ojos(V), (-0.05, H[1] - 0.105, H[2] - 0.04), (0.05, H[1] - 0.06, H[2] - 0.004), 0.0004 * Q)
    ob = bl.malla("m_ojos", v, q)
    bl.decimar(ob, int(2000 / Q))
    bl.uv_desde(ob, C.uv_ojos)
    bl.material_simple(ob, "ojo", (0.8, 0.78, 0.72), rug=0.05)
    bl.pesos_fijos(ob, "cabeza")
    bl.emparentar(ob, arm)
    bajas.append(ob)

    # ---- dientes
    sup, inf = C.dientes(V)
    for nombre, S, hueso in (("dientes_sup", sup, "cabeza"), ("dientes_inf", inf, "mandibula")):
        v, q = sdf.malla(S, H + np.array([-0.03, -0.112, C.BOCA_Z - 0.02]), H + np.array([0.03, -0.078, C.BOCA_Z + 0.012]), 0.00025 * Q)
        if len(v) == 0:
            continue
        ob = bl.malla("m_" + nombre, v, q)
        bl.decimar(ob, int(1500 / Q))
        bl.uv_auto(ob)
        bl.material_simple(ob, "diente", tuple(V["DIENTE"]), rug=0.3)
        bl.pesos_fijos(ob, hueso)
        bl.emparentar(ob, arm)
        bajas.append(ob)
    log(ident, "ojos y dientes")

    # ---- pelo
    z0 = 0.9 if V["pelo"] == "largo" else H[2] - 0.12
    v, q = sdf.malla(C.pelo(V), (-0.115, H[1] - 0.13, z0), (0.115, H[1] + 0.22, H[2] + 0.13), 0.0009 * Q)
    pel = procesar("pelo", v, q, 14000 if V["pelo"] == "largo" else 9000, "pelo", tam=2048 if V["pelo"] == "largo" else 1024,
                   dist=0.004, color=C.colores_pelo(V, v), ao=True)
    vb = bl.verts_np(pel)
    nombres, W = C.pesos_pelo(V, vb, dist_seg(vb))
    bl.pesos_matriz(pel, nombres, W)
    bl.emparentar(pel, arm)
    log(ident, "pelo")

    # -------------------------------------------------------------- mono
    v, q = sdf.malla(S_m, (-0.4, -0.72, 0.0), (0.4, 0.3, 1.15), 0.003 * Q)
    mono = procesar("mono", v, q, 16000, "ropa", tam=2048, dist=0.012, color=C.colores_mono(V, v))

    def cand_ropa(vb):
        reg = S_m.regiones(vb)
        out = []
        for r, x in zip(reg, vb[:, 0]):
            s = "_R" if x < 0 else "_L"
            r = int(r)
            if r == C.R_TORSO_B:
                out.append(["raiz", "cadera", "columna"])
            elif r == C.R_TORSO_A:
                out.append(["columna", "pecho"])
            elif r == C.R_HOMBRO:
                out.append(["pecho", "clavicula" + s, "brazo" + s])
            elif r == C.R_BRAZO:
                out.append(["clavicula" + s, "brazo" + s, "antebrazo" + s])
            elif r == C.R_ANTEBRAZO:
                out.append(["brazo" + s, "antebrazo" + s])
            elif r == C.R_CUELLO_T:
                out.append(["pecho", "cuello"])
            else:
                out.append(["raiz"])
        return out

    pesos_por_candidatos(mono, cand_ropa(bl.verts_np(mono)))
    log(ident, "mono")

    # -------------------------------------------------------------- exportar
    bl.exportar(out, [arm] + bajas)
    log(ident, "exportado", out)

    if PREVIA:
        os.makedirs(SAL_PREVIA, exist_ok=True)
        mesa = bl.malla("mesa", np.array([[-0.75, -0.35, 0.795], [0.75, -0.35, 0.795], [0.75, -1.3, 0.795], [-0.75, -1.3, 0.795]]), np.array([[0, 1, 2, 3]]))
        bl.material_simple(mesa, "mesa", (0.25, 0.25, 0.26), rug=0.35, metal=0.7)
        texturas["mano_L"] = (mano_L, texturas["mano_R"][1])
        for nombre, (ob, tex) in texturas.items():
            bl.material_pbr(ob, "prev_" + nombre, color=tex.get("color"), normal=tex.get("normal"),
                            rug=0.45 if nombre != "mono" else 0.85)
        bl.render_previa(os.path.join(SAL_PREVIA, pre + "_a.png"), objetivo=(0, -0.3, 1.0), dist=2.0, elev=12, azim=0, lente=45)
        bl.render_previa(os.path.join(SAL_PREVIA, pre + "_cara.png"), objetivo=tuple(H + np.array([0, -0.03, -0.03])), dist=0.6, elev=5, azim=0, lente=50)
        bl.render_previa(os.path.join(SAL_PREVIA, pre + "_perfil.png"), objetivo=tuple(H + np.array([0, 0.0, -0.02])), dist=0.75, elev=8, azim=75, lente=50)
        bl.render_previa(os.path.join(SAL_PREVIA, pre + "_manos.png"), objetivo=(0, -0.62, 0.82), dist=0.9, elev=40, azim=10, lente=45)
        log(ident, "previa")


for ident in IDS:
    construir(ident)
