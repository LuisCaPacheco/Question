extends Node3D
## INTERROGART - sospechoso procedural "siniestro".
## Cabeza esculpida con primitivas (craneo, pomulos marcados, cuencas hundidas, ojos
## que brillan y te siguen, dientes, cicatrices con Decal), piel con shader (manchas,
## venas, grietas de lava), esposas encadenadas a la mesa y manos con dedos articulados
## que tamborilean. Tipos: humano | kthar | molk. Todo sale de sospechosos.json -> "rasgos".

const Proc := preload("res://scripts/Proc.gd")
const ManoScript := preload("res://scripts/Mano.gd")

const MESA_Y := 0.795

var camara_pos := Vector3(0, 1.38, 0.6)   # en mundo; Room3D la mantiene al dia
var rasgos: Dictionary = {}
var tipo := "humano"
var nervios := 0.2
var verdad_ref := 0.0
var emocion := "calma"
var hablando := 0.0
var t := 0.0
var _base_pos := Vector3.ZERO

# estado animado (valor actual y objetivo)
var _lean := 0.0
var _lean_obj := 0.0
var _tilt := 0.0
var _tilt_obj := 0.0
var _baja := 0.0
var _baja_obj := 0.0
var _grin := 0.3
var _grin_obj := 0.3
var _abre := 0.0
var _abre_min := 0.0
var _entre := 0.0
var _entre_obj := 0.0
var _cejas := 0.0
var _cejas_obj := 0.0
var _glow := 1.0
var _glow_obj := 1.0
var _flinch := 0.0
var _parp_t := 2.5
var _parp_fase := -1.0
var _tambor_t := 3.0
var _tambor := -1.0
var _mirada_off := Vector3.ZERO
var _mirada_t := 0.0
var _emocion_t := 0.0

# nodos
var torso_piv: Node3D
var cabeza_piv: Node3D
var cabeza: Node3D
var mandibula: Node3D
var boca_cav: MeshInstance3D
var dientes_sup: Node3D
var comisuras: Array = []
var cejas: Array = []          # [nodo, lado, y_base]
var ojos: Array = []
var mat_iris: Array = []
var glow_base := 2.5
var pinzas: Array = []
var sudor: Array = []
var hombros: Array = []
var codos: Array = []
var brazo_sup: Array = []
var manos: Array = []
var mat_piel: ShaderMaterial
var mat_ropa: ShaderMaterial
var mat_negro: StandardMaterial3D
var esc := Vector3.ONE

func _ready() -> void:
	_base_pos = position

func colocar(pos: Vector3) -> void:
	position = pos
	_base_pos = pos

func _col(k: String, fb: Color) -> Color:
	var v = rasgos.get(k, null)
	if v == null:
		return fb
	var s := str(v).strip_edges()
	if not s.begins_with("#"):
		s = "#" + s
	if s.length() == 7 or s.length() == 9:
		return Color.html(s)
	return fb

func _num(k: String, fb: float) -> float:
	return float(rasgos.get(k, fb))

# =====================================================================
# CONSTRUCCION
# =====================================================================

