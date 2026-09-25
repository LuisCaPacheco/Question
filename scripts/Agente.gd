extends Node3D
## INTERROGART - el agente (tú): cuerpo completo con traje y corbata (modelos/detective.glb,
## generado con herramientas/construir_detective.py). Las manos siguen a unos "objetivos"
## (Transform3D en mundo, mismo convenio que antes: muñeca en el origen, dorso +Y, dedos -Z)
## y los brazos se resuelven con IK de dos huesos, así los brazos siempre salen del cuerpo.

const ESCENA := "res://modelos/detective.glb"
const TEX := "res://modelos/tex/"
const CAPA_CABEZA := 2          # la cabeza y el pelo no los ve la cámara en primera persona
## Ejes del marco "mano" expresados en los ejes del hueso (Y a lo largo, Z dorso).
const K := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
const FLEX_REPOSO := [6.0, 14.0, 8.0]
const FLEX_MAX := [72.0, 96.0, 64.0]

const SHADER_PIEL := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D poros : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 tinte : source_color = vec4(1.0);
uniform float rug = 0.52;
uniform float ao_fuerza = 0.7;
uniform float poros_esc = 34.0;
uniform float poros_fuerza = 0.25;
uniform float sss = 0.35;
uniform float sudor = 0.0;
uniform float normal_fuerza = 1.0;
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tinte.rgb;
	float ao = mix(1.0, texture(ao_tex, UV).r, ao_fuerza);
	ALBEDO = c;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
	vec3 n1 = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 n2 = texture(poros, UV * poros_esc).rgb * 2.0 - 1.0;
	n1.xy = n1.xy * normal_fuerza + n2.xy * poros_fuerza;
	NORMAL_MAP = normalize(n1) * 0.5 + 0.5;
	float r = rug + (texture(poros, UV * poros_esc * 0.37).r - 0.5) * 0.12;
	ROUGHNESS = clamp(mix(r, 0.22, sudor), 0.08, 1.0);
	SPECULAR = 0.45;
	SSS_STRENGTH = sss;
	RIM = 0.12;
	RIM_TINT = 0.7;
}
"""

const SHADER_TELA := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 color : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform vec4 color2 : source_color = vec4(0.05, 0.05, 0.06, 1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D grano : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float usa_normal = 1.0;
uniform float trama = 90.0;
uniform float trama_fuerza = 0.35;
uniform float rug = 0.88;
uniform float brillo_borde = 0.45;
uniform float rayas = 0.0;
varying vec3 opos;
void vertex() { opos = VERTEX; }
void fragment() {
	float g = texture(grano, UV * 6.0).r;
	vec3 c = mix(color.rgb, color2.rgb, g);
	if (rayas > 0.0) {
		float s = fract((opos.x + opos.y) * rayas);
		c = mix(c, color2.rgb, smoothstep(0.42, 0.46, s) * smoothstep(0.62, 0.58, s));
	}
	ALBEDO = c * (0.9 + g * 0.2);
	vec3 n = usa_normal > 0.5 ? texture(normal_tex, UV).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
	vec2 t = UV * trama;
	vec2 w = vec2(sin(t.x * 6.2831 + sin(t.y * 3.14) * 0.5), sin(t.y * 6.2831 + sin(t.x * 3.14) * 0.5));
	n.xy += w * 0.04 * trama_fuerza;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
	ROUGHNESS = rug;
	SPECULAR = 0.25;
	RIM = brillo_borde;
	RIM_TINT = 0.3;
}
"""

var sk: Skeleton3D
var modelo: Node3D
var B := {}
## objetivos de las manos (mundo) por lado (+1 derecha, -1 izquierda)
var objetivo := {1: Transform3D(), -1: Transform3D()}
var curl := {1: 0.12, -1: 0.12}
var pulgar := {1: 0.15, -1: 0.15}
var tap := {1: [0.0, 0.0, 0.0, 0.0], -1: [0.0, 0.0, 0.0, 0.0]}
var temblor := 0.0
var inclinacion := 0.0        # el agente se inclina hacia la mesa (gestos)
var giro_cabeza := Vector2.ZERO
var mallas_cabeza: Array = []
var _t := 0.0
var _listo := false

func _ready() -> void:
	var ps: PackedScene = load(ESCENA)
	if ps == null:
		push_error("No se encontró " + ESCENA)
		return
	modelo = ps.instantiate()
	add_child(modelo)
	sk = _buscar_skel(modelo)
	if sk == null:
		push_error("detective.glb sin esqueleto")
		return
	for i in sk.get_bone_count():
		B[sk.get_bone_name(i)] = i
	_materiales()
	for lado in [1, -1]:
		objetivo[lado] = mano_reposo(lado)
	_listo = true

func _buscar_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _buscar_skel(c)
		if r:
			return r
	return null

func _hueso(nombre: String) -> int:
	return int(B.get(nombre, -1))

