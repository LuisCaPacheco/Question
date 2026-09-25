extends Node3D
## INTERROGART - Vehl Iskaar, el ilvari (modelos/ilvari.glb, generado con
## herramientas/construir_ilvari.py). Lo crea Sospechoso.gd cuando rasgos.tipo == "ilvari"
## y cada frame le pasa su estado (emoción, inclinación, boca, nervios...) en animar().
## Huesos animados: columna/pecho (inclinación, respiración), cuello/cuello2/cabeza (mira a
## la cámara), mandíbula (habla), garganta (saco vocal que se infla al hablar), cejas
## (arco superciliar), brazos con IK para que las manos sigan apoyadas en la mesa, y dedos.

const ESCENA := "res://modelos/ilvari.glb"
const AgenteScript := preload("res://scripts/Agente.gd")
const Proc := preload("res://scripts/Proc.gd")
const MESA_Y := 0.795
const FLEX_REPOSO := [8.0, 16.0, 10.0]
const FLEX_MAX := [70.0, 95.0, 70.0]

## Piel translúcida: la luz atraviesa los bordes finos (BACKLIGHT) y un brillo húmedo
## que aumenta con los nervios.
const SHADER_PIEL := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D poros : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tinte : source_color = vec4(0.78, 0.8, 0.86, 1.0);
uniform vec4 luz_interior : source_color = vec4(0.25, 0.3, 0.6, 1.0);
uniform float translucidez = 0.22;
uniform float rug = 0.42;
uniform float humedad = 0.0;
uniform float poros_esc = 40.0;
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tinte.rgb;
	ALBEDO = c;
	AO = mix(1.0, texture(ao_tex, UV).r, 0.75);
	AO_LIGHT_AFFECT = 0.3;
	vec3 n1 = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 n2 = texture(poros, UV * poros_esc).rgb * 2.0 - 1.0;
	n1.xy += n2.xy * 0.18;
	NORMAL_MAP = normalize(n1) * 0.5 + 0.5;
	ROUGHNESS = clamp(mix(rug, 0.16, humedad), 0.08, 1.0);
	SPECULAR = 0.45;
	SSS_STRENGTH = 0.5;
	BACKLIGHT = luz_interior.rgb * translucidez;
	RIM = 0.12;
	RIM_TINT = 0.8;
}
"""

## Ojos negros enteros: casi espejo, con un reflejo iridiscente en el borde.
const SHADER_OJO := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform float brillo = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(0.004, 0.004, 0.006);
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.02;
	EMISSION = mix(vec3(0.05, 0.02, 0.12), vec3(0.02, 0.12, 0.16), f) * f * 0.35 * brillo;
}
"""

var sk: Skeleton3D
var modelo: Node3D
var B := {}
var t := 0.0
var _listo := false
var _mano_rest := {}           # lado (+1 izq. del ilvari = x>0, -1 = x<0) -> Transform3D
var _look := Quaternion.IDENTITY
var _off_mano := {1: Vector3.ZERO, -1: Vector3.ZERO}
var _curl := 0.15
var _tambor := -1.0
var _tambor_t := 2.5
var _mat_piel: Array = []
var _mat_ojo: ShaderMaterial
var _mat_lente: StandardMaterial3D

func _ready() -> void:
	var ps: PackedScene = load(ESCENA)
	if ps == null:
		push_error("No se encontró " + ESCENA)
		return
	modelo = ps.instantiate()
	add_child(modelo)
	sk = _buscar_skel(modelo)
	if sk == null:
		push_error("ilvari.glb sin esqueleto")
		return
	for i in sk.get_bone_count():
		B[sk.get_bone_name(i)] = i
	for lado in [1, -1]:
		_mano_rest[lado] = sk.get_bone_global_rest(_h("mano" + _suf(lado)))
	_materiales()
	_esposas()
	_listo = true

func _buscar_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _buscar_skel(c)
		if r:
			return r
	return null

func _h(nombre: String) -> int:
	return int(B.get(nombre, -1))

## x>0 es la mano izquierda del ilvari (mira hacia +Z).
func _suf(lado: int) -> String:
	return "_L" if lado > 0 else "_R"

# ------------------------------------------------------------------ materiales

