extends Control
## INTERROGART - tarjeta de dialogo del abanico inferior.
## Asoma solo la cabecera; al pasar el raton se levanta. Al elegirla el GameManager la
## lleva al centro, la ilumina y la "quema" con el shader (animacion de eleccion).

signal elegida(carta)

const Estilo := preload("res://scripts/Estilo.gd")
const Proc := preload("res://scripts/Proc.gd")
const TAM := Vector2(176, 246)

const SHADER_QUEMA := """
shader_type canvas_item;
uniform float quema = 0.0;
uniform float brillo = 0.0;
uniform sampler2D ruido : repeat_enable, filter_linear;
uniform vec4 borde : source_color = vec4(1.0, 0.45, 0.1, 1.0);
void fragment() {
	vec4 c = COLOR;
	float n = texture(ruido, SCREEN_UV * vec2(2.6, 1.7)).r;
	float q = quema * 1.2;
	if (n < q - 0.07) {
		discard;
	}
	float e = 1.0 - smoothstep(q - 0.07, q + 0.05, n);
	c.rgb = mix(c.rgb, borde.rgb * 2.2, e * step(0.001, quema));
	c.rgb += brillo * vec3(0.9, 0.78, 0.55) * c.a;
	COLOR = c;
}
"""

var tactica := ""
var acento := Color.WHITE
var hover := false
var habilitada := true
var fijo := false
var panel: Panel
var mat: ShaderMaterial
var _lbl_txt: Label
var _lbl_pie: Label

func _init() -> void:
	size = TAM
	custom_minimum_size = TAM
	pivot_offset = Vector2(TAM.x * 0.5, TAM.y)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func configurar(tactica_: String, titulo: String, texto: String, tecla: int, acento_: Color, pie := "") -> void:
	tactica = tactica_
	acento = acento_
	panel = Panel.new()
	panel.size = TAM
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Estilo.caja(Color(0.075, 0.07, 0.066), acento.darkened(0.35), 1, 10)
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.65)
	sb.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_QUEMA
	mat.shader = sh
	mat.set_shader_parameter("ruido", Proc.ruido(77, 0.02, false, 256, 4))
	mat.set_shader_parameter("borde", Color(1.0, 0.45, 0.12))
	panel.material = mat
	# grano de papel
	var grano := TextureRect.new()
	grano.texture = Proc.ruido(91, 0.35, false, 128, 2)
	grano.stretch_mode = TextureRect.STRETCH_TILE
	grano.size = TAM - Vector2(4, 4)
	grano.position = Vector2(2, 2)
	grano.modulate = Color(1, 1, 1, 0.05)
	grano.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grano.use_parent_material = true
	panel.add_child(grano)
	var franja := ColorRect.new()
	franja.color = acento
	franja.position = Vector2(0, 0)
	franja.size = Vector2(4, TAM.y)
	franja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	franja.use_parent_material = true
	panel.add_child(franja)
	var num := Estilo.label(str(tecla), "titulo", 26, acento)
	num.position = Vector2(16, 8)
	num.use_parent_material = true
	panel.add_child(num)
	var tit := Estilo.label(titulo, "titulo", 21, Color(0.93, 0.9, 0.84))
	tit.position = Vector2(42, 12)
	tit.use_parent_material = true
	panel.add_child(tit)
	var linea := ColorRect.new()
	linea.color = acento.darkened(0.2)
	linea.position = Vector2(16, 48)
	linea.size = Vector2(44, 2)
	linea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	linea.use_parent_material = true
	panel.add_child(linea)
	_lbl_txt = Estilo.label(texto, "maquina", 13, Color(0.8, 0.77, 0.71))
	_lbl_txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_txt.position = Vector2(16, 62)
	_lbl_txt.size = Vector2(TAM.x - 28, 140)
	_lbl_txt.use_parent_material = true
	panel.add_child(_lbl_txt)
	_lbl_pie = Estilo.label(pie, "ui", 11, acento.lerp(Color(0.7, 0.7, 0.7), 0.35))
	_lbl_pie.position = Vector2(16, TAM.y - 30)
	_lbl_pie.size = Vector2(TAM.x - 28, 20)
	_lbl_pie.use_parent_material = true
	panel.add_child(_lbl_pie)
	mouse_entered.connect(func(): hover = true)
	mouse_exited.connect(func(): hover = false)

func set_pie(texto: String, color: Color) -> void:
	if _lbl_pie:
		_lbl_pie.text = texto
		_lbl_pie.add_theme_color_override("font_color", color)

func set_habilitada(v: bool) -> void:
	habilitada = v
	modulate = Color(1, 1, 1, 1) if v else Color(0.55, 0.55, 0.55, 0.9)

func set_quema(q: float) -> void:
	if mat:
		mat.set_shader_parameter("quema", q)

func set_brillo(b: float) -> void:
	if mat:
		mat.set_shader_parameter("brillo", b)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if habilitada and not fijo:
			accept_event()
			elegida.emit(self)
