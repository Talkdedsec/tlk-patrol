extends SceneTree
## Dev check: prints period, duty (any cell lit) and mean lit cells of every pattern against the expected values.
## araclar/godot.sh --headless --script res://scripts/els/patterns_check.gd

const REPORT := {
	"Double cross": "period 1.683 duty 0.36",
	"Triple alternate": "period 1.683 duty 0.52",
	"Six-burst cross fast": "period 1.25 duty 0.45-0.47",
	"Counter-rotating": "period ~0.97 duty ~1.0",
	"Sparkle": "random, duty 0.97, mean 3.7 lit",
	"Bounce": "period 0.817 duty 0.98",
}


func _initialize() -> void:
	for name in ElsPatterns.ORDER:
		var n := 6000
		var any := 0
		var lit := 0
		for i in n:
			var m := ElsPatterns.mask_at(name, i / 600.0)
			if m != 0:
				any += 1
			for c in 10:
				if m & (1 << c):
					lit += 1
		print("%-22s period %.3f duty %.2f mean lit %.1f   report: %s" % [
			name, ElsPatterns.period_of(name), float(any) / n, float(lit) / n, REPORT.get(name, "(guess)")])
	quit()
