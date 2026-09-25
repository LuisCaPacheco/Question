extends RefCounted
## INTERROGART - utilidades procedurales (sin assets externos).
## Ruido, shaders de superficie (hormigon/metal), piel (manchas, venas, grietas),
## mallas basicas, capsulas orientadas entre dos puntos y texturas dibujadas por codigo
## (cicatrices, manchas) para usarlas como Decals.

static var _cache := {}

const SHADER_SUPERFICIE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 color_a : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 color_b : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform sampler2D ruido : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float escala = 1.0;
uniform float manchas = 0.5;
uniform float rug_a = 0.9;
uniform float rug_b = 0.6;
uniform float metal = 0.0;
uniform float relieve = 0.6;
uniform vec3 estirar = vec3(1.0);
uniform float suciedad_suelo = 0.0;
uniform float lineas = 0.0;
uniform vec2 lineas_tam = vec2(0.4, 0.2);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2D tx, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z + 0.0001);
	return texture(tx, p.zy) * w.x + texture(tx, p.xz) * w.y + texture(tx, p.xy) * w.z;
}

void fragment() {
	vec3 p = wpos * escala * estirar;
	float n = tri(ruido, p * 0.35, wnrm).r;
	float n2 = tri(ruido, p * 2.7 + vec3(3.1, 7.7, 1.3), wnrm).r;
	float m = smoothstep(0.62 - manchas * 0.3, 0.92, n) * manchas;
	vec3 c = mix(color_a.rgb, color_b.rgb, m);
	c *= 0.8 + 0.4 * n2;
	if (lineas > 0.0) {
		vec3 an = abs(wnrm);
		vec2 uv = an.y > 0.5 ? wpos.xz : (an.x > 0.5 ? wpos.zy : wpos.xy);
		vec2 g = uv / lineas_tam;
		g.x += step(1.0, mod(floor(g.y), 2.0)) * 0.5;
		vec2 f = 0.5 - abs(fract(g) - 0.5);
		float borde = min(f.x * lineas_tam.x, f.y * lineas_tam.y);
		float junta = 1.0 - smoothstep(0.002, 0.007, borde);
		c *= mix(1.0, 0.42, junta * lineas);
	}
	c *= mix(1.0, clamp(wpos.y * 0.8 + 0.3, 0.0, 1.0), suciedad_suelo);
	ALBEDO = c;
	ROUGHNESS = clamp(mix(rug_a, rug_b, m) + (n2 - 0.5) * 0.2, 0.03, 1.0);
	METALLIC = metal;
	NORMAL_MAP = tri(ruido_n, p * 1.3, wnrm).rgb;
	NORMAL_MAP_DEPTH = relieve;
}
"""

const SHADER_PIEL := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base : source_color = vec4(0.7, 0.55, 0.45, 1.0);
uniform vec4 mancha : source_color = vec4(0.45, 0.3, 0.3, 1.0);
uniform vec4 vena : source_color = vec4(0.25, 0.2, 0.35, 1.0);
uniform vec4 grieta_col : source_color = vec4(1.0, 0.35, 0.05, 1.0);
uniform sampler2D ruido : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float escala = 9.0;
uniform float manchas = 0.5;
uniform float venas = 0.3;
uniform float grietas = 0.0;
uniform float brillo_grietas = 3.0;
uniform float sudor = 0.0;
uniform float rug = 0.72;
uniform float sss = 0.35;
uniform float suciedad = 0.2;
uniform float borde = 0.35;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

vec4 tri(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	return texture(ruido, p.zy) * w.x + texture(ruido, p.xz) * w.y + texture(ruido, p.xy) * w.z;
}

void fragment() {
	vec3 p = opos * escala;
	float n1 = tri(p * 0.5, onrm).r;
	float n2 = tri(p * 2.3 + vec3(5.2), onrm).r;
	float n3 = tri(p * 6.0 + vec3(1.7), onrm).r;
	vec3 c = base.rgb;
	c = mix(c, mancha.rgb, smoothstep(0.5, 0.85, n1) * manchas);
	float v = pow(1.0 - abs(n2 * 2.0 - 1.0), 14.0);
	c = mix(c, vena.rgb, v * venas);
	c *= 0.86 + 0.28 * n3;
	c = mix(c, c * 0.55, smoothstep(0.55, 0.9, n3) * suciedad);
	if (grietas > 0.0) {
		float g = pow(1.0 - abs(n1 * 2.0 - 1.0), 22.0) * grietas;
		c = mix(c, vec3(0.02), clamp(g * 1.5, 0.0, 1.0));
		EMISSION = grieta_col.rgb * g * brillo_grietas;
	}
	ALBEDO = c;
	ROUGHNESS = clamp(mix(rug, 0.16, sudor) + (n3 - 0.5) * 0.15, 0.05, 1.0);
	SPECULAR = 0.5;
	SSS_STRENGTH = sss;
	RIM = borde;
	RIM_TINT = 0.6;
}
"""

