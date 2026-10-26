extends SceneTree
## Dev check of the radio voice: which method voices each line (clip / words / tts / silent) and a short playback.
## Run with a GPU window (not headless) to see the system TTS voices: araclar/godot.sh --script res://scripts/traffic_stop/dev/voice_test.gd

const RadioVoice := preload("res://scripts/calls/radio_voice.gd")


func _initialize() -> void:
	var voice := RadioVoice.new()
	root.add_child(voice)
	await process_frame
	print("VOICE display_server=", DisplayServer.get_name(), " tts_voices=", DisplayServer.tts_get_voices_for_language("en") if DisplayServer.get_name() != "headless" else "n/a",
		" clips=", voice.has_clips(), " tts=", voice.tts_available())
	var lines := [
		"10-4, 1-Adam-12.", "1-Adam-14, take the stolen vehicle. Code 3.", "Code 2, Trespassing. A caller says a person is on private property near the Southside and will not leave.",
		"run a 10-28 for me, KEA-9291.", "1-Adam-12, that plate comes back to a Halvorsen Ranger SUV, registered to Darnell Foster. No wants or warrants.",
		"1-Adam-12, that plate comes back to a Calloway Sedan, registered to Marcus Whitaker. Be advised, owner's licence suspended.",
		"7-Sam-34, I'm on scene with a purple banana.",
	]
	for line in lines:
		print("VOICE ", voice.method_for(line), "  <- ", line)
	voice.volume_db = -12.0
	voice.speak(&"dispatch", lines[1])
	voice.speak(&"unit", "10-4, responding.")
	voice.speak(&"officer", lines[3])
	voice.speak(&"driver", "No. You can look if you want.")
	var waited := 0.0
	while voice.is_busy() and waited < 40.0:
		await create_timer(0.25).timeout
		waited += 0.25
	print("VOICE playback finished after %.1f s" % waited)
	quit()