func construir(r: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	comisuras.clear(); cejas.clear(); ojos.clear(); mat_iris.clear(); pinzas.clear()
	sudor.clear(); hombros.clear(); codos.clear(); brazo_sup.clear(); manos.clear()
	mandibula = null; boca_cav = null; dientes_sup = null
	rasgos = r
	tipo = str(r.get("tipo", "humano"))
	var cb: Array = r.get("cuerpo", [1, 1, 1])
	esc = Vector3(float(cb[0]), float(cb[1]), float(cb[2])) if cb.size() >= 3 else Vector3.ONE
	glow_base = _num("brillo_ojos", 2.5)
	var piel_c := _col("piel", Color(0.7, 0.55, 0.45))
	mat_piel = Proc.piel(piel_c, {
		"manchas": _num("manchas", 0.55),
		"venas": _num("venas", 0.35),
		"mancha": _col("mancha", piel_c.darkened(0.4).lerp(Color(0.4, 0.1, 0.12), 0.35)),
		"vena": _col("vena", Color(0.3, 0.22, 0.42)),
		"grietas": _num("grietas", 0.0),
		"grieta_col": _col("grieta_col", Color(1.0, 0.35, 0.05)),
		"suciedad": _num("suciedad", 0.3),
		"sss": 0.05 if tipo == "molk" else 0.4,
		"rug": 0.95 if tipo == "molk" else 0.68,
		"semilla": int(r.get("semilla", 5)),
	})
	mat_ropa = Proc.piel(_col("ropa", Color(0.72, 0.28, 0.08)), {
		"manchas": _num("manchas_ropa", 0.6),
		"mancha": _col("mancha_ropa", Color(0.22, 0.05, 0.03)),
		"venas": 0.0, "rug": 0.95, "sss": 0.0, "escala": 5.0, "borde": 0.12, "suciedad": 0.55,
		"semilla": 21,
	})
	mat_negro = Proc.mat(Color(0.012, 0.005, 0.005), 1.0)
	_silla()
	_cuerpo()
	_cabeza()
	_brazos()
	_cadenas()
	_parp_t = 2.0
	set_emocion("calma")

func _silla() -> void:
	var metal := Proc.superficie(Color(0.1, 0.1, 0.11), Color(0.05, 0.04, 0.035), {"metal": 0.7, "rug_a": 0.55, "rug_b": 0.8, "manchas": 0.6, "semilla": 3})
	Proc.malla(self, Proc.caja(Vector3(0.48, 0.04, 0.44)), Vector3(0, 0.46, -0.06), metal)
	Proc.malla(self, Proc.caja(Vector3(0.48, 0.5, 0.035)), Vector3(0, 0.78, -0.3), metal, Vector3(-0.12, 0, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Proc.malla(self, Proc.cilindro(0.014, 0.014, 0.46, 8), Vector3(0.21 * sx, 0.23, -0.06 + 0.19 * sz), metal)

func _cuerpo() -> void:
	var e := esc
	# caderas y piernas (casi ocultas bajo la mesa)
	Proc.malla(self, Proc.esfera(0.17), Vector3(0, 0.56, -0.08), mat_ropa, Vector3.ZERO, Vector3(1.1 * e.x, 0.7, 0.95 * e.z))
	var bota := Proc.mat(Color(0.04, 0.035, 0.03), 0.6)
	for s in [-1, 1]:
		Proc.capsula(self, Vector3(0.1 * s * e.x, 0.53, -0.05), Vector3(0.12 * s * e.x, 0.52, 0.3), 0.075 * e.x, mat_ropa)
		Proc.capsula(self, Vector3(0.12 * s * e.x, 0.52, 0.3), Vector3(0.13 * s * e.x, 0.09, 0.34), 0.06 * e.x, mat_ropa)
		Proc.malla(self, Proc.caja(Vector3(0.1, 0.07, 0.24)), Vector3(0.13 * s * e.x, 0.035, 0.4), bota)
	torso_piv = Node3D.new()
	torso_piv.position = Vector3(0, 0.5, -0.08)
	add_child(torso_piv)
	Proc.malla(torso_piv, CapsuleMesh.new(), Vector3(0, 0.3 * e.y, 0), mat_ropa, Vector3.ZERO, Vector3(0.34 * e.x, 0.62 * e.y / 2.0, 0.26 * e.z))
	for s in [-1, 1]:
		Proc.malla(torso_piv, Proc.esfera(0.066 * e.x), Vector3(0.19 * s * e.x, 0.52 * e.y, 0), mat_ropa, Vector3.ZERO, Vector3(1.1, 0.85, 1.0))
	hombros = [Vector3(-0.2 * e.x, 0.51 * e.y, 0.0), Vector3(0.2 * e.x, 0.51 * e.y, 0.0)]
	var grosor_cuello := 1.6 if tipo == "molk" else 1.0
	Proc.capsula(torso_piv, Vector3(0, 0.55 * e.y, 0.02), Vector3(0, 0.66 * e.y, 0.05), 0.056 * grosor_cuello, mat_piel)
	# cuello del mono / tunica
	Proc.malla(torso_piv, Proc.toro(0.045 * grosor_cuello, 0.078 * grosor_cuello), Vector3(0, 0.585 * e.y, 0.025), mat_ropa, Vector3(0.25, 0, 0), Vector3(1.25, 0.9, 1.0))
	if tipo == "molk":
		# rocas en los hombros, con grietas de lava
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for s in [-1, 1]:
			for i in 3:
				var tam := Vector3(rng.randf_range(0.08, 0.14), rng.randf_range(0.06, 0.11), rng.randf_range(0.08, 0.13))
				Proc.malla(torso_piv, Proc.caja(tam), Vector3((0.19 + i * 0.03) * s * e.x, (0.56 + rng.randf_range(-0.02, 0.05)) * e.y, rng.randf_range(-0.06, 0.05)), mat_piel,
					Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)))
	# placa de preso
	var placa := str(rasgos.get("placa", ""))
	if placa != "" and not bool(rasgos.get("tunica", false)):
		var z := 0.26 * e.z * 0.5 + 0.004
		var p := Proc.malla(torso_piv, Proc.caja(Vector3(0.1, 0.036, 0.004)), Vector3(0.08 * e.x, 0.42 * e.y, z), Proc.mat(Color(0.8, 0.78, 0.72), 0.9))
		var l := Label3D.new()
		l.text = placa
		l.font_size = 40
		l.pixel_size = 0.0005
		l.modulate = Color(0.05, 0.04, 0.03)
		l.outline_size = 0
		l.shaded = true
		l.position = Vector3(0, 0, 0.0025)
		p.add_child(l)
	cabeza_piv = Node3D.new()
	cabeza_piv.position = Vector3(0, 0.64 * e.y, 0.05)
	torso_piv.add_child(cabeza_piv)

func _cabeza() -> void:
	cabeza = Node3D.new()
	var ch: Array = rasgos.get("cabeza", [1, 1, 1])
	var ce := Vector3(float(ch[0]), float(ch[1]), float(ch[2])) if ch.size() >= 3 else Vector3.ONE
	cabeza.scale = ce * 1.12
	cabeza.position = Vector3(0, 0.1, 0.03)
	cabeza_piv.add_child(cabeza)
	var ojo_c := _col("ojos", Color(1.0, 0.2, 0.1))
	match tipo:
		"kthar": _cabeza_kthar(ojo_c)
		"molk": _cabeza_molk(ojo_c)
		_: _cabeza_humana(ojo_c)
	if bool(rasgos.get("capucha", false)):
		var mc := mat_ropa.duplicate() as ShaderMaterial
		var capa := Proc.esfera(0.14, 28)
		capa.is_hemisphere = true
		capa.height = 0.14
		var hood := Proc.malla(cabeza, capa, Vector3(0, 0.02, -0.005), mc, Vector3(-PI * 0.5 + 0.18, 0, 0), Vector3(1.08, 1.18, 1.25))
		hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		# sombra dentro de la capucha
		var somb := StandardMaterial3D.new()
		somb.albedo_color = Color(0.01, 0.005, 0.005)
		somb.cull_mode = BaseMaterial3D.CULL_FRONT
		somb.roughness = 1.0
		Proc.malla(cabeza, capa, Vector3(0, 0.02, -0.01), somb, Vector3(-PI * 0.5 + 0.18, 0, 0), Vector3(1.06, 1.16, 1.22))

# ---------------- HUMANO ----------------

func _cabeza_humana(ojo_c: Color) -> void:
	var P := mat_piel
	Proc.malla(cabeza, Proc.esfera(0.105, 32), Vector3(0, 0.022, -0.012), P, Vector3.ZERO, Vector3(0.9, 1.08, 1.0))
	Proc.malla(cabeza, Proc.esfera(0.085, 28), Vector3(0, -0.045, 0.012), P, Vector3.ZERO, Vector3(0.8, 0.8, 0.95))
	# pomulos afilados y mejillas hundidas
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.esfera(0.026), Vector3(0.052 * s, -0.006, 0.066), P, Vector3.ZERO, Vector3(1.0, 0.65, 0.9))
		Proc.malla(cabeza, Proc.esfera(0.028), Vector3(0.078 * s, -0.012, 0.02), P, Vector3.ZERO, Vector3(0.8, 1.2, 1.3))
	# arco ciliar prominente
	Proc.capsula(cabeza, Vector3(-0.056, 0.037, 0.082), Vector3(0.056, 0.037, 0.082), 0.016, P)
	# cuencas hundidas y ojos
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.esfera(0.026), Vector3(0.036 * s, 0.012, 0.087), mat_negro, Vector3.ZERO, Vector3(1.18, 0.9, 0.4))
		_ojo(Vector3(0.036 * s, 0.012, 0.089), 0.0125, ojo_c, s, false)
	# nariz (tabique, punta y fosas)
	Proc.capsula(cabeza, Vector3(0, 0.03, 0.097), Vector3(0, -0.019, 0.118), 0.0105, P)
	Proc.malla(cabeza, Proc.esfera(0.0145), Vector3(0, -0.024, 0.113), P, Vector3.ZERO, Vector3(1.2, 0.9, 1.0))
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.esfera(0.0105), Vector3(0.012 * s, -0.028, 0.106), P)
		Proc.malla(cabeza, Proc.esfera(0.0045, 8), Vector3(0.0075 * s, -0.035, 0.112), mat_negro)
	# orejas
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.esfera(0.03), Vector3(0.093 * s, 0.006, -0.008), P, Vector3(0, 0.35 * s, 0), Vector3(0.35, 1.0, 0.7))
	_boca(Vector3(0, -0.063, 0.094), 0.05, P, str(rasgos.get("dientes", "normal")))
	_cejas_pelo(Vector3(0.037, 0.05, 0.097), 0.024)
	_pelo()
	_cicatriz()
	_gotas_sudor(Vector3(0, 0.07, 0.088), 0.03)

