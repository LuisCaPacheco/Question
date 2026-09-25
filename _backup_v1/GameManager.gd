extends Control
## INTERROGART - GameManager (Godot 4)
## Estados: MENU (mesa vacia) -> NIVELES (6 casos, guardado) -> INTRO (cinematica)
## -> JUEGO (dialogos elegibles + evidencias + testigos + acusacion). ESC = carpeta.
## UI limpia sin iconos: tarjetas de decision debajo del registro.
## Estilo Reid duro: confrontar pega fuerte; si acusas sin 70%+ verdad, pierdes.

const DATA_PATH := "res://data/sospechosos.json"
const SAVE_PATH := "user://interrogart_save.json"
const TURNOS_MAX := 12

const LINEAS := {
	"confrontar": [
		"Las pruebas dicen que fuiste tú. No pierdas el tiempo negándolo.",
		"Te vieron ahí. Tenemos todo. Habla ahora o esto se pone peor.",
		"Deja de mentirme. Sé que estuviste ahí esa noche.",
	],
	"minimizar": [
		"Quizá no querías hacerlo. A veces nos obligan... cuéntame quién te presionó.",
		"Todos cometemos errores. Lo que importa es por qué pasó, no solo qué pasó.",
		"Si fue un accidente o te forzaron, dímelo. Eso cambia todo.",
	],
	"alternativa": [
		"¿Fue planeado o improvisado? ¿Lo pensaste o pasó de golpe?",
		"¿Fue tu idea o la de otro? ¿Tú solo o te mandaron?",
	],
	"empatia": [
		"Sé que es difícil. Estoy aquí para escucharte, no para juzgarte.",
		"Háblame de tu familia. ¿Por quién estás pasando esto?",
		"Respira. Tómate tu tiempo. Quiero entender tu lado.",
	],
}

const TACTICA_NOMBRE := {
	"confrontar": "CONFRONTAR",
	"minimizar": "MINIMIZAR",
	"alternativa": "ALTERNATIVA",
	"empatia": "EMPATIZAR",
}

const TACTICA_COLOR := {
	"confrontar": Color(0.85, 0.25, 0.2),
	"minimizar": Color(0.3, 0.7, 0.35),
	"alternativa": Color(0.85, 0.7, 0.2),
	"empatia": Color(0.3, 0.55, 0.9),
	"acusar": Color(0.65, 0.35, 0.85),
}

enum Estado { MENU, NIVELES, AJUSTES, INTRO, JUEGO }
var estado: int = Estado.MENU
var ajustes_desde_carpeta := false

const AudioManagerScript := preload("res://scripts/AudioManager.gd")
var audio  # Variant a proposito: evita chequeo estatico de tipo para no depender del cache de clases globales

var sospechosos: Array = []
var actual: Dictionary = {}
var verdad := 0.0
var empatia := 20.0
var turnos := TURNOS_MAX
var evidencias_usadas: Array = []
var testimonios_usados: Array = []
var terminado := false
var carpeta_abierta := false

# guardado
var desbloqueado_hasta := 1   # niveles 1..N abiertos
var resultados := {}          # id -> "ganado" / "perdido"
var aj_volumen := 0.8
var aj_sombras := true
var aj_sway := true

# UI raiz por estado
var p_menu: Control
var p_niveles: Control
var p_ajustes: Control
var p_intro: Control
var p_juego: Control
var p_carpeta: Control
# menu
var btn_cargar: Button
# niveles
var box_niveles: VBoxContainer
# intro
var lbl_intro_titulo: Label
var lbl_intro_texto: Label
# juego
var lbl_nombre: Label
var lbl_turnos: Label
var bar_verdad: ProgressBar
var bar_empatia: ProgressBar
var txt_log: RichTextLabel
var grid_opciones: GridContainer
var box_acusar: VBoxContainer
var lbl_estado: Label
# carpeta
var tabs: TabContainer
var box_carp_ev: VBoxContainer
var box_carp_test: VBoxContainer
var lbl_carp_caso: RichTextLabel
# ajustes
var sld_vol: HSlider
var chk_sombras: CheckBox
var chk_sway: CheckBox

