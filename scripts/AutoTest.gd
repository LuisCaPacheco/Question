extends Node
## Prueba automatica (solo si se lanza con:  -- --autotest=<carpeta_salida> [--caso=id]).
## Recorre menu -> caso -> cartas -> carpeta -> prueba, y guarda capturas PNG.

var salida := ""
var caso := "danner"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			salida = a.substr(11)
		elif a.begins_with("--caso="):
			caso = a.substr(7)
	# la prueba no debe tocar la partida guardada del jugador
	if FileAccess.file_exists(SAVE):
		_save_original = FileAccess.get_file_as_string(SAVE)
	_correr.call_deferred()

const SAVE := "user://interrogart_save.json"
var _save_original = null

func _exit_tree() -> void:
	if _save_original == null:
		DirAccess.remove_absolute(SAVE)
	else:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(_save_original)

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(salida.path_join(nombre + ".png"))
	print("AUTOTEST foto ", nombre)

func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout

## Foto desde otra cámara (ve la cabeza del agente) sin mover la del jugador.
func _vista_debug(e: Node, pos: Vector3, mira: Vector3, nombre: String) -> void:
	var c := Camera3D.new()
	c.fov = 50.0
	c.near = 0.02
	e.add_child(c)
	c.global_position = pos
	c.look_at(mira, Vector3.UP)
	c.current = true
	await _esperar(0.15)
	await _foto(nombre)
	e.cam.current = true
	c.queue_free()

## Caso con árbol: juega el camino más corto a "v_padre" (lo da simular_arbol.py).
## "G" = pulsar la grabadora. Guarda una foto por paso.
const CAMINO_VEHL := [
	"Una conversación. Soy el agente Ibarra",
	"Mira mucho esa grabadora",
	"El doctor Benn grababa cantos",
	"¿Y después? ¿Empezó a grabar sin permiso?",
	"Su asistente dice que Benn tenía",
	"Ahora lo sabe. Y yo también.",
	"[No decir nada. Dejarle terminar.]",
	"¿Todo? ¿No quedó ninguna copia?",
	"G",
	"Y ahora que lo sé todo",
	"Nira entrará en protección",
	"[Encender la grabadora]",
]

func _esperar_libre(g: Node) -> void:
	var t := 0.0
	while (g.ocupado and not g.terminado) and t < 20.0:
		await _esperar(0.1)
		t += 0.1

func _correr_arbol(g: Node, e: Node) -> void:
	if "--lateral" in OS.get_cmdline_user_args():
		await _vista_debug(e, Vector3(0.0, 1.42, -0.5), Vector3(0.0, 1.38, -0.98), "v1_cara")
		await _vista_debug(e, Vector3(0.55, 1.45, -0.7), Vector3(0.0, 1.36, -1.0), "v2_perfil")
		await _vista_debug(e, Vector3(0.0, 1.25, -0.05), Vector3(0.0, 0.83, -0.4), "v3_manos")
		g.jugar_carta(g.cartas[3])
		await _esperar(1.5)
		await _vista_debug(e, Vector3(0.0, 1.42, -0.5), Vector3(0.0, 1.38, -0.98), "v4_cara_hablando")
		if "--solo_vistas" in OS.get_cmdline_user_args():
			await _esperar_libre(g)
			await _foto("v5_tras_presion")
			get_tree().quit()
			return
	var paso := 0
	for p in CAMINO_VEHL:
		paso += 1
		var nombre := "a%02d" % paso
		if p == "G":
			g.alternar_grabadora()
			await _esperar(0.35)
			await _foto(nombre + "_mano_grabadora")
		else:
			var carta = null
			for c in g.cartas:
				if str(c.get_meta("opcion", {}).get("texto", "")).begins_with(p):
					carta = c
			if carta == null:
				var hay := []
				for c in g.cartas:
					hay.append(str(c.get_meta("opcion", {}).get("texto", "")).substr(0, 40))
				print("AUTOTEST ERROR: no hay carta '", p, "' en nodo ", g.arbol.nodo, " -> ", hay)
				await _foto(nombre + "_ERROR")
				get_tree().quit()
				return
			if paso == 1:
				carta.hover = true
				await _esperar(0.6)
				await _foto("a00_hover")
				carta.hover = false
			g.jugar_carta(carta)
			if p.begins_with("[Encender"):
				await _esperar(1.0)
				await _foto(nombre + "_mano_grabadora")
		await _esperar_libre(g)
		await _esperar(0.3)
		await _foto(nombre + "_" + str(g.arbol.nodo))
		print("AUTOTEST paso ", paso, " nodo=", g.arbol.nodo, " conf=", g.arbol.confianza, " ten=", g.arbol.tension, " grab=", g.arbol.grabando, " turnos=", g.arbol.turnos)
		if paso == 4:
			g.abrir_carpeta()
			await _esperar(2.0)
			g.carpeta_ui.cambiar_pestana(3)
			await _esperar(1.6)
			await _foto("a04b_carpeta_testigos")
			g.cerrar_carpeta()
			await _esperar(1.2)
		if g.terminado:
			break
	await _esperar(13.0)
	await _foto("a99_fin")
	print("AUTOTEST fin arbol terminado=", g.terminado, " resultado=", g.resultados.get("vehl", ""))
	get_tree().quit()

