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
	_correr.call_deferred()

func _foto(nombre: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(salida.path_join(nombre + ".png"))
	print("AUTOTEST foto ", nombre)

func _esperar(s: float) -> void:
	await get_tree().create_timer(s).timeout

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
	g.carpeta_ui.cambiar_pestana(1)
	await _esperar(0.4)
	await _foto("10_carpeta_perfil")
	g.carpeta_ui.cambiar_pestana(2)
	await _esperar(0.4)
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
