extends CharacterBody3D

@export_group("2.5D Character Textures")
# 🖼️ Drag your separate Piskel drawings into these boxes in your Inspector panel!
@export var texture_front : Texture2D  # Your character's face drawing
@export var texture_back : Texture2D   # Your character's back drawing

@export_group("Movement")
@export var speed : float = 5.0
@export var jump_velocity : float = 4.5
@export var mouse_sensitivity : float = 0.002

@onready var sprite : Sprite3D = $CharacterSprite
@onready var tp_pivot : Node3D = $CameraPivot

var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Set pixel art to stay crisp and sharp
	if sprite:
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.shaded = true
		# Default to showing your front image at launch
		if texture_front:
			sprite.texture = texture_front

func _input(event):
	# Stiff, rigid behind-the-back turning system
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		tp_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		tp_pivot.rotation.x = clamp(tp_pivot.rotation.x, deg_to_rad(-45), deg_to_rad(30))

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
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
	var direction = (transform.basis * Vector3(direction_2d.x, 0, direction_2d.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# 🔄 TEXTURE SWAPPING: Flip files depending on your travel vector
		if sprite:
			if direction_2d.y < 0 and texture_back:
				sprite.texture = texture_back
			elif direction_2d.y > 0 and texture_front:
				sprite.texture = texture_front
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	tp_pivot.rotation.y = 0
	move_and_slide()