func _ready() -> void:
	add_to_group("game")
	cargar_datos()
	cargar_save()
	audio = AudioManagerScript.new()
	add_child(audio)
	aplicar_ajustes()
	construir_ui()
	ir_menu()

func escena() -> Node:
	return get_tree().current_scene

# ---------- DATOS / SAVE ----------

func cargar_datos() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("No se pudo abrir " + DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed != null and parsed.has("sospechosos"):
		sospechosos = parsed["sospechosos"]
	sospechosos.sort_custom(func(a, b): return int(a.get("nivel", 99)) < int(b.get("nivel", 99)))

func cargar_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var s = JSON.parse_string(f.get_as_text())
	if s == null:
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

# ---------- UI ----------

func _panel_lleno() -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 40)
	m.add_theme_constant_override("margin_right", 40)
	m.add_theme_constant_override("margin_top", 24)
	m.add_theme_constant_override("margin_bottom", 24)
	m.visible = false
	add_child(m)
	return m

func _titulo(texto: String, tam := 44) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	return l

func _boton(texto: String, padre: Control, fn: Callable) -> Button:
	var b := Button.new()
	b.text = texto
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(fn)
	b.pressed.connect(func(): if audio: audio.click_soft())
	padre.add_child(b)
	return b

func _barra(titulo: String, padre: Control) -> ProgressBar:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padre.add_child(vb)
	var l := Label.new()
	l.text = titulo
	vb.add_child(l)
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.value = 0
	b.custom_minimum_size = Vector2(0, 20)
	b.show_percentage = true
	vb.add_child(b)
	return b

