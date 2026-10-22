extends Node

# Keeps co-op players' worlds in step. Alone, hits and hurts apply directly.


func hit_creature(creature: Node, amount: float, from: Vector2, push: Vector2, dizzy: float, launch: float):
	creature.receive_hit(amount, from, push, dizzy, launch)


func hurt_player(player: Node, amount: float, from: Vector2):
	player.take_damage(amount, from)


func share_player_fx(_kind: String, _args: Array):
	pass
