extends Control
## INTERROGART - GameManager (Godot 4)
## Estados: MENU -> NIVELES -> INTRO -> JUEGO. Pantalla de juego minima:
##  - arriba a la derecha: panel pequeño (verdad, duda, empatia, turnos)
##  - abajo: abanico de tarjetas de dialogo (1-5) con animacion de eleccion
##  - subtitulo breve con lo ultimo que se dijo
##  - TODO lo demas (caso, perfil, pruebas, testigos, registro, ajustes) vive en la
##    carpeta 3D de la mesa: F / ESC / clic en la carpeta.

const DATA_PATH := "res://data/sospechosos.json"
const SAVE_PATH := "user://interrogart_save.json"
const TURNOS_MAX := 12

# ---- Balance (mecánica v2, calibrado con un simulador de partidas) ----
# Cada sospechoso trae en el JSON un bloque "estrategia" que refleja su pista:
#   mult          multiplicador de verdad por táctica ("confrontar", "evidencia", "testigo"...)
#   clave         multiplicador extra para pruebas/testigos concretos ("llave", "testigo:1")
#   emp_evidencia cuánto potencia la empatía a las pruebas (1 = normal)
#   duda_extra    duda adicional que le provoca una táctica (se cierra antes)
#   requiere      la prueba rinde la mitad si antes no se usó "testigo" / "testigo:N"
#   pronto        las pruebas rinden +30 % durante los primeros N turnos
const VERDAD_INICIAL_K := 0.3     # verdad inicial = (100 - resistencia) * K
const RESISTENCIA_K := 0.75       # los sospechosos duros ceden menos verdad por acción
const DUDA_NERVIOSO := 30.0       # por debajo: tranquilo (las pruebas rinden la mitad)
const DUDA_BLOQUEADO := 75.0      # por encima: bloqueado (las palabras casi no entran)

const ArbolScript := preload("res://scripts/Arbol.gd")
const AudioManagerScript := preload("res://scripts/AudioManager.gd")
const CartaScript := preload("res://scripts/CartaDialogo.gd")
const CarpetaScript := preload("res://scripts/Carpeta.gd")
const Estilo := preload("res://scripts/Estilo.gd")

const LINEAS := {
	"confrontar": [
		"Las pruebas dicen que fuiste tú. No me hagas perder el tiempo.",
		"Te vieron. Tenemos todo. Habla ahora o esto se pone feo.",
		"Mírame. Sé exactamente lo que hiciste esa noche.",
	],
	"minimizar": [
		"Quizá no querías hacerlo. A veces nos empujan... ¿quién te presionó?",
		"Todos cometemos errores. Lo que importa es por qué pasó.",
		"Si te obligaron, dímelo. Eso lo cambia todo.",
	],
	"alternativa": [
		"¿Lo planeaste o se te fue de las manos? Solo dime cuál.",
		"¿Fue idea tuya o te mandaron? Una de las dos.",
	],
	"empatia": [
		"Sé que esto es difícil. Estoy aquí para escucharte.",
		"Háblame de los tuyos. ¿Por quién estás pasando esto?",
		"Respira. Tómate tu tiempo. Quiero entender tu lado.",
	],
	"acusar": ["Se acabó. Fuiste tú, y los dos lo sabemos."],
}

const TACTICAS := [
	["confrontar", "CONFRONTAR", Color(0.86, 0.24, 0.18)],
	["minimizar", "MINIMIZAR", Color(0.38, 0.66, 0.4)],
	["alternativa", "ALTERNATIVA", Color(0.86, 0.66, 0.24)],
	["empatia", "EMPATIZAR", Color(0.36, 0.56, 0.9)],
	["acusar", "ACUSAR", Color(0.7, 0.36, 0.86)],
]

# Casos con árbol de diálogo: título y color de la carta según el "tono" de la opción.
const TONOS := {
	"cortes": ["CORTÉS", Color(0.55, 0.72, 0.62)],
	"pregunta": ["PREGUNTAR", Color(0.86, 0.66, 0.24)],
	"directo": ["DIRECTO", Color(0.8, 0.5, 0.3)],
	"empatia": ["EMPATIZAR", Color(0.36, 0.56, 0.9)],
	"silencio": ["SILENCIO", Color(0.6, 0.6, 0.64)],
	"presion": ["PRESIONAR", Color(0.86, 0.24, 0.18)],
	"amenaza": ["AMENAZAR", Color(0.75, 0.12, 0.1)],
	"farol": ["FAROL", Color(0.8, 0.4, 0.75)],
	"prueba": ["PRUEBA", Color(0.95, 0.82, 0.45)],
	"testigo": ["TESTIGO", Color(0.62, 0.78, 0.9)],
	"promesa": ["PROMETER", Color(0.45, 0.85, 0.7)],
	"acusar": ["ACUSAR", Color(0.7, 0.36, 0.86)],
	"cerrar": ["TERMINAR", Color(0.5, 0.48, 0.46)],
}

enum Estado { MENU, NIVELES, INTRO, JUEGO }
var estado: int = Estado.MENU
var audio

var sospechosos: Array = []
var actual: Dictionary = {}
var verdad := 0.0
var empatia := 20.0
var duda := 20.0
var turnos := TURNOS_MAX
var evidencias_usadas: Array = []
var testimonios_usados: Array = []
var registro: Array = []
var terminado := false
var ocupado := false
var carpeta_abierta := false
var _lineas_mano := {}
var _aprendido := {}          # táctica -> multiplicador ya descubierto por el jugador
var _estado_previo := ""

var desbloqueado_hasta := 1
var resultados := {}
var estrellas := {}           # id de caso -> mejor calificación (1-3)
var aj_volumen := 0.8
var aj_sombras := true
var aj_sway := true

# caso con árbol de diálogo (null en los casos clásicos de tácticas)
var arbol = null
var turnos_max := TURNOS_MAX
var grabadora_on := true

# UI
var p_menu: Control
var p_niveles: Control
var p_intro: Control
var p_juego: Control
var p_fin: Control
var box_niveles: VBoxContainer
var lbl_intro_titulo: Label
var lbl_intro_texto: Label
var lbl_fin_titulo: Label
var lbl_fin_texto: Label
var lbl_fin_estrellas: Label
var lbl_fin_stats: Label
var lbl_estado: Label
var capa_fx: Control
var hud: PanelContainer
var lbl_hud_nombre: Label
var bars := {}
var lbl_turnos: Label
var turno_pips: HBoxContainer
var sub_panel: PanelContainer
var lbl_sub_quien: Label
var lbl_sub: Label
var mano_cartas: Control
var cartas: Array = []            # las cartas en juego (tácticas, u opciones del árbol)
var cartas_tacticas: Array = []
var lbl_rec: Label
var lbl_barras := {}
var lbl_sub_accion: Label
var lbl_ayuda: Label
var fx_flash: ColorRect
var _sub_tween: Tween

# carpeta (SubViewport proyectado en la carpeta 3D)
var carpeta_vp: SubViewport
var carpeta_ui

func _ready() -> void:
	add_to_group("game")
	randomize()
	cargar_datos()
	cargar_save()
	audio = AudioManagerScript.new()
	add_child(audio)
	construir_ui()
	# la sala 3D (padre) hace su _ready despues que este nodo: esperar a que exista
	_post_ready.call_deferred()

func _post_ready() -> void:
	_construir_carpeta_vp()
	aplicar_ajustes()
	ir_menu()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			add_child(load("res://scripts/AutoTest.gd").new())

func escena() -> Node:
	return get_tree().current_scene

# ---------- DATOS / SAVE ----------

func cargar_datos() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir " + DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.has("sospechosos"):
		sospechosos = parsed["sospechosos"]
	# casos grandes (árbol de diálogo) en su propio archivo: data/caso_<id>.json
	for fn in DirAccess.get_files_at("res://data"):
		if fn.begins_with("caso_") and fn.ends_with(".json"):
			var fc := FileAccess.open("res://data/" + fn, FileAccess.READ)
			var c = JSON.parse_string(fc.get_as_text()) if fc else null
			if c is Dictionary and c.has("id"):
				sospechosos.append(c)
			else:
				push_error("Caso inválido: " + fn)
	sospechosos.sort_custom(func(a, b): return int(a.get("nivel", 99)) < int(b.get("nivel", 99)))

func cargar_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var s = JSON.parse_string(f.get_as_text())
	if not (s is Dictionary):
		return
	desbloqueado_hasta = int(s.get("desbloqueado_hasta", 1))
	resultados = s.get("resultados", {})
	estrellas = s.get("estrellas", {})
	var aj: Dictionary = s.get("ajustes", {})
	aj_volumen = float(aj.get("volumen", 0.8))
	aj_sombras = bool(aj.get("sombras", true))
	aj_sway = bool(aj.get("sway", true))

