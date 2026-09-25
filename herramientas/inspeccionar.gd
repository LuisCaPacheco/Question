extends SceneTree
## godot --headless --path <proy> --script res://herramientas/inspeccionar.gd -- res://modelos/x.glb

func _init() -> void:
	var ruta := "res://modelos/detective.glb"
	for a in OS.get_cmdline_user_args():
		ruta = a
	var ps: PackedScene = load(ruta)
	var n := ps.instantiate()
	_arbol(n, 0)
	var sk := _buscar(n)
	if sk:
		print("SKELETON ", sk.get_path(), " huesos ", sk.get_bone_count())
		for i in sk.get_bone_count():
			var g := sk.get_bone_global_rest(i)
			var nm := sk.get_bone_name(i)
			if nm.begins_with("mano") or nm.begins_with("antebrazo") or nm.begins_with("brazo") or nm.begins_with("dedo2") or nm.begins_with("dedo0") or nm == "pecho" or nm.begins_with("clav") or nm == "cabeza" or nm == "mandibula" or nm.begins_with("ojo") or nm.begins_with("parpado"):
				print("  %-14s pos %s  Y %s  Z %s" % [nm, g.origin, g.basis.y.normalized(), g.basis.z.normalized()])
	quit()

func _arbol(n: Node, d: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mats := []
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			mats.append(m.resource_name if m else "-")
		extra = " surfaces=%d mats=%s blend=%d" % [mi.mesh.get_surface_count(), mats, mi.mesh.get_blend_shape_count()]
	print("  ".repeat(d), n.name, " (", n.get_class(), ")", extra)
	for c in n.get_children():
		_arbol(c, d + 1)

func _buscar(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _buscar(c)
		if r:
			return r
	return null
