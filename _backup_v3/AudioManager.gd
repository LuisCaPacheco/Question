extends Node
## Audio 100% procedural (sintetizado en runtime), sin un solo archivo de sonido externo.
## Genera ondas simples (senos, ruido filtrado, envolventes) y las guarda como AudioStreamWAV en memoria.

const MIX_RATE := 44100

var _hum_player: AudioStreamPlayer
var _heart_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx := 0

var snd_click_soft: AudioStreamWAV
var snd_click_hard: AudioStreamWAV
var snd_paper: AudioStreamWAV
var snd_evidence_hit: AudioStreamWAV
var snd_win: AudioStreamWAV
var snd_lose: AudioStreamWAV
var snd_thud: AudioStreamWAV
var snd_tap: AudioStreamWAV
var snd_door: AudioStreamWAV
var snd_card: AudioStreamWAV
var snd_voz: AudioStreamWAV
var _voz_player: AudioStreamPlayer
var _voz_t := 0.0

func _ready() -> void:
	_generar_sonidos()
	_hum_player = AudioStreamPlayer.new()
	_hum_player.stream = _synth_hum()
	_hum_player.volume_db = -20.0
	add_child(_hum_player)

	_heart_player = AudioStreamPlayer.new()
	_heart_player.stream = _synth_heartbeat()
	_heart_player.volume_db = -14.0
	add_child(_heart_player)

	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)

	_voz_player = AudioStreamPlayer.new()
	_voz_player.stream = snd_voz
	_voz_player.volume_db = -60.0
	add_child(_voz_player)

# ---------- generacion (una sola vez al iniciar) ----------

func _generar_sonidos() -> void:
	snd_click_soft = _wav(_gen_click(720.0, 0.05, 0.5))
	snd_click_hard = _wav(_gen_click(280.0, 0.08, 0.7))
	snd_paper = _wav(_gen_paper())
	snd_evidence_hit = _wav(_gen_evidence_hit())
	snd_win = _wav(_gen_win())
	snd_lose = _wav(_gen_lose())
	snd_thud = _wav(_gen_thud())
	snd_tap = _wav(_gen_click(160.0, 0.07, 0.8))
	snd_door = _wav(_gen_door())
	snd_card = _wav(_gen_whoosh())
	snd_voz = _wav(_gen_voz(), true)

## Golpe de puño en mesa de metal: grave + resonancia metalica.
func _gen_thud() -> PackedFloat32Array:
	var n := int(MIX_RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	var parciales := [[62.0, 1.0, 9.0], [187.0, 0.35, 5.0], [431.0, 0.22, 3.5], [977.0, 0.12, 4.0], [1531.0, 0.06, 5.0]]
	for i in n:
		var t := float(i) / MIX_RATE
		var v := (randf() * 2.0 - 1.0) * exp(-t * 90.0) * 0.8
		for p in parciales:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * float(p[2]))
		s[i] = v * 0.55
	return s

## Cerrojo y chirrido de puerta pesada.
func _gen_door() -> PackedFloat32Array:
	var n := int(MIX_RATE * 1.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var fase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		if t < 0.12:
			v += (randf() * 2.0 - 1.0) * exp(-t * 40.0) * 0.9 + sin(TAU * 900.0 * t) * exp(-t * 30.0) * 0.3
		if t > 0.2:
			var tt := t - 0.2
			var f := 180.0 + sin(tt * 7.0) * 60.0 + tt * 40.0
			fase += TAU * f / MIX_RATE
			var chirr := sin(fase) * (0.6 + 0.4 * sin(fase * 2.01))
			v += chirr * 0.18 * clampf(tt * 4.0, 0.0, 1.0) * exp(-tt * 1.6)
		if t > 1.35:
			v += sin(TAU * 70.0 * (t - 1.35)) * exp(-(t - 1.35) * 12.0) * 0.9
		s[i] = v * 0.6
	return s

## Carta rasgando el aire.
func _gen_whoosh() -> PackedFloat32Array:
	var n := int(MIX_RATE * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var a := clampf(0.08 + t * 1.8, 0.0, 0.9)
		lp = lp + a * ((randf() * 2.0 - 1.0) - lp)
		var env := sin(PI * t / 0.35)
		s[i] = lp * env * 0.7
	return s

## Murmullo grave de voz (sin palabras), se modula en tiempo real.
func _gen_voz() -> PackedFloat32Array:
	var n := int(MIX_RATE * 2.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var fase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := 92.0 + sin(TAU * 0.5 * t) * 14.0 + sin(TAU * 1.5 * t) * 6.0
		fase += TAU * f / MIX_RATE
		var saw := fmod(fase / TAU, 1.0) * 2.0 - 1.0
		lp = lp + 0.12 * (saw - lp)
		var silabas := 0.5 + 0.5 * sin(TAU * 4.0 * t) * sin(TAU * 1.0 * t + 0.6)
		s[i] = (lp * 0.8 + (randf() * 2.0 - 1.0) * 0.05) * silabas
	return s

func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v: float = clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32767.0)))
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w

