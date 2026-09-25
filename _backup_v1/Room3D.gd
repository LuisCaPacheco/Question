extends Node3D
## INTERROGART - Sala 3D primera persona (Godot 4, procedural, sin assets)
## Foto ref: cuarto oscuro, mesa metalica, lampara cenital, sospechoso naranja de frente.
## Sospechoso: cuerpo NARANJA visible, brazos y MANOS sobre la mesa, cabeza con
## OJOS + CEJAS (expresiones) + BOCA que se mueve al hablar + GOTAS DE SUDOR.
## Luz: spot principal APUNTADO a la cara (con sombra) + luz de relleno a la cara.
## API para GameManager: set_especie(id), react(tipo)

var spot: SpotLight3D
var face_light: SpotLight3D
var lamp_mesh: MeshInstance3D
var fill: OmniLight3D
var cam: Camera3D
var cam_base := Vector3(0, 1.32, 0.85)

var suspect_root: Node3D
var suspect_body: MeshInstance3D
var suspect_head: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var hand_l: MeshInstance3D
var hand_r: MeshInstance3D
var eye_l: MeshInstance3D
var eye_r: MeshInstance3D
var brow_l: MeshInstance3D
var brow_r: MeshInstance3D
var mouth: MeshInstance3D
var sweat: Array = []

var t := 0.0
var base_energy := 10.0
var sway := true            # ajuste: camara viva o fija
var _intro_activa := false
var _intro_tween: Tween
var _sospechoso_visible := false  # menu = mesa vacia; se muestra al empezar nivel
var nervous := 0.25       # 0 calmado - 1 panico (sube cuando le hablas duro / evidencia)
var talk_timer := 0.0     # >0 = la boca se mueve
var emotion := "normal"   # normal, nervioso, asustado, triste, enojado
var _especie_pendiente := "humano"
var _avatar_pendiente := {}
var ojos_base := 1.0
var modelo_inst: Node3D
var modelo_base_y := 0.0
var lean_x := 0.0
var carpeta_mesh: MeshInstance3D
var carpeta_home := {}
var carpeta_tween: Tween
var head_mat: StandardMaterial3D
var body_mat: StandardMaterial3D
var mouth_closed_y := 1.56

func _ready() -> void:
	_construir_mundo()
	_aplicar_especie(_especie_pendiente)
	if not _avatar_pendiente.is_empty():
		set_avatar(_avatar_pendiente)
	set_process(true)

