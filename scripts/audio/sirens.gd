extends Node
## Siren playback. Looping tones come from assets/audio/sirens (araclar/ses/sirenler.py). API: docs/api/sirens.md.
## Tone changes crossfade between two players; manual siren, air horn and rumbler are separate layers.

const DIR := "res://assets/audio/sirens/"
const TONES: Array[StringName] = [
	&"wail", &"yelp", &"prty", &"hilo", &"hyper_yelp", &"yelp2", &"pierce", &"hyper_hilo", &"mech_wail", &"rotor",
]
const SILENT_DB := -60.0
const CROSSFADE := 0.12
const MANUAL_RISE := 1.4  # seconds for the manual siren to climb from base pitch to full
const MANUAL_FALL := 2.2

var tone: StringName = &""
var volume_db: float = 0.0

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _rumbler: AudioStreamPlayer
var _horn: AudioStreamPlayer
var _manual: AudioStreamPlayer
var _blip: AudioStreamPlayer
var _click: AudioStreamPlayer
var _manual_held := false
var _manual_level := 0.0  # 0..1 climb of the manual siren
var _fades: Dictionary = {}  # AudioStreamPlayer -> Tween


func _ready() -> void:
	for i in 2:
		_players.append(_make_player(null, SILENT_DB))
	_rumbler = _make_player(_load_loop(&"rumbler"), SILENT_DB)
	_horn = _make_player(_load_loop(&"ah"), SILENT_DB)
	_manual = _make_player(_load_loop(&"man"), SILENT_DB)
	_blip = _make_player(_load(&"blip"), -3.0)
	_click = _make_player(_load(&"click"), -6.0)


func _process(delta: float) -> void:
	# Manual siren: pitch climbs while the button is held and falls back after release.
	var target := 1.0 if _manual_held else 0.0
	var rate := (1.0 / MANUAL_RISE) if _manual_held else (1.0 / MANUAL_FALL)
	_manual_level = move_toward(_manual_level, target, rate * delta)
	if _manual.playing:
		_manual.pitch_scale = lerpf(0.78, 1.7, _manual_level)
		if not _manual_held and _manual_level <= 0.0:
			_manual.stop()


## Plays a siren tone (see TONES). Switching tones crossfades; calling with the current tone does nothing.
func play(new_tone: StringName) -> void:
	if new_tone == &"":
		stop()
		return
	if not TONES.has(new_tone):
		push_warning("Sirens: unknown tone %s" % new_tone)
		return
	if new_tone == tone:
		return
	tone = new_tone
	var incoming := _players[1 - _active]
	var outgoing := _players[_active]
	incoming.stream = _load_loop(new_tone)
	incoming.volume_db = SILENT_DB
	incoming.play()
	_fade(incoming, volume_db, CROSSFADE)
	_fade(outgoing, SILENT_DB, CROSSFADE, true)
	_active = 1 - _active


func stop() -> void:
	tone = &""
	for p in _players:
		_fade(p, SILENT_DB, CROSSFADE, true)


func set_volume_db(db: float) -> void:
	volume_db = db
	var current := _players[_active]
	if current.playing and tone != &"":
		_fade(current, db, 0.05)


func is_playing() -> bool:
	return tone != &""


## Rumbler layer (low saw sweep under the siren).
func set_rumbler(on: bool) -> void:
	_layer(_rumbler, on, -4.0)


## Air horn (hold).
func set_horn(on: bool) -> void:
	_layer(_horn, on, -2.0)


## Manual siren (hold): pitch climbs while held, falls after release.
func set_manual(held: bool) -> void:
	_manual_held = held
	if held:
		if not _manual.playing:
			_manual_level = 0.0
			_manual.pitch_scale = 0.78
			_manual.volume_db = volume_db - 2.0
			_manual.play()


func blip() -> void:
	_blip.play()


func click() -> void:
	_click.play()


# --- internals --------------------------------------------------------------------

func _layer(player: AudioStreamPlayer, on: bool, db: float) -> void:
	if on:
		if not player.playing:
			player.volume_db = SILENT_DB
			player.play()
		_fade(player, db + volume_db, 0.08)
	else:
		_fade(player, SILENT_DB, 0.08, true)


func _make_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _fade(player: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool = false) -> void:
	if _fades.has(player) and is_instance_valid(_fades[player]):
		(_fades[player] as Tween).kill()
	var tw := create_tween()
	_fades[player] = tw
	tw.tween_property(player, "volume_db", to_db, seconds)
	if stop_after:
		tw.tween_callback(player.stop)


func _load(name: StringName) -> AudioStream:
	return load(DIR + String(name) + ".wav") as AudioStream


func _load_loop(name: StringName) -> AudioStream:
	var s := _load(name)
	if s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	return s
