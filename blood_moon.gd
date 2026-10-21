extends Node

# Every EVERY seconds a blood moon rises over Emberwood: the light turns
# red for a while, and as it sets the earth closes over every mine
# (dig_site.gd host_regrow), so the ore is there to dig again. The host
# keeps the clock (saved with the world); everyone sees the sky change.

const EVERY = 1200.0
const LASTS = 75.0
const RED_LIGHT = Color(1.0, 0.35, 0.28)
const RED_AMBIENT = Color(0.45, 0.16, 0.16)

@export var light_path: NodePath = ^"../../DirectionalLight3D"
@export var environment_path: NodePath = ^"../../WorldEnvironment"

var next_in: float = EVERY
var active: bool = false
var light: DirectionalLight3D
var environment: Environment
var base_light: Color
var base_ambient: Color


func _ready():

	name = "BloodMoon"
	add_to_group("net_objects")
	light = get_node_or_null(light_path)
	var world_env = get_node_or_null(environment_path)
	if world_env:
		environment = world_env.environment
		base_ambient = environment.ambient_light_color
	if light:
		base_light = light.light_color


func _process(delta):

	if not Net.is_host() or NetSync.world == null:
		return
	next_in -= delta
	if next_in > 0.0:
		return
	if active:
		for site in get_tree().get_nodes_in_group("dig_sites"):
			site.host_regrow()
		next_in = EVERY
		NetSync.object_fx(self, "set")
	else:
		next_in = LASTS
		NetSync.object_fx(self, "rise")


func host_request(_args: Array, _sender: int):
	pass


func fx_rise():

	active = true
	GameState.notify.emit("A blood moon rises. The earth stirs.")
	Sfx.play("boss_roar", -14.0, 0.5)
	tint(1.0, 6.0)


func fx_set():

	active = false
	GameState.notify.emit("The blood moon sets. The mines have closed over.")
	tint(0.0, 6.0)


func tint(amount: float, duration: float):

	var tween = create_tween().set_parallel()
	if light:
		tween.tween_property(light, "light_color", base_light.lerp(RED_LIGHT, amount), duration)
	if environment:
		tween.tween_property(environment, "ambient_light_color", base_ambient.lerp(RED_AMBIENT, amount), duration)


func net_snapshot():
	return {"next": next_in, "active": active}


func apply_snapshot(data):

	next_in = data["next"]
	if data["active"] and not active:
		active = true
		tint(1.0, 0.1)