func _gen_click(freq: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var env := exp(-t * 45.0)
		var tone := sin(TAU * freq * t)
		var noise := (randf() * 2.0 - 1.0) * exp(-t * 220.0) * 0.6
		s[i] = (tone * 0.7 + noise) * env * amp
	return s

func _gen_paper() -> PackedFloat32Array:
	var dur := 0.4
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var raw := randf() * 2.0 - 1.0
		var hp := raw - prev
		prev = raw
		var crinkle := 0.6 + 0.4 * sin(TAU * 28.0 * t)
		var env := exp(-t * 6.0) * (1.0 - exp(-t * 90.0))
		s[i] = hp * crinkle * env * 0.5
	return s

func _gen_evidence_hit() -> PackedFloat32Array:
	var dur := 0.6
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f: float = lerpf(180.0, 60.0, clampf(t / 0.25, 0.0, 1.0))
		var thump := sin(TAU * f * t) * exp(-t * 7.0)
		var ping := sin(TAU * 1200.0 * t) * exp(-t * 14.0) * 0.25
		s[i] = thump * 0.8 + ping
	return s

func _gen_win() -> PackedFloat32Array:
	var dur := 2.0
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs := [220.0, 277.18, 329.63, 440.0]
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for idx in freqs.size():
			var f: float = freqs[idx]
			var start := idx * 0.12
			var local_t: float = maxf(0.0, t - start)
			var env := (1.0 - exp(-local_t * 8.0)) * exp(-local_t * 1.2)
			v += sin(TAU * f * t) * env
		s[i] = v * 0.22
	return s

func _gen_lose() -> PackedFloat32Array:
	var dur := 1.6
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var f1: float = lerpf(196.0, 130.0, clampf(t / 1.2, 0.0, 1.0))
		var f2 := f1 * 1.0595
		var env := exp(-t * 1.6)
		var thud := sin(TAU * 55.0 * t) * exp(-t * 6.0) * 0.5
		s[i] = (sin(TAU * f1 * t) * 0.5 + sin(TAU * f2 * t) * 0.5) * env * 0.5 + thud
	return s

func _synth_hum() -> AudioStreamWAV:
	var dur := 2.0
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var hum := sin(TAU * 60.0 * t) * 0.5 + sin(TAU * 120.0 * t) * 0.2
		var noise := (randf() * 2.0 - 1.0) * 0.03
		var wobble := 0.9 + 0.1 * sin(TAU * 0.5 * t)
		s[i] = (hum * 0.15 + noise) * wobble
	return _wav(s, true)

func _synth_heartbeat() -> AudioStreamWAV:
	var dur := 1.0
	var n := int(MIX_RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	_add_thump(s, 0.0, 70.0, 0.9)
	_add_thump(s, 0.32, 55.0, 0.6)
	return _wav(s, true)

func _add_thump(s: PackedFloat32Array, start_t: float, freq: float, amp: float) -> void:
	var start_i := int(start_t * MIX_RATE)
	var dur_i := int(0.18 * MIX_RATE)
	for j in dur_i:
		var idx := start_i + j
		if idx >= s.size():
			break
		var t := float(j) / MIX_RATE
		var env := exp(-t * 26.0)
		s[idx] += sin(TAU * freq * t) * env * amp

# ---------- reproduccion ----------

func play_sfx(s: AudioStreamWAV, vol_db := 0.0, pitch := 1.0) -> void:
	if s == null or _sfx_players.is_empty():
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % _sfx_players.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()

func click_soft() -> void: play_sfx(snd_click_soft, -6.0, 1.0 + randf() * 0.05)
func click_hard() -> void: play_sfx(snd_click_hard, -3.0, 1.0 + randf() * 0.05)
func paper() -> void: play_sfx(snd_paper, -4.0, 0.95 + randf() * 0.1)
func evidence_hit() -> void: play_sfx(snd_evidence_hit, -2.0)
func thud() -> void: play_sfx(snd_thud, 0.0, 0.92 + randf() * 0.12)
func tap() -> void: play_sfx(snd_tap, -8.0, 0.9 + randf() * 0.25)
func door() -> void: play_sfx(snd_door, -4.0)
func card() -> void: play_sfx(snd_card, -6.0, 0.9 + randf() * 0.2)

## Voz del sospechoso: humano normal, kthar agudo y rasposo, molk muy grave.
func voz(tipo: String, seg: float) -> void:
	if _voz_player == null:
		return
	match tipo:
		"kthar": _voz_player.pitch_scale = 1.45
		"molk": _voz_player.pitch_scale = 0.55
		_: _voz_player.pitch_scale = 1.0
	_voz_t = seg
	if not _voz_player.playing:
		_voz_player.play(randf() * 1.5)

func _process(delta: float) -> void:
	if _voz_player == null:
		return
	if _voz_t > 0.0:
		_voz_t -= delta
		_voz_player.volume_db = lerpf(_voz_player.volume_db, -17.0, 1.0 - exp(-delta * 12.0))
	else:
		_voz_player.volume_db = lerpf(_voz_player.volume_db, -60.0, 1.0 - exp(-delta * 8.0))
		if _voz_player.playing and _voz_player.volume_db < -55.0:
			_voz_player.stop()

func win() -> void:
	stop_ambient()
	play_sfx(snd_win, 0.0)

func lose() -> void:
	stop_ambient()
	play_sfx(snd_lose, -1.0)

func start_ambient() -> void:
	if not _hum_player.playing:
		_hum_player.play()

func stop_ambient() -> void:
	_hum_player.stop()
	_heart_player.stop()

## Llamar cada vez que cambian los turnos: activa el latido cuando quedan pocos
func set_tension(turnos: int) -> void:
	if turnos in range(1, 5):
		if not _heart_player.playing:
			_heart_player.play()
		var u: float = 1.0 - float(turnos) / 4.0
		_heart_player.pitch_scale = lerpf(1.0, 1.6, u)
		_heart_player.volume_db = lerpf(-16.0, -5.0, u)
	else:
		_heart_player.stop()
