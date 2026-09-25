extends Control
## INTERROGART - expediente del caso (libro de dos paginas, 1280x800).
## Se renderiza en un SubViewport y se proyecta sobre la carpeta 3D que sostienen las
## manos del detective (estilo diario de Phasmophobia). Pestañas: CASO, PERFIL, PRUEBAS,
## TESTIGOS, REGISTRO y AJUSTES. Toda la informacion del caso vive aqui, no en pantalla.

signal accion(tipo: String, dato)

const Estilo := preload("res://scripts/Estilo.gd")
const Proc := preload("res://scripts/Proc.gd")
const W := 1280.0
const H := 800.0
const TINTA := Color(0.13, 0.11, 0.09)
const TINTA_SUAVE := Color(0.33, 0.29, 0.24)
const ROJO := Color(0.62, 0.1, 0.08)
const AZUL := Color(0.12, 0.2, 0.5)
const PESTANAS := [
	["CASO", Color(0.74, 0.62, 0.4)],
	["PERFIL", Color(0.62, 0.28, 0.22)],
	["PRUEBAS", Color(0.36, 0.47, 0.34)],
	["TESTIGOS", Color(0.34, 0.42, 0.57)],
	["REGISTRO", Color(0.55, 0.49, 0.35)],
	["AJUSTES", Color(0.4, 0.4, 0.42)],
]

const SHADER_PAPEL := """
shader_type canvas_item;
uniform sampler2D ruido : repeat_enable, filter_linear_mipmap;
uniform vec4 papel : source_color = vec4(0.87, 0.83, 0.73, 1.0);
uniform vec4 papel2 : source_color = vec4(0.79, 0.73, 0.59, 1.0);
void fragment() {
	vec2 uv = UV;
	float n = texture(ruido, uv * vec2(2.0, 1.25)).r;
	float fib = texture(ruido, uv * vec2(18.0, 70.0)).r;
	vec3 c = mix(papel.rgb, papel2.rgb, smoothstep(0.35, 0.85, n));
	c *= 0.93 + fib * 0.09;
	float lomo = abs(uv.x - 0.5);
	c *= mix(0.5, 1.0, smoothstep(0.0, 0.05, lomo));
	c *= mix(1.0, 0.93, smoothstep(0.1, 0.0, lomo));
	vec2 e = min(uv, 1.0 - uv);
	float borde = smoothstep(0.0, 0.03, min(e.x * 0.625, e.y));
	c *= mix(0.7, 1.0, borde);
	vec2 cp = (uv - vec2(0.83, 0.83)) * vec2(1.6, 1.0);
	float r = length(cp);
	float anillo = smoothstep(0.074, 0.08, r) * smoothstep(0.092, 0.083, r) + smoothstep(0.08, 0.0, r) * 0.12;
	c = mix(c, c * vec3(0.76, 0.6, 0.43), anillo * 0.5 * (0.7 + n * 0.6));
	vec2 sp = (uv - vec2(0.12, 0.9)) * vec2(1.6, 1.0);
	c = mix(c, c * vec3(0.7, 0.55, 0.45), smoothstep(0.05, 0.0, length(sp)) * 0.35 * n);
	COLOR = vec4(c, 1.0);
}
"""