func _materiales() -> void:
	var aux = AgenteScript.new()
	var poros: Texture2D = aux._ruido_normal(13, 0.11, 1.6)
	var piel_cara := _piel("ilv_cabeza", aux, poros)
	var piel_mano := _piel("ilv_mano_R", aux, poros)
	_mat_ojo = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_OJO
	_mat_ojo.shader = sh
	var tunica := StandardMaterial3D.new()
	tunica.albedo_texture = aux._tex("ilv_tunica_color.png")
	# bajo el foco cálido de la sala un gris oscuro parece crema: tinte azul noche
	tunica.albedo_color = Color(0.28, 0.34, 0.46)
	tunica.normal_enabled = true
	tunica.normal_texture = aux._tex("ilv_tunica_normal.png")
	tunica.roughness = 0.86
	tunica.rim_enabled = true
	tunica.rim = 0.2
	var collar := StandardMaterial3D.new()
	collar.albedo_color = Color(0.5, 0.52, 0.56)
	collar.metallic = 1.0
	collar.roughness = 0.32
	_mat_lente = StandardMaterial3D.new()
	_mat_lente.albedo_color = Color(0.1, 0.5, 0.7)
	_mat_lente.emission_enabled = true
	_mat_lente.emission = Color(0.3, 0.85, 1.0)
	_mat_lente.emission_energy_multiplier = 1.5
	aux.free()
	var por_nombre := {"piel": piel_mano, "piel_cara": piel_cara, "ojo": _mat_ojo, "tunica": tunica,
			"collar": collar, "lente": _mat_lente}
	for mi in sk.get_children():
		if not (mi is MeshInstance3D):
			continue
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var orig := m.mesh.surface_get_material(s)
			var nombre := orig.resource_name.get_slice(".", 0) if orig else ""
			if por_nombre.has(nombre):
				m.set_surface_override_material(s, por_nombre[nombre])

func _piel(prefijo: String, aux, poros: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_PIEL
	m.shader = sh
	m.set_shader_parameter("albedo_tex", aux._tex(prefijo + "_color.png"))
	m.set_shader_parameter("normal_tex", aux._tex(prefijo + "_normal.png"))
	var ao: Texture2D = aux._tex(prefijo + "_ao.png")
	if ao:
		m.set_shader_parameter("ao_tex", ao)
	m.set_shader_parameter("poros", poros)
	_mat_piel.append(m)
	return m

## Esposas en las muñecas (siguen al hueso de la mano) y cadena hasta la anilla de la mesa.
func _esposas() -> void:
	var metal := Proc.mat(Color(0.55, 0.56, 0.58), 0.28, 1.0)
	var anilla := Vector3(0, MESA_Y + 0.012, 0.52)
	Proc.malla(self, Proc.caja(Vector3(0.07, 0.006, 0.05)), Vector3(anilla.x, MESA_Y + 0.003, anilla.z), metal)
	Proc.malla(self, Proc.toro(0.012, 0.02), anilla, metal, Vector3(PI * 0.5, 0, 0))
	var eslabon := Proc.toro(0.005, 0.01, 12)
	for lado in [1, -1]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "mano" + _suf(lado)
		sk.add_child(ba)
		var esposa := Proc.malla(ba, Proc.toro(0.029, 0.04), Vector3(0, -0.028, -0.003), metal)
		esposa.scale = Vector3(1.0, 1.0, 0.78)
		# cadena (fija, desde la esposa en reposo)
		var w: Vector3 = to_local(sk.global_transform * (_mano_rest[lado] as Transform3D) * Vector3(0, -0.028, -0.012))
		var n := 9
		for k in n:
			var u := (k + 0.5) / n
			var p := w.lerp(anilla, u)
			p.y = maxf(MESA_Y + 0.008, p.y - sin(u * PI) * 0.012)
			var mi := Proc.malla(self, eslabon, p, metal)
			mi.basis = Proc.orient_y(anilla - w) * Basis(Vector3.UP, PI * 0.5 * (k % 2)) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.7))

# ------------------------------------------------------------------ animación

## Rotación extra q (en espacio del esqueleto) sobre la pose actual del padre.
func _girar(i: int, q: Quaternion) -> void:
	if i < 0:
		return
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var g := Basis(q) * (pg * sk.get_bone_rest(i).basis)
	sk.set_bone_pose_rotation(i, (pg.inverse() * g).orthonormalized().get_rotation_quaternion())