func guardar_save() -> void:
	var s := {
		"desbloqueado_hasta": desbloqueado_hasta,
		"resultados": resultados,
		"estrellas": estrellas,
		"ajustes": {"volumen": aj_volumen, "sombras": aj_sombras, "sway": aj_sway},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s))

func aplicar_ajustes() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.01, aj_volumen)))
	var e := escena()
	if e and e.has_method("set_sombras"):
		e.set_sombras(aj_sombras)
	if e:
		e.set("sway", aj_sway)

# =====================================================================
# UI
# =====================================================================

func _panel_lleno() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	add_child(c)
	return c

func _boton_menu(texto: String, padre: Control, fn: Callable, tam := 26) -> Button:
	var b := Button.new()
	b.text = texto
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Estilo.fuente("titulo"))
	b.add_theme_font_size_override("font_size", tam)
	b.add_theme_color_override("font_color", Color(0.78, 0.75, 0.7))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.6))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 0.5, 0.35))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.38, 0.36))
	var n := Estilo.caja(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(14, 4, 14, 4))
	var h := Estilo.caja(Color(1, 0.8, 0.5, 0.06), Color(1.0, 0.8, 0.5), 0, 0, Vector4(20, 4, 14, 4))
	h.border_width_left = 3
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(fn)
	b.pressed.connect(func(): if audio: audio.click_soft())
	padre.add_child(b)
	return b

func _fondo_oscuro(p: Control, alfa := 0.55) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, alfa + 0.3))
	g.set_color(1, Color(0, 0, 0, alfa * 0.2))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)

func _columna(p: Control, x: float, ancho: float, sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.anchor_top = 0.0
	v.anchor_bottom = 1.0
	v.offset_left = x
	v.offset_right = x + ancho
	v.offset_top = 60
	v.offset_bottom = -60
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", sep)
	p.add_child(v)
	return v

func construir_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ---- MENU ----
	p_menu = _panel_lleno()
	_fondo_oscuro(p_menu, 0.6)
	var vm := _columna(p_menu, 90, 520, 6)
	vm.add_child(Estilo.label("SECTOR 3045 · SALA DE INTERROGATORIOS", "maquina", 14, Color(0.6, 0.55, 0.5)))
	vm.add_child(Estilo.label("INTERROGAR.", "titulo", 96, Color(0.93, 0.88, 0.8)))
	var sub := Estilo.label("Un cuarto. Una luz. Una mentira.", "maquina", 18, Color(0.75, 0.3, 0.25))
	vm.add_child(sub)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 30)
	vm.add_child(sp)
	_boton_menu("Expedientes", vm, ir_niveles)
	_boton_menu("Salir", vm, func(): get_tree().quit())
	# ---- NIVELES ----
	p_niveles = _panel_lleno()
	_fondo_oscuro(p_niveles, 0.75)
	var vn := _columna(p_niveles, 90, 760, 8)
	vn.add_child(Estilo.label("EXPEDIENTES ABIERTOS", "titulo", 48, Color(0.93, 0.88, 0.8)))
	box_niveles = VBoxContainer.new()
	box_niveles.add_theme_constant_override("separation", 2)
	vn.add_child(box_niveles)
	_boton_menu("‹ Volver", vn, ir_menu, 20)
	# ---- INTRO ----
	p_intro = _panel_lleno()
	_fondo_oscuro(p_intro, 0.5)
	var vi := _columna(p_intro, 90, 620, 12)
	lbl_intro_titulo = Estilo.label("", "titulo", 54, Color(0.95, 0.9, 0.82))
	lbl_intro_titulo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vi.add_child(lbl_intro_titulo)
	lbl_intro_texto = Estilo.label("", "maquina", 18, Color(0.78, 0.74, 0.68))
	lbl_intro_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vi.add_child(lbl_intro_texto)
	_boton_menu("Entrar a la sala  (Enter)", vi, empezar_juego)
	_boton_menu("‹ Expedientes", vi, ir_niveles, 20)
	# ---- JUEGO ----
	p_juego = _panel_lleno()
	_construir_hud()
	_construir_subtitulo()
	_construir_mano_cartas()
	lbl_ayuda = Estilo.label("F · carpeta del caso", "ui", 13, Color(0.75, 0.72, 0.66, 0.55))
	lbl_ayuda.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lbl_ayuda.position = Vector2(22, 18)
	p_juego.add_child(lbl_ayuda)
	# capa para números flotantes y avisos (encima del HUD y de las cartas)
	capa_fx = Control.new()
	capa_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	capa_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_juego.add_child(capa_fx)
	# ---- FIN ----
	p_fin = _panel_lleno()
	var velo := ColorRect.new()
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.color = Color(0, 0, 0, 0.72)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_fin.add_child(velo)
	var vf := VBoxContainer.new()
	vf.set_anchors_preset(Control.PRESET_CENTER)
	vf.offset_left = -360
	vf.offset_right = 360
	vf.offset_top = -210
	vf.offset_bottom = 210
	vf.alignment = BoxContainer.ALIGNMENT_CENTER
	vf.add_theme_constant_override("separation", 12)
	p_fin.add_child(vf)
	lbl_fin_titulo = Estilo.label("", "titulo", 64, Color(0.95, 0.9, 0.82))
	lbl_fin_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_titulo)
	lbl_fin_estrellas = Estilo.label("", "titulo", 46, Color(0.95, 0.78, 0.35))
	lbl_fin_estrellas.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_estrellas)
	lbl_fin_texto = Estilo.label("", "maquina", 17, Color(0.85, 0.82, 0.76))
	lbl_fin_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_fin_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_texto)
	lbl_fin_stats = Estilo.label("", "ui", 15, Color(0.7, 0.67, 0.62))
	lbl_fin_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_fin_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_stats)
	var hf := HBoxContainer.new()
	hf.alignment = BoxContainer.ALIGNMENT_CENTER
	hf.add_theme_constant_override("separation", 28)
	vf.add_child(hf)
	_boton_menu("Reintentar", hf, func(): iniciar_caso(str(actual.get("id", ""))), 22)
	_boton_menu("Expedientes", hf, ir_niveles, 22)
	# destello de pantalla (golpes, confesion)
	fx_flash = ColorRect.new()
	fx_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_flash.color = Color(1, 1, 1, 0)
	fx_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_flash)

## Panel pequeño arriba a la derecha.
func _construir_hud() -> void:
	hud = PanelContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud.offset_left = -262
	hud.offset_right = -18
	hud.offset_top = 16
	hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Estilo.caja(Color(0.03, 0.03, 0.035, 0.62), Color(1, 1, 1, 0.07), 1, 6, Vector4(14, 10, 14, 12))
	hud.add_theme_stylebox_override("panel", sb)
	p_juego.add_child(hud)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	lbl_rec = Estilo.label("● REC", "ui", 12, Color(0.95, 0.2, 0.15))
	h.add_child(lbl_rec)
	var tw := create_tween().set_loops()
	tw.tween_property(lbl_rec, "modulate:a", 0.25, 0.7)
	tw.tween_property(lbl_rec, "modulate:a", 1.0, 0.7)
	lbl_hud_nombre = Estilo.label("", "titulo", 15, Color(0.88, 0.84, 0.77))
	lbl_hud_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_hud_nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_hud_nombre.clip_text = true
	lbl_hud_nombre.custom_minimum_size.x = 60
	h.add_child(lbl_hud_nombre)
	for d in [["verdad", "VERDAD", Color(0.9, 0.78, 0.45)], ["duda", "DUDA", Color(0.88, 0.3, 0.22)], ["empatia", "EMPATÍA", Color(0.4, 0.62, 0.92)]]:
		var fila := HBoxContainer.new()
		fila.add_theme_constant_override("separation", 8)
		fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fila)
		var l := Estilo.label(d[1], "ui", 11, Color(0.7, 0.67, 0.62))
		l.custom_minimum_size.x = 56
		fila.add_child(l)
		lbl_barras[d[0]] = l
		var b := ProgressBar.new()
		b.min_value = 0
		b.max_value = 100
		b.show_percentage = false
		b.custom_minimum_size = Vector2(0, 6)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_theme_stylebox_override("background", Estilo.caja(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 3, Vector4.ZERO))
		b.add_theme_stylebox_override("fill", Estilo.caja(d[2], Color(0, 0, 0, 0), 0, 3, Vector4.ZERO))
		fila.add_child(b)
		var n := Estilo.label("0", "ui", 12, Color(0.85, 0.82, 0.76))
		n.custom_minimum_size.x = 28
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fila.add_child(n)
		bars[d[0]] = [b, n, 0.0]
	# marca del 70 % sobre la barra de verdad
	var mv: ProgressBar = bars["verdad"][0]
	var marca := ColorRect.new()
	marca.color = Color(1, 1, 1, 0.55)
	marca.size = Vector2(1, 10)
	marca.anchor_left = 0.7
	marca.anchor_right = 0.7
	marca.offset_top = -2
	marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mv.add_child(marca)
	# estado de ánimo derivado de la duda (tranquilo / nervioso / bloqueado)
	var he := HBoxContainer.new()
	he.add_theme_constant_override("separation", 8)
	he.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(he)
	var le := Estilo.label("ESTADO", "ui", 11, Color(0.7, 0.67, 0.62))
	le.custom_minimum_size.x = 56
	he.add_child(le)
	lbl_estado = Estilo.label("", "titulo", 13, Color(0.85, 0.82, 0.76))
	lbl_estado.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	he.add_child(lbl_estado)
	var ht := HBoxContainer.new()
	ht.add_theme_constant_override("separation", 8)
	ht.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ht)
	var lt := Estilo.label("TURNOS", "ui", 11, Color(0.7, 0.67, 0.62))
	lt.custom_minimum_size.x = 56
	ht.add_child(lt)
	turno_pips = HBoxContainer.new()
	turno_pips.add_theme_constant_override("separation", 3)
	turno_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turno_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turno_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ht.add_child(turno_pips)
	_crear_pips(TURNOS_MAX)
	lbl_turnos = Estilo.label("12", "ui", 12, Color(0.85, 0.82, 0.76))
	lbl_turnos.custom_minimum_size.x = 28
	lbl_turnos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ht.add_child(lbl_turnos)

