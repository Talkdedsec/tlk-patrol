extends RefCounted
## Static data for one weapon. Numbers are tuned values;
## everything marked TODO(tahmin) is a guess and is listed in docs/api/weapons.md.

var id: StringName = &""
var display_name := ""          ## text shown in the HUD weapon line
var mag_size := 1
var start_reserve := 0
var fire_interval := 0.25       ## minimum seconds between shots
var automatic := false          ## hold LMB to keep firing (unused by default)
var draw_time := 0.5            ## HOLSTERED -> READY
var holster_time := 0.6         ## READY -> HOLSTERED (HUD line closes at the end)
var reload_time := 1.6          ## magazine swap; for tube weapons the time of ONE shell
var tube_reload := false
var damage := 25.0              ## torso damage per bullet / per pellet at point blank
var pellets := 1
var accuracy := 0.6             ## fraction of the crosshair spread used as the real bullet cone
var falloff_start := 25.0       ## metres where damage starts to drop
var falloff_end := 80.0
var falloff_min := 0.5          ## damage factor at falloff_end and beyond
var max_range := 300.0
var spread_rest := 9.0          ## crosshair inner edge (px) when standing still, aimed
var spread_move := 55.0         ## ... while moving or turning
var spread_shot := 50.0         ## ... right after a shot
var spread_aim_in := 30.0       ## ... the moment the aim camera opens
var hide_after_shot := 0.35     ## seconds the crosshair stays hidden after a shot
var kick_px := 26.0             ## camera pitch kick as an image shift at 1080p
var kick_time := 0.2            ## seconds to recover
var kick_yaw_px := 3.0
var flash_energy := 5.0
var flash_range := 9.0
var flash_size := 0.22          ## muzzle flame star radius (m)
var smoke_count := 5
var smoke_life := 1.2           ## seconds (1-1.5 s per puff)
var smoke_size := 0.5
var casing_size := Vector3(0.012, 0.012, 0.022)
var casing_color := Color(0.85, 0.66, 0.25)
var tracer := true
var aim_zoom := 1.6             ## camera distance ratio of the aim camera (tuned 1.55-1.6)
var shot_sound: StringName = &"pistol_shot"
var reload_sound: StringName = &"pistol_reload"
var pump_time := 0.0            ## seconds after the shot when the pump sound plays (shotgun)