const SHADER_FOTO := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	l = smoothstep(0.02, 0.75, l);
	COLOR = vec4(vec3(l) * vec3(1.05, 1.0, 0.9), 1.0);
}
"""

## Lineas de cuaderno para notas a mano.
class Rayado extends Control:
	var paso := 34.0
	func _draw() -> void:
		var y := paso
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.3, 0.4, 0.7, 0.22), 1.0)
			y += paso
		draw_line(Vector2(28, 0), Vector2(28, size.y), Color(0.7, 0.15, 0.12, 0.3), 1.5)

## Regla de estatura detras de la foto policial.
class Regla extends Control:
	func _draw() -> void:
		var paso := 26.0
		var y := size.y
		var i := 0
		while y > 0:
			var largo := 22.0 if i % 4 == 0 else 10.0
			draw_line(Vector2(0, y), Vector2(largo, y), Color(1, 1, 1, 0.55), 1.5)
			draw_line(Vector2(size.x - largo, y), Vector2(size.x, y), Color(1, 1, 1, 0.55), 1.5)
			y -= paso
			i += 1

var game
var pestana := 0
var sel_ev := 0
var sel_test := 0
var mugshot: Texture2D
var izq: Control
var der: Control
var _tabs: Array = []

func _ready() -> void:
	size = Vector2(W, H)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_PASS
	var tema := Theme.new()
	tema.default_font = Estilo.fuente("maquina")
	tema.default_font_size = 17
	theme = tema
	var papel := ColorRect.new()
	papel.size = size
	papel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_PAPEL
	pm.shader = sh
	pm.set_shader_parameter("ruido", Proc.ruido(123, 0.01, false, 512, 5))
	papel.material = pm
	add_child(papel)
	izq = Control.new()
	izq.position = Vector2(58, 50)
	izq.size = Vector2(526, 700)
	izq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(izq)
	der = Control.new()
	der.position = Vector2(698, 50)
	der.size = Vector2(462, 700)
	der.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(der)
	for i in PESTANAS.size():
		var b := Button.new()
		b.text = PESTANAS[i][0]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Estilo.fuente("titulo"))
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): cambiar_pestana(i))
		add_child(b)
		_tabs.append(b)
	_estilo_tabs()

# ---------------- utilidades de pagina ----------------

func _limpiar(p: Control) -> void:
	# sin remove_child: puede llamarse desde la señal del propio boton que se borra
	for c in p.get_children():
		c.visible = false
		c.queue_free()

func _col(p: Control, sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size = p.size
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return v

func _txt(p: Control, texto: String, tipo := "maquina", tam := 17, color := TINTA) -> Label:
	var l := Estilo.label(texto, tipo, tam, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 10
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_child(l)
	return l

func _raya(p: Control, ancho := 0.0, color := TINTA, grosor := 2.0) -> void:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(ancho, grosor)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL if ancho <= 0.0 else Control.SIZE_SHRINK_BEGIN
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(r)

func _sello(p: Control, texto: String, pos: Vector2, rot_deg: float, color := ROJO, tam := 30) -> Label:
	var l := Estilo.label(texto, "titulo", tam, color)
	l.add_theme_stylebox_override("normal", Estilo.caja(Color(0, 0, 0, 0), color, 3, 4, Vector4(12, 2, 12, 2)))
	l.position = pos
	l.rotation = deg_to_rad(rot_deg)
	l.modulate.a = 0.8
	p.add_child(l)
	return l

func _boton(p: Control, texto: String, fn: Callable, color := TINTA, tam := 18, alinear_izq := false) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Estilo.fuente("titulo"))
	b.add_theme_font_size_override("font_size", tam)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color.darkened(0.3))
	b.add_theme_color_override("font_pressed_color", color.darkened(0.5))
	b.add_theme_color_override("font_disabled_color", Color(color, 0.4))
	b.add_theme_stylebox_override("normal", Estilo.caja(Color(0, 0, 0, 0), color, 2, 3, Vector4(14, 7, 14, 7)))
	b.add_theme_stylebox_override("hover", Estilo.caja(Color(color, 0.12), color, 2, 3, Vector4(14, 7, 14, 7)))
	b.add_theme_stylebox_override("pressed", Estilo.caja(Color(color, 0.25), color, 2, 3, Vector4(14, 7, 14, 7)))
	b.add_theme_stylebox_override("disabled", Estilo.caja(Color(0, 0, 0, 0), Color(color, 0.3), 2, 3, Vector4(14, 7, 14, 7)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if alinear_izq:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(fn)
	b.pressed.connect(func(): accion.emit("click", null))
	p.add_child(b)
	return b

func _item(p: Control, texto: String, seleccionado: bool, fn: Callable, tachado := false) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_override("font", Estilo.fuente("maquina"))
	b.add_theme_font_size_override("font_size", 17)
	var col := TINTA_SUAVE if tachado else TINTA
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", ROJO)
	b.add_theme_color_override("font_pressed_color", ROJO)
	var fondo := Color(0.62, 0.1, 0.08, 0.12) if seleccionado else Color(0, 0, 0, 0)
	var borde := ROJO if seleccionado else Color(0, 0, 0, 0)
	var sb := Estilo.caja(fondo, borde, 0, 2, Vector4(12, 8, 10, 8))
	sb.border_width_left = 4 if seleccionado else 0
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", Estilo.caja(Color(0, 0, 0, 0.06), Color(0, 0, 0, 0), 0, 2, Vector4(12, 8, 10, 8)))
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(fn)
	b.pressed.connect(func(): accion.emit("click", null))
	p.add_child(b)
	return b

func _foto(p: Control, tam: Vector2, titulo: String, codigo: String) -> Panel:
	var marco := Panel.new()
	marco.custom_minimum_size = tam
	marco.size = tam
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Estilo.caja(Color(0.93, 0.91, 0.86), Color(0, 0, 0, 0), 0, 2)
	sb.shadow_size = 6
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(3, 4)
	marco.add_theme_stylebox_override("panel", sb)
	p.add_child(marco)
	var foto := ColorRect.new()
	foto.color = Color(0.1, 0.1, 0.11)
	foto.position = Vector2(12, 12)
	foto.size = tam - Vector2(24, 56)
	foto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(foto)
	var grano := TextureRect.new()
	grano.texture = Proc.ruido(codigo.hash() % 1000, 0.02, false, 256, 5)
	grano.stretch_mode = TextureRect.STRETCH_SCALE
	grano.position = foto.position
	grano.size = foto.size
	grano.modulate = Color(1, 1, 1, 0.22)
	grano.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(grano)
	var cod := Estilo.label(codigo, "titulo", 64, Color(1, 1, 1, 0.13))
	cod.position = foto.position + Vector2(18, foto.size.y - 86)
	marco.add_child(cod)
	var tt := Estilo.label(titulo, "maquina", 15, Color(0.85, 0.83, 0.78))
	tt.position = foto.position + Vector2(14, 12)
	tt.size = Vector2(foto.size.x - 28, 40)
	tt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	marco.add_child(tt)
	var pie := Estilo.label(codigo + "   ARCHIVO FORENSE", "mano", 17, AZUL)
	pie.position = Vector2(14, tam.y - 38)
	marco.add_child(pie)
	for esquina in [Vector2(-10, -6), Vector2(tam.x - 50, -8)]:
		var cinta := ColorRect.new()
		cinta.color = Color(0.9, 0.86, 0.7, 0.55)
		cinta.size = Vector2(60, 20)
		cinta.position = esquina
		cinta.rotation = deg_to_rad(-12.0 if esquina.x < 0 else 14.0)
		cinta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marco.add_child(cinta)
	return marco

# ---------------- pestañas ----------------

func _estilo_tabs() -> void:
	for i in _tabs.size():
		var b: Button = _tabs[i]
		var c: Color = PESTANAS[i][1]
		var sel := i == pestana
		var x := 1158.0 if sel else 1176.0
		b.position = Vector2(x, 70 + i * 96)
		b.size = Vector2(W - x - 10, 80)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c.lightened(0.12) if sel else c.darkened(0.08)
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.shadow_size = 4 if sel else 2
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.content_margin_left = 6
		for est in ["normal", "hover", "pressed"]:
			var s2 := sb.duplicate() as StyleBoxFlat
			if est == "hover":
				s2.bg_color = c.lightened(0.2)
			b.add_theme_stylebox_override(est, s2)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(0.1, 0.08, 0.06) if sel else Color(0.12, 0.1, 0.08, 0.8))
		b.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.03))

func cambiar_pestana(i: int) -> void:
	pestana = wrapi(i, 0, PESTANAS.size())
	accion.emit("pagina", pestana)
	_estilo_tabs()
	refrescar()

func tecla(k: int) -> void:
	match k:
		KEY_Q, KEY_LEFT:
			cambiar_pestana(pestana - 1)
		KEY_E, KEY_RIGHT, KEY_TAB:
			cambiar_pestana(pestana + 1)
		KEY_UP, KEY_W:
			_mover_sel(-1)
		KEY_DOWN, KEY_S:
			_mover_sel(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if pestana == 2:
				_presentar_sel()
			elif pestana == 3:
				_citar_sel()

func _elegir_ev(i: int) -> void:
	sel_ev = i
	refrescar.call_deferred()

func _elegir_test(i: int) -> void:
	sel_test = i
	refrescar.call_deferred()

func _toggle(que: String) -> void:
	accion.emit(que, not bool(game.get("aj_" + que)))
	refrescar.call_deferred()

func _mover_sel(d: int) -> void:
	if game == null:
		return
	if pestana == 2:
		var n: int = game.actual.get("evidencias", []).size()
		if n > 0:
			sel_ev = wrapi(sel_ev + d, 0, n)
	elif pestana == 3:
		var n2: int = game.actual.get("testigos", []).size()
		if n2 > 0:
			sel_test = wrapi(sel_test + d, 0, n2)
	refrescar()

func refrescar() -> void:
	if izq == null or game == null or game.actual.is_empty():
		return
	_limpiar(izq)
	_limpiar(der)
	match pestana:
		0: _pag_caso()
		1: _pag_perfil()
		2: _pag_pruebas()
		3: _pag_testigos()
		4: _pag_registro()
		5: _pag_ajustes()

# ---------------- CASO ----------------

func _pag_caso() -> void:
	var a: Dictionary = game.actual
	var v := _col(izq, 8)
	_txt(v, "DEPTO. DE INTERROGATORIOS  ·  SECTOR 3045", "maquina", 14, TINTA_SUAVE)
	_txt(v, "EXPEDIENTE %02d" % int(a.get("nivel", 0)), "titulo", 58, TINTA)
	_raya(v)
	_txt(v, str(a.get("nombre", "")).to_upper(), "titulo", 32, ROJO)
	_txt(v, str(a.get("intro", "")), "maquina", 17, TINTA_SUAVE)
	_raya(v, 60, TINTA, 1)
	_txt(v, "RESUMEN", "titulo", 20)
	_txt(v, str(a.get("briefing", "")), "maquina", 17)
	_sello(izq, "CONFIDENCIAL", Vector2(300, 6), -9.0)
	var d := _col(der, 8)
	_txt(d, "OBJETIVO", "titulo", 22)
	_txt(d, "Arranca la confesión completa (100 %% de verdad) o lanza la ACUSACIÓN FINAL con 70 %% o más. Si se te acaban los %d turnos, él gana y sale por esa puerta." % game.TURNOS_MAX, "maquina", 16)
	_raya(d, 60, TINTA, 1)
	_txt(d, "TÁCTICAS", "titulo", 20)
	for tt in [["CONFRONTAR", "Golpe duro. Mucha verdad, pero rompe la empatía."],
			["MINIMIZAR", "Dale una excusa. Funciona mejor con empatía."],
			["ALTERNATIVA", "Dos salidas, ambas culpables. Siembra duda."],
			["EMPATIZAR", "Baja la guardia. Potencia las pruebas."],
			["ACUSAR", "Todo o nada. Menos de 70 % = pierdes."]]:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.add_child(h)
		var n := Estilo.label(tt[0], "titulo", 16, ROJO)
		n.custom_minimum_size.x = 118
		h.add_child(n)
		var ex := _txt(h, tt[1], "maquina", 14)
		ex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_raya(d, 60, TINTA, 1)
	var nota := Control.new()
	nota.custom_minimum_size = Vector2(0, 190)
	nota.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(nota)
	var ray := Rayado.new()
	ray.size = Vector2(der.size.x, 190)
	ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nota.add_child(ray)
	var nt := Estilo.label("Nota del jefe:\n" + str(a.get("pista", a.get("secreto", ""))), "mano", 21, AZUL)
	nt.position = Vector2(36, 4)
	nt.size = Vector2(der.size.x - 44, 186)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nt.add_theme_constant_override("line_spacing", -3)
	nota.add_child(nt)

# ---------------- PERFIL ----------------

func _pag_perfil() -> void:
	var a: Dictionary = game.actual
	var marco := Panel.new()
	marco.position = Vector2(40, 10)
	marco.size = Vector2(380, 470)
	marco.rotation = deg_to_rad(-2.0)
	marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Estilo.caja(Color(0.93, 0.91, 0.86), Color(0, 0, 0, 0), 0, 2)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(4, 5)
	marco.add_theme_stylebox_override("panel", sb)
	izq.add_child(marco)
	var fondo := ColorRect.new()
	fondo.color = Color(0.08, 0.08, 0.09)
	fondo.position = Vector2(14, 14)
	fondo.size = Vector2(352, 390)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(fondo)
	if mugshot:
		var tr := TextureRect.new()
		tr.texture = mugshot
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = fondo.position
		tr.size = fondo.size
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER_FOTO
		fm.shader = sh
		tr.material = fm
		marco.add_child(tr)
	var regla := Regla.new()
	regla.position = fondo.position
	regla.size = fondo.size
	regla.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marco.add_child(regla)
	var placa := Estilo.label(str(a.get("rasgos", {}).get("placa", "3045")), "titulo", 22, Color(0.9, 0.9, 0.85))
	placa.add_theme_stylebox_override("normal", Estilo.caja(Color(0.05, 0.05, 0.05, 0.85), Color(0, 0, 0, 0), 0, 2, Vector4(10, 2, 10, 2)))
	placa.position = Vector2(120, 350)
	marco.add_child(placa)
	var pie := Estilo.label(str(a.get("nombre", "")), "mano", 24, AZUL)
	pie.position = Vector2(18, 412)
	marco.add_child(pie)
	_sello(izq, "PELIGROSO", Vector2(250, 520), 8.0, ROJO, 34)
	var huellas := _txt(izq, "Huellas: 10/10 registradas\nADN: en archivo\nAlias: " + str(a.get("alias", "—")), "maquina", 15, TINTA_SUAVE)
	huellas.position = Vector2(40, 510)
	huellas.size = Vector2(220, 90)
	var d := _col(der, 7)
	for par in [["NOMBRE", str(a.get("nombre", ""))], ["ESPECIE", str(a.get("especie", ""))], ["OCUPACIÓN", str(a.get("rol", ""))]]:
		_txt(d, par[0], "titulo", 15, TINTA_SUAVE)
		_txt(d, par[1], "maquina", 18)
	_raya(d, 60, TINTA, 1)
	_txt(d, "PERFIL PSICOLÓGICO", "titulo", 20)
	_txt(d, str(a.get("perfil", "Sin evaluar.")), "maquina", 15)
	_txt(d, "ANTECEDENTES", "titulo", 20)
	var ant: Array = a.get("antecedentes", [])
	for x in ant:
		_txt(d, "— " + str(x), "maquina", 15)
	_raya(d, 60, TINTA, 1)
	_txt(d, "Observado en sala: " + _observacion(), "mano", 20, AZUL)

func _observacion() -> String:
	var v: float = game.verdad
	var du: float = game.duda
	if game.terminado:
		return "Caso cerrado."
	if v >= 80.0:
		return "Está al borde. Un empujón más."
	if du >= 65.0:
		return "Suda. Le tiemblan las manos. Evita mirarme."
	if v >= 50.0:
		return "Ya no sonríe tanto. Calcula cada palabra."
	if game.empatia < 20.0:
		return "Se divierte. Cree que tiene el control."
	return "Tranquilo. Demasiado tranquilo. Me estudia."

# ---------------- PRUEBAS ----------------

func _pag_pruebas() -> void:
	var evs: Array = game.actual.get("evidencias", [])
	var v := _col(izq, 6)
	_txt(v, "PRUEBAS RECOGIDAS", "titulo", 30)
	_txt(v, "Elige una y preséntala. Cada prueba gasta un turno.", "maquina", 14, TINTA_SUAVE)
	_raya(v)
	sel_ev = clampi(sel_ev, 0, maxi(0, evs.size() - 1))
	for i in evs.size():
		var ev: Dictionary = evs[i]
		var usada: bool = game.evidencias_usadas.has(ev.get("id", ""))
		var t := "EV-%02d   %s%s" % [i + 1, ev.get("nombre", ""), "   [PRESENTADA]" if usada else ""]
		_item(v, t, i == sel_ev, _elegir_ev.bind(i), usada)
	if evs.is_empty():
		return
	var ev2: Dictionary = evs[sel_ev]
	var usada2: bool = game.evidencias_usadas.has(ev2.get("id", ""))
	var d := _col(der, 12)
	var f := _foto(d, Vector2(440, 270), str(ev2.get("nombre", "")), "EV-%02d" % (sel_ev + 1))
	f.rotation = deg_to_rad(1.5)
	_txt(d, str(ev2.get("nombre", "")).to_upper(), "titulo", 24)
	_txt(d, str(ev2.get("descripcion", "")), "maquina", 17)
	var imp := float(ev2.get("danio_verdad", 20))
	_txt(d, "Impacto estimado: " + ("DEMOLEDOR" if imp >= 30 else ("ALTO" if imp >= 25 else "MEDIO")), "mano", 21, AZUL)
	if usada2:
		_sello(der, "PRESENTADA", Vector2(250, 620), -8.0, TINTA_SUAVE, 30)
	else:
		var b := _boton(d, "PRESENTAR AL SOSPECHOSO  (1 turno)", _presentar_sel, ROJO, 20)
		b.disabled = game.terminado or game.ocupado

func _presentar_sel() -> void:
	var evs: Array = game.actual.get("evidencias", [])
	if sel_ev < evs.size():
		var id: String = evs[sel_ev].get("id", "")
		if not game.evidencias_usadas.has(id):
			accion.emit("evidencia", id)

# ---------------- TESTIGOS ----------------

func _pag_testigos() -> void:
	var ts: Array = game.actual.get("testigos", [])
	var v := _col(izq, 6)
	_txt(v, "DECLARACIONES", "titulo", 30)
	_txt(v, "Lee una declaración en su cara. Gasta un turno.", "maquina", 14, TINTA_SUAVE)
	_raya(v)
	if ts.is_empty():
		_txt(v, "Sin testigos registrados.", "mano", 22, AZUL)
		return
	sel_test = clampi(sel_test, 0, ts.size() - 1)
	for i in ts.size():
		var tg: Dictionary = ts[i]
		var usado: bool = game.testimonios_usados.has(i)
		_item(v, "T-%02d   %s%s" % [i + 1, tg.get("nombre", ""), "   [CITADO]" if usado else ""], i == sel_test, _elegir_test.bind(i), usado)
	var tg2: Dictionary = ts[sel_test]
	var usado2: bool = game.testimonios_usados.has(sel_test)
	var d := _col(der, 12)
	_txt(d, "DECLARACIÓN JURADA", "titulo", 16, TINTA_SUAVE)
	_txt(d, str(tg2.get("nombre", "")).to_upper(), "titulo", 28)
	_raya(d)
	var q := _txt(d, "«" + str(tg2.get("texto", "")) + "»", "maquina", 19)
	q.add_theme_constant_override("line_spacing", 4)
	_raya(d, 60, TINTA, 1)
	_txt(d, "Firmado ante el agente de guardia.", "mano", 19, AZUL)
	if usado2:
		_sello(der, "CITADO", Vector2(280, 600), 6.0, TINTA_SUAVE, 32)
	else:
		var b := _boton(d, "LEERLE LA DECLARACIÓN  (1 turno)", _citar_sel, AZUL, 20)
		b.disabled = game.terminado or game.ocupado

func _citar_sel() -> void:
	var ts: Array = game.actual.get("testigos", [])
	if sel_test < ts.size() and not game.testimonios_usados.has(sel_test):
		accion.emit("testigo", sel_test)

# ---------------- REGISTRO ----------------

func _pag_registro() -> void:
	var v := _col(izq, 6)
	_txt(v, "TRANSCRIPCIÓN", "titulo", 30)
	_raya(v)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.scroll_following = true
	rt.custom_minimum_size = Vector2(0, 600)
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", Estilo.fuente("maquina"))
	rt.add_theme_font_override("bold_font", Estilo.fuente("titulo"))
	rt.add_theme_font_size_override("normal_font_size", 15)
	rt.add_theme_font_size_override("bold_font_size", 16)
	rt.add_theme_color_override("default_color", TINTA)
	rt.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	v.add_child(rt)
	for e in game.registro:
		rt.append_text(_formato(e) + "\n\n")
	var d := _col(der, 10)
	_txt(d, "NOTAS", "titulo", 30)
	_raya(d)
	var nota := Control.new()
	nota.custom_minimum_size = Vector2(0, 560)
	nota.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(nota)
	var ray := Rayado.new()
	ray.size = Vector2(der.size.x, 560)
	ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nota.add_child(ray)
	var lineas: Array = []
	lineas.append("Turnos: %d de %d" % [game.turnos, game.TURNOS_MAX])
	lineas.append("Verdad: %d %%   Empatía: %d %%" % [int(game.verdad), int(game.empatia)])
	lineas.append("Pruebas usadas: %d / %d" % [game.evidencias_usadas.size(), game.actual.get("evidencias", []).size()])
	lineas.append("Testigos citados: %d / %d" % [game.testimonios_usados.size(), game.actual.get("testigos", []).size()])
	lineas.append(_observacion())
	if game.verdad >= 70.0 and not game.terminado:
		lineas.append("YA PUEDO ACUSARLO.")
	var nt := Estilo.label("\n".join(lineas), "mano", 21, AZUL)
	nt.position = Vector2(36, 2)
	nt.size = Vector2(der.size.x - 44, 540)
	nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nt.add_theme_constant_override("line_spacing", 2)
	nota.add_child(nt)

func _formato(e: Dictionary) -> String:
	var quien := str(e.get("quien", ""))
	var texto := str(e.get("texto", "")).replace("[", "(").replace("]", ")")
	match str(e.get("tipo", "")):
		"tu":
			return "[b][color=#1f3480]DETECTIVE:[/color][/b] " + texto
		"accion":
			return "[i][color=#5a4e40]" + texto + "[/color][/i]"
		"fin_bien":
			return "[b][color=#1d5a24]" + quien + ":[/color][/b] " + texto
		"fin_mal":
			return "[b][color=#8a1a12]" + quien + ":[/color][/b] " + texto
		_:
			return "[b][color=#8a1a12]" + quien.to_upper() + ":[/color][/b] " + texto

# ---------------- AJUSTES ----------------

func _pag_ajustes() -> void:
	var v := _col(izq, 14)
	_txt(v, "AJUSTES", "titulo", 40)
	_raya(v)
	_txt(v, "Volumen", "titulo", 20)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.value = game.aj_volumen * 100.0
	s.custom_minimum_size = Vector2(380, 28)
	s.focus_mode = Control.FOCUS_NONE
	s.add_theme_stylebox_override("slider", Estilo.caja(Color(0.13, 0.11, 0.09, 0.5), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	s.add_theme_stylebox_override("grabber_area", Estilo.caja(ROJO, Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	s.add_theme_stylebox_override("grabber_area_highlight", Estilo.caja(ROJO.lightened(0.2), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	s.value_changed.connect(func(x): accion.emit("volumen", x / 100.0))
	v.add_child(s)
	_boton(v, ("[X]  " if game.aj_sombras else "[  ]  ") + "Gráficos altos (sombras, niebla volumétrica, reflejos)", _toggle.bind("sombras"), TINTA, 17, true)
	_boton(v, ("[X]  " if game.aj_sway else "[  ]  ") + "Cámara viva (respiración y mirada con el ratón)", _toggle.bind("sway"), TINTA, 17, true)
	_raya(v, 60, TINTA, 1)
	_txt(v, "Controles", "titulo", 20)
	_txt(v, "1-5 · tarjetas de diálogo\nF / ESC · abrir o cerrar la carpeta\nQ / E · cambiar de pestaña\n↑ / ↓ · elegir prueba o testigo\nEnter · presentar\nClic derecho · cerrar carpeta", "maquina", 15, TINTA_SUAVE)
	var d := _col(der, 16)
	_txt(d, "PARTIDA", "titulo", 40)
	_raya(d)
	_boton(d, "GUARDAR PARTIDA", func(): accion.emit("guardar", null), TINTA, 22)
	_boton(d, "CERRAR CARPETA", func(): accion.emit("cerrar", null), TINTA, 22)
	_boton(d, "ABANDONAR CASO", func(): accion.emit("abandonar", null), ROJO, 22)
	_boton(d, "MENÚ PRINCIPAL", func(): accion.emit("menu", null), ROJO, 22)
	_sello(der, "USO INTERNO", Vector2(200, 560), -6.0, TINTA_SUAVE, 26)
