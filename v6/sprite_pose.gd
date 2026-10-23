extends RefCounted

# Poses a character sprite. It faces the camera the way a Y billboard does,
# but it can also lean and squash around its feet, which a billboard can't
# (billboards throw away the node's rotation).


# Moves the pivot to the bottom edge so lean and squash keep the feet planted.
# Glow layers parented to the sprite follow it, so they get the same pivot.
static func pin_to_feet(sprite: Sprite3D):

	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.offset.y = sprite.texture.get_height() / 2.0
	for child in sprite.get_children():
		if child is Sprite3D:
			child.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			child.offset.y = child.texture.get_height() / 2.0


# lean: radians, positive tips the top toward screen-left
static func apply(sprite: Sprite3D, lean: float, squash: Vector2, base_scale: float = 1.0):

	var toward_cam = Vector3.BACK
	var cam = sprite.get_viewport().get_camera_3d()
	if cam:
		toward_cam = cam.global_basis.z
		toward_cam.y = 0.0

	var world = Basis(Vector3.UP, atan2(toward_cam.x, toward_cam.z)) * Basis(Vector3.BACK, lean)
	var parent_turn = sprite.get_parent_node_3d().global_basis.orthonormalized()
	sprite.basis = parent_turn.inverse() * world * Basis.from_scale(
		Vector3(squash.x, squash.y, 1.0) * base_scale
	)


# How far a world direction points to the right on screen (-1..1)
static func screen_x(sprite: Node3D, dir: Vector3) -> float:

	var cam = sprite.get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var right = cam.global_basis.x
	right.y = 0.0
	return dir.dot(right.normalized())