# ---------------- KTHAR (alien) ----------------

func _cabeza_kthar(ojo_c: Color) -> void:
	var P := mat_piel
	# craneo alargado hacia atras
	Proc.malla(cabeza, Proc.esfera(0.1, 32), Vector3(0, 0.06, -0.07), P, Vector3(-0.55, 0, 0), Vector3(0.8, 1.0, 1.6))
	Proc.malla(cabeza, Proc.esfera(0.085, 28), Vector3(0, -0.01, 0.02), P, Vector3.ZERO, Vector3(0.76, 1.05, 0.86))
	# crestas oseas
	for i in 5:
		var z := -0.02 - i * 0.04
		var y := 0.125 - i * 0.012
		Proc.malla(cabeza, Proc.cilindro(0.0, 0.012 - i * 0.0012, 0.035, 8), Vector3(0, y, z), P, Vector3(-0.9 - i * 0.12, 0, 0))
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.esfera(0.024), Vector3(0.05 * s, -0.012, 0.058), P, Vector3.ZERO, Vector3(1.0, 0.6, 1.0))
		# cuenca y ojo negro rasgado
		Proc.malla(cabeza, Proc.esfera(0.03), Vector3(0.037 * s, 0.014, 0.08), mat_negro, Vector3(0, 0, 0.4 * s), Vector3(1.45, 0.78, 0.5))
		_ojo(Vector3(0.037 * s, 0.014, 0.086), 0.022, ojo_c, s, true)
		# rendijas nasales
		Proc.malla(cabeza, Proc.caja(Vector3(0.0035, 0.016, 0.004)), Vector3(0.008 * s, -0.022, 0.093), mat_negro, Vector3(0, 0, 0.3 * s))
		# pinzas laterales
		var pz := Node3D.new()
		pz.position = Vector3(0.046 * s, -0.045, 0.05)
		cabeza.add_child(pz)
		Proc.capsula(pz, Vector3.ZERO, Vector3(0.008 * s, -0.05, 0.03), 0.0075, P)
		Proc.malla(pz, Proc.cilindro(0.0, 0.0075, 0.026, 8), Vector3(0.004 * s, -0.062, 0.042), Proc.mat(Color(0.08, 0.07, 0.06), 0.3), Vector3(PI + 0.5, 0, 0))
		pinzas.append([pz, s])
	_boca(Vector3(0, -0.058, 0.086), 0.06, P, "agujas")
	_cejas_pelo(Vector3(0.036, 0.047, 0.09), 0.02, true)
	_gotas_sudor(Vector3(0, 0.07, 0.078), 0.03)

