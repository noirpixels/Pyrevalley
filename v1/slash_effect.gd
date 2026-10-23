extends MeshInstance3D

# Flat glowing arc drawn on the ground for Veyl's sword swing.

const SEGMENTS = 16

var radius: float = 6.0
var arc_degrees: float = 120.0


func _ready():
	var half = deg_to_rad(arc_degrees) / 2.0
	var verts = PackedVector3Array()

	# Triangle fan from the centre, facing -Z (forward)
	for i in range(SEGMENTS):
		var a0 = -half + (2.0 * half) * i / SEGMENTS
		var a1 = -half + (2.0 * half) * (i + 1) / SEGMENTS
		verts.append(Vector3.ZERO)
		verts.append(Vector3(sin(a1), 0, -cos(a1)) * radius)
		verts.append(Vector3(sin(a0), 0, -cos(a0)) * radius)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var arc_mesh = ArrayMesh.new()
	arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = arc_mesh

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.6)
	material_override = mat

	var tween = create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(queue_free)
