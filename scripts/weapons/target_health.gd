extends Node
## Fallback health for shootable nodes that have no damage API of their own (placeholder capsules, props).
## Attached lazily by the adapter layer as a child named "WeaponHealth". Real NPCs should expose
## apply_weapon_hit(info) instead (see docs/api/weapons.md).

signal downed(lethal: bool)

var max_hp := 100.0
var hp := 100.0
var hits := 0
var is_downed := false


## Applies damage and returns {"hp", "downed", "lethal", "hits"}; `downed` is true only on the hit that downs the target.
func take(amount: float, _part: String) -> Dictionary:
	var just_downed := false
	if not is_downed:
		hits += 1
		hp = maxf(hp - amount, 0.0)
		if hp <= 0.0:
			is_downed = true
			just_downed = true
			downed.emit(true)
	return {"hp": hp, "downed": just_downed, "lethal": just_downed, "hits": hits}