# ---------------- MOLK (roca) ----------------

func _cabeza_molk(ojo_c: Color) -> void:
	var P := mat_piel
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rasgos.get("semilla", 9)) + 3
	Proc.malla(cabeza, Proc.caja(Vector3(0.21, 0.19, 0.2)), Vector3(0, 0.02, -0.01), P, Vector3(0.05, 0.0, 0.03))
	for i in 8:
		var tam := Vector3(rng.randf_range(0.06, 0.12), rng.randf_range(0.05, 0.11), rng.randf_range(0.06, 0.11))
		var pos := Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.0, 0.12), rng.randf_range(-0.1, 0.03))
		Proc.malla(cabeza, Proc.caja(tam), pos, P, Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)))
	# cuencas y ojos-brasa hundidos bajo una losa de frente
	for s in [-1, 1]:
		Proc.malla(cabeza, Proc.caja(Vector3(0.05, 0.035, 0.03)), Vector3(0.046 * s, 0.012, 0.09), mat_negro)
		_ojo(Vector3(0.046 * s, 0.012, 0.097), 0.013, ojo_c, s, false, true)
	var losa := Node3D.new()
	losa.position = Vector3(0, 0.043, 0.1)
	cabeza.add_child(losa)
	Proc.malla(losa, Proc.caja(Vector3(0.22, 0.045, 0.07)), Vector3(0, 0, -0.01), P, Vector3(0.25, 0, 0))
	cejas.append([losa, 0, losa.position.y])
	# mandibula de piedra con colmillos
	boca_cav = Proc.malla(cabeza, Proc.caja(Vector3(0.15, 0.02, 0.03)), Vector3(0, -0.05, 0.088), mat_negro)
	mandibula = Node3D.new()
	mandibula.position = Vector3(0, -0.045, -0.03)
	cabeza.add_child(mandibula)
	Proc.malla(mandibula, Proc.caja(Vector3(0.2, 0.065, 0.16)), Vector3(0, -0.04, 0.06), P, Vector3(-0.08, 0, 0))
	var colmillo := Proc.mat(Color(0.72, 0.66, 0.52), 0.5)
	for s in [-1, 1]:
		Proc.malla(mandibula, Proc.cilindro(0.0, 0.013, 0.055, 8), Vector3(0.068 * s, 0.012, 0.125), colmillo, Vector3(-0.15, 0, 0.12 * s))
	for i in 5:
		Proc.malla(mandibula, Proc.caja(Vector3(0.014, 0.014, 0.01)), Vector3(-0.035 + i * 0.0175, 0.0, 0.132), colmillo)

# ---------------- piezas comunes ----------------

func _ojo(pos: Vector3, rad: float, iris_c: Color, s: int, alien: bool, brasa := false) -> void:
	var piv := Node3D.new()
	piv.position = pos
	cabeza.add_child(piv)
	var mi := Proc.mat_emision(iris_c, glow_base)
	if brasa:
		Proc.malla(piv, Proc.esfera(rad), Vector3.ZERO, mi)
	elif alien:
		var negro := Proc.mat(Color(0.01, 0.01, 0.012), 0.05, 0.3)
		negro.clearcoat_enabled = true
		negro.clearcoat = 1.0
		var cuerpo := Node3D.new()
		cuerpo.rotation.z = 0.4 * s
		piv.add_child(cuerpo)
		Proc.malla(cuerpo, Proc.esfera(rad), Vector3.ZERO, negro, Vector3.ZERO, Vector3(1.4, 0.72, 0.55))
		# iris incandescente con pupila de rendija, como un depredador
		Proc.malla(cuerpo, Proc.esfera(rad * 0.5, 16), Vector3(0, 0, rad * 0.5), mi, Vector3.ZERO, Vector3(1.0, 1.25, 0.3))
		Proc.malla(cuerpo, Proc.caja(Vector3(rad * 0.1, rad * 0.95, rad * 0.05)), Vector3(0, 0, rad * 0.68), Proc.mat(Color(0, 0, 0), 0.1))
	else:
		var escl := Proc.mat(_col("esclera", Color(0.78, 0.7, 0.55)), 0.2)
		Proc.malla(piv, Proc.esfera(rad), Vector3.ZERO, escl)
		Proc.malla(piv, Proc.esfera(rad * 0.56), Vector3(0, 0, rad * 0.72), mi, Vector3.ZERO, Vector3(1, 1, 0.45))
		var pup := Proc.mat(Color(0, 0, 0), 0.05)
		Proc.malla(piv, Proc.esfera(rad * 0.24, 10), Vector3(0, 0, rad * 0.95), pup, Vector3.ZERO, Vector3(1.0 if not bool(rasgos.get("pupila_rendija", false)) else 0.35, 1, 0.4))
	ojos.append(piv)
	mat_iris.append(mi)

