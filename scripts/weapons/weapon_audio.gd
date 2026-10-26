extends Node
## Plays the weapon sounds from assets/audio/weapons/<id>.wav (synthesized by araclar/ses/silah_sesleri.py).
## Small pitch jitter per play; missing files are skipped silently so the module also runs before the first import.

const DIR := "res://assets/audio/weapons/"
const POOL_SIZE := 8
const PITCH_JITTER := 0.03

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func play(sound_id: StringName, volume_db := 0.0, jitter := PITCH_JITTER) -> void:
	var stream := _stream(sound_id)
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	player.play()


func has_sound(sound_id: StringName) -> bool:
	return _stream(sound_id) != null


func _stream(sound_id: StringName) -> AudioStream:
	if _streams.has(sound_id):
		return _streams[sound_id]
	var path := "%s%s.wav" % [DIR, sound_id]
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[sound_id] = stream
	return stream
