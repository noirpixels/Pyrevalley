extends RefCounted

# Player names in multiplayer: which characters are allowed, and a filter
# for swearing and slurs that sees through the usual disguises. The
# multiplayer menu checks a name before connecting, and the host checks
# every name as it arrives (net.gd register), so a modified game can't get
# past it. No filter catches everything; the host can also kick players
# from the pause menu. The word lists are in blocked_words.gd.
#
# How a name is checked (only a hidden copy is changed; the name shown is
# what the player typed):
#   1. lowercase, and numbers that stand in for letters turned back
#      (sh1t -> shit, 455 -> ass)
#   2. spaces, dashes, underscores and apostrophes taken out (s h i t -> shit)
#   3. innocent words that hide a blocked one removed (Scunthorpe, class)
#   4. blocked words looked for anywhere (ANYWHERE) or as whole words
#      (WHOLE), with and without repeated letters squashed (shiiit -> shit)

const Words = preload("res://blocked_words.gd")

const MIN_LENGTH = 3
const MAX_LENGTH = 16
const SEPARATORS = [" ", "-", "_", "'"]
const LOOKALIKES = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g", "@": "a", "$": "s", "!": "i", "|": "i", "+": "t"}

static var _allowed_chars: RegEx = null


# What was typed, trimmed, with runs of spaces made single
static func tidy(name: String) -> String:

	var parts = name.strip_edges().split(" ", false)
	return " ".join(parts)


# "" when the name is fine, otherwise why it isn't
static func problem(name: String) -> String:

	name = tidy(name)
	if name.length() < MIN_LENGTH:
		return "Names need at least %d characters." % MIN_LENGTH
	if name.length() > MAX_LENGTH:
		return "Names can be at most %d characters." % MAX_LENGTH
	if _allowed_chars == null:
		_allowed_chars = RegEx.create_from_string("^[A-Za-z0-9 _'\\-]+$")
	if _allowed_chars.search(name) == null:
		return "Names can only use letters, numbers, spaces and - _ '"
	if offensive(name):
		return "That name isn't allowed here. Pick another."
	if squash(joined(name)) in Words.RESERVED.map(squash):
		return "That name is reserved. Pick another."
	return ""


static func offensive(name: String) -> bool:

	var text = joined(name)
	for safe in Words.ALLOW:
		text = text.replace(safe, "")
	var squashed = squash(text)

	for word in Words.ANYWHERE:
		if text.contains(word):
			return true
		# Squashed matching only for words it can't turn into common
		# letters ("kkk" would become "k")
		var short = squash(word)
		if short.length() >= 4 and squashed.contains(short):
			return true

	# Whole words: each word of the name, the name as one word, and each
	# word with its digits dropped (Ass69)
	var tokens = [text]
	for token in split_words(name):
		tokens.append(unmask(token))
		tokens.append(letters_only(token))
	for token in tokens:
		for safe in Words.ALLOW:
			if token == safe:
				token = ""
		if token == "":
			continue
		for word in Words.WHOLE:
			# Stretched letters only make a word longer, so "Bobs" isn't "boobs"
			if token == word or (squash(token) == squash(word) and token.length() >= word.length()):
				return true
	return false


# Lowercase, lookalikes turned back into letters, separators removed
static func joined(name: String) -> String:

	var text = unmask(name)
	for sep in SEPARATORS:
		text = text.replace(sep, "")
	return text


static func unmask(text: String) -> String:

	text = text.to_lower()
	var out = ""
	for c in text:
		out += LOOKALIKES.get(c, c)
	return out


static func letters_only(text: String) -> String:

	var out = ""
	for c in text.to_lower():
		if c >= "a" and c <= "z":
			out += c
	return out


static func split_words(name: String) -> Array:

	var text = name
	for sep in SEPARATORS:
		text = text.replace(sep, " ")
	return Array(text.split(" ", false))


# Runs of one letter made single: shiiiit -> shit
static func squash(text: String) -> String:

	var out = ""
	for c in text:
		if out.is_empty() or out[-1] != c:
			out += c
	return out
