extends Node3D
## INTERROGART - sala de interrogatorio 3D en primera persona (Godot 4, 100% procedural).
## - Lampara colgante que oscila, foco con sombra suave, cono visible en niebla volumetrica,
##   polvo iluminado solo dentro de la luz y humo de cigarro.
## - Hormigon, suelo, mesa de metal cepillado, espejo de una via, puerta, reloj real,
##   grabadora con carretes, camara con LED, manchas (Decals).
## - Manos del detective sobre la mesa con gestos (golpe, calma, empatia...).
## - Carpeta del expediente estilo "diario de Phasmophobia": la mano la toma de la mesa,
##   la levanta ante la camara y la abre; las paginas son un SubViewport con UI real.
## API usada por GameManager: ver seccion "API".

const Proc := preload("res://scripts/Proc.gd")
const SospechosoScript := preload("res://scripts/Sospechoso.gd")
const AgenteScript := preload("res://scripts/Agente.gd")
const CarpetaScript := preload("res://scripts/Carpeta.gd")
const Estilo := preload("res://scripts/Estilo.gd")
const REPOSO_ADELANTE := -0.06
const TAB_W := 0.034          # lo que sobresale la pestaña del borde de la hoja
const TAB_L := 0.052          # alto de la pestaña (a lo largo del borde)
const ANG_IZQ := 174.0        # ángulo de la tapa/hojas pasadas (la carpeta abierta en V)

## Hoja de la carpeta: plano que se dobla sobre el lomo en el vertex shader (se curva
## al pasarla); cada cara muestra su trozo del SubViewport (vivo o instantánea) o papel.
const SHADER_HOJA := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex_frente : source_color, filter_linear;
uniform sampler2D tex_dorso : source_color, filter_linear;
uniform vec4 rect_frente = vec4(0.0);
uniform vec4 rect_dorso = vec4(0.0);
uniform float angulo = 0.0;
uniform float lag = 0.0;
uniform float ancho = 0.3;
uniform vec4 papel : source_color = vec4(0.83, 0.79, 0.69, 1.0);
varying float u_borde;
void vertex() {
	float x = VERTEX.x;
	float u = clamp(x / ancho, 0.0, 1.0);
	float th = angulo - lag * u * u;
	VERTEX = vec3(x * cos(th) - VERTEX.y * sin(th), x * sin(th) + VERTEX.y * cos(th), VERTEX.z);
	u_borde = u;
}
void fragment() {
	vec4 r = FRONT_FACING ? rect_frente : rect_dorso;
	vec3 c;
	if (abs(r.z) < 0.001) {
		float b = min(UV.y, 1.0 - UV.y);
		c = papel.rgb * mix(0.8, 1.0, smoothstep(0.0, 0.03, b)) * mix(0.75, 1.0, smoothstep(0.0, 0.08, u_borde));
	} else {
		vec2 t = r.xy + UV * r.zw;
		c = FRONT_FACING ? texture(tex_frente, t).rgb : texture(tex_dorso, t).rgb;
	}
	ALBEDO = c;
}
"""

const MESA_Y := 0.795
const CAM_BASE := Vector3(0, 1.24, 0.45)
const CAM_PITCH := -13.0
const PAG_W := 0.3
const PAG_H := 0.375

const SHADER_PARTICULA := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform vec4 tinte : source_color = vec4(1.0);
uniform float ambiente = 0.02;
void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 c = texture(tex, UV) * tinte * COLOR;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	EMISSION = c.rgb * ambiente;
}
void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION / PI;
}
"""

const SHADER_POST := """
shader_type canvas_item;
uniform sampler2D pantalla : hint_screen_texture, filter_linear_mipmap;
uniform float vineta = 0.88;
uniform float grano = 0.05;
uniform float aberracion = 0.004;
uniform float golpe = 0.0;
uniform float negro = 0.0;
float rnd(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float d = length(c * vec2(1.0, 0.78));
	vec2 off = c * d * aberracion * 3.0;
	vec3 col;
	col.r = texture(pantalla, uv + off).r;
	col.g = texture(pantalla, uv).g;
	col.b = texture(pantalla, uv - off).b;
	float vig = smoothstep(0.82, 0.18, d);
	col *= mix(1.0 - vineta, 1.0, vig);
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col * vec3(0.88, 0.96, 1.1), col * vec3(1.06, 1.0, 0.9), smoothstep(0.02, 0.5, l));
	float g = rnd(uv * vec2(1733.0, 977.0) + fract(TIME * 7.3) * 91.0) - 0.5;
	col += g * grano * (0.6 + (1.0 - l) * 0.8);
	col = mix(col, col * vec3(1.35, 0.55, 0.5) + vec3(0.06, 0.0, 0.0), golpe * (1.0 - vig * 0.6));
	col *= 1.0 - negro;
	COLOR = vec4(col, 1.0);
}
"""

## Objetivo de una mano del agente (invisible): el cuerpo (Agente.gd) lo sigue con IK.
## Convenio: muñeca en el origen, dorso +Y, dedos -Z.
class ManoRig extends Node3D:
	var curl := 0.12
	var pulgar := 0.15
	var lado := 1
	var modo := "reposo"
	var reposo := Transform3D()
	var agarre_mesa := Transform3D()
	var agarre_mano := Transform3D()
	var gest_off := Vector3.ZERO
	var gest_roll := 0.0
	var gest_curl := 0.0

var cam: Camera3D
var cam_attr: CameraAttributesPractical
var env: Environment
var spot: SpotLight3D
var face_light: SpotLight3D
var lampara: Node3D
var bombilla_mat: StandardMaterial3D
var luz_lectura: SpotLight3D
var post_mat: ShaderMaterial
var sospechoso: Node3D
var sway := true
var base_energy := 4.2
var t := 0.0
var _intro_activa := false
var _intro_tween: Tween
var _shake := 0.0
var _look := Vector2.ZERO
var _lamp_kick := 0.0
var _flicker_extra := 0.0
var _golpe := 0.0
var _negro := 0.0
var _dof_lectura := 0.0

# carpeta
var carpeta: Node3D
var tapa_piv: Node3D
var mat_base: ShaderMaterial
var _shader_hoja: Shader
var hojas: Array = []          # por hoja: {piv, malla, mat, tab, tab_mat, z, lbls}
var hoja_f: Array = []         # 0 = en la derecha, 1 = pasada a la izquierda
var hoja_lag: Array = []       # curvatura mientras se pasa
var pestana_3d := 0            # sección abierta: hojas 0..pestana_3d están a la izquierda
var carpeta_tex: Texture2D     # la textura viva del SubViewport del expediente
var _snap: ImageTexture        # instantánea de la sección anterior (al pasar hojas)
var _tab_hover := -1
var _pase := {}                # hoja que pellizca la mano mientras se pasa
var carpeta_mesa := Transform3D()
var carpeta_blend := 0.0
var tapa := 0.0
var carpeta_estado := "mesa"
var tex_size := Vector2(1280, 800)
var _carpeta_mallas: Array = []
var _hover_mat: StandardMaterial3D
var _hover := false
var rotulo_carpeta: Label3D

# manos (objetivos) y el cuerpo del agente
var mano_i: ManoRig
var mano_d: ManoRig
var agente

# utileria
var carretes: Array = []
var led_rec: StandardMaterial3D
var led_cam: StandardMaterial3D
var brasa_mat: StandardMaterial3D
var reloj_h: Node3D
var reloj_m: Node3D
var reloj_s: Node3D
var taza: Node3D
var fotos_mesa: Array = []
var grabando := false
var grabadora: Node3D
var _hover_grab := false
const BOTON_REC := Vector3(-0.034, 0.054, 0.042)   # tecla roja, en coords. de la grabadora

# mugshot (foto del expediente)
var mug_vp: SubViewport
var mug_cam: Camera3D

func _ready() -> void:
	_construir_entorno()
	_construir_sala()
	_construir_mesa()
	_construir_lampara()
	_construir_utileria()
	_construir_particulas()
	sospechoso = SospechosoScript.new()
	sospechoso.name = "Sospechoso"
	add_child(sospechoso)
	sospechoso.colocar(Vector3(0, 0, -1.05))
	sospechoso.visible = false
	_construir_camara()
	_construir_manos()
	_construir_carpeta()
	_construir_mugshot()
	_construir_post()

func _juego() -> Node:
	return get_tree().get_first_node_in_group("game")

func _audio():
	var g := _juego()
	if g and g.get("audio"):
		return g.audio
	return null

# =====================================================================
# CONSTRUCCION
# =====================================================================

func _construir_entorno() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.004, 0.006)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.11, 0.13)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.032
	env.volumetric_fog_albedo = Color(0.9, 0.85, 0.76)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 10.0
	env.volumetric_fog_gi_inject = 0.3
	env.volumetric_fog_ambient_inject = 0.05
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.9
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.86
	we.environment = env
	add_child(we)