func _crear_pips(n: int) -> void:
	if turno_pips.get_child_count() == n:
		return
	for c in turno_pips.get_children():
		turno_pips.remove_child(c)
		c.queue_free()
	for i in n:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(6 if n > 12 else 10, 6)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turno_pips.add_child(pip)

## Subtitulo: solo la ultima frase dicha, sin datos del caso.
func _construir_subtitulo() -> void:
	sub_panel = PanelContainer.new()
	sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_panel.anchor_left = 0.5
	sub_panel.anchor_right = 0.5
	sub_panel.offset_left = -360
	sub_panel.offset_right = 360
	sub_panel.offset_top = -196
	sub_panel.offset_bottom = -132
	sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# fondo casi transparente: justo detrás están las manos del sospechoso y sus gestos
	# (entrelaza los dedos, golpea la mesa...); el contorno negro mantiene el texto legible
	sub_panel.add_theme_stylebox_override("panel", Estilo.caja(Color(0.02, 0.02, 0.025, 0.4), Color(0, 0, 0, 0), 0, 4, Vector4(18, 6, 18, 8)))
	p_juego.add_child(sub_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.add_child(v)
	# acotación (lo que hace el sospechoso), solo en los casos con árbol
	lbl_sub_accion = Estilo.label("", "maquina", 13, Color(0.68, 0.66, 0.6, 0.85))
	lbl_sub_accion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sub_accion.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub_accion.visible = false
	v.add_child(lbl_sub_accion)
	lbl_sub_quien = Estilo.label("", "titulo", 14, Color(0.9, 0.35, 0.28))
	lbl_sub_quien.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl_sub_quien)
	lbl_sub = Estilo.label("", "maquina", 17, Color(0.93, 0.9, 0.84))
	lbl_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	v.add_child(lbl_sub)
	for l in [lbl_sub_accion, lbl_sub_quien, lbl_sub]:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub_panel.modulate.a = 0.0

func _construir_mano_cartas() -> void:
	mano_cartas = Control.new()
	mano_cartas.set_anchors_preset(Control.PRESET_FULL_RECT)
	mano_cartas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_juego.add_child(mano_cartas)
	for i in TACTICAS.size():
		var d: Array = TACTICAS[i]
		var c = CartaScript.new()
		mano_cartas.add_child(c)
		c.configurar(d[0], d[1], "", i + 1, d[2], "")
		c.elegida.connect(_on_carta)
		cartas_tacticas.append(c)
	cartas = cartas_tacticas

func _construir_carpeta_vp() -> void:
	carpeta_vp = SubViewport.new()
	carpeta_vp.size = Vector2i(1280, 800)
	carpeta_vp.transparent_bg = false
	carpeta_vp.gui_disable_input = false
	carpeta_vp.handle_input_locally = true
	carpeta_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(carpeta_vp)
	carpeta_ui = CarpetaScript.new()
	carpeta_ui.game = self
	carpeta_vp.add_child(carpeta_ui)
	carpeta_ui.accion.connect(_on_carpeta_accion)
	var e := escena()
	if e and e.has_method("set_carpeta_textura"):
		e.set_carpeta_textura(carpeta_vp.get_texture(), Vector2(1280, 800))

func carpeta_input(ev: InputEvent) -> void:
	if carpeta_vp:
		carpeta_vp.push_input(ev, true)

func _mostrar_solo(p: Control) -> void:
	for x in [p_menu, p_niveles, p_intro, p_juego, p_fin]:
		x.visible = (x == p)

# =====================================================================
# NAVEGACION
# =====================================================================

func ir_menu() -> void:
	estado = Estado.MENU
	_forzar_cerrar_carpeta()
	if audio: audio.stop_ambient()
	_mostrar_solo(p_menu)
	var e := escena()
	if e and e.has_method("ocultar_sospechoso"):
		e.ocultar_sospechoso()

func ir_niveles() -> void:
	estado = Estado.NIVELES
	_forzar_cerrar_carpeta()
	if audio: audio.stop_ambient()
	_mostrar_solo(p_niveles)
	var e := escena()
	if e and e.has_method("ocultar_sospechoso"):
		e.ocultar_sospechoso()
	for c in box_niveles.get_children():
		c.queue_free()
	for s in sospechosos:
		var nv := int(s.get("nivel", 99))
		var abierto: bool = nv <= desbloqueado_hasta
		var res: String = resultados.get(s.get("id", ""), "")
		var marca := ""
		if res == "ganado":
			marca = "   ✓ CERRADO  " + _texto_estrellas(int(estrellas.get(s.get("id", ""), 1)))
		elif res == "perdido":
			marca = "   ✗ FALLIDO"
		var texto := "%02d   %s%s" % [nv, s.get("nombre", "?"), marca] if abierto else "%02d   ██████████   [BLOQUEADO]" % nv
		var b := _boton_menu(texto, box_niveles, iniciar_caso.bind(s.get("id", "")), 24)
		b.disabled = not abierto
		if abierto:
			b.tooltip_text = str(s.get("intro", ""))

func iniciar_caso(id: String) -> void:
	var s := por_id(id)
	if s.is_empty():
		return
	actual = s
	estado = Estado.INTRO
	_forzar_cerrar_carpeta()
	_mostrar_solo(p_intro)
	var e := escena()
	if e:
		if e.has_method("set_rasgos"):
			e.set_rasgos(s.get("rasgos", {}))
		if e.has_method("set_rotulo"):
			e.set_rotulo("EXP. %02d · %s" % [int(s.get("nivel", 0)), str(s.get("nombre", "")).to_upper()])
		if e.has_method("mostrar_sospechoso"):
			e.mostrar_sospechoso()
		if e.has_method("play_intro"):
			e.play_intro()
	if audio: audio.door()
	lbl_intro_titulo.text = "EXPEDIENTE %02d\n%s" % [int(s.get("nivel", 0)), str(s.get("nombre", "?")).to_upper()]
	lbl_intro_texto.text = str(s.get("intro", ""))

func por_id(id: String) -> Dictionary:
	for s in sospechosos:
		if s.get("id", "") == id:
			return s
	return {}

