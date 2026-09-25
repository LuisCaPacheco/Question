extends RefCounted
## INTERROGART - fuentes del sistema y estilos 2D compartidos (sin archivos de fuente).
## titulo: Bahnschrift condensada | maquina: Courier New | mano: Ink Free | ui: Bahnschrift

static var _f := {}

static func fuente(tipo: String) -> Font:
	if _f.has(tipo):
		return _f[tipo]
	var f := SystemFont.new()
	match tipo:
		"titulo":
			f.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Impact", "Arial"])
			f.font_weight = 700
			f.font_stretch = 75
		"maquina":
			f.font_names = PackedStringArray(["Courier New", "Consolas", "Lucida Console", "Monospace"])
			f.font_weight = 600
		"mano":
			f.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Segoe Script", "Comic Sans MS"])
		_:
			f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
			f.font_weight = 400
	f.allow_system_fallback = true
	_f[tipo] = f
	return f

static func caja(bg: Color, borde := Color(0, 0, 0, 0), ancho := 0, radio := 4, margen := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = borde
	s.set_border_width_all(ancho)
	s.set_corner_radius_all(radio)
	s.content_margin_left = margen.x
	s.content_margin_top = margen.y
	s.content_margin_right = margen.z
	s.content_margin_bottom = margen.w
	s.anti_aliasing = true
	return s

static func label(texto: String, tipo: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", fuente(tipo))
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