func _construir_sala() -> void:
	var muro := Proc.superficie(Color(0.2, 0.205, 0.195), Color(0.1, 0.1, 0.085), {
		"manchas": 0.75, "lineas": 1.0, "lineas_tam": Vector2(0.4, 0.2), "suciedad_suelo": 0.5, "relieve": 0.9, "semilla": 1, "rug_a": 0.95, "rug_b": 0.8})
	var zocalo := Proc.superficie(Color(0.13, 0.16, 0.145), Color(0.07, 0.08, 0.07), {
		"manchas": 0.8, "lineas": 1.0, "lineas_tam": Vector2(0.4, 0.2), "suciedad_suelo": 0.7, "relieve": 0.7, "semilla": 6, "rug_a": 0.6, "rug_b": 0.85})
	var suelo := Proc.superficie(Color(0.12, 0.115, 0.11), Color(0.05, 0.047, 0.045), {
		"manchas": 0.85, "lineas": 0.7, "lineas_tam": Vector2(0.6, 0.6), "rug_a": 0.9, "rug_b": 0.3, "relieve": 0.8, "semilla": 2})
	var techo := Proc.superficie(Color(0.07, 0.07, 0.07), Color(0.03, 0.03, 0.03), {"manchas": 0.6, "semilla": 9})
	Proc.malla(self, Proc.caja(Vector3(4.6, 0.1, 3.8)), Vector3(0, -0.05, -0.2), suelo)
	Proc.malla(self, Proc.caja(Vector3(4.6, 0.1, 3.8)), Vector3(0, 2.85, -0.2), techo)
	Proc.malla(self, Proc.caja(Vector3(4.6, 2.9, 0.1)), Vector3(0, 1.45, -2.0), muro)
	Proc.malla(self, Proc.caja(Vector3(4.6, 2.9, 0.1)), Vector3(0, 1.45, 1.6), muro)
	Proc.malla(self, Proc.caja(Vector3(0.1, 2.9, 3.8)), Vector3(2.3, 1.45, -0.2), muro)
	Proc.malla(self, Proc.caja(Vector3(0.1, 2.9, 3.8)), Vector3(-2.3, 1.45, -0.2), muro)
	# zocalo pintado (mitad baja de las paredes)
	Proc.malla(self, Proc.caja(Vector3(4.6, 1.1, 0.02)), Vector3(0, 0.55, -1.945), zocalo)
	Proc.malla(self, Proc.caja(Vector3(0.02, 1.1, 3.8)), Vector3(2.245, 0.55, -0.2), zocalo)
	Proc.malla(self, Proc.caja(Vector3(0.02, 1.1, 3.8)), Vector3(-2.245, 0.55, -0.2), zocalo)
	# espejo de una via (refleja la lampara) + marco
	var espejo := Proc.mat(Color(0.015, 0.02, 0.025), 0.03, 0.95)
	Proc.malla(self, Proc.caja(Vector3(1.7, 0.95, 0.03)), Vector3(0.95, 1.55, -1.935), espejo)
	var marco := Proc.superficie(Color(0.14, 0.14, 0.15), Color(0.07, 0.06, 0.05), {"metal": 0.8, "rug_a": 0.4, "rug_b": 0.7, "semilla": 4})
	for b in [[Vector3(1.8, 0.05, 0.06), Vector3(0.95, 2.05, -1.93)], [Vector3(1.8, 0.05, 0.06), Vector3(0.95, 1.05, -1.93)],
			[Vector3(0.05, 1.05, 0.06), Vector3(0.075, 1.55, -1.93)], [Vector3(0.05, 1.05, 0.06), Vector3(1.825, 1.55, -1.93)]]:
		Proc.malla(self, Proc.caja(b[0]), b[1], marco)
	# puerta metalica con ventanuco y luz fria del pasillo
	var puerta := Proc.superficie(Color(0.16, 0.18, 0.17), Color(0.08, 0.07, 0.06), {"metal": 0.6, "rug_a": 0.55, "rug_b": 0.85, "manchas": 0.8, "semilla": 12})
	Proc.malla(self, Proc.caja(Vector3(0.92, 2.05, 0.06)), Vector3(-1.35, 1.025, -1.93), puerta)
	Proc.malla(self, Proc.caja(Vector3(0.26, 0.32, 0.01)), Vector3(-1.35, 1.6, -1.895), Proc.mat_emision(Color(0.35, 0.45, 0.55), 0.9, Color(0.05, 0.06, 0.07)))
	for i in 4:
		Proc.malla(self, Proc.caja(Vector3(0.26, 0.004, 0.012)), Vector3(-1.35, 1.48 + i * 0.08, -1.89), marco)
	Proc.malla(self, Proc.caja(Vector3(0.86, 0.012, 0.01)), Vector3(-1.35, 0.006, -1.9), Proc.mat_emision(Color(0.4, 0.5, 0.6), 2.0))
	Proc.malla(self, Proc.cilindro(0.012, 0.012, 0.12, 8), Vector3(-1.0, 1.0, -1.88), marco, Vector3(0, 0, PI * 0.5))
	var pasillo := OmniLight3D.new()
	pasillo.position = Vector3(-1.35, 1.6, -1.7)
	pasillo.light_color = Color(0.5, 0.6, 0.75)
	pasillo.light_energy = 0.25
	pasillo.omni_range = 1.2
	add_child(pasillo)
	# tuberias y rejilla
	var tubo := Proc.superficie(Color(0.2, 0.19, 0.17), Color(0.12, 0.08, 0.05), {"metal": 0.7, "rug_a": 0.5, "rug_b": 0.9, "manchas": 0.9, "semilla": 14})
	Proc.malla(self, Proc.cilindro(0.045, 0.045, 4.5, 16), Vector3(0, 2.62, -1.86), tubo, Vector3(0, 0, PI * 0.5))
	Proc.malla(self, Proc.cilindro(0.026, 0.026, 4.5, 12), Vector3(0, 2.5, -1.89), tubo, Vector3(0, 0, PI * 0.5))
	Proc.malla(self, Proc.caja(Vector3(0.5, 0.3, 0.03)), Vector3(-0.2, 2.45, -1.94), marco)
	for i in 6:
		Proc.malla(self, Proc.caja(Vector3(0.46, 0.012, 0.035)), Vector3(-0.2, 2.33 + i * 0.045, -1.92), Proc.mat(Color(0.02, 0.02, 0.02)), Vector3(0.5, 0, 0))
	# reloj de pared con la hora real
	var reloj := Node3D.new()
	reloj.position = Vector3(-0.55, 2.12, -1.935)
	add_child(reloj)
	Proc.malla(reloj, Proc.cilindro(0.15, 0.15, 0.03, 32), Vector3.ZERO, Proc.mat(Color(0.04, 0.04, 0.04), 0.4), Vector3(PI * 0.5, 0, 0))
	Proc.malla(reloj, Proc.cilindro(0.132, 0.132, 0.01, 32), Vector3(0, 0, 0.016), Proc.piel(Color(0.72, 0.68, 0.58), {"venas": 0.0, "manchas": 0.7, "mancha": Color(0.45, 0.38, 0.25), "sss": 0.0, "rug": 0.5}), Vector3(PI * 0.5, 0, 0))
	for i in 12:
		var a := TAU * i / 12.0
		Proc.malla(reloj, Proc.caja(Vector3(0.006, 0.02 if i % 3 == 0 else 0.012, 0.003)), Vector3(sin(a) * 0.115, cos(a) * 0.115, 0.022), Proc.mat(Color(0.03, 0.03, 0.03)), Vector3(0, 0, -a))
	var aguja := Proc.mat(Color(0.02, 0.02, 0.02), 0.5)
	reloj_h = Node3D.new(); reloj_h.position.z = 0.024; reloj.add_child(reloj_h)
	Proc.malla(reloj_h, Proc.caja(Vector3(0.009, 0.065, 0.003)), Vector3(0, 0.03, 0), aguja)
	reloj_m = Node3D.new(); reloj_m.position.z = 0.027; reloj.add_child(reloj_m)
	Proc.malla(reloj_m, Proc.caja(Vector3(0.006, 0.1, 0.003)), Vector3(0, 0.046, 0), aguja)
	reloj_s = Node3D.new(); reloj_s.position.z = 0.03; reloj.add_child(reloj_s)
	Proc.malla(reloj_s, Proc.caja(Vector3(0.0025, 0.11, 0.002)), Vector3(0, 0.04, 0), Proc.mat(Color(0.6, 0.05, 0.03)))
	# camara de vigilancia en tripode con LED
	var negro := Proc.mat(Color(0.03, 0.03, 0.03), 0.5, 0.3)
	var tri := Node3D.new()
	tri.position = Vector3(1.75, 0, -1.35)
	tri.rotation.y = 0.75
	add_child(tri)
	for i in 3:
		var a2 := TAU * i / 3.0
		Proc.capsula(tri, Vector3(0, 1.3, 0), Vector3(sin(a2) * 0.35, 0.0, cos(a2) * 0.35), 0.012, negro)
	Proc.malla(tri, Proc.caja(Vector3(0.14, 0.12, 0.24)), Vector3(0, 1.4, 0), negro)
	Proc.malla(tri, Proc.cilindro(0.04, 0.045, 0.08), Vector3(0, 1.4, 0.15), negro, Vector3(PI * 0.5, 0, 0))
	Proc.malla(tri, Proc.cilindro(0.032, 0.032, 0.005), Vector3(0, 1.4, 0.192), Proc.mat(Color(0.02, 0.03, 0.05), 0.05, 0.6), Vector3(PI * 0.5, 0, 0))
	led_cam = Proc.mat_emision(Color(1.0, 0.05, 0.03), 5.0)
	Proc.malla(tri, Proc.esfera(0.008, 8), Vector3(0.05, 1.45, 0.12), led_cam)
	# desague y manchas en el suelo (Decals)
	Proc.malla(self, Proc.cilindro(0.09, 0.09, 0.004, 24), Vector3(0.4, 0.001, -1.45), Proc.mat(Color(0.03, 0.03, 0.03), 0.4, 0.8))
	Proc.decal(self, Proc.tex_mancha(3), Vector3(0.3, 0.0, -1.3), Vector3(1.2, 0.3, 1.0), Color(0.16, 0.02, 0.02, 0.85))
	Proc.decal(self, Proc.tex_mancha(8, false), Vector3(-0.8, 0.0, 0.4), Vector3(1.4, 0.3, 1.2), Color(0.02, 0.02, 0.015, 0.7))
	Proc.decal(self, Proc.tex_mancha(15), Vector3(1.2, 0.6, -1.95), Vector3(0.7, 0.3, 0.6), Color(0.2, 0.03, 0.02, 0.6), Vector3(PI * 0.5, 0, 0))
	Proc.decal(self, Proc.tex_mancha(21, false), Vector3(-1.9, 2.4, -1.95), Vector3(1.2, 0.3, 1.0), Color(0.05, 0.05, 0.03, 0.8), Vector3(PI * 0.5, 0, 0))

