extends RefCounted
## Turns log text into its spoken form and a lookup key for the radio clips (assets/audio/radio/manifest.json).
## "1-Adam-12" -> "one Adam twelve", "10-97" -> "ten ninety seven", "Code 3" -> "Code three",
## "KEA-9291" -> "King, Edward, Adam, nine two nine one".

const PHONETIC := {
	"A": "Adam", "B": "Boy", "C": "Charles", "D": "David", "E": "Edward", "F": "Frank", "G": "George",
	"H": "Henry", "I": "Ida", "J": "John", "K": "King", "L": "Lincoln", "M": "Mary", "N": "Nora",
	"O": "Ocean", "P": "Paul", "Q": "Queen", "R": "Robert", "S": "Sam", "T": "Tom", "U": "Union",
	"V": "Victor", "W": "William", "X": "X-ray", "Y": "Young", "Z": "Zebra",
}
const ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
	"thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
const ACRONYMS := {"BAC": "B A C", "MDT": "M D T", "SUV": "S U V", "DUI": "D U I", "ID": "I D", "ALPR": "A L P R", "BOLO": "bolo", "PIT": "pit"}

static var _plate_re: RegEx
static var _callsign_re: RegEx
static var _code_re: RegEx
static var _tencode_re: RegEx
static var _decimal_re: RegEx
static var _money_re: RegEx
static var _digits_re: RegEx


static func _init_regex() -> void:
	if _plate_re != null:
		return
	_plate_re = RegEx.create_from_string("\\b([A-Z]{3})-(\\d{4})\\b")
	_callsign_re = RegEx.create_from_string("\\b(\\d)-([A-Z][a-z]+)-(\\d{1,2})\\b")
	_code_re = RegEx.create_from_string("\\bCode (\\d)\\b")
	_tencode_re = RegEx.create_from_string("\\b10-(\\d{1,3})\\b")
	_decimal_re = RegEx.create_from_string("\\b(\\d+)\\.(\\d+)\\b")
	_money_re = RegEx.create_from_string("\\$(\\d+)")
	_digits_re = RegEx.create_from_string("\\b\\d+\\b")


static func number_words(n: int) -> String:
	if n < 20:
		return ONES[maxi(n, 0)]
	if n < 100:
		return TENS[floori(n / 10.0)] + ("" if n % 10 == 0 else " " + ONES[n % 10])
	if n < 1000:
		return ONES[floori(n / 100.0)] + " hundred" + ("" if n % 100 == 0 else " " + number_words(n % 100))
	return digit_words(str(n))


static func digit_words(digits: String) -> String:
	var out := PackedStringArray()
	for c in digits:
		if c >= "0" and c <= "9":
			out.append(ONES[int(c)])
	return " ".join(out)


static func plate_words(plate: String) -> String:
	var letters := PackedStringArray()
	var digits := ""
	for c in plate.to_upper():
		if PHONETIC.has(c):
			letters.append(PHONETIC[c])
		elif c >= "0" and c <= "9":
			digits += c
	return ", ".join(letters) + ", " + digit_words(digits)


static func spoken_form(text: String) -> String:
	_init_regex()
	var s := text
	s = _replace(s, _plate_re, func(m: RegExMatch) -> String: return plate_words(m.get_string(1) + m.get_string(2)))
	s = _replace(s, _callsign_re, func(m: RegExMatch) -> String:
		return "%s %s %s" % [ONES[int(m.get_string(1))], m.get_string(2), number_words(int(m.get_string(3)))])
	s = _replace(s, _code_re, func(m: RegExMatch) -> String: return "Code " + ONES[int(m.get_string(1))])
	s = _replace(s, _tencode_re, func(m: RegExMatch) -> String: return "ten " + number_words(int(m.get_string(1))))
	s = _replace(s, _decimal_re, func(m: RegExMatch) -> String:
		return "%s point %s" % [number_words(int(m.get_string(1))), digit_words(m.get_string(2))])
	s = _replace(s, _money_re, func(m: RegExMatch) -> String: return number_words(int(m.get_string(1))) + " dollars")
	s = _replace(s, _digits_re, func(m: RegExMatch) -> String: return number_words(int(m.get_string())))
	for acronym: String in ACRONYMS:
		s = s.replace(acronym, ACRONYMS[acronym])
	s = s.replace("\"", "").replace(":", ",").replace("...", ".").replace("  ", " ").strip_edges()
	return s


static func _replace(source: String, re: RegEx, fn: Callable) -> String:
	var out := ""
	var cursor := 0
	for m in re.search_all(source):
		out += source.substr(cursor, m.get_start() - cursor) + String(fn.call(m))
		cursor = m.get_end()
	return out + source.substr(cursor)


## Normalised lookup key: spoken form, lower case, letters/digits/apostrophes only.
static func key(text: String) -> String:
	var spoken := spoken_form(text).to_lower()
	var out := ""
	for c in spoken:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "'" or c == "-":
			out += c
		else:
			out += " "
	return " ".join(out.split(" ", false))


static func tokens(text: String) -> PackedStringArray:
	return key(text).split(" ", false)