func _boca(pos: Vector3, ancho: float, P: Material, estilo: String) -> void:
	var labio := Proc.piel(_col("labios", _col("piel", Color(0.6, 0.45, 0.4)).darkened(0.35).lerp(Color(0.35, 0.08, 0.1), 0.3)), {"venas": 0.0, "manchas": 0.3, "rug": 0.45})
	boca_cav = Proc.malla(cabeza, Proc.caja(Vector3(ancho, 0.012, 0.012)), pos + Vector3(0, 0, -0.004), mat_negro)
	if estilo != "agujas":
		Proc.capsula(cabeza, pos + Vector3(-ancho * 0.48, 0.0075, 0.002), pos + Vector3(ancho * 0.48, 0.0075, 0.002), 0.0052, labio)
	dientes_sup = Node3D.new()
	dientes_sup.position = pos + Vector3(0, 0.0025, 0.0015)
	cabeza.add_child(dientes_sup)
	_fila_dientes(dientes_sup, ancho * 0.88, estilo, false)
	# mandibula articulada (menton + labio inferior + dientes inferiores)
	mandibula = Node3D.new()
	var piv_y := pos.y + 0.03
	mandibula.position = Vector3(0, piv_y, pos.z - 0.06)
	cabeza.add_child(mandibula)
	var rel := pos - mandibula.position
	var inf := Node3D.new()
	inf.position = rel + Vector3(0, -0.004, 0.0)
	mandibula.add_child(inf)
	_fila_dientes(inf, ancho * 0.8, estilo, true)
	if estilo != "agujas":
		Proc.capsula(mandibula, rel + Vector3(-ancho * 0.42, -0.0095, 0.0), rel + Vector3(ancho * 0.42, -0.0095, 0.0), 0.0058, labio)
	Proc.malla(mandibula, Proc.esfera(0.055), rel + Vector3(0, -0.03, -0.047), P, Vector3.ZERO, Vector3(1.05, 0.62, 0.9))
	if tipo == "kthar":
		Proc.malla(mandibula, Proc.cilindro(0.022, 0.0, 0.06, 12), rel + Vector3(0, -0.045, -0.02), P, Vector3(0.35, 0, 0))
	else:
		Proc.malla(mandibula, Proc.esfera(0.026), rel + Vector3(0, -0.042, -0.03), P, Vector3.ZERO, Vector3(1.25, 0.9, 1.0))
	# comisuras: la sonrisa torcida
	if estilo != "agujas":
		for s in [-1, 1]:
			var cm := Node3D.new()
			cm.position = pos + Vector3(ancho * 0.5 * s, 0.002, 0.0)
			cabeza.add_child(cm)
			Proc.capsula(cm, Vector3.ZERO, Vector3(0.012 * s, 0, -0.002), 0.0038, labio)
			comisuras.append([cm, s])

func _fila_dientes(padre: Node3D, ancho: float, estilo: String, inferior: bool) -> void:
	var col := _col("dientes_color", Color(0.78, 0.72, 0.52))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13 if inferior else 31
	var n := 12 if estilo == "agujas" else 9
	for i in n:
		var u := float(i) / float(n - 1)
		var x := lerpf(-ancho * 0.5, ancho * 0.5, u)
		var z := -absf(x) * 0.35
		var c := col
		var m: Mesh
		var rot := Vector3.ZERO
		if estilo == "podridos" and rng.randf() < 0.18:
			continue  # hueco: diente que falta
		if estilo == "agujas" or estilo == "afilados":
			var pr := PrismMesh.new()
			pr.size = Vector3(ancho / n * 0.85, 0.011 if estilo == "agujas" else 0.009, 0.003)
			m = pr
			rot = Vector3(0, 0, 0.0 if inferior else PI)
		elif estilo == "podridos":
			m = Proc.caja(Vector3(ancho / n * 0.8, rng.randf_range(0.004, 0.009), 0.003))
			c = col.lerp(Color(0.25, 0.18, 0.08), rng.randf_range(0.2, 0.8))
		else:
			m = Proc.caja(Vector3(ancho / n * 0.86, 0.0075, 0.003))
		var dy := 0.003 if inferior else -0.003
		Proc.malla(padre, m, Vector3(x, dy, z), Proc.mat(c, 0.35), rot)

func _cejas_pelo(pos: Vector3, largo: float, crestas := false) -> void:
	var colp := _col("pelo", Color(0.05, 0.04, 0.035))
	var m: Material = mat_piel if crestas else Proc.mat(colp, 0.9)
	for s in [-1, 1]:
		var cn := Node3D.new()
		cn.position = Vector3(pos.x * s, pos.y, pos.z)
		cabeza.add_child(cn)
		Proc.capsula(cn, Vector3(-largo * 0.5, 0, 0), Vector3(largo * 0.5, 0, 0), 0.0045 if not crestas else 0.0065, m)
		cejas.append([cn, s, cn.position.y])

func _pelo() -> void:
	var p := str(rasgos.get("peinado", "calvo"))
	if p == "calvo":
		return
	var colp := _col("pelo", Color(0.05, 0.04, 0.035))
	var mp := Proc.piel(colp, {"manchas": 0.4, "venas": 0.0, "rug": 0.55 if p == "grasiento" else 0.85, "sss": 0.0, "escala": 40.0, "borde": 0.5, "suciedad": 0.4})
	var cap := Proc.esfera(0.108, 28)
	cap.is_hemisphere = true
	cap.height = 0.108
	var tilt := -0.42 if p == "rapado" else -0.3
	Proc.malla(cabeza, cap, Vector3(0, 0.03, -0.014), mp, Vector3(tilt, 0, 0), Vector3(0.93, 1.02, 1.03))
	match p:
		"largo":
			Proc.capsula(cabeza, Vector3(0, 0.03, -0.075), Vector3(0, -0.16, -0.07), 0.07, mp)
			for s in [-1, 1]:
				Proc.capsula(cabeza, Vector3(0.082 * s, 0.05, 0.0), Vector3(0.085 * s, -0.13, -0.01), 0.022, mp)
				Proc.capsula(cabeza, Vector3(0.06 * s, 0.1, 0.05), Vector3(0.078 * s, 0.0, 0.055), 0.012, mp)
		"moño":
			Proc.malla(cabeza, Proc.esfera(0.042), Vector3(0, 0.08, -0.105), mp)
		"grasiento":
			for i in 4:
				var x := -0.03 + i * 0.022
				Proc.capsula(cabeza, Vector3(x, 0.11, 0.05), Vector3(x + 0.012, 0.05, 0.092), 0.005, mp)

