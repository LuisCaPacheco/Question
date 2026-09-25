extends Node3D
## INTERROGART - mano procedural articulada (3 falanges por dedo + pulgar).
## Muñeca en el origen, palma hacia -Y, dedos hacia -Z.
## lado: +1 mano derecha, -1 izquierda (el pulgar queda hacia el centro del cuerpo).

const Proc := preload("res://scripts/Proc.gd")

var lado := 1
var curl := 0.12            # 0 abierta .. 1 puño
var pulgar := 0.15          # cierre del pulgar
var tap: Array = [0.0, 0.0, 0.0, 0.0]   # levanta cada dedo (tamborileo); indice..meñique
var temblor := 0.0

var _dedos: Array = []
var _pulgar_a: Node3D
var _pulgar_b: Node3D
var _t := 0.0

func construir(piel: Material, una: Material, lado_: int, largo := 1.0, grosor := 1.0, garras := false) -> void:
	lado = lado_
	for c in get_children():
		c.queue_free()
	_dedos.clear()
	_t = randf() * 10.0
	# palma + dorso
	Proc.malla(self, Proc.esfera(0.05), Vector3(0, 0, -0.046), piel, Vector3.ZERO, Vector3(0.96 * grosor, 0.36, 1.05))
	Proc.malla(self, Proc.esfera(0.03), Vector3(0, 0.002, -0.004), piel, Vector3.ZERO, Vector3(1.25 * grosor, 0.6, 1.0))
	var xs := [-0.028, -0.0095, 0.0095, 0.027]
	var largos := [0.074, 0.082, 0.077, 0.061]
	for i in 4:
		var x: float = xs[i] * lado * grosor
		var p1 := Node3D.new()
		p1.position = Vector3(x, 0.003, -0.088 + absf(xs[i]) * 0.25)
		p1.rotation.y = -x * 2.4
		add_child(p1)
		var L: float = largos[i] * largo
		var rr: float = 0.0088 * grosor * (0.88 if i == 3 else 1.0)
		Proc.malla(p1, Proc.esfera(rr * 1.18, 12), Vector3(0, 0.001, 0), piel)
		Proc.capsula(p1, Vector3.ZERO, Vector3(0, 0, -L * 0.45), rr, piel)
		var p2 := Node3D.new()
		p2.position = Vector3(0, 0, -L * 0.45)
		p1.add_child(p2)
		Proc.capsula(p2, Vector3.ZERO, Vector3(0, 0, -L * 0.3), rr * 0.93, piel)
		var p3 := Node3D.new()
		p3.position = Vector3(0, 0, -L * 0.3)
		p2.add_child(p3)
		Proc.capsula(p3, Vector3.ZERO, Vector3(0, 0, -L * 0.25), rr * 0.86, piel)
		var ul := (0.02 if garras else 0.0075) * largo
		var u := Proc.malla(p3, Proc.caja(Vector3(rr * 1.45, rr * 0.45, ul)), Vector3(0, rr * 0.6, -L * 0.25 - (ul * 0.35 if garras else -0.002)), una)
		if garras:
			u.rotation.x = -0.3
		_dedos.append([p1, p2, p3])
	# pulgar: sale del lado interno y apunta hacia delante-adentro
	_pulgar_a = Node3D.new()
	_pulgar_a.position = Vector3(-0.036 * lado * grosor, -0.004, -0.028)
	_pulgar_a.rotation.y = 0.7 * lado
	add_child(_pulgar_a)
	Proc.capsula(_pulgar_a, Vector3.ZERO, Vector3(0, 0, -0.036 * largo), 0.0115 * grosor, piel)
	_pulgar_b = Node3D.new()
	_pulgar_b.position = Vector3(0, 0, -0.036 * largo)
	_pulgar_a.add_child(_pulgar_b)
	Proc.capsula(_pulgar_b, Vector3.ZERO, Vector3(0, 0, -0.03 * largo), 0.0098 * grosor, piel)
	var ulp := (0.018 if garras else 0.008) * largo
	Proc.malla(_pulgar_b, Proc.caja(Vector3(0.014 * grosor, 0.004, ulp)), Vector3(0, 0.0065, -0.03 * largo), una)
	_aplicar()

func _process(delta: float) -> void:
	_t += delta
	_aplicar()

func _aplicar() -> void:
	for i in _dedos.size():
		var d: Array = _dedos[i]
		var tr := sin(_t * 23.0 + i * 1.7) * temblor * 0.1
		var c := clampf(curl + tr, -0.25, 1.2)
		(d[0] as Node3D).rotation.x = -c * 1.2 + float(tap[i]) * 0.6
		(d[1] as Node3D).rotation.x = -c * 1.45
		(d[2] as Node3D).rotation.x = -c * 1.0
	if _pulgar_a:
		_pulgar_a.rotation.x = -pulgar * 0.8
		_pulgar_b.rotation.x = -pulgar * 1.0
