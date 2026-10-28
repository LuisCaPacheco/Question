"""Previa rápida de la cabeza de un humano (sin horneado ni esqueleto): malla de alta con
colores por vértice, ojos con iris pintado y pelo. Para iterar la forma de cuerpo_humano.py.
Uso: blender --background --factory-startup --python previa_cabeza.py -- danner [sara elena]
Variables: CALIDAD (1 = fino, 2 = rápido), PREVIA_DIR
Salida: _previa/cab_<id>_{frente,tres,perfil}.png
"""
import sys, os, time
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import numpy as np
import bpy
import bl, sdf, cuerpo_humano as C

Q = float(os.environ.get("CALIDAD", "1.5"))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
IDS = [a for a in ARGS if a in C.VARIANTES] or list(C.VARIANTES)
SAL = os.environ.get("PREVIA_DIR", os.path.join(AQUI, "_previa"))
T0 = time.time()
# iris "natural" para la previa (en el juego lo pone la ficha)
IRIS = {"danner": (0.25, 0.17, 0.06), "sara": (0.35, 0.45, 0.5), "elena": (0.2, 0.32, 0.5)}


def log(*a):
    print("[cab %5.1fs]" % (time.time() - T0), *a, flush=True)


def mat_vcol(ob, nombre, rug=0.5, sss=0.0, spec=0.5, clear=0.0):
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    nt = mat.node_tree
    bs = nt.nodes.get("Principled BSDF")
    at = nt.nodes.new("ShaderNodeVertexColor")
    at.layer_name = "Col"
    nt.links.new(at.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = rug
    for k, v in (("Subsurface Weight", sss), ("Specular IOR Level", spec), ("Coat Weight", clear)):
        if k in bs.inputs:
            bs.inputs[k].default_value = v
    if "Subsurface Radius" in bs.inputs:
        bs.inputs["Subsurface Radius"].default_value = (0.004, 0.0015, 0.001)
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def color_ojo(V, v):
    uv = C.uv_ojos(v)
    p = (uv - 0.5) * 2.0
    r = np.linalg.norm(p, axis=1)
    escl = C.lineal(V["ficha"].get("esclera"), (0.75, 0.7, 0.62)) * 0.9
    iris = np.array(IRIS.get(V["id"], (0.2, 0.15, 0.1)), np.float32)
    c = np.tile(escl, (len(v), 1))
    en_iris = (r < 0.47)[:, None]
    c = np.where(en_iris, iris * (0.6 + 0.4 * (r / 0.47))[:, None], c)
    c = np.where((r < 0.17)[:, None], 0.01, c)
    # solo la cara frontal del globo es "ojo"; detrás, oscuro
    c = np.where((v[:, 1] > C.H[1] + C.OJO[1] + 0.004)[:, None], 0.05, c)
    return c.astype(np.float32)


def construir(ident):
    V = C.variante(ident)
    bl.limpiar()
    H = C.H
    v, q = sdf.malla(C.cabeza(V), (-0.105, H[1] - 0.145, 0.98), (0.105, H[1] + 0.13, H[2] + 0.13), 0.0008 * Q)
    ob = bl.malla("cab", v, q)
    n = bl.normales_np(ob)
    bl.color_vertices(ob, C.colores_cabeza(V, v, n))
    mat_vcol(ob, "piel", rug=0.55, sss=0.25, spec=0.35)
    log(ident, "cabeza", len(v))
    v, q = sdf.malla(C.ojos(V), (-0.05, H[1] - 0.105, H[2] - 0.04), (0.05, H[1] - 0.06, H[2] - 0.004), 0.0004 * Q)
    ob = bl.malla("ojos", v, q)
    bl.color_vertices(ob, color_ojo(V, v))
    mat_vcol(ob, "ojo", rug=0.05, spec=0.8, clear=1.0)
    sup, inf = C.dientes(V)
    for S in (sup, inf):
        v, q = sdf.malla(S, H + np.array([-0.03, -0.112, C.BOCA_Z - 0.02]), H + np.array([0.03, -0.078, C.BOCA_Z + 0.012]), 0.0003 * Q)
        if len(v):
            bl.material_simple(bl.malla("dientes", v, q), "diente", tuple(V["DIENTE"]), rug=0.3)
    z0 = 0.9 if V["pelo"] == "largo" else H[2] - 0.12
    v, q = sdf.malla(C.pelo(V), (-0.115, H[1] - 0.13, z0), (0.115, H[1] + 0.22, H[2] + 0.13), 0.0009 * Q)
    ob = bl.malla("pelo", v, q)
    bl.color_vertices(ob, C.colores_pelo(V, v))
    mat_vcol(ob, "pelo", rug=0.55, spec=0.4)
    log(ident, "pelo", len(v))
    # cuello del mono (referencia de escala)
    bl.material_simple(bl.malla("mono", *sdf.malla(C.mono(V, C._v([-0.125, -0.53, 0.82]), C._v([0.125, -0.53, 0.82])),
                                                   (-0.3, -0.25, 0.85), (0.3, 0.2, 1.12), 0.004)), "ropa", tuple(V["ROPA"]), rug=0.85)
    os.makedirs(SAL, exist_ok=True)
    o = tuple(H + np.array([0, -0.03, -0.03]))
    bl.render_previa(os.path.join(SAL, "cab_%s_frente.png" % ident), objetivo=o, dist=0.55, elev=4, azim=0, lente=50)
    bl.render_previa(os.path.join(SAL, "cab_%s_tres.png" % ident), objetivo=o, dist=0.55, elev=6, azim=35, lente=50)
    bl.render_previa(os.path.join(SAL, "cab_%s_perfil.png" % ident), objetivo=tuple(H + np.array([0, 0.0, -0.02])), dist=0.65, elev=4, azim=88, lente=50)
    log(ident, "previa")


for ident in IDS:
    construir(ident)
