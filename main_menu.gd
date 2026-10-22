extends Control

# The title: the forest drifting behind, embers rising, and the way in:
# carry on a saved journey, start a new world (a random seed, or one you
# type), play co-op, or quit.

const UI = preload("res://ui_kit.gd")

var layers = []
var embers = []
var ember_canvas: Control
var main_box: VBoxContainer
var coop_box: VBoxContainer
var seed_edit: LineEdit
var name_edit: LineEdit
var address_edit: LineEdit
var host_list: VBoxContainer
var status: Label
var time: float = 0.0


func _ready():

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.set_default_clear_color(Color(0.03, 0.025, 0.035))
	for l in [["sky", 0.0], ["far", 8.0], ["mid", 18.0], ["near", 34.0]]:
		var tex = TextureRect.new()
		tex.texture = load("res://Menu/%s.png" % l[0])
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tex)
		layers.append([tex, l[1]])
	var shade = ColorRect.new()
	shade.color = Color(0.02, 0.015, 0.03, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	ember_canvas = Control.new()
	ember_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ember_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ember_canvas.draw.connect(draw_embers)
	add_child(ember_canvas)

	var title = UI.title("PYREVALLEY", 96, UI.EMBER)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500
	title.offset_right = 500
	title.offset_top = 80
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub = UI.label("THE HOLLOW", 24, UI.TEXT)
	sub.add_theme_font_override("font", Style.display_font)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -300
	sub.offset_right = 300
	sub.offset_top = 190
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	build_main()
	build_coop()
	status = UI.label(Net.last_message, 18, Color(1.0, 0.8, 0.6))
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status.offset_left = -500
	status.offset_right = 500
	status.offset_top = -60
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)
	Net.last_message = ""

	Net.hosts_changed.connect(refresh_hosts)
	Net.joined_world.connect(_on_joined)
	Net.connection_failed.connect(func(why): status.text = why)
	Sfx.play_music("menu")
	Sfx.stop_ambience()


func build_main():

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 12)
	UI.centered(main_box)
	main_box.offset_top = 40
	add_child(main_box)
	if GameState.has_save():
		var b = UI.button("CONTINUE", continue_game)
		main_box.add_child(b)
		b.grab_focus.call_deferred()
	var new_b = UI.button("NEW JOURNEY", new_game)
	main_box.add_child(new_b)
	if not GameState.has_save():
		new_b.grab_focus.call_deferred()
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "world seed (blank for random)"
	seed_edit.custom_minimum_size = Vector2(240, 36)
	main_box.add_child(seed_edit)
	if Net.available():
		main_box.add_child(UI.button("CO-OP", show_coop.bind(true)))
	main_box.add_child(UI.button("QUIT", func(): get_tree().quit()))


func build_coop():

	coop_box = VBoxContainer.new()
	coop_box.add_theme_constant_override("separation", 10)
	UI.centered(coop_box)
	coop_box.offset_top = 40
	coop_box.visible = false
	add_child(coop_box)
	name_edit = LineEdit.new()
	name_edit.text = "Veyl"
	name_edit.placeholder_text = "your name"
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(300, 36)
	coop_box.add_child(name_edit)
	var host_b = UI.button("HOST MY WORLD", host_game)
	host_b.custom_minimum_size = Vector2(300, 44)
	coop_box.add_child(host_b)
	var row = HBoxContainer.new()
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "host address"
	address_edit.text = "127.0.0.1"
	address_edit.custom_minimum_size = Vector2(190, 36)
	row.add_child(address_edit)
	var join_b = UI.button("JOIN", func(): join_game(address_edit.text))
	join_b.custom_minimum_size = Vector2(100, 36)
	row.add_child(join_b)
	coop_box.add_child(row)
	coop_box.add_child(UI.label("Games on your network:", 16, UI.MUTED))
	host_list = VBoxContainer.new()
	coop_box.add_child(host_list)
	coop_box.add_child(UI.button("BACK", show_coop.bind(false)))


func show_coop(on: bool):

	main_box.visible = not on
	coop_box.visible = on
	if on:
		Net.listen_for_hosts()
		refresh_hosts()
	else:
		Net.stop_discovery()


func refresh_hosts():

	for child in host_list.get_children():
		child.queue_free()
	if Net.hosts.is_empty():
		host_list.add_child(UI.label("  (none yet)", 15, UI.MUTED))
	for address in Net.hosts:
		var h = Net.hosts[address]
		var b = UI.button("%s's world  ·  %s" % [h["name"], address], join_game.bind(address))
		b.custom_minimum_size = Vector2(300, 36)
		host_list.add_child(b)


func continue_game():

	GameState.save_path = GameState.SAVE_PATH
	if GameState.load_game():
		get_tree().change_scene_to_file("res://game.tscn")


func new_game():

	GameState.save_path = GameState.SAVE_PATH
	var text = seed_edit.text.strip_edges()
	var world_seed = int(text) if text.is_valid_int() and int(text) > 0 else randi() % 999999 + 1
	if text != "" and not text.is_valid_int():
		world_seed = abs(text.hash()) % 999999 + 1
	GameState.new_game(world_seed)
	GameState.save_game()
	get_tree().change_scene_to_file("res://game.tscn")


func host_game():

	if GameState.has_save():
		GameState.load_game()
	else:
		GameState.new_game(randi() % 999999 + 1)
	var err = Net.host(player_name())
	if err != "":
		status.text = err
		return
	get_tree().change_scene_to_file("res://game.tscn")


func join_game(address: String):

	status.text = "Joining %s..." % address
	Net.join(address, player_name())


func player_name() -> String:
	var n = name_edit.text.strip_edges()
	return n if n != "" else "Veyl"


func _on_joined():
	get_tree().change_scene_to_file("res://game.tscn")


func _process(delta):

	time += delta
	for l in layers:
		l[0].position.x = sin(time * 0.05) * l[1]
	if randf() < 0.3:
		embers.append({"pos": Vector2(randf() * size.x, size.y + 10), "vel": Vector2(randf_range(-20, 20), randf_range(-90, -40)), "life": randf_range(3.0, 7.0)})
	for e in embers:
		e["pos"] += e["vel"] * delta
		e["vel"].x += sin(time * 2.0 + e["pos"].y * 0.01) * 6.0 * delta
		e["life"] -= delta
	embers = embers.filter(func(e): return e["life"] > 0.0)
	ember_canvas.queue_redraw()


func draw_embers():

	for e in embers:
		var a = clamp(e["life"] / 2.0, 0.0, 1.0)
		ember_canvas.draw_circle(e["pos"], 2.0, Color(1.0, 0.55, 0.2, a))
