extends Node

# Veyl's fighting (combat_moves.gd says what each move does). A press
# while a swing is still recovering is remembered briefly, so mashing
# chains cleanly. Hits land a beat after the press, as the blade comes
# round, and are judged against each creature's body box. Hits in a row
# build a combo that multiplies damage; the hit that completes it ends the
# chain with a short pause.

const CombatMoves = preload("res://combat_moves.gd")
const Items = preload("res://items.gd")
const SlashEffect = preload("res://slash_effect.gd")

const ATTACK_BUFFER = 0.15
const COMBO_WINDOW = 1.3
const MAX_COMBO = 4
const COMBO_STEP = 0.12
const COMBO_END_LAG = 0.35
# Switching between strike and heavy rattles a target this much more
const ALTERNATE_DIZZY = 1.6
const HIT_STOP_SCALE = 0.05

var player: CharacterBody2D
var attack_timer: float = 0.0
var buffered: String = ""
var buffer_timer: float = 0.0
var combo: int = 0
var combo_timer: float = 0.0
var last_kind: String = ""
var last_kind_timer: float = 0.0


func _ready():
	player = get_parent()


func weapon() -> Dictionary:
	return Items.weapon_stats(GameState.gear.get("weapon"))


func busy() -> bool:
	return attack_timer > 0.0


func _physics_process(delta):

	attack_timer = max(attack_timer - delta, 0.0)
	buffer_timer = max(buffer_timer - delta, 0.0)
	last_kind_timer = max(last_kind_timer - delta, 0.0)
	if combo > 0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			drop_combo()

	if player.remote or player.dead or player.input_blocked:
		return

	var kind = ""
	if Input.is_action_just_pressed("launch"):
		kind = "launch"
	elif Input.is_action_just_pressed("slam"):
		kind = "slam"
	elif Input.is_action_just_pressed("strike"):
		kind = "strike"
		if Input.is_action_pressed("move_up"):
			kind = "launch"
		elif Input.is_action_pressed("move_down"):
			kind = "slam"
	elif Input.is_action_just_pressed("heavy"):
		kind = "heavy"
	if kind != "":
		buffered = kind
		buffer_timer = ATTACK_BUFFER

	if buffer_timer > 0.0 and attack_timer <= 0.0:
		var k = buffered
		buffered = ""
		buffer_timer = 0.0
		attack(k)


func attack(kind: String):

	var w = weapon()
	var move = CombatMoves.get_move(kind, not player.is_on_floor(), w["moves"])
	attack_timer = w["cooldown"] * move["cooldown"]
	player.animator.swing(move["anim"])
	Sfx.play("attack", -4.0, {"launch": 1.2, "slam": 0.85, "aerial": 0.8, "heavy": 0.9}.get(move["name"], 1.0))
	var slash = SlashEffect.new(move["name"], w["range"], player.facing)
	player.add_child(slash)
	if NetSync.has_method("share_player_fx"):
		NetSync.share_player_fx("swing", [move["anim"], move["name"], w["range"]])
	await get_tree().create_timer(move["impact"]).timeout
	if is_instance_valid(player) and not player.dead:
		land(move, w)


func land(move: Dictionary, w: Dictionary):

	var rect = CombatMoves.hit_rect(move, player.global_position, player.facing, w["range"])
	# Gobs of ash can be batted out of the air
	for p in get_tree().get_nodes_in_group("projectiles"):
		if rect.grow(10.0).has_point(p.global_position):
			p.deflect()
	var hits = []
	for creature in get_tree().get_nodes_in_group("creatures"):
		if creature.is_dead() or not creature.visible:
			continue
		if rect.intersects(creature.hurt_rect()):
			hits.append(creature)
	if hits.is_empty():
		return

	combo = min(combo + 1, MAX_COMBO)
	combo_timer = COMBO_WINDOW
	var combo_mult = 1.0 + COMBO_STEP * (combo - 1)
	var alternate = (move["name"] == "strike" and last_kind == "heavy") or (move["name"] == "heavy" and last_kind == "strike")
	if move["name"] in ["strike", "heavy"]:
		last_kind = move["name"]
		last_kind_timer = 1.0
	var crit_any = false
	for creature in hits:
		var crit = move["name"] == "aerial" and creature.launched
		crit_any = crit_any or crit
		var mult = move["damage"] * combo_mult
		if crit:
			mult *= CombatMoves.AERIAL_CRIT
		if creature.is_dizzy():
			mult *= CombatMoves.DIZZY_BONUS
		var amount = max(1, roundi(w["attack"] * mult - creature.defense * 0.5))
		var launch: float = move["launch"]
		if move["name"] == "aerial" and not creature.launched:
			launch = 0.0
		var dizzy: float = move["dizzy"] * (ALTERNATE_DIZZY if alternate and last_kind_timer > 0.0 else 1.0)
		var push = Vector2(player.facing * move["push"], 0)
		NetSync.hit_creature(creature, amount, player.global_position, push, dizzy, launch)
		var fx = get_tree().get_first_node_in_group("fx")
		if fx:
			var at = creature.global_position + Vector2(0, -creature.height * 0.5)
			fx.sparks(at, Vector2(player.facing, -0.3), Color(1.0, 0.75, 0.35) if crit else Color(1.0, 0.5, 0.15), 20 if crit else 10)
			if crit:
				fx.number(at + Vector2(0, -40), "CRITICAL!", Color(1.0, 0.8, 0.3), 26)

	# Hits in the air give the jump and dash back; a chop down bounces Veyl
	if not player.is_on_floor():
		player.refresh_air()
		if move["name"] == "aerial":
			player.velocity.y = min(player.velocity.y, -460.0)

	var heavy = crit_any or move["name"] in ["heavy", "launch"] or combo >= MAX_COMBO
	Sfx.play("hit_heavy" if heavy else "hit", -3.0)
	hit_stop(0.12 if crit_any else (0.08 if heavy else 0.045))
	var game = get_tree().get_first_node_in_group("game")
	if game:
		game.shake(0.6 if crit_any else (0.35 if heavy else 0.15))
	Pad.rumble(0.4, 0.5 if heavy else 0.0, 0.1)

	if combo >= MAX_COMBO or move["name"] == "aerial":
		if combo > 1:
			var fx = get_tree().get_first_node_in_group("fx")
			if fx:
				fx.number(player.global_position + Vector2(0, -150), "%d HIT!" % combo, Color(1.0, 0.85, 0.3), 26)
		combo = 0
		attack_timer += COMBO_END_LAG
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_combo(combo, MAX_COMBO)


func drop_combo():

	combo = 0
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_combo(0, MAX_COMBO)


# The world freezes for a blink on a hit. With other players connected the
# game can't slow for one of them, so only Veyl's pose holds instead.
func hit_stop(duration: float):

	if Net.has_method("online") and Net.online():
		player.animator.hold(duration)
		return
	Engine.time_scale = HIT_STOP_SCALE
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