func _construir_mesa() -> void:
	var acero := Proc.superficie(Color(0.34, 0.35, 0.36), Color(0.16, 0.16, 0.15), {
		"metal": 0.85, "rug_a": 0.3, "rug_b": 0.6, "estirar": Vector3(1.0, 1.0, 18.0), "manchas": 0.55, "relieve": 0.12, "semilla": 4, "escala": 1.5})
	var borde := Proc.superficie(Color(0.12, 0.12, 0.13), Color(0.06, 0.05, 0.04), {"metal": 0.8, "rug_a": 0.45, "rug_b": 0.8, "semilla": 5})
	Proc.malla(self, Proc.caja(Vector3(1.5, 0.04, 0.9)), Vector3(0, MESA_Y - 0.02, -0.25), acero)
	Proc.malla(self, Proc.caja(Vector3(1.52, 0.035, 0.02)), Vector3(0, MESA_Y - 0.022, 0.2), borde)
	Proc.malla(self, Proc.caja(Vector3(1.52, 0.035, 0.02)), Vector3(0, MESA_Y - 0.022, -0.7), borde)
	Proc.malla(self, Proc.caja(Vector3(0.02, 0.035, 0.92)), Vector3(0.76, MESA_Y - 0.022, -0.25), borde)
	Proc.malla(self, Proc.caja(Vector3(0.02, 0.035, 0.92)), Vector3(-0.76, MESA_Y - 0.022, -0.25), borde)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Proc.malla(self, Proc.caja(Vector3(0.045, MESA_Y - 0.04, 0.045)), Vector3(0.68 * sx, (MESA_Y - 0.04) * 0.5, -0.25 + 0.38 * sz), borde)
	# manchas de cafe / suciedad sobre la mesa
	Proc.decal(self, Proc.tex_mancha(31, false), Vector3(0.45, MESA_Y, 0.02), Vector3(0.14, 0.05, 0.14), Color(0.18, 0.1, 0.04, 0.55))
	Proc.decal(self, Proc.tex_mancha(44), Vector3(-0.15, MESA_Y, -0.55), Vector3(0.3, 0.05, 0.25), Color(0.14, 0.02, 0.02, 0.5))

func _construir_lampara() -> void:
	lampara = Node3D.new()
	lampara.position = Vector3(0, 2.8, -0.42)
	add_child(lampara)
	Proc.capsula(lampara, Vector3.ZERO, Vector3(0, -0.72, 0), 0.006, Proc.mat(Color(0.02, 0.02, 0.02), 0.6))
	var esmalte := Proc.superficie(Color(0.12, 0.16, 0.13), Color(0.05, 0.05, 0.04), {"metal": 0.5, "rug_a": 0.35, "rug_b": 0.8, "manchas": 0.7, "semilla": 17})
	var pantalla := Proc.malla(lampara, Proc.cilindro(0.05, 0.26, 0.2, 40), Vector3(0, -0.82, 0), esmalte)
	pantalla.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var interior := StandardMaterial3D.new()
	interior.albedo_color = Color(0.9, 0.86, 0.75)
	interior.cull_mode = BaseMaterial3D.CULL_FRONT
	interior.emission_enabled = true
	interior.emission = Color(1.0, 0.85, 0.6)
	interior.emission_energy_multiplier = 0.6
	var inner := Proc.malla(lampara, Proc.cilindro(0.047, 0.255, 0.195, 40), Vector3(0, -0.82, 0), interior)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Proc.malla(lampara, Proc.cilindro(0.02, 0.02, 0.05, 12), Vector3(0, -0.72, 0), esmalte)
	bombilla_mat = Proc.mat_emision(Color(1.0, 0.86, 0.6), 8.0, Color(1, 0.95, 0.85))
	var bomb := Proc.malla(lampara, Proc.esfera(0.045, 20), Vector3(0, -0.87, 0), bombilla_mat)
	bomb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spot = SpotLight3D.new()
	spot.position = Vector3(0, -0.9, 0)
	spot.rotation_degrees = Vector3(-79, 0, 0)
	spot.light_color = Color(1.0, 0.86, 0.64)
	spot.light_energy = base_energy
	spot.spot_range = 4.5
	spot.spot_angle = 40.0
	spot.spot_angle_attenuation = 0.9
	spot.spot_attenuation = 0.9
	spot.shadow_enabled = true
	spot.shadow_blur = 1.5
	spot.light_size = 0.06
	spot.shadow_bias = 0.02
	spot.light_volumetric_fog_energy = 3.2
	lampara.add_child(spot)
	# rebote tenue hacia el techo (la pantalla por dentro)
	var techo_l := OmniLight3D.new()
	techo_l.position = Vector3(0, -0.7, 0)
	techo_l.light_color = Color(1.0, 0.8, 0.55)
	techo_l.light_energy = 0.18
	techo_l.omni_range = 1.3
	techo_l.light_volumetric_fog_energy = 0.0
	lampara.add_child(techo_l)
	# relleno de cara MUY bajo (la sombra de las cuencas es lo que da miedo)
	face_light = SpotLight3D.new()
	face_light.position = Vector3(0, 1.25, 0.2)
	face_light.light_color = Color(1.0, 0.9, 0.78)
	face_light.light_energy = 0.45
	face_light.spot_range = 3.0
	face_light.spot_angle = 22.0
	face_light.light_volumetric_fog_energy = 0.0
	add_child(face_light)
	face_light.look_at(Vector3(0, 1.38, -0.95), Vector3.UP)
	# contraluz frio desde el espejo: separa la silueta del fondo
	var rim := SpotLight3D.new()
	rim.position = Vector3(0.5, 1.9, -1.85)
	rim.light_color = Color(0.45, 0.58, 0.8)
	rim.light_energy = 2.4
	rim.spot_range = 2.5
	rim.spot_angle = 30.0
	rim.light_volumetric_fog_energy = 0.3
	add_child(rim)
	rim.look_at(Vector3(0, 1.3, -1.05), Vector3.UP)
	var probe := ReflectionProbe.new()
	probe.position = Vector3(0, 1.4, -0.4)
	probe.size = Vector3(4.5, 2.8, 3.7)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)

