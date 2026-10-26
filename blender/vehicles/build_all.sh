#!/usr/bin/env bash
# Regenerates every vehicle glb under assets/models/vehicles/. Usage: blender/vehicles/build_all.sh
cd "$(dirname "$0")/../.."
B="/e/Blender/blender-5.2.2-windows-x64/blender.exe"
run() { "$B" -b --factory-startup --python "$@" 2>&1 | grep -E "EXPORTED|Error|Traceback|rror:" ; }
run blender/vehicles/patrol_sedan.py
run blender/vehicles/patrol_sedan.py -- --unmarked
run blender/vehicles/sheriff_pickup.py
run blender/vehicles/suv.py
run blender/vehicles/suv.py -- --patrol
run blender/vehicles/suv.py -- --sheriff
run blender/vehicles/civilians.py