# ---------- ruido ----------

static func ruido(semilla: int, freq := 0.012, normal := false, tam := 512, oct := 5) -> NoiseTexture2D:
	var clave := "r_%d_%.4f_%s_%d_%d" % [semilla, freq, normal, tam, oct]
	if _cache.has(clave):
		return _cache[clave]
	var n := FastNoiseLite.new()
	n.seed = semilla
	n.frequency = freq
	n.fractal_octaves = oct
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = tam
	t.height = tam
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 5.0
	_cache[clave] = t
	return t

static func _shader(clave: String, codigo: String) -> Shader:
	if _cache.has(clave):
		return _cache[clave]
	var s := Shader.new()
	s.code = codigo
	_cache[clave] = s
	return s

# ---------- materiales ----------

static func mat(color: Color, rug := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rug
	m.metallic = metal
	return m

static func mat_emision(color: Color, energia := 2.0, albedo := Color(0.02, 0.02, 0.02)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energia
	m.roughness = 0.3
	return m

## Superficie en coordenadas de mundo (triplanar): hormigon, metal cepillado, suelo...
static func superficie(a: Color, b: Color, o := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("sh_superficie", SHADER_SUPERFICIE)
	m.set_shader_parameter("color_a", a)
	m.set_shader_parameter("color_b", b)
	m.set_shader_parameter("ruido", ruido(int(o.get("semilla", 11)), float(o.get("freq", 0.012))))
	m.set_shader_parameter("ruido_n", ruido(int(o.get("semilla", 11)) + 100, 0.03, true))
	m.set_shader_parameter("escala", float(o.get("escala", 1.0)))
	m.set_shader_parameter("manchas", float(o.get("manchas", 0.5)))
	m.set_shader_parameter("rug_a", float(o.get("rug_a", 0.9)))
	m.set_shader_parameter("rug_b", float(o.get("rug_b", 0.6)))
	m.set_shader_parameter("metal", float(o.get("metal", 0.0)))
	m.set_shader_parameter("relieve", float(o.get("relieve", 0.6)))
	m.set_shader_parameter("estirar", o.get("estirar", Vector3.ONE))
	m.set_shader_parameter("suciedad_suelo", float(o.get("suciedad_suelo", 0.0)))
	m.set_shader_parameter("lineas", float(o.get("lineas", 0.0)))
	m.set_shader_parameter("lineas_tam", o.get("lineas_tam", Vector2(0.4, 0.2)))
	return m

## Piel / tela en espacio de objeto (no "nada" cuando el personaje se mueve).
static func piel(base: Color, o := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("sh_piel", SHADER_PIEL)
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("mancha", o.get("mancha", base.darkened(0.35).lerp(Color(0.45, 0.12, 0.12), 0.35)))
	m.set_shader_parameter("vena", o.get("vena", Color(0.28, 0.22, 0.4)))
	m.set_shader_parameter("grieta_col", o.get("grieta_col", Color(1.0, 0.35, 0.05)))
	m.set_shader_parameter("ruido", ruido(int(o.get("semilla", 5)), 0.02))
	m.set_shader_parameter("escala", float(o.get("escala", 9.0)))
	m.set_shader_parameter("manchas", float(o.get("manchas", 0.5)))
	m.set_shader_parameter("venas", float(o.get("venas", 0.3)))
	m.set_shader_parameter("grietas", float(o.get("grietas", 0.0)))
	m.set_shader_parameter("brillo_grietas", float(o.get("brillo_grietas", 3.0)))
	m.set_shader_parameter("sudor", float(o.get("sudor", 0.0)))
	m.set_shader_parameter("rug", float(o.get("rug", 0.72)))
	m.set_shader_parameter("sss", float(o.get("sss", 0.35)))
	m.set_shader_parameter("suciedad", float(o.get("suciedad", 0.2)))
	m.set_shader_parameter("borde", float(o.get("borde", 0.35)))
	return m

# ---------- mallas ----------

static func esfera(r: float, segs := 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = maxi(6, segs / 2)
	return s

static func caja(tam: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = tam
	return b

static func cilindro(r_arriba: float, r_abajo: float, alto: float, segs := 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_arriba
	c.bottom_radius = r_abajo
	c.height = alto
	c.radial_segments = segs
	return c

static func toro(r_int: float, r_ext: float, segs := 20) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = r_int
	t.outer_radius = r_ext
	t.rings = segs
	t.ring_segments = 8
	return t

static func malla(padre: Node, m: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO, esc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = esc
	mi.material_override = material
	padre.add_child(mi)
	return mi

## Base ortonormal cuyo eje Y apunta en la direccion dada.
static func orient_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	if y.length() < 0.0001:
		return Basis()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

## Capsula entre dos puntos (coordenadas locales del padre).
static func capsula(padre: Node, a: Vector3, b: Vector3, r: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = maxf(a.distance_to(b) + r * 2.0, r * 2.0 + 0.001)
	cap.radial_segments = 16
	cap.rings = 6
	mi.mesh = cap
	mi.material_override = material
	mi.set_meta("h0", cap.height)
	mi.set_meta("r", r)
	padre.add_child(mi)
	colocar_capsula(mi, a, b)
	return mi

## Recoloca una capsula creada con capsula() entre dos puntos nuevos (estira si hace falta).
static func colocar_capsula(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var r: float = mi.get_meta("r", 0.05)
	var h0: float = mi.get_meta("h0", 1.0)
	var h := maxf(a.distance_to(b) + r * 2.0, r * 2.0 + 0.001)
	var bas := orient_y(b - a)
	bas = Basis(bas.x, bas.y * (h / h0), bas.z)
	mi.transform = Transform3D(bas, (a + b) * 0.5)

# ---------- texturas dibujadas (para Decals) ----------

## Cicatriz: linea rosada irregular con puntos de sutura opcionales.
static func tex_cicatriz(puntadas: bool) -> ImageTexture:
	var clave := "cic_%s" % puntadas
	if _cache.has(clave):
		return _cache[clave]
	var w := 64
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for y in h:
		var cx := w * 0.5 + sin(y * 0.07) * 4.0 + rng.randf_range(-0.6, 0.6)
		var ancho := 4.5 * sin(PI * float(y) / h) + 1.0
		for x in w:
			var d := absf(x - cx)
			if d < ancho + 3.0:
				var a := clampf(1.0 - (d - ancho) / 3.0, 0.0, 1.0)
				var nucleo := clampf(1.0 - d / maxf(ancho, 0.1), 0.0, 1.0)
				var c := Color(0.55, 0.18, 0.18).lerp(Color(0.85, 0.5, 0.48), nucleo * 0.6)
				c.a = a * 0.95
				img.set_pixel(x, y, c)
	if puntadas:
		var yy := 30
		while yy < h - 30:
			var cx2 := int(w * 0.5 + sin(yy * 0.07) * 4.0)
			for x in range(cx2 - 14, cx2 + 15):
				for t in 3:
					var py := yy + t - 1 + int((x - cx2) * 0.15)
					if x >= 0 and x < w and py >= 0 and py < h:
						img.set_pixel(x, py, Color(0.06, 0.03, 0.03, 0.95))
			yy += 34
	var tex := ImageTexture.create_from_image(img)
	_cache[clave] = tex
	return tex

## Mancha organica (sangre seca, cafe, suciedad). Blanca: se tinta con Decal.modulate.
static func tex_mancha(semilla: int, gotas := true) -> ImageTexture:
	var clave := "man_%d_%s" % [semilla, gotas]
	if _cache.has(clave):
		return _cache[clave]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fn := FastNoiseLite.new()
	fn.seed = semilla
	fn.frequency = 0.05
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var blobs := []
	blobs.append([Vector2(n * 0.5, n * 0.5), n * 0.26])
	if gotas:
		for i in 9:
			var ang := rng.randf() * TAU
			var dist := rng.randf_range(n * 0.25, n * 0.46)
			blobs.append([Vector2(n * 0.5, n * 0.5) + Vector2(cos(ang), sin(ang)) * dist, rng.randf_range(1.5, 5.0)])
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var a := 0.0
			var ns := 1.0 + fn.get_noise_2d(x, y) * 0.55
			for b in blobs:
				var r: float = b[1] * ns
				var d: float = p.distance_to(b[0])
				a = maxf(a, clampf((r - d) / 2.5, 0.0, 1.0))
			if a > 0.0:
				var k := 0.75 + fn.get_noise_2d(x * 3.0, y * 3.0) * 0.25
				img.set_pixel(x, y, Color(k, k, k, a * 0.9))
	var tex := ImageTexture.create_from_image(img)
	_cache[clave] = tex
	return tex

## Textura radial suave (humo, polvo, brillos).
static func tex_suave() -> GradientTexture2D:
	if _cache.has("suave"):
		return _cache["suave"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["suave"] = t
	return t

static func decal(padre: Node, tex: Texture2D, pos: Vector3, tam: Vector3, color: Color, rot := Vector3.ZERO) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = tam
	d.position = pos
	d.rotation = rot
	d.modulate = color
	d.albedo_mix = 1.0
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	padre.add_child(d)
	return d
