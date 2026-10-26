extends SceneTree
## Dev probe: lists the system TTS voices Godot sees (needs a window, not --headless).

func _initialize() -> void:
	var voices := DisplayServer.tts_get_voices()
	print("TTS count=", voices.size(), " all=", voices)
	print("TTS en=", DisplayServer.tts_get_voices_for_language("en"), " en-US=", DisplayServer.tts_get_voices_for_language("en-US"))
	print("TTS feature=", DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH))
	quit()
