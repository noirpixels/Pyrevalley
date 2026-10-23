extends RefCounted

# Shared bits for particle effects.

static var _dot: Texture2D


# A soft round dot, so glowing particles aren't hard squares
static func soft_dot() -> Texture2D:

	if _dot == null:
		var gradient = Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.add_point(0.35, Color(1, 1, 1, 0.9))
		gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
		var tex = GradientTexture2D.new()
		tex.gradient = gradient
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 32
		tex.height = 32
		_dot = tex
	return _dot
