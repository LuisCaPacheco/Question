"""Prueba: mano derecha del detective -> previsualizacion PNG (sin exportar)."""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bl, sdf, mano
import importlib
importlib.reload(sdf); importlib.reload(mano); importlib.reload(bl)

SAL = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(os.path.dirname(__file__), "_previa")
os.makedirs(SAL, exist_ok=True)
H = float(os.environ.get("VOXEL", "0.0006"))

bl.limpiar()
t0 = time.time()
S, A, unas = mano.esculpir()
v, q = sdf.malla(S, (-0.08, -0.08, -0.04), (0.055, 0.2, 0.032), H)
print("mano alta", len(v), len(q), "t", round(time.time() - t0, 1))
alta = bl.malla("mano_alta", v, q)
t0 = time.time()
U = mano.esculpir_unas(unas)
vu, qu = sdf.malla(U, (-0.08, 0.05, -0.04), (0.055, 0.2, 0.032), H * 0.6)
print("uñas", len(vu), "t", round(time.time() - t0, 1))
un = bl.malla("unas", vu, qu)
# color por vertice
reg = S.regiones(v)
n = bl.normales_np(alta)
col = mano.colores(v, reg, n, A)
bl.color_vertices(alta, col)
bl.material_pbr(alta, "piel_prev", rug=0.5)
mat = alta.data.materials[0]
nt = mat.node_tree
bs = nt.nodes.get("Principled BSDF")
vc = nt.nodes.new('ShaderNodeVertexColor'); vc.layer_name = "Col"
nt.links.new(vc.outputs['Color'], bs.inputs['Base Color'])
try:
    bs.inputs["Subsurface Weight"].default_value = 0.25
    bs.inputs["Subsurface Radius"].default_value = (0.012, 0.005, 0.003)
    bs.inputs["Subsurface Scale"].default_value = 0.2
except Exception as ex:
    print("sss", ex)
bl.material_simple(un, "una", (0.78, 0.55, 0.5), rug=0.25)
mesa = bl.malla("mesa", np.array([[-0.4, -0.3, -0.0215], [0.4, -0.3, -0.0215], [0.4, 0.4, -0.0215], [-0.4, 0.4, -0.0215]]), np.array([[0, 1, 2, 3]]))
bl.material_simple(mesa, "mesa", (0.08, 0.08, 0.085), rug=0.4, metal=0.6)
bl.render_previa(os.path.join(SAL, "mano_a.png"), objetivo=(-0.005, 0.07, 0.0), dist=0.36, elev=38, azim=-20, lente=60)
bl.render_previa(os.path.join(SAL, "mano_b.png"), objetivo=(-0.01, 0.08, 0.0), dist=0.3, elev=12, azim=-75, lente=60)
bl.render_previa(os.path.join(SAL, "mano_c.png"), objetivo=(0.0, 0.1, 0.0), dist=0.2, elev=30, azim=-170, lente=60)
print("OK")
