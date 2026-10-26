extends Node
## Frame-time probe for recordings and measurements. Wall-clock frame times include the movie encoder when recording
## with --write-movie, so the viewport's CPU / GPU render times are reported next to them.
## Prints "PERF ..." lines every `interval` seconds and a final summary when it leaves the tree.

var interval := 5.0

var _rid: RID
var _last_us := 0
var _frame_ms: Array[float] = []
var _cpu_ms: Array[float] = []
var _gpu_ms: Array[float] = []
var _all_frame_ms: Array[float] = []
var _all_cpu_ms: Array[float] = []
var _all_gpu_ms: Array[float] = []
var _draw_calls := 0
var _since := 0.0


func _ready() -> void:
	_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_last_us = Time.get_ticks_usec()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var wall := float(now - _last_us) / 1000.0
	_last_us = now
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_rid) + RenderingServer.get_frame_setup_time_cpu()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_rid)
	_frame_ms.append(wall)
	_cpu_ms.append(cpu)
	_gpu_ms.append(gpu)
	_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_since += delta
	if _since >= interval:
		_since = 0.0
		print("PERF ", _summary(_frame_ms, _cpu_ms, _gpu_ms))
		var recycler := get_tree().root.find_child("TrafficRecycler", true, false)
		if recycler != null:
			print("PERF   ambient cars recycled so far: ", recycler.get("recycled"), " (not rebuilt)")
		_all_frame_ms.append_array(_frame_ms)
		_all_cpu_ms.append_array(_cpu_ms)
		_all_gpu_ms.append_array(_gpu_ms)
		_frame_ms.clear()
		_cpu_ms.clear()
		_gpu_ms.clear()


func _exit_tree() -> void:
	_all_frame_ms.append_array(_frame_ms)
	_all_cpu_ms.append_array(_cpu_ms)
	_all_gpu_ms.append_array(_gpu_ms)
	if not _all_frame_ms.is_empty():
		print("PERF TOTAL ", _summary(_all_frame_ms, _all_cpu_ms, _all_gpu_ms))


func _summary(frames: Array[float], cpu: Array[float], gpu: Array[float]) -> String:
	var sorted := frames.duplicate()
	sorted.sort()
	var p99: float = sorted[mini(int(sorted.size() * 0.99), sorted.size() - 1)] if not sorted.is_empty() else 0.0
	var mean_frame := _mean(frames)
	return "frames=%d wall=%.2f ms (%.1f fps) p99=%.2f ms max=%.2f ms | render cpu=%.2f ms gpu=%.2f ms | draw calls=%d | process=%.2f ms physics=%.2f ms" % [
		frames.size(), mean_frame, 1000.0 / maxf(mean_frame, 0.001), p99, sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0,
		_mean(cpu), _mean(gpu), _draw_calls,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()
