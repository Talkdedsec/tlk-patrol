class_name HudStyle
extends RefCounted
## Shared HUD fonts (Open Sans, SIL OFL, see assets/fonts/OFL-OpenSans.txt) and text helpers.

const FONT_PATH := "res://assets/fonts/OpenSans-Variable.ttf"
const FONT_ITALIC_PATH := "res://assets/fonts/OpenSans-Italic-Variable.ttf"

# OpenType axis tags as integers ('wght', 'wdth').
const TAG_WEIGHT := 0x77676874
const TAG_WIDTH := 0x77647468
const TAG_TNUM := 0x746E756D  # tabular figures

static var _cache: Dictionary = {}


## Open Sans at a weight (400 regular, 600 semibold, 700 bold), width (75..100, 100 = normal), optional italic.
static func font(weight: int = 400, width: int = 100, italic: bool = false, tabular: bool = false) -> Font:
	var key := Vector4i(weight, width, 1 if italic else 0, 1 if tabular else 0)
	if _cache.has(key):
		return _cache[key]
	var fv := FontVariation.new()
	fv.base_font = load(FONT_ITALIC_PATH if italic else FONT_PATH)
	fv.variation_opentype = {TAG_WEIGHT: weight, TAG_WIDTH: width}
	if tabular:
		fv.opentype_features = {TAG_TNUM: 1}
	_cache[key] = fv
	return fv


## Draws text with its baseline-left at `pos`. For centered/right text pass align and a box `width`.
static func draw_text(ci: CanvasItem, text: String, pos: Vector2, size: int, color: Color, weight: int = 400,
		width: int = 100, align: int = HORIZONTAL_ALIGNMENT_LEFT, box: float = -1.0, italic: bool = false,
		tabular: bool = false) -> void:
	ci.draw_string(font(weight, width, italic, tabular), pos, text, align, box, size, color)


static func text_width(text: String, size: int, weight: int = 400, width: int = 100, italic: bool = false) -> float:
	return font(weight, width, italic).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Draws text with a dark outline (HUD text over the 3D scene).
static func draw_outlined(ci: CanvasItem, text: String, pos: Vector2, size: int, color: Color, outline: Color,
		weight: int = 400, width: int = 100, align: int = HORIZONTAL_ALIGNMENT_LEFT, box: float = -1.0,
		outline_size: int = 2) -> void:
	var f := font(weight, width)
	ci.draw_string_outline(f, pos, text, align, box, size, outline_size, outline)
	ci.draw_string(f, pos, text, align, box, size, color)