func _caja(nombre: String, tam: Vector3, pos: Vector3, color: Color, rugoso := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nombre
	var box := BoxMesh.new()
	box.size = tam
	mi.mesh = box
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95 if rugoso else 0.35
	mi.material_override = mat
	add_child(mi)
	return mi

func _mat(color: Color, rugoso := true, emision := false, ecolor := Color.WHITE, eenergia := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9 if rugoso else 0.4
	if emision:
		m.emission_enabled = true
		m.emission = ecolor
		m.emission_energy_multiplier = eenergia
	return m

func _construir_mundo() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.008, 0.01)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.11, 0.1)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Glow/bloom real: la lampara y los ojos "queman" un poco, como en las fotos de referencia
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Fog: base plana suave + volumetrica real (el "rayo de luz" de la lampara ya no es una caja falsa)
	e.fog_enabled = true
	e.fog_light_color = Color(0.02, 0.02, 0.02)
	e.fog_density = 0.008
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.045
	e.volumetric_fog_albedo = Color(0.85, 0.8, 0.7)
	e.volumetric_fog_emission = Color(0.05, 0.045, 0.04)
	e.volumetric_fog_gi_inject = 0.6
	e.volumetric_fog_ambient_inject = 0.15
	# SSAO/SSIL: contacto y rebote de luz baratos, sin necesitar GI horneada
	e.ssao_enabled = true
	e.ssao_intensity = 1.6
	e.ssao_radius = 0.9
	e.ssil_enabled = true
	e.ssil_intensity = 1.4
	# Reflejos de pantalla para el espejo/metal de la mesa
	e.ssr_enabled = true
	e.ssr_max_steps = 32
	# Gradacion de color sutil: negros mas negros, un pelin frio en sombras / calido en luces
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.12
	e.adjustment_saturation = 0.92
	env.environment = e
	add_child(env)

	# Cuarto (un poco mas claro para que se vea, el negro puro mataba todo)
	_caja("Suelo", Vector3(6, 0.1, 5), Vector3(0, -0.05, 0), Color(0.16, 0.15, 0.14))
	_caja("Techo", Vector3(6, 0.1, 5), Vector3(0, 3.0, 0), Color(0.07, 0.07, 0.07))
	_caja("ParedN", Vector3(6, 3, 0.1), Vector3(0, 1.5, -2.5), Color(0.19, 0.18, 0.17))
	_caja("ParedS", Vector3(6, 3, 0.1), Vector3(0, 1.5, 2.5), Color(0.12, 0.12, 0.12))
	_caja("ParedE", Vector3(0.1, 3, 5), Vector3(3, 1.5, 0), Color(0.17, 0.16, 0.15))
	_caja("ParedO", Vector3(0.1, 3, 5), Vector3(-3, 1.5, 0), Color(0.17, 0.16, 0.15))
	_caja("Espejo", Vector3(1.6, 1.0, 0.05), Vector3(1.2, 1.7, -2.44), Color(0.06, 0.09, 0.12), false)

	# Mesa + evidencias + tripode
	_caja("Mesa", Vector3(1.7, 0.07, 1.1), Vector3(0, 0.76, -0.25), Color(0.36, 0.37, 0.39), false)
	_caja("PataMesa", Vector3(0.09, 0.76, 0.09), Vector3(0, 0.38, -0.25), Color(0.08, 0.08, 0.08))
	carpeta_mesh = _caja("Carpeta", Vector3(0.38, 0.025, 0.3), Vector3(-0.35, 0.81, -0.15), Color(0.4, 0.3, 0.14))
	_caja("Papel1", Vector3(0.28, 0.006, 0.32), Vector3(0.25, 0.805, -0.3), Color(0.85, 0.83, 0.78))
	_caja("Papel2", Vector3(0.28, 0.006, 0.32), Vector3(0.28, 0.812, -0.28), Color(0.8, 0.78, 0.72))
	# Zona clicable en la carpeta: abre el expediente (como el libro de Phasmo, pero carpeta)
	var zona := Area3D.new()
	zona.name = "ZonaCarpeta"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.35, 0.6)
	col.shape = shape
	zona.position = Vector3(-0.1, 0.85, -0.2)
	zona.add_child(col)
	add_child(zona)
	zona.input_event.connect(_on_carpeta_click)
	_caja("TripodeCabeza", Vector3(0.22, 0.16, 0.18), Vector3(1.7, 1.35, -1.9), Color(0.05, 0.05, 0.05))
	_caja("TripodePata", Vector3(0.06, 1.3, 0.06), Vector3(1.7, 0.65, -1.9), Color(0.05, 0.05, 0.05))

	# Lampara
	_caja("Cable", Vector3(0.03, 0.7, 0.03), Vector3(0, 2.65, -0.3), Color(0.02, 0.02, 0.02))
	var pantalla := MeshInstance3D.new()
	pantalla.name = "Pantalla"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08; cyl.bottom_radius = 0.3; cyl.height = 0.25
	pantalla.mesh = cyl
	pantalla.position = Vector3(0, 2.2, -0.3)
	pantalla.material_override = _mat(Color(0.1, 0.1, 0.1), true)
	add_child(pantalla)
	lamp_mesh = MeshInstance3D.new()
	var bomb := SphereMesh.new(); bomb.radius = 0.06; bomb.height = 0.12
	lamp_mesh.mesh = bomb
	lamp_mesh.position = Vector3(0, 2.1, -0.3)
	lamp_mesh.material_override = _mat(Color(1, 0.9, 0.7), false, true, Color(1, 0.85, 0.55), 4.0)
	add_child(lamp_mesh)

	# LUZ PRINCIPAL: apuntada a la CARA del sospechoso (0, 1.5, -1.25), con sombra
	spot = SpotLight3D.new()
	spot.position = Vector3(0, 2.3, -0.55)
	spot.light_color = Color(1.0, 0.88, 0.66)
	spot.light_energy = base_energy
	spot.spot_range = 9.0
	spot.spot_angle = 42.0
	spot.shadow_enabled = true
	add_child(spot)
	spot.look_at(Vector3(0, 1.35, -1.25), Vector3.UP)
	# El rayo de luz ya no es una malla falsa: lo dibuja la niebla volumetrica real (ver Environment)
	# LUZ DE CARA: levanta el rostro sin matar la sombra (sin sombras, suave)
	face_light = SpotLight3D.new()
	face_light.position = Vector3(0, 1.35, 0.6)
	face_light.light_color = Color(1.0, 0.92, 0.78)
	face_light.light_energy = 1.6
	face_light.spot_range = 5.0
	face_light.spot_angle = 30.0
	face_light.shadow_enabled = false
	add_child(face_light)
	face_light.look_at(Vector3(0, 1.45, -1.25), Vector3.UP)
	# Relleno minimo
	fill = OmniLight3D.new()
	fill.position = Vector3(0, 1.5, 2.0)
	fill.light_color = Color(0.35, 0.4, 0.55)
	fill.light_energy = 0.25
	fill.omni_range = 6.0
	add_child(fill)
	# Contraluz frio detras del sospechoso: separa su silueta del fondo oscuro (look noir)
	var rim := SpotLight3D.new()
	rim.position = Vector3(0, 1.7, -2.3)
	rim.light_color = Color(0.45, 0.55, 0.75)
	rim.light_energy = 2.2
	rim.spot_range = 2.5
	rim.spot_angle = 35.0
	rim.shadow_enabled = false
	add_child(rim)
	rim.look_at(Vector3(0, 1.4, -1.25), Vector3.UP)
	# Reflejos reales del cuarto en el espejo/metal (probe estatico, barato)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 1.4, -0.6)
	probe.size = Vector3(5.6, 2.8, 4.6)
	probe.origin_offset = Vector3.ZERO
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

	_construir_sospechoso()

	# Camara primera persona + manos del detective
	cam = Camera3D.new()
	cam.position = cam_base
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 62.0
	get_viewport().physics_object_picking = true  # para clicar la carpeta de la mesa
	add_child(cam)
	cam.current = true
	# Profundidad de campo: la cara del sospechoso nitida, el fondo (espejo, paredes) suave
	var dof := CameraAttributesPractical.new()
	dof.dof_blur_far_enabled = true
	dof.dof_blur_far_distance = 2.6
	dof.dof_blur_far_transition = 1.5
	dof.dof_blur_amount = 0.15
	cam.attributes = dof
	var skin := _mat(Color(0.72, 0.56, 0.44), true)
	for lado in [-1, 1]:
		var mano := MeshInstance3D.new()
		mano.name = "ManoDetective"
		var mb := BoxMesh.new(); mb.size = Vector3(0.11, 0.05, 0.22)
		mano.mesh = mb
		mano.material_override = skin
		cam.add_child(mano)
		mano.position = Vector3(0.28 * lado, -0.28, -0.75)
		mano.rotation_degrees = Vector3(0, -8 * lado, 0)

	_construir_vignette()

