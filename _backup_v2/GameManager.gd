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

var desbloqueado_hasta := 1
var resultados := {}
var aj_volumen := 0.8
var aj_sombras := true
var aj_sway := true

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
var hud: PanelContainer
var lbl_hud_nombre: Label
var bars := {}
var lbl_turnos: Label
var turno_pips: HBoxContainer
var sub_panel: PanelContainer
var lbl_sub_quien: Label
var lbl_sub: Label
var mano_cartas: Control
var cartas: Array = []
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
	var aj: Dictionary = s.get("ajustes", {})
	aj_volumen = float(aj.get("volumen", 0.8))
	aj_sombras = bool(aj.get("sombras", true))
	aj_sway = bool(aj.get("sway", true))

func guardar_save() -> void:
	var s := {
		"desbloqueado_hasta": desbloqueado_hasta,
		"resultados": resultados,
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
	# ---- FIN ----
	p_fin = _panel_lleno()
	var vf := VBoxContainer.new()
	vf.set_anchors_preset(Control.PRESET_CENTER)
	vf.offset_left = -330
	vf.offset_right = 330
	vf.offset_top = -170
	vf.offset_bottom = 170
	vf.alignment = BoxContainer.ALIGNMENT_CENTER
	vf.add_theme_constant_override("separation", 10)
	p_fin.add_child(vf)
	lbl_fin_titulo = Estilo.label("", "titulo", 64, Color(0.95, 0.9, 0.82))
	lbl_fin_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_titulo)
	lbl_fin_texto = Estilo.label("", "maquina", 17, Color(0.85, 0.82, 0.76))
	lbl_fin_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_fin_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vf.add_child(lbl_fin_texto)
	var hf := HBoxContainer.new()
	hf.alignment = BoxContainer.ALIGNMENT_CENTER
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
	var rec := Estilo.label("● REC", "ui", 12, Color(0.95, 0.2, 0.15))
	h.add_child(rec)
	var tw := create_tween().set_loops()
	tw.tween_property(rec, "modulate:a", 0.25, 0.7)
	tw.tween_property(rec, "modulate:a", 1.0, 0.7)
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
	for i in TURNOS_MAX:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(10, 6)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		turno_pips.add_child(pip)
	lbl_turnos = Estilo.label("12", "ui", 12, Color(0.85, 0.82, 0.76))
	lbl_turnos.custom_minimum_size.x = 28
	lbl_turnos.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ht.add_child(lbl_turnos)

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
	sub_panel.add_theme_stylebox_override("panel", Estilo.caja(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0), 0, 4, Vector4(18, 6, 18, 8)))
	p_juego.add_child(sub_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.add_child(v)
	lbl_sub_quien = Estilo.label("", "titulo", 14, Color(0.9, 0.35, 0.28))
	lbl_sub_quien.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl_sub_quien)
	lbl_sub = Estilo.label("", "maquina", 17, Color(0.93, 0.9, 0.84))
	lbl_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	v.add_child(lbl_sub)
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
		cartas.append(c)

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
			marca = "   ✓ CERRADO"
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
	verdad = 100.0 - float(actual.get("resistencia_base", 70))
	empatia = 20.0
	duda = 15.0
	turnos = TURNOS_MAX
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
	var dlg: Dictionary = actual.get("dialogos", {})
	_decir_sospechoso(str(dlg.get("saludo", "...")))
	carpeta_ui.pestana = 0
	carpeta_ui.mugshot = e.get_mugshot() if e and e.has_method("get_mugshot") else null
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

func _decir_sospechoso(texto: String) -> void:
	_reg("sosp", str(actual.get("nombre", "")), texto)
	_subtitulo(str(actual.get("nombre", "")).to_upper(), texto, Color(0.9, 0.35, 0.28))
	var e := escena()
	if e and e.has_method("hablar"):
		e.hablar(clampf(texto.length() * 0.045, 1.0, 5.0))
	if audio and audio.has_method("voz"):
		audio.voz(str(actual.get("rasgos", {}).get("tipo", "humano")), clampf(texto.length() * 0.045, 1.0, 5.0))