## Tarjeta de decision: panel oscuro con borde lateral de color por tactica
func _estilo_tarjeta(acento: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.10, 0.13, 0.96)
	s.border_color = acento
	s.set_border_width_all(0)
	s.border_width_left = 5
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _tarjeta(texto: String, tactica: String, padre: Control, fn: Callable) -> Button:
	var acento: Color = TACTICA_COLOR.get(tactica, Color(0.5, 0.5, 0.5))
	var b := Button.new()
	b.text = texto
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", _estilo_tarjeta(acento))
	b.add_theme_stylebox_override("hover", _estilo_tarjeta(acento.lightened(0.25)))
	b.add_theme_stylebox_override("pressed", _estilo_tarjeta(acento.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", _estilo_tarjeta(Color(0.3, 0.3, 0.3)))
	b.pressed.connect(fn)
	b.pressed.connect(func(): if audio: (audio.click_hard() if tactica == "acusar" else audio.click_soft()))
	padre.add_child(b)
	return b

func construir_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ---- MENU ----
	p_menu = _panel_lleno()
	var vm := VBoxContainer.new()
	vm.alignment = BoxContainer.ALIGNMENT_CENTER
	vm.add_theme_constant_override("separation", 12)
	p_menu.add_child(vm)
	vm.add_child(_titulo("Interrogar.", 72))
	var sub := Label.new()
	sub.text = "3045 · un cuarto · una luz · la verdad"
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vm.add_child(sub)
	_boton("Nueva partida", vm, ir_niveles)
	btn_cargar = _boton("Cargar partida", vm, ir_niveles)
	_boton("Ajustes", vm, func(): ir_ajustes(false))
	# ---- NIVELES ----
	p_niveles = _panel_lleno()
	var vn := VBoxContainer.new()
	vn.add_theme_constant_override("separation", 8)
	p_niveles.add_child(vn)
	vn.add_child(_titulo("Expedientes", 36))
	box_niveles = VBoxContainer.new()
	box_niveles.add_theme_constant_override("separation", 6)
	vn.add_child(box_niveles)
	_boton("Volver", vn, ir_menu)
	# ---- AJUSTES ----
	p_ajustes = _panel_lleno()
	var va := VBoxContainer.new()
	va.alignment = BoxContainer.ALIGNMENT_CENTER
	va.add_theme_constant_override("separation", 12)
	p_ajustes.add_child(va)
	va.add_child(_titulo("Ajustes", 36))
	var lv := Label.new()
	lv.text = "Volumen"
	va.add_child(lv)
	sld_vol = HSlider.new()
	sld_vol.min_value = 0
	sld_vol.max_value = 100
	sld_vol.value = aj_volumen * 100
	sld_vol.value_changed.connect(func(v): aj_volumen = v / 100.0; aplicar_ajustes())
	va.add_child(sld_vol)
	chk_sombras = CheckBox.new()
	chk_sombras.text = "Sombras (calidad)"
	chk_sombras.button_pressed = aj_sombras
	chk_sombras.toggled.connect(func(on): aj_sombras = on; aplicar_ajustes())
	va.add_child(chk_sombras)
	chk_sway = CheckBox.new()
	chk_sway.text = "Cámara viva (respiración)"
	chk_sway.button_pressed = aj_sway
	chk_sway.toggled.connect(func(on): aj_sway = on; aplicar_ajustes())
	va.add_child(chk_sway)
	_boton("Guardar y volver", va, func(): guardar_save(); ir_ajustes_volver())
	# ---- INTRO ----
	p_intro = _panel_lleno()
	var vi := VBoxContainer.new()
	vi.alignment = BoxContainer.ALIGNMENT_CENTER
	vi.add_theme_constant_override("separation", 14)
	p_intro.add_child(vi)
	lbl_intro_titulo = _titulo("", 34)
	vi.add_child(lbl_intro_titulo)
	lbl_intro_texto = Label.new()
	lbl_intro_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_intro_texto.add_theme_font_size_override("font_size", 18)
	vi.add_child(lbl_intro_texto)
	_boton("COMENZAR INTERROGATORIO (Enter)", vi, empezar_juego)
	_boton("Volver a expedientes", vi, ir_niveles)
	# ---- JUEGO ----
	p_juego = _panel_lleno()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	p_juego.add_child(scroll)
	var vj := VBoxContainer.new()
	vj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vj.add_theme_constant_override("separation", 6)
	scroll.add_child(vj)
	lbl_nombre = Label.new()
	lbl_nombre.add_theme_font_size_override("font_size", 20)
	vj.add_child(lbl_nombre)
	lbl_turnos = Label.new()
	vj.add_child(lbl_turnos)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	vj.add_child(hb)
	bar_verdad = _barra("VERDAD", hb)
	bar_empatia = _barra("EMPATIA", hb)
	txt_log = RichTextLabel.new()
	txt_log.bbcode_enabled = true
	txt_log.scroll_following = true
	txt_log.custom_minimum_size = Vector2(0, 90)
	txt_log.add_theme_font_size_override("normal_font_size", 13)
	vj.add_child(txt_log)
	var lo := Label.new()
	lo.text = "DECISIONES  (teclas 1-5 · F = carpeta · ESC = carpeta)"
	lo.add_theme_font_size_override("font_size", 12)
	lo.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vj.add_child(lo)
	grid_opciones = GridContainer.new()
	grid_opciones.columns = 2
	grid_opciones.add_theme_constant_override("h_separation", 5)
	grid_opciones.add_theme_constant_override("v_separation", 5)
	vj.add_child(grid_opciones)
	box_acusar = VBoxContainer.new()
	vj.add_child(box_acusar)
	lbl_estado = Label.new()
	lbl_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vj.add_child(lbl_estado)
	var hj := HBoxContainer.new()
	hj.add_theme_constant_override("separation", 8)
	vj.add_child(hj)
	_boton("Carpeta (F)", hj, abrir_carpeta)
	_boton("Abandonar caso", hj, ir_niveles)
	# ---- CARPETA ----
	p_carpeta = _panel_lleno()
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 8)
	p_carpeta.add_child(vc)
	vc.add_child(_titulo("Expediente del caso", 30))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vc.add_child(tabs)
	var t_caso := ScrollContainer.new()
	t_caso.name = "CASO"
	tabs.add_child(t_caso)
	lbl_carp_caso = RichTextLabel.new()
	lbl_carp_caso.bbcode_enabled = true
	lbl_carp_caso.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_carp_caso.add_theme_font_size_override("normal_font_size", 15)
	t_caso.add_child(lbl_carp_caso)
	var t_ev := ScrollContainer.new()
	t_ev.name = "EVIDENCIAS"
	tabs.add_child(t_ev)
	box_carp_ev = VBoxContainer.new()
	box_carp_ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_ev.add_child(box_carp_ev)
	var t_test := ScrollContainer.new()
	t_test.name = "TESTIGOS"
	tabs.add_child(t_test)
	box_carp_test = VBoxContainer.new()
	box_carp_test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t_test.add_child(box_carp_test)
	var hc := HBoxContainer.new()
	hc.add_theme_constant_override("separation", 8)
	vc.add_child(hc)
	_boton("Guardar partida", hc, func(): guardar_save(); lbl_estado.text = "Partida guardada.")
	_boton("Ajustes", hc, func(): ir_ajustes(true))
	_boton("Cerrar (ESC)", hc, cerrar_carpeta)

func _mostrar_solo(p: Control) -> void:
	for x in [p_menu, p_niveles, p_ajustes, p_intro, p_juego, p_carpeta]:
		x.visible = (x == p)

# ---------- NAVEGACION ----------

func ir_menu() -> void:
	estado = Estado.MENU
	carpeta_abierta = false
	if audio: audio.stop_ambient()
	_mostrar_solo(p_menu)
	var e := escena()
	if e and e.has_method("ocultar_sospechoso"):
		e.ocultar_sospechoso()

func ir_niveles() -> void:
	estado = Estado.NIVELES
	carpeta_abierta = false
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
			marca = "  [COMPLETADO]"
		elif res == "perdido":
			marca = "  [FALLADO]"
		var b := Button.new()
		var candado := "" if abierto else "[BLOQUEADO] "
		b.text = "%sNIVEL %d — %s (%s)%s\n  %s" % [candado, nv, s.get("nombre", "?"), s.get("especie", ""), marca, s.get("intro", "")]
		b.disabled = not abierto
		b.pressed.connect(iniciar_caso.bind(s.get("id", "")))
		box_niveles.add_child(b)

func ir_ajustes(desde_carpeta: bool) -> void:
	ajustes_desde_carpeta = desde_carpeta
	estado = Estado.AJUSTES
	sld_vol.value = aj_volumen * 100
	chk_sombras.button_pressed = aj_sombras
	chk_sway.button_pressed = aj_sway
	_mostrar_solo(p_ajustes)

func ir_ajustes_volver() -> void:
	if ajustes_desde_carpeta and estado == Estado.AJUSTES and not actual.is_empty():
		_mostrar_solo(p_carpeta)
	else:
		ir_menu()

# ---------- CASO / INTRO / JUEGO ----------

func por_id(id: String) -> Dictionary:
	for s in sospechosos:
		if s.get("id", "") == id:
			return s
	return {}

func iniciar_caso(id: String) -> void:
	var s := por_id(id)
	if s.is_empty():
		return
	actual = s
	estado = Estado.INTRO
	carpeta_abierta = false
	_mostrar_solo(p_intro)
	var e := escena()
	if e:
		if e.has_method("set_especie"):
			e.set_especie(str(s.get("id", "")))
		if e.has_method("set_avatar"):
			e.set_avatar(s.get("avatar", {}))
		if e.has_method("mostrar_sospechoso"):
			e.mostrar_sospechoso()
		if e.has_method("play_intro"):
			e.play_intro()
	lbl_intro_titulo.text = "NIVEL %d — %s" % [int(s.get("nivel", 0)), s.get("nombre", "?")]
	lbl_intro_texto.text = "%s\n\n%s\n\nRol: %s (%s)\n\nTienes %d turnos. Al 100%% de verdad, confiesa." % [
		s.get("intro", ""), s.get("briefing", ""), s.get("rol", ""), s.get("especie", ""), TURNOS_MAX]

func empezar_juego() -> void:
	if actual.is_empty():
		return
	estado = Estado.JUEGO
	verdad = 100.0 - float(actual.get("resistencia_base", 70))
	empatia = 20.0
	turnos = TURNOS_MAX
	evidencias_usadas = []
	testimonios_usados = []
	terminado = false
	carpeta_abierta = false
	_mostrar_solo(p_juego)
	lbl_nombre.text = "NIVEL %d — %s (%s)" % [int(actual.get("nivel", 0)), actual.get("nombre", ""), actual.get("especie", "")]
	txt_log.clear()
	var dlg: Dictionary = actual.get("dialogos", {})
	log_line("[color=gray]%s: %s[/color]" % [actual.get("rol", ""), dlg.get("saludo", "...")])
	log_line("Elige una tarjeta (1-5). Abre la carpeta de la mesa o pulsa F para evidencias y testigos. Con 70% o más de verdad puedes lanzar la ACUSACION FINAL.")
	if audio: audio.start_ambient()
	refrescar()

func log_line(t: String) -> void:
	txt_log.append_text(t + "\n\n")

func gastar_turno() -> bool:
	if terminado or estado != Estado.JUEGO:
		return false
	turnos -= 1
	if turnos <= 0 and verdad < 100.0:
		perder(false, "")
		return false
	return true

func _reaccionar_sala(tipo: String) -> void:
	var e := escena()
	if e and e.has_method("react"):
		e.react(tipo)

func elegir_opcion(tipo: String) -> void:
	if not gastar_turno():
		return
	var pool: Array = LINEAS.get(tipo, ["Habla."])
	var linea: String = pool[randi() % pool.size()]
	var nombre: String = actual.get("nombre", "?")
	var dlg: Dictionary = actual.get("dialogos", {})
	var tag: String = TACTICA_NOMBRE.get(tipo, tipo.to_upper())
	if tipo == "confrontar":
		var g := 16.0
		empatia = maxf(0.0, empatia - 10.0)
		if empatia < 15.0:
			g *= 0.5
		verdad = minf(100.0, verdad + g)
		log_line("[b]TU [%s]:[/b] %s\n[color=gray]%s: %s[/color] [color=orange](+%.0f, -10 emp)[/color]" % [tag, linea, nombre, dlg.get("presionado", "..."), g])
	elif tipo == "minimizar":
		var g := 10.0 + empatia * 0.06
		verdad = minf(100.0, verdad + g)
		empatia = minf(100.0, empatia + 6.0)
		log_line("[b]TU [%s]:[/b] %s\n[color=gray]%s: %s[/color] [color=green](+%.0f)[/color]" % [tag, linea, nombre, dlg.get("niega", "..."), g])
	elif tipo == "alternativa":
		var g := 12.0
		verdad = minf(100.0, verdad + g)
		log_line("[b]TU [%s]:[/b] %s\n[color=gray]%s: ...duda... %s[/color] [color=green](+%.0f)[/color]" % [tag, linea, nombre, dlg.get("niega", "..."), g])
	else:
		empatia = minf(100.0, empatia + 18.0)
		verdad = minf(100.0, verdad + 5.0)
		log_line("[b]TU [%s]:[/b] %s\n[color=cyan]%s: %s[/color] [color=cyan](+18 emp)[/color]" % [tag, linea, nombre, dlg.get("empatia", "...")])
	_reaccionar_sala(tipo)
	refrescar()
	chequear_win()

func mostrar_evidencia(id: String) -> void:
	if terminado or estado != Estado.JUEGO or evidencias_usadas.has(id):
		return
	for ev in actual.get("evidencias", []):
		if ev.get("id", "") == id:
			if not gastar_turno():
				return
			evidencias_usadas.append(id)
			var mult := 1.0 + (empatia / 200.0)
			var g: float = float(ev.get("danio_verdad", 20)) * mult
			verdad = minf(100.0, verdad + g)
			log_line("[b]TU [EVIDENCIA: %s][/b]\n[color=green]%s: %s  (+%.0f)[/color]" % [ev.get("nombre", ""), actual.get("nombre", ""), ev.get("texto_exito", ""), g])
			if audio: audio.evidence_hit()
			_reaccionar_sala("evidencia")
			refrescar()
			chequear_win()
			return

func presentar_testimonio(idx: int) -> void:
	if terminado or estado != Estado.JUEGO or testimonios_usados.has(idx):
		return
	var tests: Array = actual.get("testigos", [])
	if idx < 0 or idx >= tests.size():
		return
	if not gastar_turno():
		return
	testimonios_usados.append(idx)
	var tg: Dictionary = tests[idx]
	var mult := 1.0 + (empatia / 250.0)
	var g: float = float(tg.get("danio_verdad", 12)) * mult
	verdad = minf(100.0, verdad + g)
	log_line("[b]TU [TESTIGO: %s][/b]\n[color=green]%s: %s  (+%.0f)[/color]" % [tg.get("nombre", ""), actual.get("nombre", ""), tg.get("texto_exito", ""), g])
	if audio: audio.paper()
	_reaccionar_sala("evidencia")
	refrescar()
	chequear_win()

func acusacion_final() -> void:
	if terminado or estado != Estado.JUEGO:
		return
	if verdad >= 70.0:
		ganar(true)
	else:
		perder(true, "Lo acusaste con solo %.0f%% de verdad. %s se ríe, pide su abogado y el caso se hunde. (Necesitabas 70%% o más)" % [verdad, actual.get("nombre", "")])

func chequear_win() -> void:
	if terminado:
		return
	if verdad >= 100.0:
		ganar(false)

func ganar(por_acusacion: bool) -> void:
	terminado = true
	var nombre: String = actual.get("nombre", "?")
	if por_acusacion:
		log_line("[color=green][b]ACUSACION: Fuiste tú y lo sabemos.[/b] %s se derrumba: %s[/color]" % [nombre, actual.get("verdad_final", "")])
	else:
		log_line("[color=green][b]CONFIESA.[/b] %s: %s[/color]" % [nombre, actual.get("verdad_final", "")])
	lbl_estado.text = "VERDAD REVELADA. Siguiente nivel desbloqueado. Ve a Expedientes."
	resultados[actual.get("id", "")] = "ganado"
	desbloqueado_hasta = maxi(desbloqueado_hasta, int(actual.get("nivel", 1)) + 1)
	guardar_save()
	if audio: audio.win()
	refrescar()

func perder(forzado: bool, motivo: String) -> void:
	terminado = true
	var nombre: String = actual.get("nombre", "?")
	if forzado:
		log_line("[color=red]%s[/color]" % motivo)
	else:
		log_line("[color=red][b]%s:[/b] Se acabó, detective. No tienes nada. Me voy. (gana el interrogado)[/color]" % nombre)
		lbl_estado.text = "Sin turnos. GANA EL INTERROGADO, tú pierdes. Reintenta el nivel."
	resultados[actual.get("id", "")] = "perdido"
	guardar_save()
	if audio: audio.lose()
	refrescar()

func refrescar() -> void:
	bar_verdad.value = verdad
	bar_empatia.value = empatia
	lbl_turnos.text = "Turnos: %d / %d   |   Verdad: %.0f%%   |   Empatía: %.0f%%" % [turnos, TURNOS_MAX, verdad, empatia]
	if audio and not terminado:
		audio.set_tension(turnos)
	for c in grid_opciones.get_children():
		c.queue_free()
	for c in box_acusar.get_children():
		c.queue_free()
	# Cuadritos 2x2 con texto corto; la frase completa sale en el registro al elegir
	var defs := ["confrontar", "minimizar", "alternativa", "empatia"]
	var num := 1
	for d in defs:
		var pool: Array = LINEAS[d]
		var linea: String = pool[randi() % pool.size()]
		if linea.length() > 46:
			linea = linea.substr(0, 46) + "…"
		_tarjeta("%d  %s\n%s" % [num, TACTICA_NOMBRE[d], linea], d, grid_opciones, elegir_opcion.bind(d)).disabled = terminado
		num += 1
	_tarjeta("5  ACUSACION FINAL (70%+)", "acusar", box_acusar, acusacion_final).disabled = terminado
	if not terminado:
		lbl_estado.text = "Elige un cuadrito (1-5). Carpeta de la mesa o F para evidencias y testigos."

# ---------- CARPETA (ESC / F / clic) ----------

func abrir_carpeta() -> void:
	if estado != Estado.JUEGO or actual.is_empty() or carpeta_abierta:
		return
	carpeta_abierta = true
	if audio: audio.paper()
	var e := escena()
	if e and e.has_method("anim_carpeta_abrir"):
		e.anim_carpeta_abrir()
		await get_tree().create_timer(0.55).timeout
	_mostrar_solo(p_carpeta)
	lbl_carp_caso.clear()
	lbl_carp_caso.append_text("[b]NIVEL %d — %s[/b] (%s)\n[i]%s[/i]\n\n%s\n\n[b]Rol:[/b] %s\n[b]Pista:[/b] %s" % [
		int(actual.get("nivel", 0)), actual.get("nombre", ""), actual.get("especie", ""),
		actual.get("intro", ""), actual.get("briefing", ""),
		actual.get("rol", ""), actual.get("secreto", "")])
	for c in box_carp_ev.get_children():
		c.queue_free()
	for ev in actual.get("evidencias", []):
		var usada: bool = evidencias_usadas.has(ev.get("id", ""))
		var b := Button.new()
		b.text = ("[USADA] " if usada else "PRESENTAR: ") + "%s — %s" % [ev.get("nombre", ""), ev.get("descripcion", "")]
		b.disabled = usada or terminado
		b.pressed.connect(mostrar_evidencia.bind(ev.get("id", "")))
		box_carp_ev.add_child(b)
	for c in box_carp_test.get_children():
		c.queue_free()
	var tests: Array = actual.get("testigos", [])
	if tests.is_empty():
		var l := Label.new()
		l.text = "Sin testigos registrados."
		box_carp_test.add_child(l)
	for i in tests.size():
		var tg: Dictionary = tests[i]
		var usado: bool = testimonios_usados.has(i)
		var bt := Button.new()
		bt.text = ("[USADO] " if usado else "CITAR: ") + "%s — \"%s\"" % [tg.get("nombre", ""), tg.get("texto", "")]
		bt.disabled = usado or terminado
		bt.pressed.connect(presentar_testimonio.bind(i))
		box_carp_test.add_child(bt)

func cerrar_carpeta() -> void:
	if estado != Estado.JUEGO:
		return
	carpeta_abierta = false
	var e := escena()
	if e and e.has_method("anim_carpeta_cerrar"):
		e.anim_carpeta_cerrar()
	_mostrar_solo(p_juego)
	refrescar()

# ---------- TECLADO ----------

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if estado == Estado.INTRO and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE):
			empezar_juego()
			return
		if estado != Estado.JUEGO:
			return
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_F:
			if carpeta_abierta:
				cerrar_carpeta()
			else:
				abrir_carpeta()
			return
		if carpeta_abierta or terminado:
			return
		match k.keycode:
			KEY_1: elegir_opcion("confrontar")
			KEY_2: elegir_opcion("minimizar")
			KEY_3: elegir_opcion("alternativa")
			KEY_4: elegir_opcion("empatia")
			KEY_5: acusacion_final()
