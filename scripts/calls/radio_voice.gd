extends Node
## Radio speech queue. Lines are spoken one after another; the log line is shown immediately by Calls.radio()
## so the voice may trail the text.
## Lookup order for a line: full clip -> word-by-word composition from the bank -> system TTS -> silence.
## Clips come from araclar/ses/telsiz_uret.py (SAPI voice + radio filter) and are listed in assets/audio/radio/manifest.json.

const SpeechText := preload("res://scripts/calls/speech_text.gd")

const DIR := "res://assets/audio/radio/"
const MANIFEST := DIR + "manifest.json"
const MAX_QUEUE := 12
const WORD_GAP := 0.03
# Same clip for every speaker; the speaker only changes pitch/speed. TODO(tahmin): voices.
const PITCH := {&"dispatch": 1.0, &"unit": 0.9, &"officer": 0.84, &"you": 0.86, &"driver": 0.94, &"pa": 0.8}
## Speakers heard over the radio get the transmit chirp and squelch tail; face-to-face speech (you, driver, pa) does not.
const RADIO_KINDS: Array[StringName] = [&"dispatch", &"unit", &"officer"]

signal utterance_started(kind: StringName, text: String)
signal utterance_finished(kind: StringName, text: String)

var enabled: bool = true
var use_tts_fallback: bool = true
var volume_db: float = -2.0
var queue: Array[Dictionary] = []

var _lines: Dictionary = {}
var _words: Dictionary = {}
var _streams: Dictionary = {}
var _voice: AudioStreamPlayer
var _fx: AudioStreamPlayer
var _running := false
var _tts_voice := ""
var _chirp: AudioStream
var _squelch: AudioStream


func _ready() -> void:
	_voice = AudioStreamPlayer.new()
	_fx = AudioStreamPlayer.new()
	add_child(_voice)
	add_child(_fx)
	_load_manifest()
	_chirp = _load_stream("chirp.wav")
	_squelch = _load_stream("squelch.wav")
	if DisplayServer.get_name() != "headless":
		var voices := DisplayServer.tts_get_voices_for_language("en")
		if not voices.is_empty():
			_tts_voice = voices[0]


func has_clips() -> bool:
	return not _lines.is_empty()


func tts_available() -> bool:
	return not _tts_voice.is_empty()


## How a line would be voiced: &"clip", &"words", &"tts" or &"silent".
func method_for(text: String) -> StringName:
	var key := SpeechText.key(text)
	if _lines.has(key):
		return &"clip"
	if _compose(key).size() > 0:
		return &"words"
	return &"tts" if tts_available() and use_tts_fallback else &"silent"


## Queues a line. kind: dispatch, unit, officer (radio), you, driver, pa (face to face / loudspeaker).
func speak(kind: StringName, text: String) -> void:
	if not enabled or text.strip_edges().is_empty():
		return
	var key := SpeechText.key(text)
	var item := {"kind": kind, "text": text, "streams": [], "tts": false}
	if _lines.has(key):
		item["streams"] = [_load_stream(_lines[key])]
	else:
		var parts := _compose(key)
		if parts.size() > 0:
			item["streams"] = parts
		elif tts_available() and use_tts_fallback:
			item["tts"] = true
		else:
			return
	if queue.size() >= MAX_QUEUE:
		queue.pop_front()
	queue.append(item)
	if not _running:
		_run()


func is_busy() -> bool:
	return _running or not queue.is_empty()


func clear() -> void:
	queue.clear()
	_voice.stop()
	if tts_available():
		DisplayServer.tts_stop()


func _run() -> void:
	_running = true
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		await _play_item(item)
	_running = false


func _play_item(item: Dictionary) -> void:
	var kind: StringName = item["kind"]
	utterance_started.emit(kind, item["text"])
	var pitch: float = PITCH.get(kind, 1.0)
	if RADIO_KINDS.has(kind):
		await _play(_fx, _chirp, 1.0, -6.0)
	if item["tts"]:
		await _speak_tts(SpeechText.spoken_form(item["text"]), pitch)
	else:
		for stream: AudioStream in item["streams"]:
			await _play(_voice, stream, pitch, volume_db)
			await get_tree().create_timer(WORD_GAP).timeout
	if RADIO_KINDS.has(kind):
		await _play(_fx, _squelch, 1.0, -9.0)
	await get_tree().create_timer(0.18).timeout
	utterance_finished.emit(kind, item["text"])


func _play(player: AudioStreamPlayer, stream: AudioStream, pitch: float, db: float) -> void:
	if stream == null:
		return
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = db
	player.play()
	await get_tree().create_timer(stream.get_length() / pitch + 0.02).timeout


func _speak_tts(text: String, pitch: float) -> void:
	DisplayServer.tts_speak(text, _tts_voice, 70, pitch, 1.05)
	var waited := 0.0
	await get_tree().create_timer(0.2).timeout
	while DisplayServer.tts_is_speaking() and waited < 14.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


## Word clips for a key, or [] when any word is missing.
func _compose(key: String) -> Array:
	var parts: Array = []
	for token in key.split(" ", false):
		if not _words.has(token):
			return []
		parts.append(_load_stream(_words[token]))
	return parts


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary:
		_lines = parsed.get("lines", {})
		_words = parsed.get("words", {})


func _load_stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var stream := load_wav(DIR + file)
	_streams[file] = stream
	return stream


## Loads a wav through the importer when an .import file exists, otherwise parses the RIFF header directly
## (new clips work before the editor has imported them).
static func load_wav(path: String) -> AudioStream:
	if FileAccess.file_exists(path + ".import"):
		return load(path) as AudioStream
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var channels := 1
	var rate := 16000
	var bits := 16
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var chunk := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		if chunk == "fmt ":
			channels = bytes.decode_u16(pos + 10)
			rate = bytes.decode_u32(pos + 12)
			bits = bytes.decode_u16(pos + 22)
		elif chunk == "data":
			data = bytes.slice(pos + 8, mini(pos + 8 + size, bytes.size()))
			break
		pos += 8 + size + (size % 2)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.stereo = channels == 2
	wav.data = data
	return wav