## --gestos: cada gesto de Ilvari.GESTOS, uno a uno, con una foto en su punto más intenso.
## --solo=a,b,c limita la lista; --sin_ui oculta los subtítulos y las cartas (tapan las manos).
func _correr_gestos(e: Node) -> void:
	var il = e.sospechoso.ilvari
	if il == null:
		print("AUTOTEST ERROR: el caso no tiene modelo ilvari")
		get_tree().quit()
		return
	if "--sin_ui" in OS.get_cmdline_user_args():
		for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
			c.visible = false
	var ids: Array = il.GESTOS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--solo="):
			ids = Array(a.substr(7).split(","))
	var n := 0
	for id in ids:
		n += 1
		var def = il.GESTOS[id]
		var partes: Array = def if def is Array else [def]
		var pico := 0.0
		for p in partes:
			var ee: Array = p.get("e", [0.3, 1.0, 0.5])
			var pk := float(p.get("retraso", 0.0)) + float(ee[0])
			if str(p.get("curva", "")) == "pulso":
				pk = float(p.get("retraso", 0.0)) + (float(ee[0]) + float(ee[1]) + float(ee[2])) * 0.5
			pico = maxf(pico, pk)
		e.gestos_sospechoso([id])
		await _esperar(pico + 0.35)
		await _foto("g%02d_%s" % [n, id])
		e.gestos_sospechoso([])
		await _esperar(1.6)
	print("AUTOTEST fin gestos: ", n)
	get_tree().quit()

func _correr() -> void:
	var g := get_parent()
	var e := get_tree().current_scene
	await _esperar(1.5)
	await _foto("01_menu")
	g.desbloqueado_hasta = 99
	g.iniciar_caso(caso)
	await _esperar(4.0)
	await _foto("02_intro")
	g.empezar_juego()
	await _esperar(2.5)
	await _foto("03_juego")
	if "--gestos" in OS.get_cmdline_user_args():
		await _correr_gestos(e)
		return
	if g.arbol:
		await _correr_arbol(g, e)
		return
	if "--rapido" in OS.get_cmdline_user_args():
		g.jugar_carta(g.cartas[0])
		await _esperar(3.0)
		await _foto("04_reaccion")
		get_tree().quit()
		return
	# hover sobre la carta 2
	g.cartas[1].hover = true
	await _esperar(0.6)
	await _foto("04_hover")
	g.cartas[1].hover = false
	g.jugar_carta(g.cartas[0])
	await _esperar(0.45)
	await _foto("05_carta_elegida")
	await _esperar(0.35)
	await _foto("06_golpe")
	await _esperar(1.1)
	await _foto("06b_feedback")
	await _esperar(1.4)
	await _foto("07_respuesta")
	g.abrir_carpeta()
	await _esperar(0.7)
	await _foto("08_carpeta_tomando")
	await _esperar(1.3)
	await _foto("09_carpeta_caso")
	if "--lateral" in OS.get_cmdline_user_args():
		await _vista_debug(e, Vector3(0.95, 1.35, 0.75), Vector3(0.0, 1.05, 0.2), "09x_lateral")
		await _vista_debug(e, Vector3(-0.4, 1.9, 1.2), Vector3(0.0, 1.0, 0.1), "09y_arriba")
		await _vista_debug(e, Vector3(0.35, 1.0, -0.6), Vector3(0.0, 1.05, 0.35), "09z_frente")
		await _vista_debug(e, Vector3(0.85, 1.25, 0.05), Vector3(0.28, 0.98, 0.25), "09w_antebrazo")
		await _vista_debug(e, Vector3(0.6, 1.7, 0.6), Vector3(0.2, 0.95, 0.2), "09v_hombro")
	g.carpeta_ui.cambiar_pestana(1)
	await _esperar(0.5)
	await _foto("10a_pasando_hoja")
	await _esperar(0.9)
	await _foto("10_carpeta_perfil")
	g.carpeta_ui.cambiar_pestana(3)
	await _esperar(1.5)
	await _foto("10b_carpeta_testigos")
	g.carpeta_ui.cambiar_pestana(2)
	await _esperar(0.45)
	await _foto("10c_volviendo_hoja")
	await _esperar(1.0)
	await _foto("11_carpeta_pruebas")
	var ev: Dictionary = g.actual.get("evidencias", [])[0]
	g.mostrar_evidencia(str(ev.get("id", "")))
	await _esperar(2.2)
	await _foto("12_evidencia")
	await _esperar(2.0)
	g.carpeta_ui.cambiar_pestana(4)
	g.abrir_carpeta()
	await _esperar(2.0)
	await _foto("13_registro")
	g.cerrar_carpeta()
	await _esperar(1.2)
	# con verdad alta, ACUSAR (carta 5) gana el caso y muestra la pantalla final
	g.verdad = 88.0
	g.jugar_carta(g.cartas[4])
	await _esperar(5.0)
	await _foto("14_confesion")
	await _esperar(9.0)
	await _foto("15_fin")
	print("AUTOTEST fin")
	get_tree().quit()