func _cicatriz() -> void:
	var c := str(rasgos.get("cicatriz", ""))
	if c == "":
		return
	var tex := Proc.tex_cicatriz(bool(rasgos.get("puntadas", true)))
	var col := Color(1, 1, 1, 1)
	match c:
		"ojo":
			Proc.decal(cabeza, tex, Vector3(0.036, 0.01, 0.08), Vector3(0.022, 0.08, 0.1), col, Vector3(PI * 0.5, 0, 0.18))
		"mejilla":
			Proc.decal(cabeza, tex, Vector3(-0.05, -0.03, 0.07), Vector3(0.02, 0.1, 0.09), col, Vector3(PI * 0.5, -0.5, 0.75))
		"sonrisa":
			for s in [-1, 1]:
				Proc.decal(cabeza, tex, Vector3(0.042 * s, -0.052, 0.07), Vector3(0.016, 0.1, 0.05), col, Vector3(PI * 0.5, 0.55 * s, -1.05 * s))

func _gotas_sudor(pos: Vector3, ancho: float) -> void:
	if tipo == "molk":
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.85, 0.95, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 1.0
	for i in 4:
		var g := Proc.malla(cabeza, Proc.esfera(0.005, 8), pos + Vector3(-ancho + ancho * 0.66 * i, 0, 0), m, Vector3.ZERO, Vector3(1, 1.5, 0.6))
		g.visible = false
		g.set_meta("y0", g.position.y)
		sudor.append(g)

func _brazos() -> void:
	var e := esc
	codos = [Vector3(-0.27 * e.x, 0.845, 0.3), Vector3(0.27 * e.x, 0.845, 0.3)]
	var munecas := [Vector3(-0.13 * e.x, 0.83, 0.55), Vector3(0.13 * e.x, 0.83, 0.55)]
	var grosor := _num("grosor_manos", 1.0)
	var largo := _num("largo_dedos", 1.15)
	var garras := bool(rasgos.get("garras", false))
	var mat_una := Proc.mat(_col("unas", Color(0.14, 0.11, 0.08)), 0.35)
	var metal := Proc.mat(Color(0.55, 0.56, 0.58), 0.28, 1.0)
	for i in 2:
		var s := -1 if i == 0 else 1
		var w: Vector3 = munecas[i]
		brazo_sup.append(Proc.capsula(self, torso_piv.transform * hombros[i], codos[i], 0.05 * e.x, mat_ropa))
		Proc.capsula(self, codos[i], w + (codos[i] - w).normalized() * 0.05, 0.043 * e.x, mat_ropa)
		Proc.capsula(self, w + (codos[i] - w).normalized() * 0.06, w, 0.03 * grosor, mat_piel)
		# esposa
		var esposa := Proc.malla(self, Proc.toro(0.033 * grosor, 0.045 * grosor), w + (codos[i] - w).normalized() * 0.02, metal)
		esposa.basis = Proc.orient_y(w - codos[i])
		var m = ManoScript.new()
		add_child(m)
		m.construir(mat_piel, mat_una, -s, largo, grosor, garras)
		m.transform = Transform3D(Basis(Vector3.UP, PI - s * 0.32), Vector3(w.x, MESA_Y + 0.019 * grosor, w.z))
		manos.append(m)

func _cadenas() -> void:
	var metal := Proc.mat(Color(0.5, 0.5, 0.52), 0.32, 1.0)
	var anilla := Vector3(0, MESA_Y + 0.012, 0.46)
	Proc.malla(self, Proc.caja(Vector3(0.07, 0.006, 0.05)), Vector3(anilla.x, MESA_Y + 0.003, anilla.z), metal)
	Proc.malla(self, Proc.toro(0.012, 0.02), anilla, metal, Vector3(PI * 0.5, 0, 0))
	var munecas := [Vector3(-0.13 * esc.x, 0.8, 0.51), Vector3(0.13 * esc.x, 0.8, 0.51)]
	var eslabon := Proc.toro(0.005, 0.01, 12)
	for w in munecas:
		var a: Vector3 = w
		var b := anilla
		var n := 9
		for k in n:
			var u := (k + 0.5) / n
			var p := a.lerp(b, u)
			p.y = maxf(MESA_Y + 0.008, p.y - sin(u * PI) * 0.01)
			var mi := Proc.malla(self, eslabon, p, metal)
			# anillo con el plano a lo largo de la cadena, alternando 90 grados
			var bas := Proc.orient_y(b - a)
			mi.basis = bas * Basis(Vector3.UP, PI * 0.5 * (k % 2)) * Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, 1.7))

# =====================================================================
# API
# =====================================================================