func _construir_utileria() -> void:
	var plastico := Proc.superficie(Color(0.06, 0.06, 0.065), Color(0.03, 0.03, 0.03), {"rug_a": 0.45, "rug_b": 0.7, "semilla": 23})
	# grabadora de cinta (se enciende / apaga con clic: GameManager.alternar_grabadora)
	var gr := Node3D.new()
	gr.position = Vector3(0.52, MESA_Y, -0.36)
	gr.rotation.y = -0.35
	add_child(gr)
	grabadora = gr
	Proc.malla(gr, Proc.caja(Vector3(0.2, 0.045, 0.12)), Vector3(0, 0.0225, 0), plastico)
	Proc.malla(gr, Proc.caja(Vector3(0.12, 0.004, 0.06)), Vector3(-0.02, 0.046, -0.01), Proc.mat(Color(0.05, 0.06, 0.07), 0.05, 0.3))
	for i in 2:
		var c := Node3D.new()
		c.position = Vector3(-0.05 + i * 0.06, 0.047, -0.01)
		gr.add_child(c)
		Proc.malla(c, Proc.cilindro(0.022, 0.022, 0.004, 20), Vector3.ZERO, Proc.mat(Color(0.7, 0.68, 0.62), 0.5))
		Proc.malla(c, Proc.caja(Vector3(0.04, 0.005, 0.006)), Vector3.ZERO, Proc.mat(Color(0.1, 0.1, 0.1)))
		Proc.malla(c, Proc.cilindro(0.016, 0.016, 0.0045, 16), Vector3(0, 0.0005, 0), Proc.mat(Color(0.12, 0.08, 0.05), 0.4))
		carretes.append(c)
	for i in 5:
		Proc.malla(gr, Proc.caja(Vector3(0.022, 0.01, 0.018)), Vector3(-0.06 + i * 0.026, 0.049, 0.042), Proc.mat(Color(0.2, 0.2, 0.21) if i != 1 else Color(0.5, 0.05, 0.04), 0.5))
	led_rec = Proc.mat_emision(Color(1.0, 0.08, 0.04), 0.0)
	Proc.malla(gr, Proc.esfera(0.005, 8), Vector3(0.08, 0.047, -0.03), led_rec)
	var l := Label3D.new()
	l.text = "REC"
	l.font_size = 28
	l.pixel_size = 0.0004
	l.modulate = Color(0.7, 0.7, 0.7)
	l.position = Vector3(0.08, 0.0455, -0.012)
	l.rotation = Vector3(-PI * 0.5, 0, 0)
	gr.add_child(l)
	# taza de cafe frio
	taza = Node3D.new()
	taza.position = Vector3(0.5, MESA_Y, 0.03)
	add_child(taza)
	var ceramica := Proc.piel(Color(0.78, 0.76, 0.7), {"venas": 0.0, "manchas": 0.6, "mancha": Color(0.45, 0.32, 0.2), "sss": 0.0, "rug": 0.35, "escala": 12.0, "borde": 0.1})
	Proc.malla(taza, Proc.cilindro(0.04, 0.036, 0.095, 28), Vector3(0, 0.0475, 0), ceramica)
	Proc.malla(taza, Proc.cilindro(0.036, 0.036, 0.002, 24), Vector3(0, 0.08, 0), Proc.mat(Color(0.05, 0.025, 0.01), 0.08))
	Proc.malla(taza, Proc.toro(0.018, 0.028, 16), Vector3(0.045, 0.05, 0), ceramica, Vector3(PI * 0.5, 0, 0))
	# cenicero con cigarro humeante
	var cen := Node3D.new()
	cen.position = Vector3(0.36, MESA_Y, -0.62)
	add_child(cen)
	var vidrio := StandardMaterial3D.new()
	vidrio.albedo_color = Color(0.2, 0.22, 0.2, 0.55)
	vidrio.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	vidrio.roughness = 0.08
	vidrio.metallic_specular = 0.9
	Proc.malla(cen, Proc.cilindro(0.065, 0.06, 0.025, 28), Vector3(0, 0.0125, 0), vidrio)
	Proc.malla(cen, Proc.cilindro(0.05, 0.05, 0.004, 20), Vector3(0, 0.006, 0), Proc.mat(Color(0.18, 0.17, 0.16), 1.0))
	for i in 3:
		Proc.capsula(cen, Vector3(-0.02 + i * 0.012, 0.009, -0.02 + i * 0.015), Vector3(0.0 + i * 0.01, 0.009, 0.01 + i * 0.008), 0.004, Proc.mat(Color(0.55, 0.45, 0.3), 0.9))
	var cig := Proc.mat(Color(0.85, 0.83, 0.78), 0.8)
	Proc.capsula(cen, Vector3(0.06, 0.028, 0.0), Vector3(0.0, 0.016, 0.0), 0.0042, cig)
	brasa_mat = Proc.mat_emision(Color(1.0, 0.3, 0.05), 3.0)
	Proc.malla(cen, Proc.esfera(0.0048, 8), Vector3(-0.001, 0.0158, 0.0), brasa_mat)
	var humo := _particulas_humo()
	humo.position = Vector3(-0.002, 0.02, 0.0)
	cen.add_child(humo)
	# papeles sueltos y boligrafo
	var papel := Proc.piel(Color(0.8, 0.77, 0.68), {"venas": 0.0, "manchas": 0.5, "mancha": Color(0.6, 0.5, 0.35), "sss": 0.0, "rug": 0.95, "escala": 6.0, "borde": 0.1})
	Proc.malla(self, Proc.caja(Vector3(0.21, 0.002, 0.29)), Vector3(0.62, MESA_Y + 0.001, -0.05), papel, Vector3(0, 0.5, 0))
	Proc.malla(self, Proc.caja(Vector3(0.21, 0.002, 0.29)), Vector3(0.6, MESA_Y + 0.0025, -0.1), papel, Vector3(0, 0.2, 0))
	Proc.capsula(self, Vector3(0.36, MESA_Y + 0.006, -0.05), Vector3(0.44, MESA_Y + 0.006, -0.14), 0.005, Proc.mat(Color(0.05, 0.08, 0.2), 0.3, 0.4))

func _mat_particula(tinte: Color, ambiente := 0.02) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_PARTICULA
	m.shader = sh
	m.set_shader_parameter("tex", Proc.tex_suave())
	m.set_shader_parameter("tinte", tinte)
	m.set_shader_parameter("ambiente", ambiente)
	return m

func _construir_particulas() -> void:
	# polvo flotando en el cono de luz (solo se ve donde hay luz)
	var p := GPUParticles3D.new()
	p.amount = 140
	p.lifetime = 16.0
	p.preprocess = 16.0
	p.position = Vector3(0, 1.4, -0.45)
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.45, 0.6, 0.45)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.004
	pm.initial_velocity_max = 0.018
	pm.gravity = Vector3(0, -0.002, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_influence_min = 0.01
	pm.turbulence_influence_max = 0.04
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	q.material = _mat_particula(Color(1.0, 0.95, 0.85, 0.45), 0.0)
	p.draw_pass_1 = q
	add_child(p)

func _particulas_humo() -> GPUParticles3D:
	var h := GPUParticles3D.new()
	h.amount = 48
	h.lifetime = 5.0
	h.preprocess = 5.0
	h.visibility_aabb = AABB(Vector3(-1, -0.2, -1), Vector3(2, 2.5, 2))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.06
	pm.gravity = Vector3(0, 0.02, 0)
	pm.damping_min = 0.005
	pm.damping_max = 0.01
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 1.6
	pm.turbulence_noise_speed_random = 0.4
	pm.turbulence_influence_min = 0.06
	pm.turbulence_influence_max = 0.14
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.25))
	curva.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curva
	pm.scale_curve = ct
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 0.3))
	g.add_point(0.6, Color(1, 1, 1, 0.14))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	h.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	q.material = _mat_particula(Color(0.72, 0.74, 0.78, 0.8), 0.01)
	h.draw_pass_1 = q
	return h

func _construir_camara() -> void:
	cam = Camera3D.new()
	cam.position = CAM_BASE
	cam.rotation_degrees = Vector3(CAM_PITCH, 0, 0)
	cam.fov = 56.0
	cam.near = 0.02
	cam.cull_mask = 0xFFFFF & ~2    # sin la cabeza/pelo del agente (capa 2)
	add_child(cam)
	cam.current = true
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 2.3
	cam_attr.dof_blur_far_transition = 1.4
	cam_attr.dof_blur_amount = 0.12
	cam.attributes = cam_attr
	# luz de lectura: se enciende al sostener la carpeta (como la linterna de Phasmo)
	luz_lectura = SpotLight3D.new()
	luz_lectura.position = Vector3(0.12, 0.12, 0.05)
	luz_lectura.rotation_degrees = Vector3(-12, 8, 0)
	luz_lectura.light_color = Color(1.0, 0.88, 0.7)
	luz_lectura.light_energy = 0.0
	luz_lectura.spot_range = 1.4
	luz_lectura.spot_angle = 38.0
	luz_lectura.light_volumetric_fog_energy = 0.0
	cam.add_child(luz_lectura)

func _construir_manos() -> void:
	agente = AgenteScript.new()
	agente.name = "Agente"
	add_child(agente)
	for lado in [-1, 1]:
		var rig := ManoRig.new()
		rig.lado = lado
		add_child(rig)
		# reposo: la pose en la que se modeló el cuerpo, un poco más adelantada
		var r: Transform3D = agente.mano_reposo(lado)
		r.origin += Vector3(-0.01 * lado, 0.0, REPOSO_ADELANTE)
		rig.reposo = r
		rig.transform = rig.reposo
		# agarre sobre la mesa (palma encima del borde derecho de la carpeta)
		rig.agarre_mesa = Transform3D(Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)), Vector3(0.36, 0.022, 0.06))
		# sosteniendo ante la cámara: la mano abraza el borde lateral (palma hacia la
		# carpeta, dedos por detrás, pulgar por delante de la hoja). Coordenadas de la
		# carpeta abierta; la izquierda se lleva con la tapa.
		rig.agarre_mano = _marco_mano(Vector3(-lado * 0.35, -0.55, -0.76), Vector3(lado, 0.0, 0.0), Vector3((PAG_W + 0.045) * lado, 0.028, 0.085))
		if lado < 0:
			mano_i = rig
		else:
			mano_d = rig

## Marco de mano (convenio ManoRig) a partir de la dirección de los dedos y del dorso.
func _marco_mano(dedos: Vector3, dorso: Vector3, pos: Vector3) -> Transform3D:
	var z := -dedos.normalized()
	var y := (dorso - z * dorso.dot(z)).normalized()
	var x := y.cross(z)
	return Transform3D(Basis(x, y, z), pos)

func _mat_hoja() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader_hoja
	m.set_shader_parameter("ancho", PAG_W)
	return m

