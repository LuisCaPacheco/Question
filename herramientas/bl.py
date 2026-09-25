"""INTERROGART - utilidades de Blender (bpy) para construir personajes por codigo.

- malla(): de arrays numpy a objeto de Blender (rapido, con foreach_set)
- suavizar / decimar / uv / aplicar modificadores
- hornear(): normal / color / AO de la malla densa a la de juego (selected to active, Cycles)
- armadura(): huesos por posiciones; pesos calculados por distancia a segmentos
- exportar(): glb con skin + morph targets
"""
import bpy
import bmesh
import numpy as np
import os
import math
from mathutils import Vector, Matrix


def limpiar():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    return sc


def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def malla(nombre, verts, caras, suave=True):
    verts = np.asarray(verts, dtype=np.float32)
    caras = np.asarray(caras, dtype=np.int64)
    me = bpy.data.meshes.new(nombre)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.ravel())
    n = caras.shape[1]
    me.loops.add(len(caras) * n)
    me.loops.foreach_set("vertex_index", caras.ravel().astype(np.int32))
    me.polygons.add(len(caras))
    me.polygons.foreach_set("loop_start", (np.arange(len(caras)) * n).astype(np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    ob = _link(bpy.data.objects.new(nombre, me))
    if suave:
        me.shade_smooth()
    normales_fuera(ob)
    return ob


def normales_fuera(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def activar(ob, extra=()):
    bpy.context.view_layer.update()
    for o in bpy.context.scene.objects:
        if o is not None:
            o.select_set(False)
    for o in extra:
        o.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def aplicar_mods(ob):
    activar(ob)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def suavizar(ob, iter=2, factor=0.5):
    m = ob.modifiers.new("suave", 'SMOOTH')
    m.iterations = iter
    m.factor = factor
    aplicar_mods(ob)


def decimar(ob, caras_objetivo):
    """caras_objetivo = triangulos finales aproximados."""
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris <= caras_objetivo:
        return
    m = ob.modifiers.new("dec", 'DECIMATE')
    m.ratio = caras_objetivo / tris
    m.use_collapse_triangulate = True
    aplicar_mods(ob)


def copia(ob, nombre):
    o2 = ob.copy()
    o2.data = ob.data.copy()
    o2.name = nombre
    return _link(o2)


def uv_auto(ob, angulo=66.0, margen=0.004):
    activar(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(angulo), island_margin=margen, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode='OBJECT')


def color_vertices(ob, colores, nombre="Col"):
    """colores: (N,3|4) por vertice (lineal)."""
    me = ob.data
    c = np.asarray(colores, dtype=np.float32)
    if c.shape[1] == 3:
        c = np.concatenate([c, np.ones((len(c), 1), np.float32)], axis=1)
    attr = me.color_attributes.new(nombre, 'FLOAT_COLOR', 'POINT')
    attr.data.foreach_set("color", c.ravel())
    return attr


def verts_np(ob):
    v = np.empty(len(ob.data.vertices) * 3, dtype=np.float32)
    ob.data.vertices.foreach_get("co", v)
    return v.reshape(-1, 3)


def set_verts(ob, v):
    ob.data.vertices.foreach_set("co", np.asarray(v, dtype=np.float32).ravel())
    ob.data.update()


def normales_np(ob):
    me = ob.data
    n = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("normal", n)
    return n.reshape(-1, 3)


# ------------------------------------------------------------------ materiales / horneado

def imagen(nombre, tam, color=(0.5, 0.5, 1.0, 1.0), datos=False):
    img = bpy.data.images.new(nombre, tam, tam, alpha=False, float_buffer=False)
    img.generated_color = color
    if datos:
        img.colorspace_settings.name = 'Non-Color'
    return img


def _mat_horneo(ob, img):
    """Material de la malla de juego con un nodo imagen activo (destino del horneado)."""
    mat = bpy.data.materials.new(ob.name + "_bake")
    mat.use_nodes = True
    nt = mat.node_tree
    tex = nt.nodes.new('ShaderNodeTexImage')
    tex.image = img
    nt.nodes.active = tex
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return mat


def _mat_emision_color(ob, attr="Col"):
    mat = bpy.data.materials.new(ob.name + "_emit")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    em = nt.nodes.new('ShaderNodeEmission')
    ca = nt.nodes.new('ShaderNodeVertexColor')
    ca.layer_name = attr
    nt.links.new(ca.outputs['Color'], em.inputs['Color'])
    nt.links.new(em.outputs['Emission'], out.inputs['Surface'])
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def _cycles():
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 8
    try:
        sc.cycles.use_denoising = False
    except Exception:
        pass


def hornear(alta, baja, carpeta, prefijo, tam=1024, distancia=0.004, ao=True, color=True):
    """Hornea normal (tangente), color (atributo 'Col' de la malla alta) y AO. Guarda PNG."""
    _cycles()
    sc = bpy.context.scene
    res = {}
    bk = sc.render.bake
    bk.use_selected_to_active = True
    bk.cage_extrusion = distancia
    bk.max_ray_distance = distancia * 2.5
    bk.margin = 8
    # --- normal
    img = imagen(prefijo + "_n", tam, (0.5, 0.5, 1.0, 1.0), datos=True)
    _mat_horneo(baja, img)
    activar(baja, [alta])
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT', use_selected_to_active=True,
                        cage_extrusion=distancia, max_ray_distance=distancia * 2.5, margin=8)
    res["normal"] = _guardar(img, carpeta, prefijo + "_normal.png")
    if color:
        img = imagen(prefijo + "_c", tam, (0.5, 0.5, 0.5, 1.0))
        _mat_horneo(baja, img)
        _mat_emision_color(alta)
        activar(baja, [alta])
        bpy.ops.object.bake(type='EMIT', use_selected_to_active=True,
                            cage_extrusion=distancia, max_ray_distance=distancia * 2.5, margin=8)
        res["color"] = _guardar(img, carpeta, prefijo + "_color.png")
    if ao:
        sc.cycles.samples = 48
        img = imagen(prefijo + "_ao", tam, (1, 1, 1, 1), datos=True)
        _mat_horneo(baja, img)
        activar(baja)
        bpy.ops.object.bake(type='AO', use_selected_to_active=False, margin=8)
        res["ao"] = _guardar(img, carpeta, prefijo + "_ao.png")
        sc.cycles.samples = 8
    return res


def _guardar(img, carpeta, nombre):
    os.makedirs(carpeta, exist_ok=True)
    ruta = os.path.join(carpeta, nombre)
    img.filepath_raw = ruta
    img.file_format = 'PNG'
    img.save()
    return ruta


def material_pbr(ob, nombre, color=None, normal=None, rug=0.55, base=(0.8, 0.8, 0.8, 1), metal=0.0, sss=0.0):
    """Material Principled con texturas (para que el glb lleve algo razonable)."""
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    nt = mat.node_tree
    bs = nt.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value = rug
    bs.inputs["Metallic"].default_value = metal
    bs.inputs["Base Color"].default_value = base
    if color:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(color, check_existing=True)
        nt.links.new(t.outputs['Color'], bs.inputs['Base Color'])
    if normal:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(normal, check_existing=True)
        t.image.colorspace_settings.name = 'Non-Color'
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(t.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bs.inputs['Normal'])
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return mat


def material_simple(ob, nombre, base, rug=0.6, metal=0.0):
    mat = bpy.data.materials.new(nombre)
    mat.use_nodes = True
    bs = mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*base[:3], 1.0)
    bs.inputs["Roughness"].default_value = rug
    bs.inputs["Metallic"].default_value = metal
    if ob is not None:
        ob.data.materials.clear()
        ob.data.materials.append(mat)
    return mat


# ------------------------------------------------------------------ armadura y pesos

def armadura(nombre, huesos):
    """huesos: lista de dicts {nombre, cabeza, cola, padre, arriba(opcional), deform}."""
    arm = bpy.data.armatures.new(nombre)
    ob = _link(bpy.data.objects.new(nombre, arm))
    activar(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for h in huesos:
        b = eb.new(h["nombre"])
        b.head = Vector(h["cabeza"])
        b.tail = Vector(h["cola"])
        if "arriba" in h:
            b.align_roll(Vector(h["arriba"]))
        b.use_deform = h.get("deform", True)
    for h in huesos:
        if h.get("padre"):
            eb[h["nombre"]].parent = eb[h["padre"]]
            eb[h["nombre"]].use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def dist_segmento(p, a, b):
    a = np.asarray(a, np.float32)
    b = np.asarray(b, np.float32)
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(float(ab @ ab), 1e-12), 0, 1)
    q = a + t[:, None] * ab
    return np.linalg.norm(p - q, axis=1), t


def pesos(ob, huesos, candidatos, potencia=4.0, max_inf=3):
    """Asigna pesos por distancia a los segmentos de los huesos.
    huesos: {nombre: (cabeza, cola)}; candidatos: array (N,) de listas de nombres permitidos
    (o una funcion idx->lista). Crea los vertex groups."""
    v = verts_np(ob)
    nombres = list(huesos.keys())
    D = np.stack([dist_segmento(v, *huesos[n])[0] for n in nombres], axis=1)  # (N, B)
    W = 1.0 / (np.maximum(D, 1e-4) ** potencia)
    mask = np.zeros_like(W)
    for i in range(len(v)):
        for n in candidatos[i]:
            mask[i, nombres.index(n)] = 1.0
    W *= mask
    # quedarse con las max_inf mayores
    if max_inf < W.shape[1]:
        orden = np.argsort(-W, axis=1)
        corte = np.zeros_like(W, dtype=bool)
        np.put_along_axis(corte, orden[:, :max_inf], True, axis=1)
        W = np.where(corte, W, 0.0)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    grupos = {n: ob.vertex_groups.new(name=n) for n in nombres}
    for j, n in enumerate(nombres):
        idx = np.nonzero(W[:, j] > 0.002)[0]
        g = grupos[n]
        for i in idx:
            g.add([int(i)], float(W[i, j]), 'REPLACE')
    return W


def pesos_matriz(ob, nombres, W, minimo=0.002):
    """Asigna pesos ya calculados: W (N, len(nombres)), filas normalizadas."""
    for j, n in enumerate(nombres):
        g = ob.vertex_groups.get(n) or ob.vertex_groups.new(name=n)
        idx = np.nonzero(W[:, j] > minimo)[0]
        for i in idx:
            g.add([int(i)], float(W[i, j]), 'REPLACE')


def pesos_fijos(ob, hueso):
    g = ob.vertex_groups.new(name=hueso)
    g.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')


def emparentar(ob, arm):
    ob.parent = arm
    m = ob.modifiers.new("Armature", 'ARMATURE')
    m.object = arm


def exportar(ruta, objetos=None):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    if objetos is not None:
        bpy.context.view_layer.update()
        for o in bpy.context.scene.objects:
            if o is not None:
                o.select_set(o in objetos)
    kw = dict(filepath=ruta, export_format='GLB', export_yup=True, export_skins=True,
              export_morph=True, export_apply=False, export_animations=False,
              use_selection=objetos is not None, export_texcoords=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(**kw, export_image_format='AUTO')
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)


# ------------------------------------------------------------------ previsualizacion

def render_previa(ruta, objetivo=(0, 0, 0), dist=0.5, elev=25.0, azim=-30.0, lente=50, tam=(900, 700), engine='BLENDER_EEVEE'):
    sc = bpy.context.scene
    try:
        sc.render.engine = engine
    except TypeError:
        sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x, sc.render.resolution_y = tam
    sc.render.film_transparent = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.03, 0.03, 0.035, 1)
        bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.get("CamPrevia")
    if cam is None:
        cam = _link(bpy.data.objects.new("CamPrevia", bpy.data.cameras.new("CamPrevia")))
    cam.data.lens = lente
    cam.data.clip_start = 0.005
    o = Vector(objetivo)
    e, a = math.radians(elev), math.radians(azim)
    cam.location = o + Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (o - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    k = (dist / 0.3) ** 2
    for nombre, loc, en, tam_l in (("Llave", (1.2, -1.5, 2.2), 14.0, 0.4), ("Relleno", (-2.0, -0.6, 0.6), 2.5, 1.2), ("Contra", (0.6, 2.0, 1.5), 7.0, 0.5)):
        l = bpy.data.objects.get(nombre)
        if l is None:
            l = _link(bpy.data.objects.new(nombre, bpy.data.lights.new(nombre, 'AREA')))
        l.data.energy = en * k
        l.data.size = tam_l * dist
        l.location = o + Vector(loc) * dist
        l.rotation_euler = (o - l.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = ruta
    bpy.ops.render.render(write_still=True)