func _sufijo(lado: int) -> String:
	return "_R" if lado > 0 else "_L"

## Marco de la mano (mundo) en la pose de reposo del modelo.
func mano_reposo(lado: int) -> Transform3D:
	var i := _hueso("mano" + _sufijo(lado))
	if i < 0:
		return Transform3D()
	var g := sk.global_transform * sk.get_bone_global_rest(i)
	return Transform3D(g.basis * K, g.origin)

func hombro_global(lado: int) -> Vector3:
	var i := _hueso("brazo" + _sufijo(lado))
	return (sk.global_transform * sk.get_bone_global_pose(i)).origin

# ------------------------------------------------------------------ materiales

func _tex(nombre: String) -> Texture2D:
	var ruta := TEX + nombre
	if ResourceLoader.exists(ruta):
		return load(ruta)
	return null

func _ruido_normal(semilla: int, freq: float, fuerza: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = semilla
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.as_normal_map = true
	t.bump_strength = fuerza
	t.generate_mipmaps = true
	return t

func _ruido(semilla: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = semilla
	n.frequency = freq
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t

func mat_piel(prefijo: String, tinte := Color(1, 1, 1)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_PIEL
	m.shader = sh
	m.set_shader_parameter("albedo_tex", _tex(prefijo + "_color.png"))
	m.set_shader_parameter("normal_tex", _tex(prefijo + "_normal.png"))
	var ao := _tex(prefijo + "_ao.png")
	if ao:
		m.set_shader_parameter("ao_tex", ao)
	m.set_shader_parameter("poros", _ruido_normal(7, 0.09, 2.2))
	m.set_shader_parameter("tinte", tinte)
	return m

func mat_tela(color: Color, normal: String, rug := 0.88, color2 := Color(-1, 0, 0), trama := 90.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_TELA
	m.shader = sh
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("color2", color.lightened(0.08) if color2.r < 0 else color2)
	var t := _tex(normal)
	m.set_shader_parameter("normal_tex", t)
	m.set_shader_parameter("usa_normal", 1.0 if t else 0.0)
	m.set_shader_parameter("grano", _ruido(31, 0.06))
	m.set_shader_parameter("rug", rug)
	m.set_shader_parameter("trama", trama)
	return m

func _materiales() -> void:
	var piel := mat_piel("det_mano_R")
	var cara := mat_piel("det_cabeza")
	var unas := StandardMaterial3D.new()
	unas.albedo_color = Color(0.83, 0.66, 0.6)
	unas.roughness = 0.28
	unas.clearcoat_enabled = true
	unas.clearcoat = 0.4
	unas.subsurf_scatter_enabled = true
	unas.subsurf_scatter_strength = 0.2
	var chaqueta := mat_tela(Color(0.035, 0.036, 0.043), "det_chaqueta_normal.png", 0.9)
	var pantalon := mat_tela(Color(0.035, 0.036, 0.043), "det_pantalon_normal.png", 0.9)
	var camisa := mat_tela(Color(0.72, 0.72, 0.69), "det_camisa_normal.png", 0.8, Color(0.66, 0.67, 0.66), 140.0)
	var corbata := mat_tela(Color(0.2, 0.018, 0.025), "det_corbata_normal.png", 0.5, Color(0.36, 0.3, 0.12), 160.0)
	corbata.set_shader_parameter("rayas", 26.0)
	corbata.set_shader_parameter("brillo_borde", 0.25)
	var pelo := StandardMaterial3D.new()
	pelo.albedo_color = Color(0.03, 0.024, 0.02)
	pelo.roughness = 0.5
	pelo.normal_enabled = true
	pelo.normal_texture = _tex("det_pelo_normal.png")
	var zapatos := StandardMaterial3D.new()
	zapatos.albedo_color = Color(0.018, 0.014, 0.012)
	zapatos.roughness = 0.24
	zapatos.clearcoat_enabled = true
	var reloj := StandardMaterial3D.new()
	reloj.albedo_color = Color(0.62, 0.55, 0.4)
	reloj.metallic = 1.0
	reloj.roughness = 0.28
	var por_nombre := {"piel": piel, "piel_cara": cara, "unas": unas, "chaqueta": chaqueta, "pantalon": pantalon,
			"camisa": camisa, "corbata": corbata, "pelo": pelo, "zapatos": zapatos, "reloj": reloj}
	for mi in sk.get_children():
		if not (mi is MeshInstance3D):
			continue
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var orig := m.mesh.surface_get_material(s)
			var nombre := orig.resource_name.get_slice(".", 0) if orig else ""
			if por_nombre.has(nombre):
				m.set_surface_override_material(s, por_nombre[nombre])
		if m.name.begins_with("m_cabeza") or m.name.begins_with("m_pelo") or m.name == "cabeza" or m.name == "pelo":
			m.layers = CAPA_CABEZA
			mallas_cabeza.append(m)

# ------------------------------------------------------------------ IK

func _process(delta: float) -> void:
	if not _listo:
		return
	_t += delta
	var ip := _hueso("pecho")
	if ip >= 0:
		var r := sk.get_bone_rest(ip).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(ip, Quaternion(Vector3.RIGHT, -inclinacion * 0.12) * r)
	var ic := _hueso("cabeza")
	if ic >= 0:
		var rc := sk.get_bone_rest(ic).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(ic, rc * Quaternion(Vector3.RIGHT, giro_cabeza.y) * Quaternion(Vector3.FORWARD, giro_cabeza.x))
	for lado in [1, -1]:
		_brazo(lado)
		_dedos(lado)

func _arco(a: Vector3, b: Vector3) -> Basis:
	a = a.normalized()
	b = b.normalized()
	var d := a.dot(b)
	if d > 0.99999:
		return Basis()
	if d < -0.99999:
		var eje := a.cross(Vector3.UP)
		if eje.length() < 0.01:
			eje = a.cross(Vector3.RIGHT)
		return Basis(eje.normalized(), PI)
	return Basis(Quaternion(a, b))

func _brazo(lado: int) -> void:
	var s := _sufijo(lado)
	var i_cl := _hueso("clavicula" + s)
	var i_br := _hueso("brazo" + s)
	var i_ab := _hueso("antebrazo" + s)
	var i_ma := _hueso("mano" + s)
	if i_ma < 0:
		return
	var inv := sk.global_transform.affine_inverse()
	var T: Transform3D = inv * (objetivo[lado] as Transform3D)
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
	var W := T.origin
	var d := W - S
	var dist := clampf(d.length(), absf(L1 - L2) + 0.002, L1 + L2 - 0.002)
	var dir := d.normalized()
	W = S + dir * dist
	var a := (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(L1 * L1 - a * a, 0.0))
	# el codo apunta hacia fuera, abajo y un poco atras
	var polo := Vector3(0.95 * lado, -0.6, 0.35)
	var pp := polo - dir * polo.dot(dir)
	if pp.length() < 0.001:
		pp = Vector3(lado, 0, 0)
	pp = pp.normalized()
	var E := S + dir * a + pp * h
	# brazo
	var R1 := _arco(G_ab0.origin - S, E - S)
	var G_br := Transform3D(R1 * G_br0.basis, S)
	# antebrazo
	var G_ab1 := G_br * r_ab
	var R2 := _arco(R1 * (G_ma0.origin - G_ab0.origin), W - E)
	var bas_ab := R2 * G_ab1.basis
	# giro del antebrazo (pronación): acercar su "dorso" al dorso de la mano objetivo
	var eje := (W - E).normalized()
	var dorso_ab := bas_ab * (G_ab0.basis.inverse() * (G_ma0.basis * K).y)
	var dorso_obj := T.basis.y
	var v1 := (dorso_ab - eje * dorso_ab.dot(eje)).normalized()
	var v2 := (dorso_obj - eje * dorso_obj.dot(eje)).normalized()
	if v1.length() > 0.1 and v2.length() > 0.1:
		var ang := atan2(eje.dot(v1.cross(v2)), v1.dot(v2))
		bas_ab = Basis(eje, ang * 0.7) * bas_ab
	var G_ab := Transform3D(bas_ab, E)
	var bas_ma := (T.basis.orthonormalized() * K.inverse()).orthonormalized()
	sk.set_bone_pose_rotation(i_br, (G_cl.basis.inverse() * G_br.basis).orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_ab, (G_br.basis.inverse() * G_ab.basis).orthonormalized().get_rotation_quaternion())
	sk.set_bone_pose_rotation(i_ma, (G_ab.basis.inverse() * bas_ma).orthonormalized().get_rotation_quaternion())

func _dedos(lado: int) -> void:
	var s := _sufijo(lado)
	var c: float = curl[lado]
	var tp: Array = tap[lado]
	for f in range(1, 5):
		var extra := 1.25 if f == 4 else (1.1 if f == 3 else 1.0)
		var trem := sin(_t * 23.0 + f * 1.7) * temblor * 0.06
		for k in 3:
			var i := _hueso("dedo%d_%d%s" % [f, k, s])
			if i < 0:
				continue
			var reposo: float = FLEX_REPOSO[k] * (1.35 if f == 4 else 1.0)
			var obj: float = clampf(c + trem, -0.15, 1.15) * FLEX_MAX[k] * extra
			if k == 0:
				obj -= float(tp[f - 1]) * 30.0
			var delta_g := deg_to_rad(obj - reposo)
			var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -delta_g))
	var p: float = pulgar[lado]
	for k in 3:
		var i := _hueso("dedo0_%d%s" % [k, s])
		if i < 0:
			continue
		var ang := deg_to_rad([22.0, 30.0, 40.0][k] * (p - 0.15))
		var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -ang))
