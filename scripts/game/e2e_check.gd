extends SceneTree
## Starts scripts/game/e2e_run.gd (end-to-end check with real input events) as a node, so it can name the autoloads.
##   araclar/godot.sh --headless --fixed-fps 60 --script res://scripts/game/e2e_check.gd -- [--only boot,foot,drive,radar,hud,calls,stop,pursuit,flee,armed,talk,weapons]


func _initialize() -> void:
	var run := (load("res://scripts/game/e2e_run.gd") as GDScript).new() as Node
	run.name = "E2eRun"
	root.add_child(run)