## Vinieta + grano de pelicula como capa final de pantalla, sobre 3D y UI (look "camara de interrogatorio")
func _construir_vignette() -> void:
	var capa := CanvasLayer.new()
	capa.name = "Vignette"
	capa.layer = 10
	add_child(capa)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode blend_mul;

uniform float vignette_strength : hint_range(0.0, 2.0) = 0.85;
uniform float vignette_softness : hint_range(0.1, 2.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.028;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered * vec2(1.0, 0.75));
	float vig = smoothstep(0.75, 0.75 - vignette_softness, dist);
	float shade = mix(1.0 - vignette_strength, 1.0, vig);
	float grain = (rand(UV + fract(TIME)) - 0.5) * grain_amount;
	float v = clamp(shade + grain, 0.0, 1.0);
	COLOR = vec4(v, v, v, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	capa.add_child(rect)

func _construir_sospechoso() -> void:
	suspect_root = Node3D.new()
	suspect_root.name = "Sospechoso"
	suspect_root.position = Vector3(0, 0, -1.25)
	suspect_root.visible = _sospechoso_visible  # en menu la mesa esta vacia
	add_child(suspect_root)
	body_mat = _mat(Color(0.75, 0.28, 0.08), true)  # mono naranja preso
	body_mat.rim_enabled = true
	body_mat.rim = 0.25
	body_mat.rim_tint = 0.3
	head_mat = _mat(Color(0.76, 0.6, 0.48), true)
	# Fresnel de contraluz en la piel + un poco de traslucidez (subsurface) bajo la luz dura
	head_mat.rim_enabled = true
	head_mat.rim = 0.45
	head_mat.rim_tint = 0.6
	head_mat.subsurf_scatter_enabled = true
	head_mat.subsurf_scatter_strength = 0.35
	# Torso
	suspect_body = MeshInstance3D.new()
	var cap := CapsuleMesh.new(); cap.radius = 0.3; cap.height = 1.0
	suspect_body.mesh = cap
	suspect_body.position = Vector3(0, 0.85, 0)
	suspect_body.material_override = body_mat
	suspect_root.add_child(suspect_body)
	# Brazos hacia la mesa
	for lado in [-1, 1]:
		var brazo := MeshInstance3D.new()
		var ab := CapsuleMesh.new(); ab.radius = 0.08; ab.height = 0.62
		brazo.mesh = ab
		brazo.material_override = body_mat
		brazo.position = Vector3(0.3 * lado, 0.95, 0.3)
		brazo.rotation_degrees = Vector3(68, 0, -12 * lado)
		suspect_root.add_child(brazo)
		if lado < 0: arm_l = brazo
		else: arm_r = brazo
		# Manos SOBRE la mesa (y ~0.81 en mundo = 0.81 local porque root y=0)
		var mano := MeshInstance3D.new()
		var hb := SphereMesh.new(); hb.radius = 0.09; hb.height = 0.12
		mano.mesh = hb
		mano.scale = Vector3(1.0, 0.6, 1.3)
		mano.material_override = head_mat
		mano.position = Vector3(0.24 * lado, 0.82, 0.62)
		suspect_root.add_child(mano)
		if lado < 0: hand_l = mano
		else: hand_r = mano
	# Cabeza
	suspect_head = MeshInstance3D.new()
	var hs := SphereMesh.new(); hs.radius = 0.22; hs.height = 0.44
	suspect_head.mesh = hs
	suspect_head.position = Vector3(0, 1.52, 0.02)
	suspect_head.material_override = head_mat
	suspect_root.add_child(suspect_head)
	# Ojos (brillo bajo: se ven, no queman)
	for lado in [-1, 1]:
		var ojo := MeshInstance3D.new()
		var es := SphereMesh.new(); es.radius = 0.032; es.height = 0.064
		ojo.mesh = es
		ojo.position = Vector3(0.075 * lado, 1.55, 0.2)
		ojo.material_override = _mat(Color(0.95, 0.93, 0.8), false, true, Color(0.9, 0.85, 0.6), 0.7)
		suspect_root.add_child(ojo)
		if lado < 0: eye_l = ojo
		else: eye_r = ojo
		# Cejas = expresiones
		var ceja := MeshInstance3D.new()
		var cb := BoxMesh.new(); cb.size = Vector3(0.09, 0.02, 0.02)
		ceja.mesh = cb
		ceja.position = Vector3(0.075 * lado, 1.66, 0.2)
		ceja.material_override = _mat(Color(0.08, 0.06, 0.05), true)
		suspect_root.add_child(ceja)
		if lado < 0: brow_l = ceja
		else: brow_r = ceja
	# Boca (se abre al hablar)
	mouth = MeshInstance3D.new()
	var mm := BoxMesh.new(); mm.size = Vector3(0.1, 0.02, 0.02)
	mouth.mesh = mm
	mouth.position = Vector3(0, mouth_closed_y, 0.2)
	mouth.material_override = _mat(Color(0.25, 0.08, 0.08), true)
	suspect_root.add_child(mouth)
	# Sudor: 3 gotas en la frente (ocultas hasta que se pone nervioso)
	var sweat_mat := StandardMaterial3D.new()
	sweat_mat.albedo_color = Color(0.6, 0.8, 1.0, 0.85)
	sweat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sweat_mat.roughness = 0.1
	for i in 3:
		var g := MeshInstance3D.new()
		var gs := SphereMesh.new(); gs.radius = 0.018; gs.height = 0.036
		g.mesh = gs
		g.material_override = sweat_mat
		g.position = Vector3(-0.08 + 0.08 * i, 1.63, 0.19)
		g.visible = false
		suspect_root.add_child(g)
		sweat.append(g)
	# Silla
	var silla := MeshInstance3D.new()
	var sb := BoxMesh.new(); sb.size = Vector3(0.5, 0.5, 0.5)
	silla.mesh = sb
	silla.position = Vector3(0, 0.25, -0.25)
	silla.material_override = _mat(Color(0.08, 0.08, 0.08), true)
	suspect_root.add_child(silla)
	set_emotion("normal")

# ---- API para GameManager ----

func ocultar_sospechoso() -> void:
	_sospechoso_visible = false
	if suspect_root:
		suspect_root.visible = false

func mostrar_sospechoso() -> void:
	_sospechoso_visible = true
	if suspect_root:
		suspect_root.visible = true

## Intro cinematografica: la camara avanza hacia la mesa + destello de lampara
func play_intro() -> void:
	if cam == null:
		return
	_intro_activa = true
	cam.position = Vector3(0, 1.6, 1.7)
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_intro_tween.tween_property(cam, "position", cam_base, 4.0)
	_intro_tween.finished.connect(_fin_intro)
	base_energy = 14.0
	await get_tree().create_timer(0.6).timeout
	base_energy = 10.0

func _fin_intro() -> void:
	_intro_activa = false

func set_sombras(on: bool) -> void:
	if spot:
		spot.shadow_enabled = on

func _on_carpeta_click(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var g := get_tree().get_first_node_in_group("game")
			if g and g.has_method("abrir_carpeta"):
				g.abrir_carpeta()

func _hex(h: String, fb: Color) -> Color:
	var c := h.strip_edges()
	if not c.begins_with("#"):
		c = "#" + c
	if c.length() == 7 or c.length() == 9:
		return Color.html(c)
	return fb

## Aplica el diseño del avatar desde el JSON (data/sospechosos.json -> avatar).
## Puedes editar piel, ropa, tamaño de cabeza/cuerpo y color/tamaño de ojos sin tocar codigo.
func set_avatar(d: Dictionary) -> void:
	_avatar_pendiente = d
	if suspect_body == null or suspect_head == null or d.is_empty():
		return
	if d.has("ropa"):
		body_mat.albedo_color = _hex(str(d["ropa"]), body_mat.albedo_color)
	if d.has("piel"):
		head_mat.albedo_color = _hex(str(d["piel"]), head_mat.albedo_color)
	if d.has("cabeza"):
		var a: Array = d["cabeza"]
		if a.size() >= 3:
			suspect_head.scale = Vector3(float(a[0]), float(a[1]), float(a[2]))
	if d.has("cuerpo"):
		var b: Array = d["cuerpo"]
		if b.size() >= 3:
			suspect_body.scale = Vector3(float(b[0]), float(b[1]), float(b[2]))
	if hand_l:
		hand_l.material_override = head_mat
	if hand_r:
		hand_r.material_override = head_mat
	if d.has("ojos"):
		var ec := _hex(str(d["ojos"]), Color(1, 0.9, 0.2))
		for o in [eye_l, eye_r]:
			if o:
				var m := (o.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
				m.emission = ec
				o.material_override = m
	ojos_base = float(d.get("ojos_tam", 1.0))
	set_emotion(emotion)
	_cargar_modelo(str(d.get("modelo", "")), float(d.get("esc", 1.0)), float(d.get("my", 0.0)), float(d.get("rot", 0.0)))

func set_especie(id_o_especie: String) -> void:
	_especie_pendiente = id_o_especie
	if suspect_body == null or suspect_head == null:
		return
	_aplicar_especie(_especie_pendiente)

func _aplicar_especie(id_o_especie: String) -> void:
	var s := id_o_especie.to_lower()
	body_mat.albedo_color = Color(0.75, 0.28, 0.08)
	if "kthar" in s or "vex" in s:
		head_mat.albedo_color = Color(0.55, 0.62, 0.58)
		suspect_head.scale = Vector3(0.9, 1.3, 0.95)
		suspect_body.scale = Vector3(0.85, 1.0, 0.85)
	elif "molk" in s or "gruul" in s:
		head_mat.albedo_color = Color(0.42, 0.37, 0.32)
		suspect_head.scale = Vector3(1.3, 0.95, 1.25)
		suspect_body.scale = Vector3(1.5, 1.15, 1.3)
	else:
		head_mat.albedo_color = Color(0.76, 0.6, 0.48)
		suspect_head.scale = Vector3.ONE
		suspect_body.scale = Vector3.ONE
	if hand_l: hand_l.material_override = head_mat
	if hand_r: hand_r.material_override = head_mat

## Reacción a cada frase del jugador. Llamar desde GameManager.
## tipo: presion | evidencia | empatia | confrontar | minimizar | alternativa
func react(tipo: String) -> void:
	talk_timer = 1.6 + randf() * 1.2  # mueve la boca al responder
	match tipo:
		"presion", "confrontar":
			nervous = minf(1.0, nervous + 0.3)
			set_emotion("asustado" if nervous > 0.65 else "nervioso")
		"evidencia":
			nervous = minf(1.0, nervous + 0.4)
			set_emotion("asustado")
		"empatia":
			nervous = maxf(0.0, nervous - 0.25)
			set_emotion("triste" if nervous > 0.4 else "normal")
		"minimizar":
			nervous = maxf(0.0, nervous - 0.1)
			set_emotion("nervioso")
		"alternativa":
			nervous = minf(1.0, nervous + 0.15)
			set_emotion("nervioso")
		_:
			nervous = minf(1.0, nervous + 0.1)
			set_emotion("nervioso")

func set_emotion(e: String) -> void:
	emotion = e
	if brow_l == null:
		return
	var eb := Vector3.ONE * ojos_base
	match e:
		"normal":
			brow_l.rotation_degrees = Vector3(0, 0, 0)
			brow_r.rotation_degrees = Vector3(0, 0, 0)
			eye_l.scale = eb; eye_r.scale = eb
		"nervioso":
			brow_l.rotation_degrees = Vector3(0, 0, 12)
			brow_r.rotation_degrees = Vector3(0, 0, -12)
			eye_l.scale = eb * 1.15; eye_r.scale = eb * 1.15
		"asustado":
			brow_l.rotation_degrees = Vector3(0, 0, 22)
			brow_r.rotation_degrees = Vector3(0, 0, -22)
			eye_l.scale = eb * 1.4; eye_r.scale = eb * 1.4
		"triste":
			brow_l.rotation_degrees = Vector3(0, 0, -14)
			brow_r.rotation_degrees = Vector3(0, 0, 14)
			eye_l.scale = eb * 0.9; eye_r.scale = eb * 0.9
		"enojado":
			brow_l.rotation_degrees = Vector3(0, 0, -20)
			brow_r.rotation_degrees = Vector3(0, 0, 20)
			eye_l.scale = Vector3(eb.x * 0.85, eb.y * 0.7, eb.z * 0.85)
			eye_r.scale = Vector3(eb.x * 0.85, eb.y * 0.7, eb.z * 0.85)
	# Lenguaje corporal para los modelos Quaternius (sin rig facial)
	match e:
		"asustado":
			lean_x = -0.09  # se echa atras
		"triste":
			lean_x = 0.08  # cabeza gacha
		"enojado":
			lean_x = 0.12  # se te echa encima
		_:
			lean_x = 0.0

## Instancia el modelo Quaternius del caso y oculta el procedural.
## Si el modelo no carga, queda el procedural como respaldo.
func _cargar_modelo(path: String, esc: float, my: float, rot_y: float) -> void:
	if modelo_inst:
		modelo_inst.queue_free()
		modelo_inst = null
	_mostrar_procedural(true)
	if path == "" or not ResourceLoader.exists(path):
		return
	var ps := ResourceLoader.load(path) as PackedScene
	if ps == null:
		return
	modelo_inst = ps.instantiate() as Node3D
	if modelo_inst == null:
		return
	suspect_root.add_child(modelo_inst)
	modelo_inst.position = Vector3(0, my, 0.1)
	modelo_inst.rotation_degrees = Vector3(0, rot_y, 0)
	modelo_inst.scale = Vector3.ONE * esc
	modelo_base_y = my
	_mostrar_procedural(false)

func _mostrar_procedural(v: bool) -> void:
	for n in [suspect_body, suspect_head, arm_l, arm_r, hand_l, hand_r, eye_l, eye_r, brow_l, brow_r, mouth]:
		if n:
			(n as MeshInstance3D).visible = v
	for g in sweat:
		(g as MeshInstance3D).visible = false

## Carpeta estilo Phasmo: vuela de la mesa a tus manos y se abre ante la camara
func anim_carpeta_abrir() -> void:
	if carpeta_mesh == null or cam == null:
		return
	if carpeta_tween and carpeta_tween.is_valid():
		carpeta_tween.kill()
	if carpeta_home.is_empty():
		carpeta_home = {"pos": carpeta_mesh.position, "rot": carpeta_mesh.rotation, "scl": carpeta_mesh.scale}
	var fwd := -cam.global_transform.basis.z
	var dest: Vector3 = cam.global_position + fwd * 0.55 + Vector3(0, -0.02, 0)
	carpeta_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	carpeta_tween.tween_property(carpeta_mesh, "global_position", dest, 0.55)
	carpeta_tween.tween_property(carpeta_mesh, "rotation", Vector3(deg_to_rad(-70.0), 0, 0), 0.55)
	carpeta_tween.tween_property(carpeta_mesh, "scale", (carpeta_home["scl"] as Vector3) * 1.8, 0.55)

func anim_carpeta_cerrar() -> void:
	if carpeta_mesh == null or carpeta_home.is_empty():
		return
	if carpeta_tween and carpeta_tween.is_valid():
		carpeta_tween.kill()
	carpeta_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	carpeta_tween.tween_property(carpeta_mesh, "position", carpeta_home["pos"], 0.4)
	carpeta_tween.tween_property(carpeta_mesh, "rotation", carpeta_home["rot"], 0.4)
	carpeta_tween.tween_property(carpeta_mesh, "scale", carpeta_home["scl"], 0.4)

func _process(delta: float) -> void:
	t += delta
	var flick := 1.0
	var r := randf()
	if r < 0.03: flick = 0.5
	elif r < 0.06: flick = 0.7
	flick *= 1.0 + sin(t * 31.0) * 0.03 + sin(t * 7.3) * 0.04
	spot.light_energy = base_energy * flick
	var bm := lamp_mesh.material_override as StandardMaterial3D
	if bm: bm.emission_energy_multiplier = 4.0 * flick
	if talk_timer > 0: talk_timer -= delta
	# Boca: abierta/cerrada rapido mientras habla
	if mouth:
		if talk_timer > 0:
			var a := absf(sin(t * 18.0))
			mouth.scale = Vector3(1.0, 0.4 + a * 2.2, 1.0)
		else:
			mouth.scale = mouth.scale.lerp(Vector3.ONE, delta * 6.0)
	# Nerviosismo: temblor + manos que se mueven + sudor
	var amp := 0.01 + nervous * 0.05
	if suspect_root:
		suspect_root.rotation.y = sin(t * 0.7) * 0.06 + sin(t * 9.0) * amp * 0.4
		suspect_root.rotation.x = lerpf(suspect_root.rotation.x, lean_x, delta * 3.0)
		suspect_root.position.x = sin(t * 8.0) * amp * 0.35
		suspect_root.position.y = sin(t * 2.1) * 0.008
	# Modelo hablando: rebote sutil (no tiene boca riggeada)
	if modelo_inst and talk_timer > 0:
		modelo_inst.position.y = modelo_base_y + absf(sin(t * 14.0)) * 0.025
	if hand_l and hand_r:
		hand_l.position.x = -0.24 + sin(t * (3.0 + nervous * 8.0)) * amp * 0.5
		hand_r.position.x = 0.24 + sin(t * (3.0 + nervous * 8.0) + 1.5) * amp * 0.5
	for i in sweat.size():
		var g: MeshInstance3D = sweat[i]
		var hay_sudor := nervous > 0.35
		g.visible = hay_sudor
		if hay_sudor:
			g.position.y = 1.63 - fmod(t * (0.02 + nervous * 0.05) + i * 0.02, 0.08)
	if cam:
		if _intro_activa:
			pass # la intro mueve la camara por tween, no interferir
		elif sway:
			cam.position = cam_base + Vector3(sin(t * 0.5) * 0.02, sin(t * 0.8) * 0.015, 0)
