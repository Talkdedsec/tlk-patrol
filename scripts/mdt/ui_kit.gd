extends RefCounted
## Shared look of the MDT, the traffic stop panel and the overlay: Open Sans fonts (SIL OFL, assets/fonts),
## the measured palette and small control helpers. Used through preload; no class_name on purpose.

const FONT_PATH := "res://assets/fonts/OpenSans-Variable.ttf"
const FONT_ITALIC_PATH := "res://assets/fonts/OpenSans-Italic-Variable.ttf"

# Overlay text
const WHITE := Color("FDFFFF")
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const AMBER := Color("E8C860")
const CHASE_RED := Color("F5626A")
const PROMPT_GREEN := Color("8FE5A0")
const LOG_MINT := Color("CFE8D8")

# Dialog panel
const PANEL_BG := Color(0.051, 0.067, 0.09, 0.9)  # #0d1117
const PANEL_EDGE := Color(1.0, 1.0, 1.0, 0.07)
const ROW_BG := Color("141518")
const ROW_HOVER := Color("26272A")
const ROW_PRESSED := Color("0C0D0F")
const HEADER_BG := Color("0D1117")
const HEADER_TEXT := Color("8F9399")
const OPTION_TEXT := Color("E4E4E5")
const ORANGE := Color("F0A020")
const PASS_GREEN := Color("2FE04A")
const FAIL_RED := Color("FF5A50")
const SCROLL_THUMB := Color("6F7374")

# MDT
const MDT_BEZEL := Color("1B1C21")
const MDT_BEZEL_LINE := Color("43444A")
const MDT_HEADER := Color("0D2746")
const MDT_TAB_ROW := Color("071322")
const MDT_CONTENT := Color("040C16")
const MDT_TAB := Color("112948")
const MDT_TAB_LINE := Color("27456A")
const MDT_TAB_HOVER := Color("1E3E67")
const MDT_TAB_ACTIVE := Color("58BDFF")
const MDT_TAB_ACTIVE_TEXT := Color("0A1A30")
const MDT_BUTTON := Color("1E3E65")
const MDT_BUTTON_LINE := Color("4A7FB0")
const MDT_TEXT := Color("F3FBFF")
const MDT_TITLE := Color("DBE9F5")
const MDT_GREEN := Color("7DE08F")
const MDT_STAMP := Color("A8B0C0")
const MDT_DISPATCH := Color("81C6EF")
const MDT_UNIT := Color("ADB5CB")
const MDT_ME := Color("A2FDDB")
const MDT_FOOTER := Color("A5B3C2")
const MDT_SCROLL := Color("6C7076")

static var _fonts: Dictionary = {}


## Open Sans at a weight (400 regular, 600 semibold, 700 bold), optionally italic.
static func font(weight: int = 400, italic: bool = false) -> Font:
	var key := weight * 2 + (1 if italic else 0)
	if _fonts.has(key):
		return _fonts[key]
	var variation := FontVariation.new()
	variation.base_font = load(FONT_ITALIC_PATH if italic else FONT_PATH)
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
	_fonts[key] = variation
	return variation


static func text_width(text: String, size: int, weight: int = 400, italic: bool = false) -> float:
	return font(weight, italic).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func box(bg: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0), border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if border_width > 0:
		style.border_color = border
		style.set_border_width_all(border_width)
	return style


static func label(text: String, size: int, color: Color, weight: int = 400, italic: bool = false, outlined: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override("font", font(weight, italic))
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if outlined:
		node.add_theme_color_override("font_outline_color", OUTLINE)
		node.add_theme_constant_override("outline_size", 3)
	return node


## RichTextLabel with the Open Sans family wired to [b], [i] and plain text.
static func rich(size: int, color: Color, line_gap: int = 0, weight: int = 400) -> RichTextLabel:
	var node := RichTextLabel.new()
	node.bbcode_enabled = true
	node.scroll_active = true
	node.selection_enabled = false
	node.context_menu_enabled = false
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("normal_font", font(weight))
	node.add_theme_font_override("bold_font", font(700))
	node.add_theme_font_override("italics_font", font(weight, true))
	node.add_theme_font_override("bold_italics_font", font(700, true))
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		node.add_theme_font_size_override(key, size)
	node.add_theme_color_override("default_color", color)
	node.add_theme_constant_override("line_separation", line_gap)
	return node


## Thin rounded scrollbar without a track (8 px wide, #6F7374).
static func style_scrollbar(bar: ScrollBar, thumb: Color, width: float = 8.0) -> void:
	var grabber := box(thumb, 4)
	for name in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(name, grabber)
	for name in ["scroll", "scroll_focus"]:
		bar.add_theme_stylebox_override(name, StyleBoxEmpty.new())
	bar.custom_minimum_size.x = width
	bar.modulate = Color(1, 1, 1, 1)


static func hex(color: Color) -> String:
	return "#" + color.to_html(false)


## BBCode helper: wraps text in a colour tag.
static func tint(text: String, color: Color) -> String:
	return "[color=%s]%s[/color]" % [hex(color), text]
