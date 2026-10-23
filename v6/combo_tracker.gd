extends RefCounted

# Veyl's chain of consecutive hits. Every hit that lands within WINDOW of
# the last adds STEP_BONUS damage. The chain can't grow past the Max Combo
# stat: the hit that reaches it is the finisher and the chain starts over,
# so combo damage tops out at 1 + STEP_BONUS * (max - 1).

const WINDOW = 1.0
const STEP_BONUS = 0.1

var count: int = 0
var timer: float = 0.0


# Returns true when the chain just ran out
func tick(delta: float) -> bool:
	if count == 0:
		return false
	timer -= delta
	if timer <= 0.0:
		count = 0
		return true
	return false


# Counts a landed attack; returns its damage multiplier
func add_hit(max_combo: int) -> float:
	count = min(count + 1, max_combo)
	timer = WINDOW
	return 1.0 + STEP_BONUS * (count - 1)


func finished(max_combo: int) -> bool:
	return count >= max_combo


func drop():
	count = 0
	timer = 0.0