func empezar_juego() -> void:
	if actual.is_empty():
		return
	estado = Estado.JUEGO
	arbol = ArbolScript.new() if str(actual.get("modo", "")) == "arbol" else null
	verdad = (100.0 - float(actual.get("resistencia_base", 70))) * VERDAD_INICIAL_K
	empatia = 20.0
	duda = 15.0
	_aprendido = {}
	_estado_previo = estado_duda()
	_limpiar_avisos()
	turnos_max = int(actual.get("turnos", TURNOS_MAX)) if arbol else TURNOS_MAX
	turnos = turnos_max
	_crear_pips(turnos_max)
	evidencias_usadas = []
	testimonios_usados = []
	registro = []
	terminado = false
	ocupado = false
	_lineas_mano = {}
	for t in TACTICAS:
		_lineas_mano[t[0]] = _linea(t[0])
	_mostrar_solo(p_juego)
	lbl_hud_nombre.text = str(actual.get("nombre", "")).to_upper()
	for k in bars:
		bars[k][2] = 0.0
	var e := escena()
	if e and e.has_method("limpiar_mesa"):
		e.limpiar_mesa()
	if audio: audio.start_ambient()
	if e and e.has_method("mostrar_sospechoso"):
		e.mostrar_sospechoso()
	carpeta_ui.pestana = 0
	carpeta_ui.mugshot = e.get_mugshot() if e and e.has_method("get_mugshot") else null
	for c in cartas_tacticas:
		c.visible = arbol == null
	var nombres := {"verdad": "VERDAD", "duda": "DUDA", "empatia": "EMPATÍA"}
	if arbol:
		nombres = {"verdad": "VERDAD", "duda": "TENSIÓN", "empatia": "CONFIANZA"}
	for k in nombres:
		lbl_barras[k].text = nombres[k]
	# en el árbol las cartas asoman más: el subtítulo sube para no quedar tapado
	sub_panel.offset_top = -236.0 if arbol else -196.0
	sub_panel.offset_bottom = -172.0 if arbol else -132.0
	lbl_ayuda.text = "F · carpeta del caso     G / clic · grabadora" if arbol else "F · carpeta del caso"
	if arbol:
		var r: Dictionary = arbol.iniciar(actual)
		_sync_arbol(false)
		_set_grabadora(arbol.grabando)
		_mostrar_resultado_arbol(r)
		refrescar()
		_poblar_cartas_arbol()
		return
	_set_grabadora(true)
	var dlg: Dictionary = actual.get("dialogos", {})
	_decir_sospechoso(str(dlg.get("saludo", "...")))
	cartas = cartas_tacticas
	refrescar()
	_colocar_cartas(true)

func _linea(tactica: String) -> String:
	var pool: Array = LINEAS.get(tactica, ["..."])
	return pool[randi() % pool.size()]

# =====================================================================
# DIALOGO
# =====================================================================

func _reg(tipo: String, quien: String, texto: String) -> void:
	registro.append({"tipo": tipo, "quien": quien, "texto": texto})

func _decir_sospechoso(texto: String, accion := "") -> void:
	if accion != "":
		_reg("accion", "", accion)
	_reg("sosp", str(actual.get("nombre", "")), texto)
	_subtitulo(str(actual.get("nombre", "")).to_upper(), texto, Color(0.9, 0.35, 0.28))
	lbl_sub_accion.text = accion
	lbl_sub_accion.visible = accion != ""
	var e := escena()
	if e and e.has_method("hablar"):
		e.hablar(clampf(texto.length() * 0.045, 1.0, 5.0))
	if audio and audio.has_method("voz"):
		audio.voz(str(actual.get("rasgos", {}).get("tipo", "humano")), clampf(texto.length() * 0.045, 1.0, 5.0))

func _decir_detective(texto: String) -> void:
	_reg("tu", "DETECTIVE", texto)
	_subtitulo("TÚ", texto, Color(0.55, 0.7, 0.95))

# ---------------------------------------------------------------------
# CASOS CON ÁRBOL DE DIÁLOGO (Arbol.gd): lo que digas cambia lo que contesta
# ---------------------------------------------------------------------

## Copia el estado del árbol a las variables que pintan el HUD y la carpeta.
## verdad = revelaciones, duda = tensión, empatía = confianza.
func _sync_arbol(mostrar := true) -> void:
	turnos = arbol.turnos
	evidencias_usadas = arbol.pruebas.duplicate()
	testimonios_usados = []
	var tests: Array = actual.get("testigos", [])
	for i in tests.size():
		if arbol.testigos.has(str(tests[i].get("id", ""))):
			testimonios_usados.append(i)
	_ajustar(arbol.verdad() - verdad, arbol.confianza - empatia, arbol.tension - duda, mostrar)

func _set_grabadora(on: bool) -> void:
	grabadora_on = on
	if lbl_rec:
		lbl_rec.text = "● REC" if on else "○ SIN GRABAR"
		lbl_rec.add_theme_color_override("font_color", Color(0.95, 0.2, 0.15) if on else Color(0.6, 0.6, 0.6))
	var e := escena()
	if e:
		e.set("grabando", on)

func _mostrar_resultado_arbol(r: Dictionary) -> void:
	var e := escena()
	if r.get("dice", "") != "":
		_decir_sospechoso(str(r["dice"]), str(r.get("accion", "")))
	if e and e.get("sospechoso"):
		e.sospechoso.set_emocion(str(r.get("emocion", "calma")))
		e.sospechoso._emocion_t = 0.0      # la emoción del nodo se mantiene
	# la acotación se representa con el cuerpo (mira la puerta, entrelaza los dedos...)
	if e and e.has_method("gestos_sospechoso") and (r.get("nodo_nuevo", false) or not (r.get("gestos", []) as Array).is_empty()):
		e.gestos_sospechoso(r.get("gestos", []), str(r.get("accion", "")))
	if arbol.espera_grabadora():
		_aviso("QUIERE QUE LO GRABES", Color(0.95, 0.3, 0.2), "Clic en la grabadora (o tecla G).")

## Crea una carta por cada opción visible del nodo actual.
func _poblar_cartas_arbol() -> void:
	for c in cartas:
		if not cartas_tacticas.has(c):
			c.queue_free()
	cartas = []
	var vs := get_viewport_rect().size
	var ops: Array = arbol.opciones_visibles()
	for i in ops.size():
		var o: Dictionary = ops[i]
		var tono: Array = TONOS.get(str(o.get("tono", "")), ["HABLAR", Color(0.7, 0.7, 0.7)])
		var c = CartaScript.new()
		mano_cartas.add_child(c)
		c.configurar("arbol", tono[0], str(o.get("texto", "")), i + 1, tono[1], _pie_opcion(o))
		c.set_meta("opcion", o)
		c.position = Vector2(vs.x * 0.5 - c.size.x * 0.5, vs.y + 30.0 + i * 12.0)
		c.elegida.connect(_on_carta)
		cartas.append(c)

func _pie_opcion(o: Dictionary) -> String:
	if o.has("prueba"):
		for ev in actual.get("evidencias", []):
			if ev.get("id", "") == o["prueba"]:
				return "Enseña: " + str(ev.get("nombre", ""))
	if o.has("testigo"):
		for tg in actual.get("testigos", []):
			if tg.get("id", "") == o["testigo"]:
				return "Cita: " + str(tg.get("nombre", ""))
	if o.has("grabadora"):
		return "Enciende la grabadora" if o["grabadora"] else "Apaga la grabadora"
	if o.has("fin"):
		return "Termina el interrogatorio"
	return ""

func _gesto_de_tono(tono: String) -> String:
	match tono:
		"presion", "amenaza", "farol": return "confrontar"
		"acusar": return "acusar"
		"empatia", "promesa", "cortes": return "empatia"
		"prueba": return "evidencia"
		"testigo": return "testigo"
	return ""

func _jugar_opcion(carta) -> void:
	var o: Dictionary = carta.get_meta("opcion", {})
	if o.is_empty() or turnos <= 0:
		return
	ocupado = true
	await _animar_carta(carta)
	var e := escena()
	_decir_detective(str(o.get("texto", "")))
	var g := _gesto_de_tono(str(o.get("tono", "")))
	if g != "" and e and e.has_method("gesto"):
		e.gesto(g)
	if o.has("prueba"):
		for ev in actual.get("evidencias", []):
			if ev.get("id", "") == o["prueba"] and e and e.has_method("deslizar_evidencia"):
				e.deslizar_evidencia(str(ev.get("nombre", "")))
				if audio: audio.paper()
	var r: Dictionary = arbol.elegir(o)
	if o.has("grabadora"):
		await _anim_grabadora(bool(o["grabadora"]))
	await _esperar(clampf(str(o.get("texto", "")).length() * 0.03, 1.0, 2.4))
	await _aplicar_resultado_arbol(r)

## Clic en la grabadora de la mesa o tecla G.
func alternar_grabadora() -> void:
	if ocupado or terminado or carpeta_abierta or estado != Estado.JUEGO:
		return
	if arbol == null:
		_aviso("PROTOCOLO", Color(0.7, 0.7, 0.7), "En este expediente la grabadora no se puede apagar.")
		return
	ocupado = true
	var r: Dictionary = arbol.alternar_grabadora()
	_reg("accion", "", "Enciendes la grabadora." if arbol.grabando else "Apagas la grabadora.")
	await _anim_grabadora(arbol.grabando)
	await _esperar(0.5)
	await _aplicar_resultado_arbol(r)

