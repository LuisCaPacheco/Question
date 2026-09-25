extends RefCounted
## INTERROGART - motor de los casos con árbol de diálogo ("modo": "arbol" en el JSON).
## Solo estado y reglas; el GameManager se encarga de mostrarlo. Mantener idéntico a
## herramientas/simular_arbol.py (el simulador valida el árbol con estas mismas reglas).
##
## Cada acción (opción, grabadora, prueba o testigo sacados de la carpeta) gasta un turno
## y devuelve un resultado:
##   {"dice": String, "accion": String, "emocion": String, "fin": String, "nodo_nuevo": bool}
## "fin" vacío = la conversación sigue.

var caso: Dictionary = {}
var A: Dictionary = {}
var N: Dictionary = {}

var nodo := ""
var confianza := 0.0
var tension := 0.0
var flags := {}
var grabando := true
var pruebas: Array = []        # ids de evidencia ya enseñadas
var testigos: Array = []       # ids de testigo ya citados
var turnos := 16
var turnos_max := 16
var revelaciones := 0          # nodos "revela" visitados (alimenta la barra de verdad)
var _visitados := {}

func iniciar(c: Dictionary) -> Dictionary:
	caso = c
	A = c.get("arbol", {})
	N = A.get("nodos", {})
	turnos_max = int(c.get("turnos", 16))
	turnos = turnos_max
	confianza = float(c.get("confianza_inicial", 15))
	tension = float(c.get("tension_inicial", 18))
	grabando = bool(c.get("grabadora_inicial", true))
	flags = {}
	pruebas = []
	testigos = []
	revelaciones = 0
	_visitados = {}
	var fin := _entrar(str(A.get("inicio", "")))
	return _resultado(fin, true)

## Porcentaje de la historia que ya ha salido a la luz (0..100).
func verdad() -> float:
	var total := 0
	for n in N.values():
		if n.get("revela", false):
			total += 1
	# con la mitad de las revelaciones ya se sabe casi todo: la barra satura antes
	return clampf(100.0 * revelaciones / maxf(1.0, total * 0.5), 0.0, 100.0)

func nodo_actual() -> Dictionary:
	return N.get(nodo, {})

## El nodo actual pide encender la grabadora (se resalta en la mesa).
func espera_grabadora() -> bool:
	return bool(nodo_actual().get("espera_grabadora", false)) and not grabando

func final_info(id: String) -> Dictionary:
	return A.get("finales", {}).get(id, {"tipo": "derrota", "titulo": id.to_upper(), "texto": ""})

# ---------------------------------------------------------------- reglas

func _lista(x) -> Array:
	if x is Array:
		return x
	return [x] if x != null and str(x) != "" else []

func cumple(si) -> bool:
	if not (si is Dictionary) or si.is_empty():
		return true
	if si.has("flag") and not flags.has(si["flag"]):
		return false
	for f in si.get("flags", []):
		if not flags.has(f):
			return false
	if si.has("no_flag") and flags.has(si["no_flag"]):
		return false
	if si.has("grabadora") and bool(si["grabadora"]) != grabando:
		return false
	if si.has("confianza_min") and confianza < float(si["confianza_min"]):
		return false
	if si.has("tension_max") and tension > float(si["tension_max"]):
		return false
	if si.has("prueba_usada") and not pruebas.has(si["prueba_usada"]):
		return false
	return true

func _aplicar(ef) -> void:
	if not (ef is Dictionary):
		return
	confianza = clampf(confianza + float(ef.get("confianza", 0)), 0.0, 100.0)
	tension = clampf(tension + float(ef.get("tension", 0)), 0.0, 100.0)
	for f in _lista(ef.get("flag")):
		flags[f] = true
	for f in _lista(ef.get("quitar_flag")):
		flags.erase(f)

func _entrar(nid: String) -> String:
	nodo = nid
	var n := nodo_actual()
	_aplicar(n.get("al_entrar"))
	if n.get("revela", false):
		if not _visitados.has(nid):
			revelaciones += 1
		if not grabando:
			flags["hablo_off"] = true
	_visitados[nid] = true
	return str(n.get("fin", ""))

func _comprobar(fin: String) -> String:
	if fin != "":
		return fin
	if tension >= 100.0:
		var tm: Dictionary = A.get("tension_max", {})
		for f in tm.get("con_flag", {}):
			if flags.has(f):
				return str(tm["con_flag"][f])
		return str(tm.get("fin", "d_abogado"))
	if turnos <= 0:
		return "d_amanecer"
	return ""