func _construir_carpeta() -> void:
	_shader_hoja = Shader.new()
	_shader_hoja.code = SHADER_HOJA
	carpeta = Node3D.new()
	carpeta.name = "Carpeta"
	add_child(carpeta)
	carpeta_mesa = Transform3D(Basis(Vector3.UP, 0.28), Vector3(-0.66, MESA_Y + 0.001, -0.3))
	carpeta.transform = carpeta_mesa
	var manila := Proc.piel(Color(0.6, 0.46, 0.27), {"manchas": 0.55, "mancha": Color(0.38, 0.26, 0.13), "venas": 0.0, "rug": 0.85, "sss": 0.0, "escala": 6.0, "borde": 0.12, "suciedad": 0.45, "semilla": 44})
	_carpeta_mallas.append(Proc.malla(carpeta, Proc.caja(Vector3(0.315, 0.003, 0.39)), Vector3(0.1575, 0.0015, 0), manila))
	_carpeta_mallas.append(Proc.malla(carpeta, Proc.caja(Vector3(0.11, 0.003, 0.035)), Vector3(0.22, 0.0015, -0.21), manila))
	_carpeta_mallas.append(Proc.malla(carpeta, Proc.caja(Vector3(0.3, 0.012, 0.375)), Vector3(0.155, 0.009, 0.0), Proc.mat(Color(0.8, 0.77, 0.68), 0.95)))
	# hoja base (la última página, bajo todas las hojas)
	var plano := PlaneMesh.new()
	plano.size = Vector2(PAG_W, PAG_H)
	plano.center_offset = Vector3(PAG_W * 0.5, 0, 0)
	plano.subdivide_width = 18
	mat_base = _mat_hoja()
	var base := MeshInstance3D.new()
	base.mesh = plano
	base.material_override = mat_base
	base.position = Vector3(0.005, 0.0152, 0)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carpeta.add_child(base)
	tapa_piv = Node3D.new()
	tapa_piv.position = Vector3(0, 0.0172, 0)
	carpeta.add_child(tapa_piv)
	_carpeta_mallas.append(Proc.malla(tapa_piv, Proc.caja(Vector3(0.315, 0.003, 0.39)), Vector3(0.1575, 0.0015, 0), manila))
	# forro interior de la tapa (papel liso, casi siempre tapado por la primera hoja)
	var forro := Proc.malla(tapa_piv, Proc.caja(Vector3(0.305, 0.0004, 0.38)), Vector3(0.155, -0.0003, 0), Proc.mat(Color(0.72, 0.66, 0.54), 0.95))
	forro.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# hojas separadoras con pestañas (una por sección de la carpeta)
	_construir_hojas(plano)
	# rotulos en la tapa
	var sello := Label3D.new()
	sello.text = "CONFIDENCIAL"
	sello.font_size = 64
	sello.pixel_size = 0.0006
	sello.modulate = Color(0.55, 0.08, 0.06, 0.85)
	sello.outline_size = 0
	sello.shaded = true
	sello.position = Vector3(0.16, 0.0033, 0.08)
	sello.rotation = Vector3(-PI * 0.5, 0.25, 0)
	tapa_piv.add_child(sello)
	rotulo_carpeta = Label3D.new()
	rotulo_carpeta.text = "EXPEDIENTE"
	rotulo_carpeta.font_size = 26
	rotulo_carpeta.pixel_size = 0.0006
	rotulo_carpeta.modulate = Color(0.1, 0.08, 0.06)
	rotulo_carpeta.outline_size = 0
	rotulo_carpeta.shaded = true
	rotulo_carpeta.position = Vector3(0.16, 0.0033, -0.1)
	rotulo_carpeta.rotation = Vector3(-PI * 0.5, 0, 0)
	tapa_piv.add_child(rotulo_carpeta)
	# cinta roja de cierre
	_carpeta_mallas.append(Proc.malla(tapa_piv, Proc.caja(Vector3(0.012, 0.0015, 0.39)), Vector3(0.27, 0.0036, 0), Proc.mat(Color(0.45, 0.06, 0.05), 0.7)))
	_hover_mat = StandardMaterial3D.new()
	_hover_mat.albedo_color = Color(1.0, 0.85, 0.55, 0.1)
	_hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hover_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_hover_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _construir_mugshot() -> void:
	mug_vp = SubViewport.new()
	mug_vp.size = Vector2i(360, 450)
	mug_vp.own_world_3d = false
	mug_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mug_vp)
	mug_cam = Camera3D.new()
	mug_cam.fov = 24.0
	mug_vp.add_child(mug_cam)
	mug_cam.position = Vector3(0, 1.32, -0.2)
	mug_cam.look_at(Vector3(0, 1.3, -0.95), Vector3.UP)

func _construir_post() -> void:
	# capa -1: encima del 3D pero debajo de la interfaz (el texto no se ensucia)
	var capa := CanvasLayer.new()
	capa.name = "Post"
	capa.layer = -1
	add_child(capa)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_POST
	post_mat.shader = sh
	rect.material = post_mat
	capa.add_child(rect)

# =====================================================================
# API (GameManager)
# =====================================================================

func ocultar_sospechoso() -> void:
	sospechoso.visible = false
	grabando = false
	limpiar_mesa()

func mostrar_sospechoso() -> void:
	sospechoso.visible = true
	grabando = true
	if mug_vp:
		mug_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## Construye el sospechoso a partir de "rasgos" del JSON.
func set_rasgos(r: Dictionary) -> void:
	sospechoso.construir(r)
	sospechoso.nervios = 0.2
	sospechoso.verdad_ref = 0.0
	# foto del expediente: el ilvari tiene la cabeza más alta
	if mug_cam:
		var alto := 1.36 if str(r.get("tipo", "")) == "ilvari" else 1.3
		mug_cam.position = Vector3(0, alto + 0.02, -0.2)
		mug_cam.look_at(Vector3(0, alto, -0.97), Vector3.UP)

func set_rotulo(texto: String) -> void:
	if rotulo_carpeta:
		rotulo_carpeta.text = texto

func set_estado_sospechoso(verdad: float, duda: float) -> void:
	sospechoso.verdad_ref = verdad
	sospechoso.nervios = clampf(duda / 100.0, 0.0, 1.0)

func reaccion(tipo: String, verdad: float, empatia: float) -> void:
	sospechoso.reaccionar(tipo, verdad, empatia)

func hablar(seg: float) -> void:
	sospechoso.hablar(seg)

func get_mugshot() -> Texture2D:
	return mug_vp.get_texture() if mug_vp else null

func set_sombras(on: bool) -> void:
	if spot:
		spot.shadow_enabled = on
	if env:
		env.volumetric_fog_enabled = on
		env.ssil_enabled = on
		env.ssr_enabled = on
		env.ssao_enabled = on

## Intro: la camara entra desde la puerta hasta la silla + destello de la lampara.
func play_intro() -> void:
	if cam == null:
		return
	_intro_activa = true
	cam.position = Vector3(0.25, 1.62, 1.35)
	cam.rotation_degrees = Vector3(-4, 8, 0)
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_intro_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_intro_tween.tween_property(cam, "position", CAM_BASE, 3.4)
	_intro_tween.tween_property(cam, "rotation_degrees", Vector3(CAM_PITCH, 0, 0), 3.4)
	_intro_tween.chain().tween_callback(func(): _intro_activa = false)
	_flicker_extra = 1.2
	_lamp_kick = 1.0

## Gesto de las manos del detective segun la tarjeta elegida.
func gesto(tipo: String) -> void:
	var tw := create_tween().set_parallel(true)
	match tipo:
		"confrontar", "acusar":
			var rigs: Array = [mano_i, mano_d] if tipo == "acusar" else [mano_d]
			var sube: Array = []
			var baja: Array = []
			var vuelve: Array = []
			for rig in rigs:
				sube.append([rig, "gest_off", Vector3(-0.04 * rig.lado, 0.17, 0.06)])
				sube.append([rig, "gest_curl", 0.95])
				baja.append([rig, "gest_off", Vector3(-0.03 * rig.lado, -0.004, -0.03)])
				vuelve.append([rig, "gest_off", Vector3.ZERO])
				vuelve.append([rig, "gest_curl", 0.0])
			_paso(tw, sube, 0.22, Tween.TRANS_QUAD, Tween.EASE_OUT)
			_paso(tw, baja, 0.07, Tween.TRANS_QUAD, Tween.EASE_IN)
			tw.chain().tween_callback(_impacto.bind(1.0 if tipo == "acusar" else 0.7))
			tw.chain().tween_interval(0.45)
			_paso(tw, vuelve, 0.6)
		"empatia":
			var ida: Array = []
			var vuelta: Array = []
			for rig in [mano_i, mano_d]:
				ida.append([rig, "gest_off", Vector3(-0.03 * rig.lado, 0.0, -0.1)])
				ida.append([rig, "gest_curl", -0.12])
				vuelta.append([rig, "gest_off", Vector3.ZERO])
				vuelta.append([rig, "gest_curl", 0.0])
			_paso(tw, ida, 0.8)
			tw.chain().tween_interval(1.4)
			_paso(tw, vuelta, 0.9)
		"minimizar":
			_paso(tw, [[mano_d, "gest_off", Vector3(-0.06, 0.06, -0.06)], [mano_d, "gest_roll", -1.9], [mano_d, "gest_curl", 0.15]], 0.55)
			tw.chain().tween_interval(1.1)
			_paso(tw, [[mano_d, "gest_off", Vector3.ZERO], [mano_d, "gest_roll", 0.0], [mano_d, "gest_curl", 0.0]], 0.6)
		"alternativa":
			for rig in [mano_i, mano_d]:
				_paso(tw, [[rig, "gest_off", Vector3(0, 0.05, -0.03)]], 0.18)
				_paso(tw, [[rig, "gest_off", Vector3(0, 0.0, -0.03)]], 0.1, Tween.TRANS_QUAD, Tween.EASE_IN)
				tw.chain().tween_callback(_toque)
				tw.chain().tween_interval(0.25)
			_paso(tw, [[mano_i, "gest_off", Vector3.ZERO], [mano_d, "gest_off", Vector3.ZERO]], 0.5)
		"evidencia", "testigo":
			_paso(tw, [[mano_d, "gest_off", Vector3(-0.12, 0.0, -0.2)]], 0.45, Tween.TRANS_CUBIC, Tween.EASE_OUT)
			tw.chain().tween_interval(0.5)
			_paso(tw, [[mano_d, "gest_off", Vector3.ZERO]], 0.6)
		_:
			tw.kill()

