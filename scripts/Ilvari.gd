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

## Ojos negros: casi espejo, con un reflejo iridiscente en el borde. La pupila es una
## rendija vertical sobre un iris muy oscuro: dilatada (pupila = 1) ocupa todo el ojo;
## estrecha (0.05) deja ver el iris. Los párpados son dobles: primero baja una membrana
## brillante y después la piel (cierre 0..1). Las coordenadas salen de la normal en
## espacio de vista (cada ojo es convexo, así que el centro es lo que mira a la cámara).
const SHADER_OJO := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform float brillo = 1.0;
uniform float pupila = 0.72;
uniform float cierre = 0.0;
uniform vec3 piel = vec3(0.42, 0.44, 0.5);
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec2 p = NORMAL.xy;
	float ancho = mix(0.06, 1.3, pupila);
	float e = length(vec2(p.x / ancho, p.y / 1.25));
	float pup = 1.0 - smoothstep(0.82, 1.0, e);
	float r = length(p);
	vec3 iris = mix(vec3(0.07, 0.02, 0.15), vec3(0.02, 0.17, 0.18), smoothstep(0.1, 0.75, r));
	iris *= 0.6 + 0.4 * sin(atan(p.y, p.x) * 34.0 + r * 9.0);
	vec3 col = mix(iris, vec3(0.004, 0.004, 0.006), pup);
	vec3 emi = iris * (1.0 - pup) * 0.45 + mix(vec3(0.05, 0.02, 0.12), vec3(0.02, 0.12, 0.16), f) * f * 0.35 * brillo;
	float rug = 0.04;
	float cc = 1.0;
	float borde_m = 1.1 - 2.3 * clamp(cierre * 1.35, 0.0, 1.0);
	float borde_p = 1.1 - 2.3 * clamp(cierre * 1.35 - 0.35, 0.0, 1.0);
	float mem = smoothstep(borde_m - 0.05, borde_m + 0.05, p.y);
	float lid = smoothstep(borde_p - 0.06, borde_p + 0.06, p.y);
	col = mix(col, vec3(0.5, 0.56, 0.66), mem * 0.85);
	emi = mix(emi, vec3(0.08, 0.1, 0.16) * (0.5 + f), mem);
	col = mix(col, piel, lid);
	emi = mix(emi, vec3(0.0), lid);
	rug = mix(mix(rug, 0.06, mem), 0.55, lid);
	cc = mix(cc, 0.0, lid);
	ALBEDO = col;
	ROUGHNESS = rug;
	SPECULAR = mix(0.9, 0.4, lid);
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = 0.02;
	EMISSION = emi;
}
"""

## Pupila de reposo según la emoción (1 = todo negro).
const PUPILA_EMO := {"calma": 0.72, "burla": 0.5, "nervioso": 0.6, "asustado": 0.97, "furioso": 0.32, "quebrado": 0.9, "triunfo": 0.45}
## Borde de la mesa del lado del ilvari (z local): por aquí pasa la cadena si las manos
## bajan de la mesa.
const BORDE_Z := 0.35

# ------------------------------------------------------------------ gestos (acotaciones)
## Cada acotación del guion ("Entrelaza los dedos", "Mira hacia la puerta"...) se convierte
## en uno o varios gestos. Un gesto es un diccionario de canales con la envolvente
## "e": [entra, se mantiene, sale] en segundos; puede ser una lista de partes, y cada parte
## puede empezar más tarde ("retraso"). Canales:
##   mirar: grabadora, puerta, espejo, reloj, pared, manos, mesa, mesa_cerca ("vel" = rapidez)
##   lean (inclinarse), yaw, pitch (bajar la cabeza), tilt (ladear), hombros (+ suben, - caen)
##   resp, resp_vel (respiración), abre (boca), aprieta (mandíbula), garganta (saco vocal),
##   vibra (vibración del canto), luz (la garganta se ilumina), sienes (- oscurecen, + aclaran),
##   lente (el traductor), cierre (párpados), pupila, fija (deja de apartar la vista),
##   temblor, temblor_manos, sin_tambor, grave (canto en infrasonido: sala y sonido)
##   manos / mano_d / mano_i: pose (centro, planas, palmas, boca, pecho, cruzados, bajo_mesa,
##   arriba, adelante, atras, tira, grabadora); curl (dedos), dedos_d: "senala"
##   ev: [[segundo, efecto, fuerza]]: cadena, golpe, pitido, chirrido, camara_reloj
##   curva: "pulso" = sube y baja una sola vez (asentir, respirar hondo)
const GESTOS := {
	# --- mirada
	"mira_grabadora": {"mirar": "grabadora", "e": [0.35, 1.6, 0.5]},
	"mira_grabadora_larga": {"mirar": "grabadora", "fija": 1.0, "e": [0.4, 3.2, 0.7]},
	"mira_puerta": {"mirar": "puerta", "vel": 10.0, "e": [0.15, 0.45, 0.3]},
	"mira_espejo": [{"mirar": "espejo", "e": [0.5, 1.4, 0.6]}, {"fija": 1.0, "pupila": 0.95, "e": [0.3, 2.5, 0.6], "retraso": 2.0}],
	"mira_reloj": {"mirar": "reloj", "e": [0.5, 2.2, 0.7], "ev": [[0.5, "camara_reloj", 1.0]]},
	"aparta_mirada": {"mirar": "pared", "tilt": -0.06, "e": [0.6, 3.5, 0.9]},
	"mira_manos": {"mirar": "manos", "hombros": 0.25, "e": [0.7, 3.2, 0.9]},
	"mira_mesa": {"mirar": "mesa", "e": [0.7, 3.5, 0.9]},
	"mira_cifra": [{"mirar": "mesa", "e": [0.5, 4.5, 1.0]}, {"temblor": 1.0, "temblor_manos": 1.0, "e": [1.2, 2.5, 1.5], "retraso": 2.2, "ev": [[1.0, "cadena", 0.35], [2.2, "cadena", 0.45]]}],
	"lee_reves": {"mirar": "mesa_cerca", "tilt": 0.5, "lean": 0.16, "e": [0.6, 2.2, 0.7]},
	"fija": {"fija": 1.0, "e": [0.3, 4.0, 0.8]},
	"estudia": {"fija": 1.0, "tilt": 0.16, "lean": 0.08, "pupila": 0.3, "e": [1.0, 3.0, 1.0]},
	"tarda_mirar": [{"mirar": "mesa", "e": [0.3, 1.2, 0.8]}, {"fija": 1.0, "pupila": 0.95, "e": [0.5, 3.0, 0.8], "retraso": 1.4}],
	# --- cabeza y cara
	"ladea": {"tilt": 0.42, "e": [1.2, 2.5, 1.2]},
	"asiente": {"pitch": 0.3, "curva": "pulso", "e": [0.0, 1.1, 0.0]},
	"asiente_grabadora": [{"mirar": "grabadora", "e": [0.4, 2.2, 0.6]}, {"pitch": 0.25, "curva": "pulso", "e": [0.0, 0.9, 0.0], "retraso": 0.7}],
	"levanta_vista": {"pitch": -0.14, "hombros": -0.35, "lean": -0.05, "fija": 1.0, "e": [0.8, 3.0, 1.0]},
	"sonrisa": {"abre": 0.2, "tilt": 0.2, "garganta": 0.1, "pupila": 0.4, "e": [0.4, 1.8, 0.6]},
	"aprieta_mandibula": {"aprieta": 1.0, "temblor": 0.2, "garganta": -0.06, "e": [0.15, 2.5, 0.8]},
	"cierra_ojos": {"cierre": 1.0, "e": [0.9, 2.0, 0.6]},
	"pupilas_raya": {"pupila": 0.05, "e": [0.25, 4.0, 1.5]},
	"pupilas_llenas": {"pupila": 1.0, "e": [0.8, 4.0, 1.5]},
	"sienes_oscuras": {"sienes": -1.0, "e": [1.5, 5.0, 2.0]},
	"sienes_claras": {"sienes": 1.0, "e": [1.5, 5.0, 2.0]},
	"cuello_tensa": {"garganta": -0.2, "pitch": -0.08, "hombros": 0.15, "e": [0.4, 3.0, 1.0]},
	"garganta_luz": {"luz": 1.0, "vibra": 0.4, "e": [0.12, 0.7, 1.2]},
	"baja_voz": {"lean": 0.1, "pitch": 0.12, "garganta": -0.08, "e": [0.6, 3.0, 1.0]},
	"voz_grave": {"vibra": 0.5, "garganta": 0.15, "e": [0.3, 3.0, 1.0]},
	"pausa": {"fija": 1.0, "resp": -0.6, "e": [0.3, 2.0, 0.8]},
	# --- respiración y traductor
	"respira_hondo": {"lean": -0.08, "hombros": 0.45, "garganta": 0.3, "curva": "pulso", "e": [0.0, 3.2, 0.0]},
	"respira_rapido": {"resp": 1.5, "resp_vel": 3.0, "e": [0.5, 4.0, 1.5]},
	"collar_zumba": {"lente": 0.8, "e": [0.3, 2.0, 0.8]},
	"collar_pitido": {"lente": 1.0, "e": [0.05, 0.25, 0.2], "ev": [[0.05, "pitido", 1.0]]},
	"collar_chirrido": {"lente": 1.0, "e": [0.05, 0.5, 0.3], "ev": [[0.05, "chirrido", 1.0]]},
	"grave": {"grave": 1.0, "vibra": 1.0, "abre": 0.12, "luz": 0.35, "e": [1.2, 6.0, 2.5]},
	"grave_apaga": {"grave": 1.0, "vibra": 1.0, "e": [0.0, 0.3, 3.5]},
	# --- cuerpo
	"endereza": {"lean": -0.12, "pitch": -0.06, "hombros": -0.15, "e": [0.8, 4.0, 1.2]},
	"habla_grabadora": [{"mirar": "grabadora", "fija": 1.0, "e": [0.6, 6.0, 1.0]}, {"lean": -0.1, "hombros": -0.15, "e": [0.8, 6.0, 1.2]}],
	"inclina": {"lean": 0.42, "e": [0.7, 3.5, 1.0]},
	"echa_atras": {"lean": -0.28, "e": [0.8, 4.0, 1.0]},
	"cruza_brazos": {"lean": -0.25, "manos": "cruzados", "curl": 0.3, "e": [0.9, 4.0, 1.2], "ev": [[0.25, "cadena", 0.35]]},
	"dobla": {"lean": 0.55, "pitch": 0.5, "hombros": 0.4, "manos": "centro", "curl": 0.5, "e": [1.0, 3.5, 1.5]},
	"encoge": [{"lean": -0.3, "hombros": 0.7, "pitch": 0.25, "e": [0.12, 0.6, 1.4]}, {"temblor": 0.6, "e": [0.1, 1.2, 1.0]}],
	"hombros_bajan": {"hombros": -0.55, "lean": 0.06, "e": [1.2, 4.0, 1.5]},
	"rinde": {"hombros": -0.7, "lean": 0.12, "pitch": 0.15, "e": [1.5, 4.0, 2.0]},
	"rigido": {"lean": -0.05, "pitch": -0.04, "fija": 1.0, "manos": "planas", "curl": -0.12, "resp": -0.7, "sin_tambor": 1.0, "e": [0.6, 5.0, 1.0]},
	"tiembla": {"temblor": 1.0, "temblor_manos": 1.0, "e": [1.0, 3.0, 1.5], "ev": [[1.0, "cadena", 0.4], [2.2, "cadena", 0.5], [3.4, "cadena", 0.4]]},
	"abraza_pecho": {"manos": "pecho", "curl": 0.35, "hombros": 0.35, "lean": 0.08, "e": [1.0, 3.5, 1.3], "ev": [[0.3, "cadena", 0.45]]},
	# --- manos
	"entrelaza": {"manos": "centro", "curl": 0.62, "e": [0.8, 4.0, 1.0], "ev": [[0.5, "cadena", 0.4], [0.9, "cadena", 0.25]]},
	"enrosca_dedos": {"manos": "centro", "curl": 1.0, "temblor_manos": 0.35, "e": [1.2, 4.0, 1.2]},
	"deja_tamborilear": {"curl": 0.05, "sin_tambor": 1.0, "e": [0.2, 4.0, 0.5]},
	"planas": {"manos": "planas", "curl": -0.12, "sin_tambor": 1.0, "e": [0.6, 4.0, 1.0]},
	"palmas_arriba": {"manos": "palmas", "curl": -0.05, "sin_tambor": 1.0, "e": [1.0, 3.5, 1.2], "ev": [[0.4, "cadena", 0.3]]},
	"arana_mesa": {"manos": "atras", "curl": 0.75, "temblor_manos": 0.2, "e": [2.4, 1.0, 1.0]},
	"puno": {"curl": 1.1, "manos": "tira", "e": [0.07, 2.5, 1.0], "ev": [[0.06, "cadena", 0.8]]},
	"tapa_boca": {"mano_d": "boca", "curl": 0.2, "hombros": 0.3, "e": [0.8, 3.0, 1.2], "ev": [[0.3, "cadena", 0.5]]},
	"senala_grabadora": {"mano_d": "grabadora", "dedos_d": "senala", "temblor_manos": 0.6, "mirar": "grabadora", "e": [0.7, 2.6, 0.9], "ev": [[0.3, "cadena", 0.35]]},
	"toca_papel": {"mano_d": "adelante", "dedos_d": "senala", "mirar": "mesa", "e": [1.6, 2.0, 1.2]},
	"esconde_manos": {"manos": "bajo_mesa", "e": [1.0, 60.0, 2.2], "ev": [[0.3, "cadena", 0.5]]},
	"vuelve_manos": {"manos": "bajo_mesa", "e": [0.4, 0.2, 2.2], "ev": [[1.8, "cadena", 0.3]]},
	"manos_tiemblan": {"temblor_manos": 1.0, "curl": 0.4, "e": [0.6, 3.5, 1.2], "ev": [[0.4, "cadena", 0.3], [0.8, "cadena", 0.25], [1.2, "cadena", 0.35], [1.7, "cadena", 0.25], [2.1, "cadena", 0.3], [2.6, "cadena", 0.25], [3.1, "cadena", 0.3]]},
	"golpe_mesa": [
		{"mano_d": "arriba", "curl": -0.1, "e": [0.28, 0.0, 0.08]},
		{"curl": -0.1, "sin_tambor": 1.0, "e": [0.3, 0.8, 0.6]},
		{"lean": 0.12, "e": [0.3, 0.5, 0.8], "ev": [[0.36, "golpe", 0.8], [0.38, "cadena", 1.0]]},
	],
}

## Canales que se suman (valor x peso) y canales en los que gana el gesto más fuerte.
const SUMA := ["lean", "yaw", "pitch", "tilt", "hombros", "resp", "resp_vel", "garganta", "vibra", "luz",
		"sienes", "lente", "temblor", "temblor_manos", "grave", "cierre"]
const MAXIMO := ["mirar", "vel", "abre", "aprieta", "pupila", "fija", "sin_tambor", "curl", "manos",
		"mano_d", "mano_i", "dedos_d"]

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
var _mat_cara: ShaderMaterial
var _tinte_cara := Color(0.78, 0.8, 0.86)
var _luz: OmniLight3D           # dentro de la garganta (se ilumina con el canto)
var _pupila := 0.72
var _eslabones := {1: [], -1: []}
var _anilla := Vector3.ZERO
var _cadena_len := {1: 0.4, -1: 0.4}
var _cadena_salto := 0.0
# gestos
var sala := {}                 # puntos de la sala (mundo) que puede mirar; los pone Room3D
var sala_efecto: Callable      # Room3D: golpe, cadena, grave, pitido, chirrido, camara_reloj
var _activos: Array = []       # {g, t, soltar, w0, tr, hechos}
var _G := {}                   # canales sumados en este frame
var _M := {}                   # canal -> [peso, valor] del gesto más fuerte
var _grave_env := 0.0

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
	var ig := _h("garganta")
	if ig >= 0:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "garganta"
		sk.add_child(ba)
		_luz = OmniLight3D.new()
		_luz.light_color = Color(0.36, 0.72, 0.95)
		_luz.omni_range = 0.24
		_luz.light_energy = 0.0
		_luz.shadow_enabled = false
		ba.add_child(_luz)
	_canales()
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
	_mat_cara = piel_cara
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
## La cadena se recoloca cada frame (_cadenas_update): sigue a las manos, pasa por el borde
## de la mesa si las esconde y salta cuando golpea.
func _esposas() -> void:
	var metal := Proc.mat(Color(0.55, 0.56, 0.58), 0.28, 1.0)
	_anilla = Vector3(0, MESA_Y + 0.012, 0.52)
	Proc.malla(self, Proc.caja(Vector3(0.07, 0.006, 0.05)), Vector3(_anilla.x, MESA_Y + 0.003, _anilla.z), metal)
	Proc.malla(self, Proc.toro(0.012, 0.02), _anilla, metal, Vector3(PI * 0.5, 0, 0))
	var eslabon := Proc.toro(0.005, 0.01, 12)
	for lado in [1, -1]:
		var ba := BoneAttachment3D.new()
		ba.bone_name = "mano" + _suf(lado)
		sk.add_child(ba)
		var esposa := Proc.malla(ba, Proc.toro(0.029, 0.04), Vector3(0, -0.028, -0.003), metal)
		esposa.scale = Vector3(1.0, 1.0, 0.78)
		var w: Vector3 = to_local(sk.global_transform * (_mano_rest[lado] as Transform3D) * Vector3(0, -0.028, -0.012))
		_cadena_len[lado] = w.distance_to(_anilla) * 1.25 + 0.04
		var lista: Array = []
		for k in 9:
			lista.append(Proc.malla(self, eslabon, w.lerp(_anilla, (k + 0.5) / 9.0), metal))
		_eslabones[lado] = lista

func _muneca(lado: int) -> Vector3:
	return to_local(sk.global_transform * sk.get_bone_global_pose(_h("mano" + _suf(lado))) * Vector3(0, -0.028, -0.012))

func _en_polilinea(pts: Array, largos: Array, total: float, u: float) -> Vector3:
	var d := clampf(u, 0.0, 1.0) * total
	for k in largos.size():
		var l: float = largos[k]
		if d <= l or k == largos.size() - 1:
			return (pts[k] as Vector3).lerp(pts[k + 1], clampf(d / maxf(l, 0.0001), 0.0, 1.0))
		d -= l
	return pts[pts.size() - 1]

func _cadenas_update(delta: float) -> void:
	_cadena_salto = move_toward(_cadena_salto, 0.0, delta * 2.5)
	var tm: float = _G.get("temblor_manos", 0.0) + _G.get("temblor", 0.0) * 0.5
	for lado in [1, -1]:
		var w := _muneca(lado)
		var pts: Array = [w]
		if w.y < MESA_Y - 0.01 or w.z < BORDE_Z - 0.02:
			pts.append(Vector3(w.x * 0.85, MESA_Y + 0.006, BORDE_Z))
		pts.append(_anilla)
		var largos: Array = []
		var total := 0.0
		for k in pts.size() - 1:
			var l := (pts[k] as Vector3).distance_to(pts[k + 1])
			largos.append(l)
			total += l
		var holgura := maxf(0.0, float(_cadena_len[lado]) - total)
		var lista: Array = _eslabones[lado]
		var n := lista.size()
		for k in n:
			var u := (k + 0.5) / n
			var p := _en_polilinea(pts, largos, total, u)
			var sig := _en_polilinea(pts, largos, total, u + 0.5 / n) - _en_polilinea(pts, largos, total, u - 0.5 / n)
			var arco := sin(u * PI)
			p.y -= arco * minf(holgura * 0.45, 0.05)
			p.y += arco * _cadena_salto * 0.035 * (0.6 + 0.4 * sin(t * 43.0 + k * 1.7))
			p += Vector3(sin(t * 37.0 + k), 0.0, cos(t * 29.0 + k * 2.0)) * tm * 0.003
			if p.z > BORDE_Z - 0.005 and absf(p.x) < 0.75:
				p.y = maxf(MESA_Y + 0.008, p.y)
			var mi: MeshInstance3D = lista[k]
			mi.position = p
			mi.basis = Proc.orient_y(sig if sig.length() > 0.0001 else Vector3.FORWARD) * Basis(Vector3.UP, PI * 0.5 * (k % 2)) \
					* Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.7))

# ------------------------------------------------------------------ motor de gestos

## Empieza los gestos de una acotación. Lo que estaba haciendo se suelta poco a poco.
func gestos(ids: Array) -> void:
	for a in _activos:
		if not a.soltar:
			a.soltar = true
			a.w0 = _peso(a)
			a.tr = 0.0
	for id in ids:
		var def = GESTOS.get(str(id))
		if def == null:
			push_warning("Ilvari: gesto desconocido '%s'" % id)
			continue
		var partes: Array = def if def is Array else [def]
		for g in partes:
			_activos.append({"g": g, "t": -float(g.get("retraso", 0.0)), "soltar": false, "w0": 0.0, "tr": 0.0, "hechos": {}})

## Gestos que se deducen del texto de la acotación (para casos sin lista "gestos").
func inferir(texto: String) -> Array:
	var s := texto.to_lower()
	var out: Array = []
	var reglas := [
		["grabadora", "mira_grabadora"], ["puerta", "mira_puerta"], ["espejo", "mira_espejo"], ["reloj", "mira_reloj"],
		["aparta la mirada", "aparta_mirada"], ["asiente", "asiente"], ["ladea", "ladea"], ["entrelaza", "entrelaza"],
		["tamborilea", "deja_tamborilear"], ["golpea", "golpe_mesa"], ["tiembla", "tiembla"], ["mandíbula", "aprieta_mandibula"],
		["cierra los ojos", "cierra_ojos"], ["boca", "tapa_boca"], ["abraza", "abraza_pecho"], ["cruza", "cruza_brazos"],
		["inclina", "inclina"], ["endereza", "endereza"], ["hombros", "hombros_bajan"], ["respira hondo", "respira_hondo"],
		["pupilas se estrechan", "pupilas_raya"], ["pupilas se abren", "pupilas_llenas"], ["grave", "grave"],
		["pitido", "collar_pitido"], ["chirrido", "collar_chirrido"], ["sus manos", "mira_manos"], ["se dobla", "dobla"],
		["se encoge", "encoge"],
	]
	for r in reglas:
		if s.contains(r[0]) and not out.has(r[1]):
			out.append(r[1])
	return out

func _peso(a: Dictionary) -> float:
	var g: Dictionary = a.g
	var e: Array = g.get("e", [0.3, 1.0, 0.5])
	var at := float(e[0])
	var ho := float(e[1])
	var re := float(e[2])
	var tt: float = a.t
	var w := 0.0
	if tt < 0.0:
		w = 0.0
	elif str(g.get("curva", "")) == "pulso":
		w = sin(PI * clampf(tt / maxf(at + ho + re, 0.01), 0.0, 1.0))
	elif tt < at:
		w = smoothstep(0.0, at, tt)
	elif tt < at + ho:
		w = 1.0
	else:
		w = 1.0 - smoothstep(0.0, maxf(re, 0.001), tt - at - ho)
	if a.soltar:
		w = minf(w, float(a.w0) * (1.0 - smoothstep(0.0, maxf(re, 0.3), float(a.tr))))
	return w

## Avanza los gestos, dispara sus efectos y suma los canales en _G / _M.
func _canales(delta := 0.0) -> void:
	var G := {}
	for k in SUMA:
		G[k] = 0.0
	var M := {}
	var vivos: Array = []
	for a in _activos:
		a.t += delta
		if a.soltar:
			a.tr += delta
		var g: Dictionary = a.g
		var e: Array = g.get("e", [0.3, 1.0, 0.5])
		var total := float(e[0]) + float(e[1]) + float(e[2])
		var fin: bool = (a.soltar and a.tr > maxf(float(e[2]), 0.3)) or a.t > total
		# efectos puntuales (solo si el gesto sigue en marcha)
		if not a.soltar:
			for ev in g.get("ev", []):
				var clave := str(ev[0]) + str(ev[1])
				if a.t >= float(ev[0]) and not a.hechos.has(clave):
					a.hechos[clave] = true
					_efecto(str(ev[1]), float(ev[2]))
		if fin:
			continue
		vivos.append(a)
		var w := _peso(a)
		if w <= 0.0:
			continue
		for k in SUMA:
			if g.has(k):
				G[k] += float(g[k]) * w
		for k in MAXIMO:
			if g.has(k) and w > float((M.get(k, [0.0, null]) as Array)[0]):
				M[k] = [w, g[k]]
	_activos = vivos
	_G = G
	_M = M

## [peso, valor] del gesto más fuerte en un canal de tipo MAXIMO.
func _m(k: String) -> Array:
	return _M.get(k, [0.0, null])

func _efecto(tipo: String, fuerza: float) -> void:
	if tipo == "golpe":
		_cadena_salto = 1.0
	elif tipo == "cadena":
		_cadena_salto = maxf(_cadena_salto, fuerza * 0.45)
	if sala_efecto.is_valid():
		sala_efecto.call(tipo, fuerza)

## Punto (en mundo) al que mira un gesto.
func _punto(nombre: String, s) -> Vector3:
	match nombre:
		"manos":
			var c := (_muneca(1) + _muneca(-1)) * 0.5
			return to_global(c + Vector3(0, 0.0, 0.05))
		"mesa":
			return to_global(Vector3(0, MESA_Y, 0.62))
	return sala.get(nombre, s.camara_pos)

## Pose de la mano (espacio del esqueleto) para cada nombre de gesto.
func _pose_mano(nombre: String, lado: int) -> Transform3D:
	var R: Transform3D = _mano_rest[lado]
	match nombre:
		"centro":
			R.origin.x = lado * 0.05
			R.origin += Vector3(0, 0.012, 0.03)
			R.basis = Basis(Vector3.UP, -lado * 0.55) * R.basis
		"planas":
			R.origin.x *= 1.12
		"palmas":
			R.origin.y += 0.035
			R.basis = Basis(Vector3.BACK, lado * 2.9) * R.basis
		"boca":
			# la palma sobre la boca y los dedos (larguísimos) cruzando la cara en diagonal
			var dd := Vector3(-lado * 0.55, 0.83, 0.05)
			R = _en_hueso("cabeza", Transform3D(_base_mano(dd, Vector3(0, 0, 1)), Vector3(0, 1.27, 0.2) - dd.normalized() * 0.1))
		"pecho":
			# se abraza: cada mano sobre el hombro contrario, los dedos por encima hacia la espalda
			var dd := Vector3(-lado * 0.55, 0.55, -0.62)
			var z := 0.15 if lado > 0 else 0.12
			R = _en_hueso("pecho", Transform3D(_base_mano(dd, Vector3(-lado * 0.3, 0.3, 1)), Vector3(-lado * 0.07, 0.98 + lado * 0.01, z)))
		"cruzados":
			# antebrazos cruzados a media altura (el izquierdo por delante) y las manos metidas
			# bajo el brazo contrario, con los dedos hacia la espalda
			var dd := Vector3(-lado * 0.35, 0.05, -0.93)
			var z := 0.2 if lado > 0 else 0.16
			R = _en_hueso("pecho", Transform3D(_base_mano(dd, Vector3(-lado, 0.2, 0)), Vector3(-lado * 0.17, 0.93 + lado * 0.015, z)))
		"bajo_mesa":
			R.origin += Vector3(lado * 0.02, -0.2, -0.32)
		"arriba":
			R.origin += Vector3(0, 0.2, -0.03)
			R.basis = Basis(Vector3.RIGHT, 0.35) * R.basis
		"adelante":
			R.origin += Vector3(-lado * 0.04, 0.0, 0.16)
		"atras":
			R.origin += Vector3(0, 0, -0.07)
		"tira":
			R.origin += Vector3(0, 0.006, -0.035)
		"grabadora":
			var gl: Vector3 = sala.get("grabadora", Vector3.ZERO)
			var g := sk.global_transform.affine_inverse() * gl
			var dv := g - R.origin
			dv.y = 0.0
			if dv.length() > 0.001:
				R.origin += dv.normalized() * 0.1 + Vector3(0, 0.09, 0)
				R.basis = Basis(Vector3.UP, atan2(dv.x, dv.z)) * Basis(Vector3.RIGHT, -0.25) * R.basis
	return R

## Base del hueso de la mano: su eje Y va a lo largo de los dedos y el Z sale por el dorso.
func _base_mano(dedos: Vector3, dorso: Vector3) -> Basis:
	var y := dedos.normalized()
	var z := (dorso - y * dorso.dot(y)).normalized()
	return Basis(y.cross(z), y, z)

## Una pose escrita en coordenadas de reposo (espacio del esqueleto) que sigue al hueso:
## si el pecho se inclina o la cabeza gira, la mano va con ellos.
func _en_hueso(hueso: String, T: Transform3D) -> Transform3D:
	var i := _h(hueso)
	return sk.get_bone_global_pose(i) * sk.get_bone_global_rest(i).affine_inverse() * T
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
	_canales(delta)
	var G := _G
	var nerv: float = s.nervios
	var emo: String = s.emocion
	var mira: Array = _m("mirar")
	var wm: float = mira[0]
	var fija: float = _m("fija")[0]
	var temb_cuerpo: float = G.temblor
	# --- tronco: inclinación hacia la mesa, sobresalto y respiración lenta y profunda
	var resp := sin(t * (0.9 + nerv * 1.8) * (1.0 + G.resp_vel)) * maxf(0.1, 1.0 + G.resp)
	var lean: float = s._lean * 0.55 - s._flinch * 0.22 + resp * 0.012 + G.lean
	var sacude := Vector2(sin(t * 33.0), cos(t * 26.0)) * temb_cuerpo * 0.012
	# --- a dónde mira (cámara o un punto de la sala); se calcula antes para girar el torso
	var ih := _h("cabeza")
	var inv := sk.global_transform.affine_inverse()
	var hp := sk.get_bone_global_pose(ih).origin
	var cam: Vector3 = inv * (s.camara_pos + s._mirada_off * 0.4 * (1.0 - fija))
	var d := (cam - hp).normalized()
	var yaw := clampf(atan2(d.x, d.z), -0.7, 0.7)
	var pitch := clampf(asin(clampf(-d.y, -1.0, 1.0)), -0.4, 0.5)
	if wm > 0.0:
		var dt := (inv * _punto(str(mira[1]), s) - hp).normalized()
		yaw = lerpf(yaw, clampf(atan2(dt.x, dt.z), -1.45, 1.45), wm)
		pitch = lerpf(pitch, clampf(asin(clampf(-dt.y, -1.0, 1.0)), -0.6, 0.85), wm)
	var giro := yaw * 0.2 * wm
	_girar(_h("columna"), Quaternion(Vector3.RIGHT, lean * 0.45 + sacude.x) * Quaternion(Vector3.UP, giro * 0.4))
	_girar(_h("pecho"), Quaternion(Vector3.RIGHT, lean * 0.55) * Quaternion(Vector3.FORWARD, sin(t * 0.31) * 0.012 + sacude.y) * Quaternion(Vector3.UP, giro * 0.6))
	# hombros: suben con el miedo, caen con el cansancio
	var hombros: float = G.hombros + resp * 0.04
	for lado in [1, -1]:
		_girar(_h("clavicula" + _suf(lado)), Quaternion(Vector3.BACK, lado * hombros * 0.22))
	# --- cabeza: el giro se reparte en tres huesos (cuello largo)
	var temblor := Vector2(sin(t * 31.0), cos(t * 27.0)) * (nerv * nerv * (1.0 - fija) + temb_cuerpo * 0.8) * 0.012
	var q_obj := Quaternion(Vector3.UP, yaw - giro + G.yaw + temblor.x) \
			* Quaternion(Vector3.RIGHT, pitch + s._baja * 0.55 + G.pitch + temblor.y + sin(t * 0.5) * 0.02) \
			* Quaternion(Vector3.BACK, s._tilt + G.tilt + sin(t * 0.23) * 0.03)
	var vel := 2.6
	var mv: Array = _m("vel")
	if mv[0] > 0.0:
		vel = lerpf(vel, float(mv[1]), mv[0])
	elif wm > 0.0:
		vel = 4.0
	_look = _look.slerp(q_obj, 1.0 - exp(-delta * vel))
	_girar(_h("cuello"), Quaternion.IDENTITY.slerp(_look, 0.2))
	_girar(_h("cuello2"), Quaternion.IDENTITY.slerp(_look, 0.25))
	_poner_global(ih, Basis(_look) * sk.get_bone_global_rest(ih).basis)
	# --- mandíbula y saco vocal (canta en infrasonido: el saco vibra al hablar)
	var ij := _h("mandibula")
	if ij >= 0:
		var r := sk.get_bone_rest(ij).basis.get_rotation_quaternion()
		var ab: Array = _m("abre")
		var abre: float = maxf(s._abre, float(ab[1]) * ab[0] if ab[0] > 0.0 else 0.0)
		abre *= 1.0 - float(_m("aprieta")[0])
		sk.set_bone_pose_rotation(ij, r * Quaternion(Vector3.RIGHT, abre * 0.28))
	var ig := _h("garganta")
	if ig >= 0:
		var inf: float = 0.03 * resp + G.garganta
		if s.hablando > 0.0:
			inf += 0.22 + 0.16 * sin(t * 11.0) * sin(t * 3.7 + 1.0)
		inf += nerv * nerv * 0.08 * sin(t * 23.0)
		inf += G.vibra * 0.12 * sin(t * 38.0) * (0.7 + 0.3 * sin(t * 3.1))
		sk.set_bone_pose_scale(ig, Vector3.ONE * maxf(0.6, 1.0 + inf))
	# --- arco superciliar: baja con la ira, sube con el miedo
	for suf in ["_R", "_L"]:
		var ic := _h("ceja" + suf)
		if ic >= 0:
			var ro := sk.get_bone_rest(ic).origin
			sk.set_bone_pose_position(ic, ro + Vector3(0, -s._cejas * 0.0035, 0))
	# --- el traductor se ilumina al hablar (y con los gestos del collar)
	if _mat_lente:
		var lente: float = (4.0 + sin(t * 30.0) * 1.5) if s.hablando > 0.0 else 0.8 + sin(t * 1.3) * 0.3
		lente += G.lente * (5.0 + sin(t * 47.0) * 2.0)
		_mat_lente.emission_energy_multiplier = lente
	# --- piel: brillo húmedo con los nervios; se aclara con el canto; las sienes cambian de tono
	var luz := clampf(G.luz + G.grave * 0.3, 0.0, 1.0)
	for m in _mat_piel:
		(m as ShaderMaterial).set_shader_parameter("humedad", clampf(nerv * 1.1 - 0.3, 0.0, 0.8))
		(m as ShaderMaterial).set_shader_parameter("translucidez", 0.22 + luz * 0.5)
	if _mat_cara:
		var k := 1.0 + 0.3 * clampf(G.sienes, -1.0, 1.0)
		_mat_cara.set_shader_parameter("tinte", Color(_tinte_cara.r * k, _tinte_cara.g * k, _tinte_cara.b * k))
	if _luz:
		_luz.light_energy = luz * 2.6 * (0.8 + 0.2 * sin(t * 17.0))
	# --- ojos: pupila según la emoción (o el gesto) y párpados dobles
	if _mat_ojo:
		var pu: float = PUPILA_EMO.get(emo, 0.72)
		var mp: Array = _m("pupila")
		if mp[0] > 0.0:
			pu = lerpf(pu, float(mp[1]), mp[0])
		_pupila = lerpf(_pupila, pu, 1.0 - exp(-delta * 7.0))
		_mat_ojo.set_shader_parameter("pupila", _pupila)
		_mat_ojo.set_shader_parameter("cierre", clampf(G.cierre, 0.0, 1.0))
	# --- canto grave: la sala tiembla con él (Room3D) y suena por debajo del traductor
	var grave := clampf(G.grave, 0.0, 1.0)
	if (grave > 0.001 or _grave_env > 0.001) and sala_efecto.is_valid():
		sala_efecto.call("grave", grave)
	_grave_env = grave
	# --- manos: apoyadas en la mesa; con miedo se retiran, con ira se cierran
	var retro := 0.0
	match emo:
		"asustado": retro = 0.05
		"nervioso": retro = 0.015
		"quebrado": retro = -0.03
	retro += s._flinch * 0.04
	var tm: float = nerv * nerv * 0.002 + G.temblor_manos * 0.006 + temb_cuerpo * 0.004
	for lado in [1, -1]:
		var obj := Vector3(0, 0.0, -retro)
		_off_mano[lado] = (_off_mano[lado] as Vector3).lerp(obj, 1.0 - exp(-delta * 4.0))
		var T: Transform3D = _mano_rest[lado]
		T.origin += _off_mano[lado]
		# pose del gesto (la del canal con más peso: las dos manos o solo una)
		var pm: Array = _m("manos")
		var pl: Array = _m("mano_i" if lado > 0 else "mano_d")
		if pl[0] > pm[0]:
			pm = pl
		if pm[0] > 0.0:
			T = T.interpolate_with(_pose_mano(str(pm[1]), lado), pm[0])
		T.origin += Vector3(sin(t * 29.0 + lado * 1.3), sin(t * 41.0 + lado) * 0.5, cos(t * 23.0 + lado)) * tm
		_brazo(lado, T)
	var curl := 0.12
	match emo:
		"furioso": curl = 0.9
		"nervioso": curl = 0.3 + sin(t * 3.0) * 0.12
		"asustado": curl = 0.5
		"quebrado": curl = 0.22
	var mc: Array = _m("curl")
	if mc[0] > 0.0:
		curl = lerpf(curl, float(mc[1]), mc[0])
	_curl = lerpf(_curl, curl, 1.0 - exp(-delta * (5.0 if mc[0] < 0.5 else 14.0)))
	# tamborileo lento con los tres dedos de la mano derecha (salvo que un gesto lo pare)
	var sin_tambor: bool = float(_m("sin_tambor")[0]) > 0.3
	_tambor_t -= delta
	if sin_tambor:
		_tambor = -1.0
	elif _tambor_t <= 0.0 and _tambor < 0.0 and emo in ["calma", "burla", "nervioso"]:
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
	var md: Array = _m("dedos_d")
	var temblor_dedos: float = nerv * nerv + G.temblor_manos * 0.8
	for lado in [1, -1]:
		var por_dedo: Array = []
		if lado < 0 and md[0] > 0.0 and str(md[1]) == "senala":
			var w: float = md[0]
			por_dedo = [lerpf(_curl, -0.05, w), lerpf(_curl, 1.0, w), lerpf(_curl, 1.0, w), lerpf(_curl, 0.9, w)]
		_dedos(lado, _curl, tap if lado < 0 else [0.0, 0.0, 0.0], temblor_dedos, por_dedo)
	_cadenas_update(delta)

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

## c = flexión de todos los dedos; por_dedo = [índice, medio, anular, pulgar] si cada uno va distinto.
func _dedos(lado: int, c: float, tap: Array, temblor: float, por_dedo: Array = []) -> void:
	var s := _suf(lado)
	for f in range(1, 4):
		var trem := sin(t * 23.0 + f * 1.7 + lado) * temblor * 0.06
		var cf: float = float(por_dedo[f - 1]) if por_dedo.size() == 4 else c
		for k in 3:
			var i := _h("dedo%d_%d%s" % [f, k, s])
			if i < 0:
				continue
			var obj: float = clampf(cf + trem, -0.15, 1.15) * FLEX_MAX[k]
			if k == 0:
				obj -= float(tap[f - 1]) * 28.0
			var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
			sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -deg_to_rad(obj - FLEX_REPOSO[k])))
	var cp: float = float(por_dedo[3]) if por_dedo.size() == 4 else c
	for k in 3:
		var i := _h("dedo0_%d%s" % [k, s])
		if i < 0:
			continue
		var r := sk.get_bone_rest(i).basis.get_rotation_quaternion()
		sk.set_bone_pose_rotation(i, r * Quaternion(Vector3.RIGHT, -deg_to_rad([20.0, 28.0, 36.0][k] * cp)))