func opciones_visibles() -> Array:
	var out: Array = []
	for o in nodo_actual().get("opciones", []):
		if not cumple(o.get("si")):
			continue
		if o.has("prueba") and pruebas.has(o["prueba"]):
			continue
		if o.has("testigo") and testigos.has(o["testigo"]):
			continue
		out.append(o)
	return out

## Texto que dice el sospechoso en el nodo actual (variantes "dice_si").
func texto_nodo() -> String:
	var n := nodo_actual()
	for v in n.get("dice_si", []):
		if cumple(v.get("si")):
			return str(v.get("dice", ""))
	return str(n.get("dice", ""))

func _resultado(fin: String, nuevo: bool, dice := "") -> Dictionary:
	var n := nodo_actual()
	return {
		"dice": texto_nodo() if nuevo else dice,
		"accion": str(n.get("accion", "")) if nuevo else "",
		"emocion": str(n.get("emocion", "calma")),
		"fin": fin,
		"nodo_nuevo": nuevo,
	}

# ---------------------------------------------------------------- acciones

func elegir(o: Dictionary) -> Dictionary:
	turnos -= 1
	if o.has("grabadora"):
		grabando = bool(o["grabadora"])
	_aplicar(o.get("ef"))
	if o.has("prueba") and not pruebas.has(o["prueba"]):
		pruebas.append(o["prueba"])
	if o.has("testigo") and not testigos.has(o["testigo"]):
		testigos.append(o["testigo"])
	for c in o.get("ir_si", []):
		if cumple(c.get("si")):
			return _resultado(_comprobar(_entrar(str(c["ir"]))), true)
	if o.has("fin"):
		return _resultado(str(o["fin"]), false)
	return _resultado(_comprobar(_entrar(str(o["ir"]))), true)

## Encender / apagar la grabadora (cuenta como una acción).
func alternar_grabadora() -> Dictionary:
	turnos -= 1
	grabando = not grabando
	var r = nodo_actual().get("grabadora", {}).get("on" if grabando else "off")
	if r is Dictionary and r.has("si_no_flag") and flags.has(r["si_no_flag"]):
		r = null
	if r is Dictionary:
		_aplicar(r.get("ef"))
		if r.has("fin"):
			return _resultado(str(r["fin"]), false, str(r.get("dice", "")))
		if r.has("ir"):
			return _resultado(_comprobar(_entrar(str(r["ir"]))), true)
		return _resultado(_comprobar(""), false, str(r.get("dice", "")))
	var d: Dictionary = A.get("grabadora_defecto", {})
	var orden := ["on_traicion", "on_formal"] if grabando else ["off_confia", "off_sabe", "off_sospecha"]
	for k in orden:
		var x: Dictionary = d.get(k, {})
		if x.is_empty() or not cumple(x.get("si")):
			continue
		_aplicar(x.get("ef"))
		if x.has("fin"):
			return _resultado(str(x["fin"]), false, str(x.get("dice", "")))
		return _resultado(_comprobar(""), false, str(x.get("dice", "")))
	return _resultado(_comprobar(""), false)

## Prueba o testigo sacado de la carpeta. Si el nodo actual tiene una opción para ella,
## se juega esa opción; si no, reacción por defecto y la conversación sigue donde estaba.
func presentar(clase: String, id: String) -> Dictionary:
	for o in opciones_visibles():
		if str(o.get(clase, "")) == id:
			return elegir(o)
	turnos -= 1
	if clase == "prueba":
		if not pruebas.has(id):
			pruebas.append(id)
	elif not testigos.has(id):
		testigos.append(id)
	var tabla: Dictionary = A.get("pruebas_defecto" if clase == "prueba" else "testigos_defecto", {})
	var r: Dictionary = tabla.get(id, tabla.get("_", {}))
	_aplicar(r.get("ef"))
	return _resultado(_comprobar(""), false, str(r.get("dice", "...")))

## ¿Hay en el nodo actual una opción que use esta prueba / testigo? (pista en la carpeta)
func tiene_opcion(clase: String, id: String) -> bool:
	for o in opciones_visibles():
		if str(o.get(clase, "")) == id:
			return true
	return false