func set_emocion(e: String) -> void:
	emocion = e
	_abre_min = 0.0
	match e:
		"calma":
			_lean_obj = 0.0; _tilt_obj = 0.06; _grin_obj = 0.4; _entre_obj = 0.3; _cejas_obj = 0.2; _glow_obj = 1.0; _baja_obj = 0.0
		"burla":
			_lean_obj = 0.05; _tilt_obj = 0.24 * (1.0 if randf() < 0.5 else -1.0); _grin_obj = 1.05; _entre_obj = 0.5; _cejas_obj = 0.35; _glow_obj = 1.35; _baja_obj = -0.05
		"furioso":
			_lean_obj = 0.16; _tilt_obj = 0.0; _grin_obj = 0.6; _entre_obj = 0.35; _cejas_obj = 1.0; _glow_obj = 2.3; _baja_obj = 0.12; _abre_min = 0.3
		"nervioso":
			_lean_obj = -0.03; _tilt_obj = -0.05; _grin_obj = 0.15; _entre_obj = 0.0; _cejas_obj = -0.55; _glow_obj = 0.8; _baja_obj = 0.1
		"asustado":
			_lean_obj = -0.13; _tilt_obj = 0.0; _grin_obj = 0.0; _entre_obj = -0.35; _cejas_obj = -1.0; _glow_obj = 0.6; _baja_obj = -0.05; _abre_min = 0.15
		"quebrado":
			_lean_obj = 0.2; _tilt_obj = 0.12; _grin_obj = 0.0; _entre_obj = 0.2; _cejas_obj = -0.8; _glow_obj = 0.25; _baja_obj = 0.9
		"triunfo":
			_lean_obj = -0.11; _tilt_obj = 0.3; _grin_obj = 1.4; _entre_obj = 0.55; _cejas_obj = 0.45; _glow_obj = 2.8; _baja_obj = -0.12

## Reaccion a una tactica del jugador. duda y verdad en 0..100.
func reaccionar(tactica: String, verdad: float, empatia: float) -> void:
	verdad_ref = verdad
	match tactica:
		"confrontar":
			_flinch = 0.6
			set_emocion("furioso" if verdad < 55.0 else "nervioso")
		"evidencia":
			_flinch = 1.0
			set_emocion("asustado" if nervios > 0.55 else "nervioso")
		"testigo":
			_flinch = 0.35
			set_emocion("nervioso" if verdad > 40.0 else "burla")
		"minimizar":
			set_emocion("burla" if verdad < 60.0 else "nervioso")
		"alternativa":
			set_emocion("nervioso" if verdad > 35.0 else "calma")
		"empatia":
			set_emocion("burla" if empatia < 45.0 else "calma")
		"acusar_fallo":
			set_emocion("triunfo")
	_emocion_t = 6.0

func hablar(seg: float) -> void:
	hablando = seg

func _emocion_reposo() -> String:
	if verdad_ref >= 70.0:
		return "nervioso"
	if verdad_ref >= 40.0:
		return "calma"
	return "burla"

# =====================================================================
# ANIMACION
# =====================================================================

func _process(delta: float) -> void:
	if torso_piv == null or not visible:
		return
	t += delta
	var k := 1.0 - exp(-delta * 4.0)
	_lean = lerpf(_lean, _lean_obj, k)
	_tilt = lerpf(_tilt, _tilt_obj, k * 0.6)
	_baja = lerpf(_baja, _baja_obj, k * 0.8)
	_grin = lerpf(_grin, _grin_obj, k)
	_entre = lerpf(_entre, _entre_obj, k)
	_cejas = lerpf(_cejas, _cejas_obj, k * 1.5)
	_glow = lerpf(_glow, _glow_obj, k)
	_flinch = move_toward(_flinch, 0.0, delta * 2.2)
	if hablando > 0.0:
		hablando -= delta
	if _emocion_t > 0.0:
		_emocion_t -= delta
		if _emocion_t <= 0.0 and emocion not in ["quebrado", "triunfo"]:
			set_emocion(_emocion_reposo())
	# respiracion + inclinacion
	var resp := sin(t * (1.3 + nervios * 1.6))
	torso_piv.rotation.x = 0.28 + _lean - _flinch * 0.3 + resp * 0.013
	torso_piv.rotation.z = sin(t * 0.37) * 0.015
	# temblor nervioso
	var amp := nervios * nervios * 0.005
	position = _base_pos + Vector3(sin(t * 37.0) * amp, 0.0, cos(t * 29.0) * amp * 0.5)
	_cabeza_update(delta)
	for i in brazo_sup.size():
		var sh: Vector3 = torso_piv.transform * (hombros[i] as Vector3)
		Proc.colocar_capsula(brazo_sup[i], sh, codos[i])
	_ojos_update(delta)
	_boca_update(delta)
	_manos_update(delta)
	_sudor_update(delta)
	var pulso := 0.9 + 0.1 * sin(t * 3.1)
	for m in mat_iris:
		(m as StandardMaterial3D).emission_energy_multiplier = glow_base * _glow * pulso
	if tipo == "molk" and mat_piel:
		mat_piel.set_shader_parameter("brillo_grietas", 1.5 + _glow * 1.5 + nervios * 4.0)
	elif mat_piel:
		mat_piel.set_shader_parameter("sudor", clampf(nervios * 1.2 - 0.3, 0.0, 1.0))

