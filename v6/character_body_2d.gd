extends CharacterBody3D

@export_group("2.5D Character Textures")
# 🖼️ Drag your separate Piskel PNG files into these boxes in the Inspector!
@export var texture_front : Texture2D  
@export var texture_back : Texture2D   

@export_group("Movement")
@export var speed : float = 5.0
@export var jump_velocity : float = 4.5
@export var mouse_sensitivity : float = 0.002

@export_group("2.5D Camera Preset Controls")
@export var follow_smoothness : float = 10.0

# Active perspective tracking: 0 = Far Top-Down, 1 = Medium Isometric, 2 = Close Third-Person Adventure
var zoom_state : int = 1 

@onready var sprite : Sprite3D = find_child("CharacterSprite")
@onready var camera_boom : Node3D = find_child("CameraBoom")
@onready var spring_arm : SpringArm3D = find_child("SpringArm3D")
@onready var main_cam : Camera3D = find_child("MainGameCamera")

var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

# The Physical SpringArm Node Matrix: [Boom height offset (Y), Spring Arm Length, Boom lens tilt angle (X)]
var presets = {
	0: Vector3(3.0, 7.5, -65.0),   # Far Top-Down RPG style
	1: Vector3(1.0, 5.0, -35.0),   # Medium Isometric 2.5D layout
	2: Vector3(0.5, 3.0, -12.0)    # Close Over-the-Shoulder Adventure view
}

func _ready():
	# Start with the mouse captured so it can turn the body!
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if sprite:
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = true
		# 🔒 FIXED: Permanently default to back texture right at startup
		if texture_back:
			sprite.texture = texture_back

	apply_camera_preset(zoom_state, true)

func _input(event):
	# 🖱️ MOUSE TURNING CONTROL:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# 🔄 1. Horizontal Mouse: Rotates the PLAYER'S BODY directly left and right!
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# 🔄 2. Vertical Mouse: Tilts the camera boom up and down smoothly
		if camera_boom:
			camera_boom.rotate_x(-event.relative.y * mouse_sensitivity)
			camera_boom.rotation.x = clamp(camera_boom.rotation.x, deg_to_rad(-45), deg_to_rad(30))

	# Toggle mouse visibility with Escape key for menus
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Mouse wheel scroll handles zooming presets
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_state = clamp(zoom_state + 1, 0, 2)
			apply_camera_preset(zoom_state, false)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_state = clamp(zoom_state - 1, 0, 2)
			apply_camera_preset(zoom_state, false)
			
		# Left click back into the game window locks cursor again
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	# WASD directional movement
	var input_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		
	var direction_2d = input_dir.normalized()
	
	# 🧭 SYNCED DIRECTION MATH: Move relative directly to your player body's forward axis!
	var direction = (transform.basis * Vector3(direction_2d.x, 0, direction_2d.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# 🔒 HARD LOCK: Force texture to stay on the back image during all movements
		if sprite and texture_back:
			sprite.texture = texture_back
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	# 🦾 Live SpringArm Preset Lerping
	if camera_boom and spring_arm and main_cam:
		var target_preset = presets[zoom_state]
		
		camera_boom.position.y = lerp(camera_boom.position.y, target_preset.x, follow_smoothness * delta)
		camera_boom.position.x = 0
		camera_boom.position.z = 0
		
		spring_arm.spring_length = lerp(spring_arm.spring_length, target_preset.y, follow_smoothness * delta)
		
		# Keep horizontal pivot locked straight ahead relative to the body (0)
		camera_boom.rotation.y = 0
		camera_boom.rotation.z = 0
		
		main_cam.look_at(global_position + Vector3(0, 1.0, 0))

	move_and_slide()

func apply_camera_preset(preset_idx: int, instant: bool):
	var preset = presets[preset_idx]
	if instant and camera_boom and spring_arm and main_cam:
		camera_boom.position = Vector3(0, preset.x, 0)
		spring_arm.spring_length = preset.y
		camera_boom.rotation_degrees = Vector3(preset.z, 0, 0)
		main_cam.look_at(global_position + Vector3(0, 1.0, 0))