static func make(weapon_id: StringName) -> RefCounted:
	var def: RefCounted = (load("res://scripts/weapons/weapon_def.gd") as GDScript).new()
	def.id = weapon_id
	match weapon_id:
		&"pistol":
			def.display_name = "Pistol"
			def.mag_size = 17
			def.start_reserve = 34
			def.fire_interval = 0.22          # tuned minimum 0.23 s between clicks, mean 0.31 s
			def.draw_time = 0.45              # TODO(tahmin): pistol draw time is a guess
			def.holster_time = 0.6            # tuned 0.6-0.7 s
			def.reload_time = 1.6             # TODO(tahmin)
			def.damage = 28.0                 # TODO(tahmin): 4 chest hits down a 100 hp target
			def.accuracy = 0.6
			def.falloff_start = 25.0
			def.falloff_end = 80.0
			def.falloff_min = 0.5
			def.spread_rest = 9.0             # tuned +-7..12
			def.spread_move = 55.0            # tuned +-50..60
			def.spread_shot = 50.0            # tuned
			def.spread_aim_in = 30.0
			def.hide_after_shot = 0.35        # tuned
			def.kick_px = 26.0                # tuned mean -26 px
			def.kick_time = 0.2               # tuned 150-250 ms
			def.kick_yaw_px = 3.0
			def.flash_energy = 5.0
			def.flash_range = 9.0
			def.flash_size = 0.08
			def.smoke_count = 5
			def.smoke_life = 1.2
			def.smoke_size = 0.5
			def.casing_size = Vector3(0.012, 0.012, 0.022)
			def.shot_sound = &"pistol_shot"
			def.reload_sound = &"pistol_reload"
		&"rifle":
			def.display_name = "Patrol rifle"
			def.mag_size = 29
			def.start_reserve = 56
			def.fire_interval = 0.18          # TODO(tahmin): semi-automatic, one shot per click
			def.draw_time = 0.85              # tuned: sling to hand 0.6 s + settle 0.25 s
			def.holster_time = 0.8            # TODO(tahmin)
			def.reload_time = 2.3             # TODO(tahmin)
			def.damage = 100.0                # a single rifle hit put the runner down
			def.accuracy = 0.45
			def.falloff_start = 60.0
			def.falloff_end = 250.0
			def.falloff_min = 0.7
			def.spread_rest = 11.0            # tuned +-12
			def.spread_move = 52.0            # tuned +-52
			def.spread_shot = 50.0
			def.spread_aim_in = 52.0          # tuned: +-52 narrowing to +-12 over 1 s
			def.hide_after_shot = 0.3         # TODO(tahmin): one shot only
			def.kick_px = 21.0                # tuned -21 px
			def.kick_time = 0.15              # tuned about 100-150 ms
			def.kick_yaw_px = 2.0
			def.flash_energy = 6.0
			def.flash_range = 11.0
			def.flash_size = 0.11
			def.smoke_count = 6
			def.smoke_life = 1.3
			def.smoke_size = 0.6
			def.casing_size = Vector3(0.012, 0.012, 0.045)
			def.shot_sound = &"rifle_shot"
			def.reload_sound = &"rifle_reload"
		&"shotgun":
			def.display_name = "Shotgun"
			def.mag_size = 6
			def.start_reserve = 18
			def.fire_interval = 0.9           # TODO(tahmin): pump cycle; tuned gap between the two shots 1.35 s
			def.draw_time = 0.85              # TODO(tahmin): like the rifle
			def.holster_time = 0.8            # TODO(tahmin)
			def.reload_time = 0.55            # TODO(tahmin): seconds per shell
			def.tube_reload = true
			def.damage = 14.0                 # TODO(tahmin): per pellet; two close shots down a target
			def.pellets = 8
			def.accuracy = 0.5                # tight pattern: half of the crosshair spread
			def.falloff_start = 15.0
			def.falloff_end = 50.0
			def.falloff_min = 0.35
			def.max_range = 120.0
			def.spread_rest = 30.0            # tuned +-30..41
			def.spread_move = 60.0
			def.spread_shot = 55.0            # TODO(tahmin): wider than rest
			def.spread_aim_in = 45.0
			def.hide_after_shot = 0.5         # TODO(tahmin): crosshair hidden 30.1-30.7 s while pumping
			def.kick_px = 70.0                # -23 px on the first frame
			def.kick_time = 0.5               # tuned
			def.kick_yaw_px = 6.0
			def.flash_energy = 9.0
			def.flash_range = 14.0
			def.flash_size = 0.18
			def.smoke_count = 12
			def.smoke_life = 2.4              # tuned: cloud above threshold for >= 2.2 s
			def.smoke_size = 1.0
			def.casing_size = Vector3(0.02, 0.02, 0.07)
			def.casing_color = Color(0.72, 0.14, 0.1)
			def.tracer = false
			def.shot_sound = &"shotgun_shot"
			def.reload_sound = &"shotgun_shell"
			def.pump_time = 0.35
		_:
			return null
	return def


static func ids() -> Array[StringName]:
	return [&"pistol", &"rifle", &"shotgun"]


## Maps a display name or loose spelling ("Patrol rifle", "patrol_rifle", "RIFLE") to the weapon id.
static func resolve_id(weapon_name: Variant) -> StringName:
	var text := String(weapon_name).strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	match text:
		"pistol", "handgun", "sidearm":
			return &"pistol"
		"rifle", "patrol_rifle", "carbine":
			return &"rifle"
		"shotgun", "shot_gun":
			return &"shotgun"
	return &""