## Un "paso" de animacion: todos los cambios a la vez, despues del paso anterior.
func _paso(tw: Tween, cambios: Array, dur: float, trans := Tween.TRANS_SINE, ease := Tween.EASE_IN_OUT) -> void:
	for i in cambios.size():
		var c: Array = cambios[i]
		var base: Tween = tw.chain() if i == 0 else tw
		base.tween_property(c[0], c[1], c[2], dur).set_trans(trans).set_ease(ease)

func _toque() -> void:
	_shake = maxf(_shake, 0.08)
	var a = _audio()
	if a and a.has_method("tap"):
		a.tap()

func _impacto(fuerza: float) -> void:
	_shake = 0.55 * fuerza
	_lamp_kick = 1.0 * fuerza
	_flicker_extra = 0.5 * fuerza
	_golpe = 0.55 * fuerza
	var a = _audio()
	if a and a.has_method("thud"):
		a.thud()
	if taza:
		var tw := create_tween()
		tw.tween_property(taza, "position:y", MESA_Y + 0.012 * fuerza, 0.05)
		tw.tween_property(taza, "position:y", MESA_Y, 0.08).set_trans(Tween.TRANS_BOUNCE)
	sospechoso._flinch = maxf(sospechoso._flinch, 0.5 * fuerza)

## Una foto de la evidencia sale de la mano y se desliza hacia el sospechoso.
func deslizar_evidencia(titulo: String) -> void:
	var foto := Node3D.new()
	add_child(foto)
	var marco := Proc.mat(Color(0.86, 0.84, 0.78), 0.9)
	Proc.malla(foto, Proc.caja(Vector3(0.1, 0.0018, 0.125)), Vector3.ZERO, marco)
	Proc.malla(foto, Proc.caja(Vector3(0.088, 0.0005, 0.088)), Vector3(0, 0.0012, -0.012), Proc.piel(Color(0.12, 0.12, 0.13), {"venas": 0.0, "manchas": 0.8, "mancha": Color(0.3, 0.3, 0.3), "sss": 0.0, "rug": 0.2, "escala": 20.0, "semilla": fotos_mesa.size() + 60}))
	var l := Label3D.new()
	l.text = titulo.substr(0, 22)
	l.font_size = 22
	l.pixel_size = 0.00035
	l.modulate = Color(0.1, 0.08, 0.2)
	l.outline_size = 0
	l.shaded = true
	l.position = Vector3(0, 0.0012, 0.047)
	l.rotation = Vector3(-PI * 0.5, PI, 0)
	foto.add_child(l)
	var n := fotos_mesa.size()
	fotos_mesa.append(foto)
	foto.position = Vector3(0.28, MESA_Y + 0.003, -0.18)
	foto.rotation.y = PI + 0.3
	var destino := Vector3(-0.2 + (n % 4) * 0.13, MESA_Y + 0.001 + n * 0.0004, -0.4 - (n / 4) * 0.06)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(foto, "position", destino, 0.7).set_delay(0.25)
	tw.tween_property(foto, "rotation:y", PI + randf_range(-0.25, 0.25), 0.7).set_delay(0.25)

## La mano derecha del agente va hasta la grabadora y pulsa la tecla roja.
## Vuelve cuando la tecla ya está pulsada (la vuelta de la mano no se espera).
func pulsar_grabadora() -> void:
	if grabadora == null or mano_d == null:
		return
	var boton: Vector3 = grabadora.global_transform * BOTON_REC
	# la yema del índice queda ~16 cm por delante del origen de la mano (dedos = -Z)
	var punta: Vector3 = mano_d.reposo.basis * Vector3(0, -0.01, -0.16)
	var off := boton - punta - mano_d.reposo.origin
	var tw := create_tween()
	_paso(tw, [[mano_d, "gest_off", off + Vector3(0, 0.07, 0.02)], [mano_d, "gest_curl", 0.25]], 0.45, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_paso(tw, [[mano_d, "gest_off", off]], 0.1, Tween.TRANS_QUAD, Tween.EASE_IN)
	tw.chain().tween_callback(_toque)
	tw.chain().tween_interval(0.12)
	await tw.finished
	var vuelta := create_tween()
	_paso(vuelta, [[mano_d, "gest_off", off + Vector3(0, 0.05, 0.03)]], 0.15)
	_paso(vuelta, [[mano_d, "gest_off", Vector3.ZERO], [mano_d, "gest_curl", 0.0]], 0.55)

func _grabadora_hit(sp: Vector2) -> bool:
	if grabadora == null or not grabadora.visible:
		return false
	var r := _rayo_local(sp, grabadora.global_transform)
	return AABB(Vector3(-0.11, -0.005, -0.07), Vector3(0.22, 0.07, 0.14)).intersects_ray(r[0], r[1]) != null

func _set_hover_grab(v: bool) -> void:
	if v == _hover_grab:
		return
	_hover_grab = v
	for m in grabadora.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_overlay = _hover_mat if v else null
	if not _hover:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if v else Input.CURSOR_ARROW)

func limpiar_mesa() -> void:
	for f in fotos_mesa:
		if is_instance_valid(f):
			f.queue_free()
	fotos_mesa.clear()

## Fin del interrogatorio: gano=true el sospechoso se quiebra; false = se rie de ti.
func final(gano: bool) -> void:
	if gano:
		sospechoso.set_emocion("quebrado")
		sospechoso._emocion_t = 0.0
		_flicker_extra = 0.3
	else:
		sospechoso.set_emocion("triunfo")
		sospechoso._emocion_t = 0.0
		_flicker_extra = 3.0
		var tw := create_tween()
		tw.tween_property(self, "_negro", 0.85, 0.15)
		tw.tween_property(self, "_negro", 0.0, 0.5)
		tw.tween_property(self, "_negro", 0.6, 0.08)
		tw.tween_property(self, "_negro", 0.0, 0.3)
	grabando = false

# ---------------- carpeta ----------------

func set_carpeta_textura(tex: Texture2D, tam: Vector2) -> void:
	tex_size = tam
	carpeta_tex = tex
	_asignar_caras()

func carpeta_en_mano() -> bool:
	return carpeta_estado != "mesa"

# ---- hojas separadoras ----

func _construir_hojas(plano: PlaneMesh) -> void:
	var nombres: Array = CarpetaScript.PESTANAS
	var n := nombres.size()
	hojas.clear()
	hoja_f.clear()
	hoja_lag.clear()
	for k in n:
		var piv := Node3D.new()
		piv.name = "Hoja%d" % k
		carpeta.add_child(piv)
		var mi := MeshInstance3D.new()
		mi.mesh = plano
		mi.material_override = _mat_hoja()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-0.36, -0.36, -0.2), Vector3(0.72, 0.72, 0.4))
		piv.add_child(mi)
		# pestaña pegada al borde exterior, escalonada de arriba abajo
		var col: Color = nombres[k][1]
		var tab := Node3D.new()
		piv.add_child(tab)
		var tm := StandardMaterial3D.new()
		tm.albedo_color = col
		tm.roughness = 0.8
		tm.emission_enabled = true
		tm.emission = col
		tm.emission_energy_multiplier = 0.0
		var caja := Proc.malla(tab, Proc.caja(Vector3(TAB_W, 0.0009, TAB_L)), Vector3.ZERO, tm)
		caja.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lbls := []
		for cara in [1, -1]:
			var l := Label3D.new()
			l.text = str(nombres[k][0])
			l.font_size = 40
			l.pixel_size = 0.000115
			l.modulate = Color(0.08, 0.06, 0.05)
			l.outline_size = 0
			l.double_sided = false
			l.fixed_size = false
			l.font = Estilo.fuente("titulo")
			l.position = Vector3(0.0015, 0.0006 * cara, 0)
			# cara +Y (hoja a la derecha) y cara -Y (hoja pasada a la izquierda)
			l.rotation = Vector3(-PI * 0.5, 0, 0) if cara > 0 else Vector3(PI * 0.5, 0, PI)
			tab.add_child(l)
			lbls.append(l)
		hojas.append({"piv": piv, "malla": mi, "mat": mi.material_override, "tab": tab, "tab_mat": tm,
				"z": -0.15 + k * 0.06, "lbls": lbls})
		hoja_f.append(0.0)
		hoja_lag.append(0.0)
	_hojas_update()

## Ángulo del borde exterior de la hoja k (en radianes, alrededor del lomo).
func _hoja_angulo(k: int) -> float:
	return float(hoja_f[k]) * clampf(tapa, 0.0, 1.0) * deg_to_rad(ANG_IZQ)

func _hojas_update() -> void:
	var n := hojas.size()
	for k in n:
		var h: Dictionary = hojas[k]
		var th := _hoja_angulo(k)
		var lag: float = hoja_lag[k]
		var s := smoothstep(0.0, 1.0, clampf(th / deg_to_rad(ANG_IZQ), 0.0, 1.0))
		var y_der := 0.01545 + float(n - 1 - k) * 0.00028
		var y_izq := 0.0178 + float(k) * 0.00028
		(h["piv"] as Node3D).position = Vector3(0.004, lerpf(y_der, y_izq, s), 0)
		var m: ShaderMaterial = h["mat"]
		m.set_shader_parameter("angulo", th)
		m.set_shader_parameter("lag", lag)
		var te := th - lag
		var tab: Node3D = h["tab"]
		var r := PAG_W + TAB_W * 0.5 - 0.004
		tab.position = Vector3(cos(te) * r, sin(te) * r, float(h["z"]))
		tab.rotation = Vector3(0, 0, te)
		var izq := te > PI * 0.5
		(h["lbls"][0] as Label3D).visible = not izq
		(h["lbls"][1] as Label3D).visible = izq
		(h["tab_mat"] as StandardMaterial3D).emission_energy_multiplier = 0.35 if k == _tab_hover else 0.0