func _anim_grabadora(on: bool) -> void:
	var e := escena()
	if e and e.has_method("pulsar_grabadora"):
		await e.pulsar_grabadora()
	_set_grabadora(on)
	if audio: audio.click_hard()

## Prueba o testigo presentado desde la carpeta en un caso con árbol.
func _presentar_arbol(clase: String, id: String, nombre: String) -> void:
	ocupado = true
	await cerrar_carpeta()
	var e := escena()
	if clase == "prueba":
		_decir_detective("Mire esto. " + nombre + ".")
		if e and e.has_method("gesto"):
			e.gesto("evidencia")
		if e and e.has_method("deslizar_evidencia"):
			e.deslizar_evidencia(nombre)
		if audio: audio.paper()
	else:
		_decir_detective(nombre + " declaró algo que debería oír.")
		if e and e.has_method("gesto"):
			e.gesto("testigo")
	var r: Dictionary = arbol.presentar(clase, id)
	await _esperar(1.3)
	if audio and clase == "prueba": audio.evidence_hit()
	await _aplicar_resultado_arbol(r)

func _aplicar_resultado_arbol(r: Dictionary) -> void:
	var antes_rev: int = int(round(verdad))
	_sync_arbol()
	if int(round(verdad)) > antes_rev:
		_aviso("SE LE ESCAPA ALGO", Color(0.95, 0.82, 0.45), "" if grabadora_on else "...y no lo estás grabando.")
	_mostrar_resultado_arbol(r)
	var fin := str(r.get("fin", ""))
	if fin != "":
		await _fin_arbol(fin, str(r.get("dice", "")))
		return
	await _esperar(0.4)
	_poblar_cartas_arbol()
	ocupado = false
	refrescar()

func _fin_arbol(id: String, ultima: String) -> void:
	terminado = true
	ocupado = true
	var info: Dictionary = arbol.final_info(id)
	var gano := str(info.get("tipo", "")) == "victoria"
	for c in cartas:
		c.set_habilitada(false)
	var e := escena()
	# deja leer la última frase antes del telón
	if ultima != "":
		await _esperar(clampf(ultima.length() * 0.04, 2.5, 8.0))
	_limpiar_avisos()
	if e and e.has_method("final"):
		e.final(gano)
	if id in ["d_canto", "d_traicion"] and e and e.has_method("_impacto"):
		e._impacto(1.0)
		_flash(Color(1, 1, 1), 0.5)
	var caso_id := str(actual.get("id", ""))
	var n_estrellas := 0
	var record := false
	if gano:
		_flash(Color(1, 1, 1), 0.25)
		_ajustar(100.0 - verdad, 0.0, 0.0, false)
		resultados[caso_id] = "ganado"
		n_estrellas = 1 + (1 if turnos >= 3 else 0) + (1 if turnos >= 5 else 0)
		record = n_estrellas > int(estrellas.get(caso_id, 0))
		estrellas[caso_id] = maxi(n_estrellas, int(estrellas.get(caso_id, 0)))
		desbloqueado_hasta = maxi(desbloqueado_hasta, int(actual.get("nivel", 1)) + 1)
		if audio: audio.win()
	else:
		if resultados.get(caso_id, "") != "ganado":
			resultados[caso_id] = "perdido"
		if audio: audio.lose()
	guardar_save()
	refrescar()
	await _esperar(1.6)
	var stats := "Turnos restantes: %d de %d   ·   Verdad descubierta: %d %%   ·   Final: %s" % [
			turnos, turnos_max, int(verdad), str(info.get("titulo", ""))]
	if record:
		stats += "\n¡NUEVO RÉCORD!"
	if not gano:
		stats += "\nHay dos formas de ganar. Lo que digas cambia lo que contesta."
	_mostrar_fin(str(info.get("titulo", "")), str(info.get("texto", "")), n_estrellas, stats)

func _subtitulo(quien: String, texto: String, color: Color) -> void:
	lbl_sub_accion.visible = false
	lbl_sub_quien.text = quien
	lbl_sub_quien.add_theme_color_override("font_color", color)
	lbl_sub.text = texto
	lbl_sub.visible_ratio = 0.0
	if _sub_tween and _sub_tween.is_valid():
		_sub_tween.kill()
	_sub_tween = create_tween()
	_sub_tween.tween_property(sub_panel, "modulate:a", 1.0, 0.15)
	_sub_tween.tween_property(lbl_sub, "visible_ratio", 1.0, clampf(texto.length() * 0.022, 0.3, 2.2))

func _esperar(seg: float) -> void:
	await get_tree().create_timer(seg).timeout

## Clamp y efecto de "duda" (lo nervioso que esta; mueve temblor, sudor y ojos).
## Con mostrar=true enseña los cambios como números flotantes junto al HUD.
func _ajustar(dv: float, de: float, dd: float, mostrar := true) -> void:
	var antes := [verdad, empatia, duda]
	verdad = clampf(verdad + dv, 0.0, 100.0)
	empatia = clampf(empatia + de, 0.0, 100.0)
	duda = clampf(duda + dd, 0.0, 100.0)
	var e := escena()
	if e and e.has_method("set_estado_sospechoso"):
		e.set_estado_sospechoso(verdad, duda)
	refrescar()
	if not mostrar:
		return
	var cambios := [["verdad", verdad - antes[0], Color(0.95, 0.82, 0.45)],
			["empatia", empatia - antes[1], Color(0.45, 0.66, 0.95)],
			["duda", duda - antes[2], Color(0.92, 0.35, 0.26)]]
	for c in cambios:
		if absf(c[1]) >= 0.5:
			_numero_flotante(c[0], c[1], c[2])
	var st := estado_duda()
	if st != _estado_previo and arbol == null:
		match st:
			"bloqueado":
				_aviso.call_deferred("SE HA CERRADO EN BANDA", Color(0.92, 0.3, 0.22), "Las palabras apenas entran. Empatiza para bajar su duda.")
				if audio: audio.thud()
			"nervioso":
				_aviso.call_deferred(_g("ESTÁ NERVIOSO", "ESTÁ NERVIOSA"), Color(0.95, 0.72, 0.3), "Buen momento para una prueba.")
				if audio: audio.tap()
			"tranquilo":
				_aviso.call_deferred("SE HA CALMADO", Color(0.55, 0.75, 0.95), "Con calma, tiene excusas listas para tus pruebas.")
		_estado_previo = st

# ---------------------------------------------------------------------
# MECÁNICA v2: estado de la duda y personalidad de cada sospechoso
# ---------------------------------------------------------------------

## Texto en masculino o femenino según el sospechoso (campo "genero": "f" en el JSON).
func _g(masc: String, fem: String) -> String:
	return fem if str(actual.get("genero", "m")) == "f" else masc

func estado_duda() -> String:
	if duda < DUDA_NERVIOSO:
		return "tranquilo"
	return "bloqueado" if duda > DUDA_BLOQUEADO else "nervioso"

func _est() -> Dictionary:
	return actual.get("estrategia", {})

## Multiplicador de verdad de una táctica para el sospechoso actual.
func _mult(tactica: String) -> float:
	return float(_est().get("mult", {}).get(tactica, 1.0))

## Multiplicador extra de una prueba o testigo concreto ("llave", "testigo:1").
func _clave(id: String) -> float:
	return float(_est().get("clave", {}).get(id, 1.0))

## Los sospechosos con más resistencia ceden menos verdad por acción.
func _escala_resistencia() -> float:
	return (100.0 - float(actual.get("resistencia_base", 70)) * RESISTENCIA_K) / 60.0

func _requisito_cumplido(req: String) -> bool:
	if req == "testigo":
		return not testimonios_usados.is_empty()
	if req.begins_with("testigo:"):
		return testimonios_usados.has(int(req.substr(8)))
	return true

## Muestra (una vez por táctica) si al sospechoso le afecta mucho o poco.
func _revelar_afinidad(tactica: String, mult: float, nombre: String) -> void:
	if _aprendido.has(tactica):
		return
	_aprendido[tactica] = mult
	if mult >= 1.25:
		_aviso("¡PUNTO DÉBIL!", Color(0.55, 0.92, 0.5), nombre + " le afecta mucho.")
		if audio: audio.click_hard()
	elif mult <= 0.6:
		_aviso("APENAS LE AFECTA", Color(0.7, 0.7, 0.7), nombre + " casi no surte efecto.")

func _nombre_tactica(tactica: String) -> String:
	for t in TACTICAS:
		if t[0] == tactica:
			return str(t[1]).capitalize()
	return tactica.capitalize()