func _cabeza_update(delta: float) -> void:
	_mirada_t -= delta
	if _mirada_t <= 0.0:
		var r := 0.35 if emocion == "nervioso" else (0.03 if emocion in ["burla", "triunfo", "furioso"] else 0.12)
		_mirada_off = Vector3(randf_range(-r, r), randf_range(-r * 0.5, r * 0.3), 0)
		_mirada_t = randf_range(0.6, 1.6) if emocion == "nervioso" else randf_range(2.0, 4.5)
	var hp := cabeza_piv.global_position
	var dir := (camara_pos + _mirada_off * 0.4 - hp)
	if dir.length() < 0.01:
		return
	var b := Basis.looking_at(dir.normalized(), Vector3.UP, true)
	b = b * Basis(Vector3.RIGHT, _baja * 0.6 + sin(t * 0.5) * 0.02)
	b = b * Basis(Vector3.BACK, _tilt + sin(t * 0.23) * 0.03)
	var cur := cabeza_piv.global_transform.basis.orthonormalized()
	var q := Quaternion(cur).slerp(Quaternion(b.orthonormalized()), 1.0 - exp(-delta * 3.2))
	cabeza_piv.global_transform = Transform3D(Basis(q), hp)

func _ojos_update(delta: float) -> void:
	# parpadeo (poco: mirar sin parpadear da miedo)
	_parp_t -= delta
	if _parp_t <= 0.0 and _parp_fase < 0.0:
		_parp_fase = 0.0
		_parp_t = randf_range(5.0, 9.0) if emocion in ["burla", "triunfo", "calma"] else randf_range(1.2, 3.0)
	var parp := 0.0
	if _parp_fase >= 0.0:
		_parp_fase += delta / 0.16
		parp = sin(clampf(_parp_fase, 0.0, 1.0) * PI)
		if _parp_fase >= 1.0:
			_parp_fase = -1.0
	var obj := camara_pos + (_mirada_off if emocion == "nervioso" else Vector3.ZERO)
	for o in ojos:
		var n := o as Node3D
		if n.global_position.distance_to(obj) > 0.05:
			n.look_at(obj, Vector3.UP, true)
		var abiert := (1.0 - _entre * 0.5) * (1.0 - parp * 0.92)
		n.scale = Vector3(1.0 - _entre * 0.08, abiert, 1.0)

func _boca_update(delta: float) -> void:
	var abre := _abre_min
	if hablando > 0.0:
		abre = maxf(abre, 0.2 + 0.8 * absf(sin(t * 12.5) * sin(t * 5.1 + 1.0)))
	_abre = lerpf(_abre, abre, 1.0 - exp(-delta * 18.0))
	if mandibula:
		mandibula.rotation.x = _abre * (0.12 if tipo == "molk" else 0.2)
	if boca_cav:
		boca_cav.scale = Vector3(1.0 + _grin * 0.28, 0.6 + _abre * 2.6 + _grin * 0.5, 1.0)
	if dientes_sup:
		dientes_sup.scale.x = 1.0 + _grin * 0.22
	for c in comisuras:
		var s: int = c[1]
		(c[0] as Node3D).rotation.z = s * (_grin * 0.85 - 0.2)
	for p in pinzas:
		var s2: int = p[1]
		(p[0] as Node3D).rotation.z = s2 * (0.05 + _abre * 0.45 + maxf(_cejas, 0.0) * 0.25 + sin(t * 2.0) * 0.03)
	for c in cejas:
		var cn := c[0] as Node3D
		var s3: int = c[1]
		if s3 == 0:
			cn.rotation.x = 0.1 * _cejas
			cn.position.y = float(c[2]) - maxf(_cejas, 0.0) * 0.006
		else:
			cn.rotation.z = s3 * _cejas * 0.4
			cn.position.y = float(c[2]) - maxf(_cejas, 0.0) * 0.004 + maxf(-_cejas, 0.0) * 0.005

func _manos_update(delta: float) -> void:
	if manos.size() < 2:
		return
	_tambor_t -= delta
	if _tambor_t <= 0.0 and _tambor < 0.0 and emocion in ["calma", "burla", "triunfo"]:
		_tambor = 0.0
		_tambor_t = randf_range(3.0, 6.5)
	var m1 = manos[1]
	if _tambor >= 0.0:
		_tambor += delta / 0.75
		for f in 4:
			var local := _tambor * 5.0 - float(3 - f)
			m1.tap[f] = sin(local * PI) if (local > 0.0 and local < 1.0) else 0.0
		if _tambor >= 1.0:
			_tambor = -1.0
			m1.tap = [0.0, 0.0, 0.0, 0.0]
	var curl := 0.1
	match emocion:
		"furioso": curl = 0.95
		"nervioso": curl = 0.35 + sin(t * 3.0) * 0.15
		"asustado": curl = 0.55
		"quebrado": curl = 0.25
	for m in manos:
		m.temblor = nervios * nervios
		m.curl = lerpf(m.curl, curl, 1.0 - exp(-delta * 6.0))
		m.pulgar = lerpf(m.pulgar, 0.2 + curl * 0.6, 1.0 - exp(-delta * 6.0))

func _sudor_update(delta: float) -> void:
	var hay := nervios > 0.45
	for i in sudor.size():
		var g := sudor[i] as MeshInstance3D
		g.visible = hay
		if hay:
			var y0: float = g.get_meta("y0")
			g.position.y = y0 - fmod(t * (0.01 + nervios * 0.025) + i * 0.013, 0.06)
