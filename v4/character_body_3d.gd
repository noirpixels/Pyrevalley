extends CharacterBody3D

@export_group("Movement")
@export var speed : float = 5.0
@export var jump_velocity : float = 4.5

@export_group("2.5D Camera Preset Controls")
@export var follow_smoothness : float = 10.0

# Active perspective tracking: 0 = Far Top-Down, 1 = Medium Isometric, 2 = Close Third-Person Adventure
var zoom_state : int = 1 

@onready var sprite : Sprite3D = find_child("CharacterSprite")
@onready var camera_boom : Node3D = find_child("CameraBoom")
@onready var main_cam : Camera3D = find_child("MainGameCamera")

var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

# The Perspective Node Matrix: [Boom height (Y), Camera distance (Z), Boom lens tilt angle (X)]
var presets = {
	0: Vector3(8.0, 4.5, -65.0),   # Far Top-Down RPG style
	1: Vector3(4.0, 5.0, -35.0),   # Medium Isometric 2.5D layout
	2: Vector3(1.5, 3.5, -12.0)    # Close Over-the-Shoulder Adventure view
}

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if sprite:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = true

	apply_camera_preset(zoom_state, true)

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_state = clamp(zoom_state + 1, 0, 2)
			apply_camera_preset(zoom_state, false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_state = clamp(zoom_state - 1, 0, 2)
			apply_camera_preset(zoom_state, false)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		
	var direction_2d = input_dir.normalized()
	
	if main_cam:
		var camera_basis = main_cam.global_transform.basis
		var forward = Vector3(camera_basis.z.x, 0, camera_basis.z.z).normalized()
		var right = Vector3(camera_basis.x.x, 0, camera_basis.x.z).normalized()
		var direction = (forward * direction_2d.y + right * direction_2d.x).normalized()
		
		if direction != Vector3.ZERO:
			velocity.x = direction.x * speed
			velocity.z = direction.z * speed
			
			if sprite:
				if direction_2d.x > 0:
					sprite.flip_h = false
				elif direction_2d.x < 0:
					sprite.flip_h = true
		else:
			velocity.x = move_toward(velocity.x, 0, speed)
			velocity.z = move_toward(velocity.z, 0, speed)

	if camera_boom and main_cam:
		var target_preset = presets[zoom_state]
		camera_boom.position.y = lerp(camera_boom.position.y, target_preset.x, follow_smoothness * delta)
		camera_boom.position.x = 0
		camera_boom.position.z = 0
		
		main_cam.position.z = lerp(main_cam.position.z, target_preset.y, follow_smoothness * delta)
		main_cam.position.x = 0
		main_cam.position.y = 0
		
		var target_rot_x = deg_to_rad(target_preset.z)
		camera_boom.rotation.x = lerp_angle(camera_boom.rotation.x, target_rot_x, follow_smoothness * delta)
		camera_boom.rotation.y = 0
		camera_boom.rotation.z = 0
		
		# 🎯 THE ANTI-SKY LOCK: Forces the camera lens to twist around and look at the character
		main_cam.look_at(global_position + Vector3(0, 1.0, 0))

	move_and_slide()

func apply_camera_preset(preset_idx: int, instant: bool):
	var preset = presets[preset_idx]
	if instant and camera_boom and main_cam:
		camera_boom.position = Vector3(0, preset.x, 0)
		main_cam.position = Vector3(0, 0, preset.y)
		camera_boom.rotation_degrees = Vector3(preset.z, 0, 0)
		main_cam.look_at(global_position + Vector3(0, 1.0, 0))