## Qué muestra cada cara: la sección abierta (textura viva), la anterior (instantánea)
## o papel liso. modo: "fijo" | "adelante" | "atras"; a = sección de partida, b = destino.
func _asignar_caras(modo := "fijo", a := -1, b := -1) -> void:
	if hojas.is_empty():
		return
	var n := hojas.size()
	var liso := Vector4(0, 0, 0, 0)
	var izq := Vector4(0.5, 0, -0.5, 1)
	var der := Vector4(0.5, 0, 0.5, 1)
	for h in hojas:
		(h["mat"] as ShaderMaterial).set_shader_parameter("rect_frente", liso)
		(h["mat"] as ShaderMaterial).set_shader_parameter("rect_dorso", liso)
	mat_base.set_shader_parameter("rect_frente", liso)
	var poner := func(k: int, cara: String, tex: Texture2D, rect: Vector4) -> void:
		var m: ShaderMaterial = mat_base if k >= n else hojas[k]["mat"]
		if k >= n and cara == "dorso":
			return
		m.set_shader_parameter("tex_" + cara, tex)
		m.set_shader_parameter("rect_" + cara, rect)
	var p := pestana_3d
	if modo == "fijo":
		poner.call(p, "dorso", carpeta_tex, izq)
		poner.call(p + 1, "frente", carpeta_tex, der)
	elif modo == "adelante":
		poner.call(a, "dorso", _snap, izq)
		poner.call(a + 1, "frente", _snap, der)
		poner.call(b, "dorso", carpeta_tex, izq)
		poner.call(b + 1, "frente", carpeta_tex, der)
	else:
		poner.call(a, "dorso", _snap, izq)
		poner.call(a + 1, "frente", _snap, der)
		poner.call(b + 1, "frente", carpeta_tex, der)
		poner.call(b, "dorso", carpeta_tex, izq)

func carpeta_pasando() -> bool:
	return carpeta_estado == "pasando"

## Pasa hojas hasta dejar abierta la sección j. La mano derecha pasa hacia la
## izquierda; la izquierda las devuelve. Devuelve cuando la hoja ha caído.
func carpeta_ir(j: int) -> void:
	var g := _juego()
	if carpeta_estado != "abierta" or hojas.is_empty():
		return
	j = clampi(j, 0, hojas.size() - 1)
	var p := pestana_3d
	if j == p:
		return
	carpeta_estado = "pasando"
	var adelante := j > p
	var bulto: Array = range(p + 1, j + 1) if adelante else range(j + 1, p + 1)
	# instantánea de lo que se veía antes de cambiar el contenido
	if carpeta_tex:
		var img := carpeta_tex.get_image()
		if img:
			_snap = ImageTexture.create_from_image(img)
	# la mano va a la pestaña
	var rig: ManoRig = mano_d if adelante else mano_i
	var hoja_ref: int = bulto[0] if adelante else bulto[bulto.size() - 1]
	var z_tab: float = hojas[j]["z"]
	_pase = {"rig": rig, "hoja": hoja_ref, "z": z_tab, "adelante": adelante}
	rig.modo = "pagina"
	if audio_paso_ok():
		_audio().paper()
	await get_tree().create_timer(0.24).timeout
	# a partir de aquí la carpeta enseña la sección nueva
	pestana_3d = j
	if g and g.carpeta_ui:
		g.carpeta_ui.mostrar_pestana(j)
	_asignar_caras("adelante" if adelante else "atras", p, j)
	var dur := 0.62
	var t0 := 0.0
	var soltado := false
	while t0 < dur + 0.08 * bulto.size():
		var dt := get_process_delta_time()
		t0 += dt
		for i in bulto.size():
			var k: int = bulto[i]
			var orden := i if adelante else bulto.size() - 1 - i
			var f := clampf((t0 - orden * 0.05) / dur, 0.0, 1.0)
			var e := f * f * (3.0 - 2.0 * f)
			hoja_f[k] = e if adelante else 1.0 - e
			hoja_lag[k] = (1.0 if adelante else -1.0) * 0.9 * sin(PI * e) * (1.0 + orden * 0.15)
		if not soltado and t0 > dur * 0.55:
			soltado = true
			rig.modo = "carpeta"
		await get_tree().process_frame
	for k in bulto:
		hoja_f[k] = 1.0 if adelante else 0.0
		hoja_lag[k] = 0.0
	rig.modo = "carpeta"
	_pase = {}
	_asignar_caras()
	carpeta_estado = "abierta"

func audio_paso_ok() -> bool:
	var a = _audio()
	return a != null and a.has_method("paper")

## Marco de la mano que pellizca el borde de la hoja que se está pasando (coords. carpeta).
func _marco_pellizco() -> Transform3D:
	var k: int = _pase["hoja"]
	var h: Dictionary = hojas[k]
	var te := _hoja_angulo(k) - float(hoja_lag[k])
	var piv: Vector3 = (h["piv"] as Node3D).position
	var radial := Vector3(cos(te), sin(te), 0)
	var normal := Vector3(-sin(te), cos(te), 0)
	if not _pase["adelante"]:
		normal = -normal
	# la mano no gira del todo con la hoja: dorso a medio camino entre la hoja y "arriba"
	var dorso := (normal + Vector3.UP * 0.8).normalized()
	var borde := piv + radial * PAG_W + Vector3(0, 0, float(_pase["z"]))
	var dedos := (-radial + normal * -0.35).normalized()
	return _marco_mano(dedos, dorso, borde + radial * 0.075 + dorso * 0.012)

## Marco de agarre de la mano izquierda: va con el borde de la tapa (abre la carpeta).
func _agarre_izq() -> Transform3D:
	var t := clampf(tapa, 0.0, 1.0) * deg_to_rad(ANG_IZQ)
	var abierto := Basis(Vector3(0, 0, 1), deg_to_rad(ANG_IZQ))
	var local_tapa := Transform3D(abierto, tapa_piv.position).affine_inverse() * mano_i.agarre_mano
	return Transform3D(Basis(Vector3(0, 0, 1), t), tapa_piv.position) * local_tapa

func anim_carpeta_abrir() -> void:
	if carpeta_estado != "mesa":
		return
	carpeta_estado = "animando"
	_set_hover(false)
	# las hojas hasta la sección abierta se van con la tapa
	var g := _juego()
	pestana_3d = clampi(int(g.carpeta_ui.pestana) if g and g.carpeta_ui else 0, 0, hojas.size() - 1)
	for k in hojas.size():
		hoja_f[k] = 1.0 if k <= pestana_3d else 0.0
		hoja_lag[k] = 0.0
	_asignar_caras()
	mano_d.modo = "carpeta"
	if mug_vp:
		mug_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().create_timer(0.3).timeout
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "carpeta_blend", 1.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_dof_lectura", 1.0, 0.6)
	tw.tween_property(luz_lectura, "light_energy", 0.5, 0.6)
	tw.chain().tween_property(self, "tapa", 1.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): mano_i.modo = "carpeta").set_delay(0.15)
	await tw.finished
	carpeta_estado = "abierta"

func anim_carpeta_cerrar() -> void:
	while carpeta_estado == "pasando":
		await get_tree().process_frame
	if carpeta_estado != "abierta":
		return
	carpeta_estado = "animando"
	mano_i.modo = "reposo"
	var tw := create_tween()
	tw.tween_property(self, "tapa", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.set_parallel(true)
	tw.chain().tween_property(self, "carpeta_blend", 0.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_dof_lectura", 0.0, 0.55)
	tw.tween_property(luz_lectura, "light_energy", 0.0, 0.4)
	await tw.finished
	mano_d.modo = "reposo"
	carpeta_estado = "mesa"
	if mug_vp:
		mug_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _transform_sujeta() -> Transform3D:
	return cam.global_transform * Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.16), Vector3(0.0, -0.03, -0.52))

func _set_hover(v: bool) -> void:
	if v == _hover:
		return
	_hover = v
	for m in _carpeta_mallas:
		(m as MeshInstance3D).material_overlay = _hover_mat if v else null
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if v else Input.CURSOR_ARROW)

func _carpeta_mesa_hit(sp: Vector2) -> bool:
	var inv := carpeta.global_transform.affine_inverse()
	var lo := inv * cam.project_ray_origin(sp)
	var ld := inv.basis * cam.project_ray_normal(sp)
	var caja := AABB(Vector3(-0.03, -0.02, -0.25), Vector3(0.38, 0.08, 0.5))
	return caja.intersects_ray(lo, ld) != null

## Rayo de pantalla en coordenadas de un marco local (origen, dirección).
func _rayo_local(sp: Vector2, marco: Transform3D) -> Array:
	var inv := marco.affine_inverse()
	return [inv * cam.project_ray_origin(sp), inv.basis * cam.project_ray_normal(sp)]