func _decir_detective(texto: String) -> void:
	_reg("tu", "DETECTIVE", texto)
	_subtitulo("TÚ", texto, Color(0.55, 0.7, 0.95))

func _subtitulo(quien: String, texto: String, color: Color) -> void:
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
func _ajustar(dv: float, de: float, dd: float) -> void:
	verdad = clampf(verdad + dv, 0.0, 100.0)
	empatia = clampf(empatia + de, 0.0, 100.0)
	duda = clampf(duda + dd, 0.0, 100.0)
	var e := escena()
	if e and e.has_method("set_estado_sospechoso"):
		e.set_estado_sospechoso(verdad, duda)

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
	match tactica:
		"confrontar":
			var g := 16.0 if empatia >= 15.0 else 8.0
			_ajustar(g, -10.0, 14.0)
			resp = str(dlg.get("presionado", "..."))
		"minimizar":
			_ajustar(10.0 + empatia * 0.06, 6.0, 4.0)
			resp = str(dlg.get("niega", "..."))
		"alternativa":
			_ajustar(12.0, 0.0, 9.0)
			resp = str(dlg.get("alternativa", dlg.get("niega", "...")))
		"empatia":
			_ajustar(5.0, 18.0, -6.0)
			resp = str(dlg.get("empatia", "..."))
	await _esperar(1.2)
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
		if not gastar_turno():
			return
		ocupado = true
		evidencias_usadas.append(id)
		await cerrar_carpeta()
		var g: float = float(ev.get("danio_verdad", 20)) * (1.0 + empatia / 200.0)
		_decir_detective("Mira esto. " + str(ev.get("nombre", "")) + ".")
		_reg("accion", "", "Se presenta la prueba: " + str(ev.get("nombre", "")))
		var e := escena()
		if e and e.has_method("gesto"):
			e.gesto("evidencia")
		if e and e.has_method("deslizar_evidencia"):
			e.deslizar_evidencia(str(ev.get("nombre", "")))
		if audio: audio.paper()
		await _esperar(1.0)
		_ajustar(g, 0.0, 22.0)
		if audio: audio.evidence_hit()
		_flash(Color(0.8, 0.1, 0.05), 0.18)
		if e and e.has_method("reaccion"):
			e.reaccion("evidencia", verdad, empatia)
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
	_ajustar(float(tg.get("danio_verdad", 12)) * (1.0 + empatia / 250.0), 0.0, 12.0)
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
	ocupado = true
	var nombre: String = actual.get("nombre", "?")
	_ajustar(100.0, 0.0, 100.0)
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
	resultados[actual.get("id", "")] = "ganado"
	desbloqueado_hasta = maxi(desbloqueado_hasta, int(actual.get("nivel", 1)) + 1)
	guardar_save()
	if audio: audio.win()
	_ocultar_cartas()
	await _esperar(clampf(confesion.length() * 0.035, 4.0, 9.0))
	_mostrar_fin("CONFESIÓN", ("Acusación certera. " if por_acusacion else "") + "El caso queda cerrado. Siguiente expediente desbloqueado.")

func perder(motivo: String) -> void:
	terminado = true
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
	_mostrar_fin("SIN CONFESIÓN", motivo)

func _mostrar_fin(titulo: String, texto: String) -> void:
	if estado != Estado.JUEGO:
		return
	lbl_fin_titulo.text = titulo
	lbl_fin_texto.text = texto
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
			match tac:
				"confrontar": pie = "Rompe su calma  ·  -empatía" if empatia >= 15.0 else "Está cerrado: rinde la mitad"
				"minimizar": pie = "Le ofreces una salida"
				"alternativa": pie = "Dos salidas, ambas culpables"
				"empatia": pie = "Baja la guardia"
			c.set_pie(pie, c.acento.lerp(Color(0.7, 0.7, 0.7), 0.35))
		c.set_habilitada(puede)
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
		var asoma := 118.0
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
	var idx := -1
	match k.keycode:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
		KEY_4: idx = 3
		KEY_5: idx = 4
	if idx >= 0:
		jugar_carta(cartas[idx])