func _numero_flotante(barra: String, valor: float, color: Color) -> void:
	if not bars.has(barra) or capa_fx == null:
		return
	var rect: Rect2 = (bars[barra][0] as Control).get_global_rect()
	var l := Estilo.label(("+%d" if valor > 0 else "%d") % int(round(valor)), "titulo", 22, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(90, 30)
	l.position = Vector2(hud.get_global_rect().position.x - 100, rect.position.y - 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa_fx.add_child(l)
	l.scale = Vector2(0.6, 0.6)
	l.pivot_offset = Vector2(90, 15)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.parallel().tween_property(l, "position:y", l.position.y - 26, 1.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)

var _cola_avisos: Array = []
var _aviso_en_curso := false

## Aviso en la parte superior (cambios de estado, puntos débiles). Se encolan y se
## muestran de uno en uno para no tapar la cara del sospechoso ni amontonarse.
func _aviso(titulo: String, color: Color, detalle := "") -> void:
	if capa_fx == null:
		return
	for a in _cola_avisos:
		if a[0] == titulo:
			return
	_cola_avisos.append([titulo, color, detalle])
	if not _aviso_en_curso:
		_siguiente_aviso()

func _limpiar_avisos() -> void:
	_cola_avisos.clear()
	for c in capa_fx.get_children():
		c.queue_free()
	_aviso_en_curso = false

func _siguiente_aviso() -> void:
	if _cola_avisos.is_empty() or estado != Estado.JUEGO:
		_aviso_en_curso = false
		return
	_aviso_en_curso = true
	var datos: Array = _cola_avisos.pop_front()
	var titulo: String = datos[0]
	var color: Color = datos[1]
	var detalle: String = datos[2]
	var caja := VBoxContainer.new()
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caja.add_theme_constant_override("separation", 0)
	var t := Estilo.label(titulo, "titulo", 26, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	t.add_theme_constant_override("outline_size", 8)
	caja.add_child(t)
	if detalle != "":
		var d := Estilo.label(detalle, "maquina", 14, Color(0.92, 0.9, 0.85))
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		d.add_theme_constant_override("outline_size", 6)
		caja.add_child(d)
	var vs := get_viewport_rect().size
	caja.size = Vector2(640, 60)
	caja.position = Vector2((vs.x - 640) * 0.5, 10)
	capa_fx.add_child(caja)
	caja.modulate.a = 0.0
	var tw := caja.create_tween()
	tw.tween_property(caja, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(caja, "position:y", 18.0, 0.15)
	tw.tween_interval(1.5)
	tw.tween_property(caja, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		caja.queue_free()
		_siguiente_aviso())

func gastar_turno() -> bool:
	if terminado or estado != Estado.JUEGO:
		return false
	turnos -= 1
	return true

func _fin_de_turno() -> void:
	refrescar()
	if verdad >= 100.0:
		ganar(false)
	elif turnos <= 0:
		perder("Se acabó el tiempo. Su abogado entra por esa puerta.")

func _on_carta(carta) -> void:
	if ocupado or terminado or carpeta_abierta or estado != Estado.JUEGO:
		return
	jugar_carta(carta)

func jugar_carta(carta) -> void:
	if arbol:
		_jugar_opcion(carta)
		return
	var tactica: String = carta.tactica
	if tactica == "acusar":
		await _animar_carta(carta)
		acusacion_final()
		return
	if not gastar_turno():
		return
	ocupado = true
	await _animar_carta(carta)
	var linea: String = _lineas_mano.get(tactica, _linea(tactica))
	_decir_detective(linea)
	var e := escena()
	if e and e.has_method("gesto"):
		e.gesto(tactica)
	var dlg: Dictionary = actual.get("dialogos", {})
	var resp := ""
	# El estado ANTES de hablar decide cuánto entra la táctica
	var st := estado_duda()
	var bloq := 0.4 if st == "bloqueado" else 1.0
	var extra: Dictionary = _est().get("duda_extra", {})
	var mult := _mult(tactica)
	var esc := _escala_resistencia()
	await _esperar(1.2)
	match tactica:
		"confrontar":
			var g := (9.0 if empatia >= 15.0 else 4.0) * mult * bloq
			_ajustar(g * esc, -10.0, 14.0 + float(extra.get("confrontar", 0)))
			resp = str(dlg.get("presionado", "..."))
		"minimizar":
			_ajustar((5.0 + empatia * 0.05) * mult * bloq * esc, 6.0, 3.0 + float(extra.get("minimizar", 0)))
			resp = str(dlg.get("niega", "..."))
		"alternativa":
			_ajustar(7.0 * mult * bloq * esc, 0.0, 8.0 + float(extra.get("alternativa", 0)))
			resp = str(dlg.get("alternativa", dlg.get("niega", "...")))
		"empatia":
			# la empatía es la única táctica que abre a un sospechoso bloqueado
			_ajustar(2.0 * mult * esc, 16.0, -22.0 if st == "bloqueado" else -12.0)
			resp = str(dlg.get("empatia", "..."))
	if st == "bloqueado" and tactica != "empatia":
		resp = str(dlg.get("bloqueado", resp))
	_revelar_afinidad(tactica, mult, _nombre_tactica(tactica))
	if e and e.has_method("reaccion"):
		e.reaccion(tactica, verdad, empatia)
	_decir_sospechoso(resp)
	_lineas_mano[tactica] = _linea(tactica)
	await _esperar(0.6)
	ocupado = false
	_fin_de_turno()

func mostrar_evidencia(id: String) -> void:
	if ocupado or terminado or estado != Estado.JUEGO or evidencias_usadas.has(id):
		return
	for ev in actual.get("evidencias", []):
		if ev.get("id", "") != id:
			continue
		if arbol:
			_presentar_arbol("prueba", id, str(ev.get("nombre", "")))
			return
		if not gastar_turno():
			return
		ocupado = true
		evidencias_usadas.append(id)
		await cerrar_carpeta()
		# --- cuánto le pega la prueba (mecánica v2) ---
		var est := _est()
		var st := estado_duda()
		var f_estado: float = {"tranquilo": 0.5, "nervioso": 1.15, "bloqueado": 1.0}[st]
		var g: float = float(ev.get("danio_verdad", 20)) * 0.45 \
				* (1.0 + empatia / 200.0 * float(est.get("emp_evidencia", 1.0))) * f_estado
		g *= _mult("evidencia") * _clave(id)
		var req := str(est.get("requiere", {}).get(id, ""))
		var sin_contexto := req != "" and not _requisito_cumplido(req)
		if sin_contexto:
			g *= 0.5
		var acciones_hechas := TURNOS_MAX - turnos - 1
		var temprana := est.has("pronto") and acciones_hechas < int(est.get("pronto", 0))
		if temprana:
			g *= 1.3
		g *= _escala_resistencia()
		_decir_detective("Mira esto. " + str(ev.get("nombre", "")) + ".")
		_reg("accion", "", "Se presenta la prueba: " + str(ev.get("nombre", "")))
		var e := escena()
		if e and e.has_method("gesto"):
			e.gesto("evidencia")
		if e and e.has_method("deslizar_evidencia"):
			e.deslizar_evidencia(str(ev.get("nombre", "")))
		if audio: audio.paper()
		await _esperar(1.0)
		_ajustar(g, 0.0, 20.0)
		if audio: audio.evidence_hit()
		_flash(Color(0.8, 0.1, 0.05), 0.18 if st != "tranquilo" else 0.08)
		# Explica por qué la prueba pegó fuerte o flojo
		if sin_contexto:
			_aviso("LE FALTA CONTEXTO", Color(0.8, 0.7, 0.55), "Sin una declaración previa, la prueba pierde fuerza.")
		elif _clave(id) > 1.0:
			_aviso("¡PRUEBA CLAVE!", Color(0.55, 0.92, 0.5), "Justo donde más le duele.")
			if audio: audio.click_hard()
		elif st == "tranquilo":
			_aviso("TENÍA LA EXCUSA PREPARADA", Color(0.55, 0.75, 0.95), "Sube su duda antes de enseñarle pruebas.")
		elif st == "nervioso":
			_aviso("GOLPE CERTERO", Color(0.95, 0.72, 0.3), "Con los nervios, no supo reaccionar.")
		if temprana and not sin_contexto:
			_aviso("A TIEMPO", Color(0.75, 0.85, 0.6), "Llega antes de que prepare una excusa.")
		_revelar_afinidad("evidencia", _mult("evidencia"), "Enseñarle pruebas")
		if e and e.has_method("reaccion"):
			e.reaccion("evidencia", verdad, empatia)
		var dlg_ev: Dictionary = actual.get("dialogos", {})
		if st == "tranquilo" and not sin_contexto and _clave(id) <= 1.0:
			_decir_sospechoso(str(dlg_ev.get("evidencia_calmado", ev.get("texto_exito", "..."))))
		else:
			_decir_sospechoso(str(ev.get("texto_exito", "...")))
		await _esperar(0.6)
		ocupado = false
		_fin_de_turno()
		return

func presentar_testimonio(idx: int) -> void:
	if ocupado or terminado or estado != Estado.JUEGO or testimonios_usados.has(idx):
		return
	var tests: Array = actual.get("testigos", [])
	if idx < 0 or idx >= tests.size():
		return
	if arbol:
		_presentar_arbol("testigo", str(tests[idx].get("id", "")), str(tests[idx].get("nombre", "")))
		return
	if not gastar_turno():
		return
	ocupado = true
	testimonios_usados.append(idx)
	await cerrar_carpeta()
	var tg: Dictionary = tests[idx]
	_decir_detective("%s declaró: «%s»" % [tg.get("nombre", ""), tg.get("texto", "")])
	var e := escena()
	if e and e.has_method("gesto"):
		e.gesto("testigo")
	if audio: audio.paper()
	await _esperar(1.6)
	var g_tg := float(tg.get("danio_verdad", 12)) * 0.6 * (1.0 + empatia / 250.0) \
			* _mult("testigo") * _clave("testigo:%d" % idx) * _escala_resistencia()
	_ajustar(g_tg, 0.0, 10.0)
	if _clave("testigo:%d" % idx) > 1.0:
		_aviso("¡DECLARACIÓN CLAVE!", Color(0.55, 0.92, 0.5), "Ese testimonio desarma su versión.")
		if audio: audio.click_hard()
	_revelar_afinidad("testigo", _mult("testigo"), "Citar testigos")
	if e and e.has_method("reaccion"):
		e.reaccion("testigo", verdad, empatia)
	_decir_sospechoso(str(tg.get("texto_exito", "...")))
	await _esperar(0.6)
	ocupado = false
	_fin_de_turno()

func acusacion_final() -> void:
	if terminado or estado != Estado.JUEGO:
		return
	ocupado = true
	_decir_detective(LINEAS["acusar"][0])
	var e := escena()
	if e and e.has_method("gesto"):
		e.gesto("acusar")
	await _esperar(1.3)
	if verdad >= 70.0:
		ganar(true)
	else:
		if e and e.has_method("reaccion"):
			e.reaccion("acusar_fallo", verdad, empatia)
		perder("Lo acusaste con solo %d %% de verdad. Se ríe en tu cara y pide su abogado." % int(verdad))

func ganar(por_acusacion: bool) -> void:
	terminado = true
	_limpiar_avisos()
	ocupado = true
	var nombre: String = actual.get("nombre", "?")
	var verdad_lograda := verdad
	_ajustar(100.0, 0.0, 100.0, false)
	refrescar()
	var e := escena()
	if e and e.has_method("final"):
		e.final(true)
	_flash(Color(1, 1, 1), 0.25)
	var confesion := str(actual.get("verdad_final", ""))
	_reg("fin_bien", nombre, confesion)
	_subtitulo(nombre.to_upper(), confesion, Color(0.9, 0.35, 0.28))
	if e and e.has_method("hablar"):
		e.hablar(clampf(confesion.length() * 0.04, 2.0, 8.0))
	var id := str(actual.get("id", ""))
	resultados[id] = "ganado"
	# Calificación: ganar = 1 estrella; 2 si sobran 2+ turnos; 3 si sobran 4+
	var n_estrellas := 1 + (1 if turnos >= 2 else 0) + (1 if turnos >= 4 else 0)
	var record := n_estrellas > int(estrellas.get(id, 0))
	estrellas[id] = maxi(n_estrellas, int(estrellas.get(id, 0)))
	desbloqueado_hasta = maxi(desbloqueado_hasta, int(actual.get("nivel", 1)) + 1)
	guardar_save()
	if audio: audio.win()
	_ocultar_cartas()
	await _esperar(clampf(confesion.length() * 0.035, 4.0, 9.0))
	var como := ("Acusación certera con %d %% de verdad." % int(verdad_lograda)) if por_acusacion else "Confesión completa."
	_mostrar_fin("CONFESIÓN", como + " El caso queda cerrado.", n_estrellas,
			"Turnos restantes: %d de %d   ·   Pruebas: %d   ·   Testigos: %d%s" % [turnos, TURNOS_MAX,
			evidencias_usadas.size(), testimonios_usados.size(), "\n¡NUEVO RÉCORD!" if record else ""])

func perder(motivo: String) -> void:
	terminado = true
	_limpiar_avisos()
	ocupado = true
	var nombre: String = actual.get("nombre", "?")
	var e := escena()
	if e and e.has_method("final"):
		e.final(false)
	var burla := str(actual.get("dialogos", {}).get("victoria", "Se acabó, detective. Me voy a casa."))
	_reg("fin_mal", nombre, burla)
	_subtitulo(nombre.to_upper(), burla, Color(0.9, 0.35, 0.28))
	if e and e.has_method("hablar"):
		e.hablar(2.5)
	resultados[actual.get("id", "")] = "perdido"
	guardar_save()
	if audio: audio.lose()
	_ocultar_cartas()
	refrescar()
	await _esperar(4.0)
	_mostrar_fin("SIN CONFESIÓN", motivo, 0, "Verdad alcanzada: %d %%   ·   Relee la nota del jefe en la carpeta: describe su punto débil." % int(verdad))

func _texto_estrellas(n: int) -> String:
	return "★".repeat(clampi(n, 0, 3)) + "☆".repeat(3 - clampi(n, 0, 3))

func _mostrar_fin(titulo: String, texto: String, n_estrellas := 0, stats := "") -> void:
	if estado != Estado.JUEGO:
		return
	lbl_fin_titulo.text = titulo
	lbl_fin_texto.text = texto
	lbl_fin_estrellas.text = _texto_estrellas(n_estrellas)
	lbl_fin_estrellas.visible = n_estrellas > 0
	lbl_fin_stats.text = stats
	sub_panel.modulate.a = 0.0
	p_fin.visible = true
	p_fin.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p_fin, "modulate:a", 1.0, 0.8)

func _flash(c: Color, fuerza: float) -> void:
	fx_flash.color = Color(c.r, c.g, c.b, fuerza)
	var tw := create_tween()
	tw.tween_property(fx_flash, "color:a", 0.0, 0.45)

# =====================================================================
# HUD + CARTAS
# =====================================================================

func refrescar() -> void:
	if estado != Estado.JUEGO:
		return
	for i in turno_pips.get_child_count():
		var pip := turno_pips.get_child(i) as ColorRect
		var viva := i < turnos
		pip.color = (Color(0.88, 0.3, 0.22) if turnos <= 3 else Color(0.85, 0.82, 0.76)) if viva else Color(1, 1, 1, 0.08)
	lbl_turnos.text = str(turnos)
	if audio and not terminado:
		audio.set_tension(turnos)
	if arbol:
		_refrescar_arbol()
		return
	var st := estado_duda()
	if lbl_estado:
		match st:
			"tranquilo":
				lbl_estado.text = _g("TRANQUILO", "TRANQUILA") + "  ·  pruebas a medias"
				lbl_estado.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
			"nervioso":
				lbl_estado.text = _g("NERVIOSO", "NERVIOSA") + "  ·  momento de pruebas"
				lbl_estado.add_theme_color_override("font_color", Color(0.95, 0.72, 0.3))
			"bloqueado":
				lbl_estado.text = _g("BLOQUEADO", "BLOQUEADA") + "  ·  empatiza"
				lbl_estado.add_theme_color_override("font_color", Color(0.92, 0.32, 0.24))
	for c in cartas:
		var tac: String = c.tactica
		var puede := not terminado
		if tac == "acusar":
			c._lbl_txt.text = "Todo o nada. Necesitas 70 % de verdad o se te escapa."
			var listo := verdad >= 70.0
			c.set_pie("LISTO PARA ACUSAR" if listo else "ARRIESGADO", Color(0.55, 0.9, 0.5) if listo else Color(0.9, 0.4, 0.3))
		else:
			c._lbl_txt.text = "«" + str(_lineas_mano.get(tac, "")) + "»"
			var pie := ""
			var color_pie: Color = c.acento.lerp(Color(0.7, 0.7, 0.7), 0.35)
			match tac:
				"confrontar": pie = "Sube mucho la duda  ·  -empatía" if empatia >= 15.0 else "Sin empatía rinde la mitad"
				"minimizar": pie = "Le ofreces una salida"
				"alternativa": pie = "Dos salidas, ambas culpables"
				"empatia": pie = "Baja la duda  ·  +empatía"
			if st == "bloqueado":
				if tac == "empatia":
					pie = "LO ÚNICO QUE ENTRA AHORA"
					color_pie = Color(0.55, 0.9, 0.5)
				else:
					pie = "Bloqueado: casi no entra"
					color_pie = Color(0.9, 0.4, 0.3)
			elif _aprendido.has(tac):
				var m: float = _aprendido[tac]
				if m >= 1.25:
					pie += "  ·  ¡punto débil!"
					color_pie = Color(0.55, 0.9, 0.5)
				elif m <= 0.6:
					pie += "  ·  apenas le afecta"
					color_pie = Color(0.6, 0.58, 0.55)
			c.set_pie(pie, color_pie)
		c.set_habilitada(puede)
	if carpeta_ui and carpeta_abierta:
		carpeta_ui.refrescar()

const EMOCIONES := {
	"calma": ["SERENO", Color(0.55, 0.75, 0.95)],
	"burla": ["DESAFIANTE", Color(0.8, 0.6, 0.85)],
	"nervioso": ["NERVIOSO", Color(0.95, 0.72, 0.3)],
	"asustado": ["ASUSTADO", Color(0.95, 0.55, 0.3)],
	"furioso": ["FURIOSO", Color(0.92, 0.3, 0.22)],
	"quebrado": ["QUEBRADO", Color(0.7, 0.7, 0.75)],
}

func _refrescar_arbol() -> void:
	var emo := EMOCIONES.get(str(arbol.nodo_actual().get("emocion", "calma")), EMOCIONES["calma"]) as Array
	var aviso := "  ·  ¡tensión al límite!" if arbol.tension >= 80.0 else ""
	lbl_estado.text = str(emo[0]) + aviso
	lbl_estado.add_theme_color_override("font_color", Color(0.92, 0.32, 0.24) if aviso != "" else emo[1])
	for c in cartas:
		c.set_habilitada(not terminado)
	if carpeta_ui and carpeta_abierta:
		carpeta_ui.refrescar()

func _process(delta: float) -> void:
	if estado == Estado.JUEGO:
		for k in bars:
			var obj: float = verdad if k == "verdad" else (duda if k == "duda" else empatia)
			bars[k][2] = lerpf(bars[k][2], obj, 1.0 - exp(-delta * 5.0))
			(bars[k][0] as ProgressBar).value = bars[k][2]
			(bars[k][1] as Label).text = str(int(round(bars[k][2])))
		_colocar_cartas(false, delta)

## Abanico inferior: las cartas asoman la cabecera; la que tiene el raton se levanta.
func _colocar_cartas(inmediato := false, delta := 0.016) -> void:
	var vs := get_viewport_rect().size
	var n := cartas.size()
	var sep := 150.0
	var ocultar := carpeta_abierta or terminado
	var k := 1.0 if inmediato else 1.0 - exp(-delta * 12.0)
	for i in n:
		var c = cartas[i]
		if c.fijo:
			continue
		var u := float(i) - (n - 1) * 0.5
		var x: float = vs.x * 0.5 + u * sep - c.size.x * 0.5
		var asoma := 158.0 if arbol else 118.0   # en el árbol se lee la frase sin levantarla
		var y: float = vs.y - asoma + absf(u) * absf(u) * 6.0
		var rot := u * 3.2
		var esc := 1.0
		if c.hover and c.habilitada and not ocupado:
			y = vs.y - c.size.y - 16.0
			rot = 0.0
			esc = 1.08
		if ocultar or ocupado:
			y = vs.y - (0.0 if ocultar else 60.0) + absf(u) * 4.0
		c.position = c.position.lerp(Vector2(x, y), k)
		c.rotation_degrees = lerpf(c.rotation_degrees, rot, k)
		c.scale = c.scale.lerp(Vector2.ONE * esc, k)
		c.z_index = 10 if c.hover else i

## Animacion de eleccion: la carta sube al centro, brilla, y arde desde los bordes.
func _animar_carta(carta) -> void:
	carta.fijo = true
	carta.z_index = 50
	if audio: audio.card()
	var vs := get_viewport_rect().size
	var centro := Vector2(vs.x * 0.5 - carta.size.x * 0.5, vs.y * 0.5 - carta.size.y * 0.35)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(carta, "position", centro, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(carta, "rotation_degrees", 0.0, 0.32)
	tw.tween_property(carta, "scale", Vector2.ONE * 1.25, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(carta.set_brillo, 0.0, 0.35, 0.2)
	tw.chain().tween_interval(0.25)
	tw.chain().tween_method(carta.set_brillo, 0.35, 0.0, 0.3)
	tw.tween_method(carta.set_quema, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(carta, "position:y", centro.y - 40.0, 0.55)
	await tw.finished
	# vuelve a la mano desde abajo (nueva frase)
	carta.set_quema(0.0)
	carta.scale = Vector2.ONE
	carta.position = Vector2(carta.position.x, vs.y + 20.0)
	carta.fijo = false

func _ocultar_cartas() -> void:
	for c in cartas:
		c.set_habilitada(false)

# =====================================================================
# CARPETA
# =====================================================================

func puede_abrir_carpeta() -> bool:
	return estado == Estado.JUEGO and not carpeta_abierta and not ocupado and not actual.is_empty()

func abrir_carpeta() -> void:
	if not puede_abrir_carpeta():
		return
	carpeta_abierta = true
	carpeta_ui.refrescar()
	if audio: audio.paper()
	create_tween().tween_property(sub_panel, "modulate:a", 0.0, 0.2)
	create_tween().tween_property(lbl_ayuda, "modulate:a", 0.0, 0.2)
	var e := escena()
	if e and e.has_method("anim_carpeta_abrir"):
		await e.anim_carpeta_abrir()
	if audio: audio.paper()

func cerrar_carpeta() -> void:
	if not carpeta_abierta:
		return
	var e := escena()
	if e and e.has_method("anim_carpeta_cerrar"):
		if audio: audio.paper()
		while e.carpeta_estado == "animando":
			await get_tree().process_frame
		await e.anim_carpeta_cerrar()
	carpeta_abierta = false
	create_tween().tween_property(lbl_ayuda, "modulate:a", 1.0, 0.3)
	refrescar()

## Pasa las hojas de la carpeta hasta la sección i (la mano agarra la pestaña).
func ir_pestana(i: int) -> void:
	if not carpeta_abierta:
		carpeta_ui.mostrar_pestana(i)
		return
	var e := escena()
	if e and e.has_method("carpeta_ir"):
		if e.carpeta_estado == "abierta":
			e.carpeta_ir(i)
	else:
		carpeta_ui.mostrar_pestana(i)

func _forzar_cerrar_carpeta() -> void:
	p_fin.visible = false
	if carpeta_abierta:
		cerrar_carpeta()

func _on_carpeta_accion(tipo: String, dato) -> void:
	match tipo:
		"click":
			if audio: audio.click_soft()
		"pagina":
			if audio: audio.paper()
		"ir_pestana":
			ir_pestana(int(dato))
		"evidencia":
			mostrar_evidencia(str(dato))
		"testigo":
			presentar_testimonio(int(dato))
		"volumen":
			aj_volumen = float(dato)
			aplicar_ajustes()
		"sombras":
			aj_sombras = bool(dato)
			aplicar_ajustes()
		"sway":
			aj_sway = bool(dato)
			aplicar_ajustes()
		"guardar":
			guardar_save()
			_subtitulo("", "Partida guardada.", Color(0.7, 0.7, 0.7))
		"cerrar":
			cerrar_carpeta()
		"abandonar":
			ir_niveles()
		"menu":
			ir_menu()

# =====================================================================
# TECLADO
# =====================================================================

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if estado == Estado.INTRO and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE):
		empezar_juego()
		get_viewport().set_input_as_handled()
		return
	if estado != Estado.JUEGO:
		return
	if k.keycode == KEY_ESCAPE or k.keycode == KEY_F:
		if carpeta_abierta:
			var e := escena()
			if e and e.carpeta_estado == "abierta":
				cerrar_carpeta()
		else:
			abrir_carpeta()
		get_viewport().set_input_as_handled()
		return
	if carpeta_abierta:
		carpeta_ui.tecla(k.keycode)
		get_viewport().set_input_as_handled()
		return
	if terminado or ocupado:
		return
	if k.keycode == KEY_G:
		alternar_grabadora()
		get_viewport().set_input_as_handled()
		return
	var idx := -1
	match k.keycode:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
		KEY_4: idx = 3
		KEY_5: idx = 4
	if idx >= 0 and idx < cartas.size():
		jugar_carta(cartas[idx])