## Punto de la pantalla -> pixel del SubViewport del expediente (o (-1,-1) si no toca pagina).
func _pagina_hit(sp: Vector2) -> Vector2:
	if hojas.is_empty():
		return Vector2(-1, -1)
	var p := pestana_3d
	var n := hojas.size()
	for i in 2:
		var piv_pos: Vector3
		var ang := 0.0
		if i == 0:
			piv_pos = (hojas[p]["piv"] as Node3D).position
			ang = _hoja_angulo(p)
		elif p + 1 < n:
			piv_pos = (hojas[p + 1]["piv"] as Node3D).position
			ang = _hoja_angulo(p + 1)
		else:
			piv_pos = Vector3(0.005, 0.0152, 0)
		var marco := carpeta.global_transform * Transform3D(Basis(Vector3(0, 0, 1), ang), piv_pos)
		var r := _rayo_local(sp, marco)
		var lo: Vector3 = r[0]
		var ld: Vector3 = r[1]
		if absf(ld.y) < 0.000001:
			continue
		var tt := -lo.y / ld.y
		if tt <= 0.0:
			continue
		var q := lo + ld * tt
		if q.x >= 0.0 and q.x <= PAG_W and absf(q.z) <= PAG_H * 0.5:
			var u := q.x / PAG_W
			var v := (q.z + PAG_H * 0.5) / PAG_H
			var uvp := 0.5 - 0.5 * u if i == 0 else 0.5 + 0.5 * u
			return Vector2(uvp * tex_size.x, v * tex_size.y)
	return Vector2(-1, -1)

## Pestaña bajo el ratón (o -1).
func _tab_hit(sp: Vector2) -> int:
	var mejor := -1
	var mejor_t := 1e9
	for k in hojas.size():
		var tab: Node3D = hojas[k]["tab"]
		var r := _rayo_local(sp, tab.global_transform)
		var caja := AABB(Vector3(-TAB_W * 0.5, -0.003, -TAB_L * 0.5), Vector3(TAB_W, 0.006, TAB_L))
		var hit = caja.intersects_ray(r[0], r[1])
		if hit != null:
			var dist: float = (hit as Vector3).distance_to(r[0])
			if dist < mejor_t:
				mejor_t = dist
				mejor = k
	return mejor

func _input(event: InputEvent) -> void:
	if carpeta_estado != "abierta":
		if _tab_hover != -1:
			_tab_hover = -1
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var g := _juego()
	if g == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		g.cerrar_carpeta()
		get_viewport().set_input_as_handled()
		return
	var tk := _tab_hit(event.position)
	if event is InputEventMouseMotion:
		if tk != _tab_hover:
			_tab_hover = tk
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if tk >= 0 and tk != pestana_3d else Input.CURSOR_ARROW)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and tk >= 0:
		get_viewport().set_input_as_handled()
		if tk != pestana_3d:
			_tab_hover = -1
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
			g.ir_pestana(tk)
		return
	var hit := _pagina_hit(event.position)
	var ev: InputEventMouse = event.duplicate()
	if hit.x >= 0.0:
		ev.position = hit
		ev.global_position = hit
		g.carpeta_input(ev)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		ev.position = Vector2(-50, -50)
		ev.global_position = ev.position
		g.carpeta_input(ev)

func _unhandled_input(event: InputEvent) -> void:
	if carpeta_estado != "mesa":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var g := _juego()
		if g and g.has_method("puede_abrir_carpeta") and g.puede_abrir_carpeta() and _carpeta_mesa_hit(event.position):
			g.abrir_carpeta()
			get_viewport().set_input_as_handled()
		elif g and g.has_method("puede_abrir_carpeta") and g.puede_abrir_carpeta() and _grabadora_hit(event.position):
			_set_hover_grab(false)
			g.alternar_grabadora()
			get_viewport().set_input_as_handled()

# =====================================================================
# FRAME
# =====================================================================

func _process(delta: float) -> void:
	t += delta
	_luz_update(delta)
	_camara_update(delta)
	_carpeta_update()
	_manos_update(delta)
	_utileria_update(delta)
	if sospechoso:
		sospechoso.camara_pos = cam.global_position
	if carpeta_estado == "mesa":
		var g := _juego()
		var puede: bool = g != null and g.has_method("puede_abrir_carpeta") and g.puede_abrir_carpeta()
		var mp := get_viewport().get_mouse_position()
		_set_hover(puede and _carpeta_mesa_hit(mp))
		_set_hover_grab(puede and not _hover and _grabadora_hit(mp))
	_golpe = move_toward(_golpe, 0.0, delta * 1.6)
	if post_mat:
		post_mat.set_shader_parameter("golpe", _golpe)
		post_mat.set_shader_parameter("negro", _negro)
	cam_attr.dof_blur_far_distance = lerpf(2.3, 0.75, _dof_lectura)
	cam_attr.dof_blur_amount = lerpf(0.12, 0.2, _dof_lectura)

func _luz_update(delta: float) -> void:
	var flick := 1.0
	var r := randf()
	var prob := 0.012 + _flicker_extra * 0.12
	if r < prob:
		flick = randf_range(0.25, 0.6)
	elif r < prob * 2.0:
		flick = 0.8
	flick *= 1.0 + sin(t * 31.0) * 0.015 + sin(t * 7.3) * 0.025
	_flicker_extra = move_toward(_flicker_extra, 0.0, delta * 0.8)
	spot.light_energy = base_energy * flick
	bombilla_mat.emission_energy_multiplier = 8.0 * flick
	# la lampara oscila (y con ella todas las sombras)
	_lamp_kick = move_toward(_lamp_kick, 0.0, delta * 0.25)
	var amp := (0.012 if sway else 0.0) + _lamp_kick * 0.06
	lampara.rotation.x = sin(t * 1.05) * amp
	lampara.rotation.z = sin(t * 0.83 + 1.3) * amp * 0.7

func _camara_update(delta: float) -> void:
	_shake = move_toward(_shake, 0.0, delta * 2.2)
	if _intro_activa:
		return
	var vs := get_viewport().get_visible_rect().size
	var mp := get_viewport().get_mouse_position()
	var n := Vector2.ZERO
	if vs.x > 0 and vs.y > 0:
		n = ((mp / vs) - Vector2(0.5, 0.5)) * 2.0
		n = n.clamp(Vector2(-1, -1), Vector2(1, 1))
	var obj := Vector2.ZERO
	if sway and carpeta_estado == "mesa":
		obj = Vector2(-n.x * 3.2, -n.y * 2.0)
	_look = _look.lerp(obj, 1.0 - exp(-delta * 2.5))
	var pos := CAM_BASE
	if sway:
		pos += Vector3(sin(t * 0.5) * 0.01, sin(t * 0.8) * 0.007, 0)
	var sh := Vector3(randf() - 0.5, randf() - 0.5, 0.0) * _shake
	cam.position = pos + sh * 0.025
	cam.rotation_degrees = Vector3(CAM_PITCH + _look.y + sh.y * 3.0, _look.x + sh.x * 3.0, sh.x * 1.5)

func _carpeta_update() -> void:
	var b := clampf(carpeta_blend, 0.0, 1.0)
	var tr := carpeta_mesa
	if b > 0.0:
		tr = carpeta_mesa.interpolate_with(_transform_sujeta(), b)
		tr.origin += Vector3.UP * sin(b * PI) * 0.1
	carpeta.transform = tr
	tapa_piv.rotation.z = tapa * deg_to_rad(ANG_IZQ)
	_hojas_update()

func _manos_update(delta: float) -> void:
	for rig in [mano_i, mano_d]:
		if rig == null:
			continue
		var obj: Transform3D
		var curl := 0.1
		var pulg := 0.15
		if rig.modo == "pagina" and not _pase.is_empty():
			obj = carpeta.transform * _marco_pellizco()
			curl = 0.3
			pulg = 0.85
		elif rig.modo == "carpeta" or rig.modo == "pagina":
			var ag: Transform3D = rig.agarre_mano
			if rig.lado > 0:
				ag = rig.agarre_mesa.interpolate_with(rig.agarre_mano, clampf(carpeta_blend * 1.4, 0.0, 1.0))
			else:
				ag = _agarre_izq()
			obj = carpeta.transform * ag
			curl = 0.55
			pulg = 0.8
		else:
			obj = rig.reposo
			obj.origin += rig.gest_off + Vector3(0, sin(t * 1.1 + rig.lado) * 0.0015, 0)
			obj.basis = obj.basis * Basis(Vector3.BACK, rig.gest_roll)
			curl = 0.1 + rig.gest_curl
		var k := 1.0 - exp(-delta * (12.0 if rig.modo == "reposo" else 22.0))
		var cur: Transform3D = rig.transform
		var q := Quaternion(cur.basis.orthonormalized()).slerp(Quaternion(obj.basis.orthonormalized()), k)
		rig.transform = Transform3D(Basis(q), cur.origin.lerp(obj.origin, k))
		rig.curl = lerpf(rig.curl, curl, k)
		rig.pulgar = lerpf(rig.pulgar, pulg, k)
		if agente:
			agente.objetivo[rig.lado] = rig.global_transform
			agente.curl[rig.lado] = rig.curl
			agente.pulgar[rig.lado] = rig.pulgar

func _utileria_update(delta: float) -> void:
	if grabando:
		for c in carretes:
			(c as Node3D).rotation.y += delta * 2.2
	if led_rec:
		led_rec.emission_energy_multiplier = (4.0 if fmod(t, 1.2) < 0.7 else 0.4) if grabando else 0.0
	if led_cam:
		led_cam.emission_energy_multiplier = 5.0 if fmod(t, 2.0) < 1.0 else 0.6
	if brasa_mat:
		brasa_mat.emission_energy_multiplier = 2.2 + sin(t * 1.7) * 0.8 + sin(t * 5.1) * 0.3
	var hora := Time.get_time_dict_from_system()
	var s := float(hora["second"])
	var m := float(hora["minute"]) + s / 60.0
	var h := fmod(float(hora["hour"]), 12.0) + m / 60.0
	reloj_s.rotation.z = -TAU * s / 60.0
	reloj_m.rotation.z = -TAU * m / 60.0
	reloj_h.rotation.z = -TAU * h / 12.0