func _poner_global(i: int, bas: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var pg := sk.get_bone_global_pose(p).basis if p >= 0 else Basis()
	sk.set_bone_pose_rotation(i, (pg.inverse() * bas).orthonormalized().get_rotation_quaternion())

## s = el nodo Sospechoso (su estado ya suavizado).
func animar(s, delta: float) -> void:
	if not _listo:
		return
	t += delta
	var nerv: float = s.nervios
	var emo: String = s.emocion
	# --- tronco: inclinación hacia la mesa, sobresalto y respiración lenta y profunda
	var resp := sin(t * (0.9 + nerv * 1.8))
	var lean: float = s._lean * 0.55 - s._flinch * 0.22 + resp * 0.012
	_girar(_h("columna"), Quaternion(Vector3.RIGHT, lean * 0.45))
	_girar(_h("pecho"), Quaternion(Vector3.RIGHT, lean * 0.55) * Quaternion(Vector3.FORWARD, sin(t * 0.31) * 0.012))
	# --- cabeza: mira a la cámara (cuello largo: el giro se reparte en tres huesos)
	var ih := _h("cabeza")
	var inv := sk.global_transform.affine_inverse()
	var hp := sk.get_bone_global_pose(ih).origin
	var cam: Vector3 = inv * (s.camara_pos + s._mirada_off * 0.4)
	var d := (cam - hp).normalized()
	var yaw := clampf(atan2(d.x, d.z), -0.7, 0.7)
	var pitch := clampf(asin(clampf(-d.y, -1.0, 1.0)), -0.4, 0.5)
	var temblor := Vector2(sin(t * 31.0), cos(t * 27.0)) * nerv * nerv * 0.012
	var q_obj := Quaternion(Vector3.UP, yaw + temblor.x) \
			* Quaternion(Vector3.RIGHT, pitch + s._baja * 0.55 + temblor.y + sin(t * 0.5) * 0.02) \
			* Quaternion(Vector3.BACK, s._tilt + sin(t * 0.23) * 0.03)
	_look = _look.slerp(q_obj, 1.0 - exp(-delta * 2.6))
	_girar(_h("cuello"), Quaternion.IDENTITY.slerp(_look, 0.2))
	_girar(_h("cuello2"), Quaternion.IDENTITY.slerp(_look, 0.25))
	_poner_global(ih, Basis(_look) * sk.get_bone_global_rest(ih).basis)
	# --- mandíbula y saco vocal (canta en infrasonido: el saco vibra al hablar)
	var ij := _h("mandibula")
	if ij >= 0:
		var r := sk.get_bone_rest(ij).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(ij, r * Quaternion(Vector3.RIGHT, s._abre * 0.28))
	var ig := _h("garganta")
	if ig >= 0:
		var inf := 0.03 * resp
		if s.hablando > 0.0:
			inf += 0.22 + 0.16 * sin(t * 11.0) * sin(t * 3.7 + 1.0)
		inf += nerv * nerv * 0.08 * sin(t * 23.0)
		sk.set_bone_pose_scale(ig, Vector3.ONE * (1.0 + inf))
	# --- arco superciliar: baja con la ira, sube con el miedo
	for suf in ["_R", "_L"]:
		var ic := _h("ceja" + suf)
		if ic >= 0:
			var ro := sk.get_bone_rest(ic).origin
			sk.set_bone_pose_position(ic, ro + Vector3(0, -s._cejas * 0.0035, 0))
	# --- el traductor se ilumina al hablar
	if _mat_lente:
		_mat_lente.emission_energy_multiplier = (4.0 + sin(t * 30.0) * 1.5) if s.hablando > 0.0 else 0.8 + sin(t * 1.3) * 0.3
	for m in _mat_piel:
		(m as ShaderMaterial).set_shader_parameter("humedad", clampf(nerv * 1.1 - 0.3, 0.0, 0.8))
	# --- manos: apoyadas en la mesa; con miedo se retiran, con ira se cierran
	var retro := 0.0
	match emo:
		"asustado": retro = 0.05
		"nervioso": retro = 0.015
		"quebrado": retro = -0.03
	retro += s._flinch * 0.04
	for lado in [1, -1]:
		var obj := Vector3(0, 0.0, -retro)
		_off_mano[lado] = (_off_mano[lado] as Vector3).lerp(obj, 1.0 - exp(-delta * 4.0))
		var T: Transform3D = _mano_rest[lado]
		T.origin += _off_mano[lado] + Vector3(sin(t * 29.0 + lado), 0, cos(t * 23.0)) * nerv * nerv * 0.002
		_brazo(lado, T)
	var curl := 0.12
	match emo:
		"furioso": curl = 0.9
		"nervioso": curl = 0.3 + sin(t * 3.0) * 0.12
		"asustado": curl = 0.5
		"quebrado": curl = 0.22
	_curl = lerpf(_curl, curl, 1.0 - exp(-delta * 5.0))
	# tamborileo lento con los tres dedos de la mano derecha
	_tambor_t -= delta
	if _tambor_t <= 0.0 and _tambor < 0.0 and emo in ["calma", "burla", "nervioso"]:
		_tambor = 0.0
		_tambor_t = randf_range(2.5, 5.5) if emo != "nervioso" else randf_range(1.0, 2.0)
	var tap := [0.0, 0.0, 0.0]
	if _tambor >= 0.0:
		_tambor += delta / 0.6
		for f in 3:
			var local := _tambor * 4.0 - float(2 - f)
			tap[f] = sin(local * PI) if (local > 0.0 and local < 1.0) else 0.0
		if _tambor >= 1.0:
			_tambor = -1.0
	for lado in [1, -1]:
		_dedos(lado, _curl, tap if lado < 0 else [0.0, 0.0, 0.0], nerv * nerv)

func _arco(a: Vector3, b: Vector3) -> Basis:
	a = a.normalized()
	b = b.normalized()
	var dd := a.dot(b)
	if dd > 0.99999:
		return Basis()
	if dd < -0.99999:
		return Basis(a.cross(Vector3.UP).normalized(), PI)
	return Basis(Quaternion(a, b))

## IK de dos huesos (brazo + antebrazo) para llevar la muñeca a T (espacio del esqueleto).
func _brazo(lado: int, T: Transform3D) -> void:
	var s := _suf(lado)
	var i_cl := _h("clavicula" + s)
	var i_br := _h("brazo" + s)
	var i_ab := _h("antebrazo" + s)
	var i_ma := _h("mano" + s)
	if i_ma < 0:
		return
	var G_cl := sk.get_bone_global_pose(i_cl)
	var r_br := sk.get_bone_rest(i_br)
	var r_ab := sk.get_bone_rest(i_ab)
	var r_ma := sk.get_bone_rest(i_ma)
	var G_br0 := G_cl * r_br
	var G_ab0 := G_br0 * r_ab
	var G_ma0 := G_ab0 * r_ma
	var S := G_br0.origin
	var L1 := S.distance_to(G_ab0.origin)
	var L2 := G_ab0.origin.distance_to(G_ma0.origin)
	var dv := T.origin - S
	var dist := clampf(dv.length(), absf(L1 - L2) + 0.002, L1 + L2 - 0.002)
	var dir := dv.normalized()
	var W := S + dir * dist
	var a := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
	var hh := sqrt(maxf(L1 * L1 - a * a, 0.0))
	# el codo apunta hacia fuera y hacia abajo (apoyado en la mesa)
	var polo := Vector3(0.9 * lado, -0.55, -0.1)
	var pp := polo - dir * polo.dot(dir)
	if pp.length() < 0.001:
		pp = Vector3(lado, 0, 0)
	pp = pp.normalized()
	var E := S + dir * a + pp * hh
	var R1 := _arco(G_ab0.origin - S, E - S)
	var G_br := Transform3D(R1 * G_br0.basis, S)
	var G_ab1 := G_br * r_ab
	var R2 := _arco(R1 * (G_ma0.origin - G_ab0.origin), W - E)
	var G_ab := Transform3D(R2 * G_ab1.basis, E)
	sk.set_bone_pose_rotation(i_br, (G_cl.basis.inverse() * G_br.basis).orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_ab, (G_br.basis.inverse() * G_ab.basis).orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_ma, (G_ab.basis.inverse() * T.basis).orthonormalized().get_rotation_quaternion())

func _dedos(lado: int, c: float, tap: Array, temblor: float) -> void:
	var s := _suf(lado)
	for f in range(1, 4):
		var trem := sin(t * 23.0 + f * 1.7 + lado) * temblor * 0.06
		for k in 3:
			var i := _h("dedo%d_%d%s" % [f, k, s])
			if i < 0:
				continue
			var obj: float = clampf(c + trem, -0.15, 1.15) * FLEX_MAX[k]
			if k == 0:
				obj -= float(tap[f - 1]) * 28.0
			var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -deg_to_rad(obj - FLEX_REPOSO[k])))
	for k in 3:
		var i := _h("dedo0_%d%s" % [k, s])
		if i < 0:
			continue
		var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -deg_to_rad([20.0, 28.0, 36.0][k] * c)))
