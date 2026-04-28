extends RefCounted
class_name AgentPanel

## Pure data container for one HUD agent panel.
## HudRoot reads these fields every frame to drive drawing.

const LOG_MAX: int = 3

var agent_id    : int    = 0
var role        : String = ""
var label       : String = ""
var ai_label    : String = ""
var role_color  : Color  = Color.WHITE

var health       : float = 100.0
var max_health   : float = 100.0
var stamina      : float = 100.0
var max_stamina  : float = 100.0
## Lerped display values; animate toward actual health/stamina each frame
var display_health  : float = 100.0
var display_stamina : float = 100.0

var action_text  : String       = "-"
var status_text  : String       = "none"
var is_active    : bool         = true

## AI candidates; each entry is a Dictionary with keys: type, norm, chosen, + type-specific fields
var candidates   : Array        = []
## Rolling log of last 3 decisions (most-recent first)
var decision_log : Array[String] = []
## Last known grid position; used to compute direction arrows in HUD
var grid_pos     : Vector2i     = Vector2i(-1, -1)
var next_pos     : Vector2i     = Vector2i(-1, -1)
var decision_kind: String       = ""

# -------------------------------------------------------------------------

func setup(agent: Agent) -> void:
	agent_id = agent.agent_id
	role     = agent._role
	match role:
		"rusher_red":
			label      = "Rusher Red"
			ai_label   = "MINIMAX"
			role_color = Color(0.937, 0.267, 0.267)
		"sneaky_blue":
			label      = "Sneaky Blue"
			ai_label   = "MCTS"
			role_color = Color(0.18, 1.00, 0.92)
		"police":
			label      = "Police Hunter"
			ai_label   = "FUZZY"
			role_color = Color(1.0, 0.86, 0.24)
		_:
			label      = role
			ai_label   = "AI"
			role_color = Color.WHITE

	if agent.stats != null:
		max_health  = agent.stats.max_health
		max_stamina = agent.stats.max_stamina
	health  = agent.health
	stamina = agent.stamina
	display_health  = health
	display_stamina = stamina

func update_from_agent(agent: Agent) -> void:
	health      = agent.health
	stamina     = agent.stamina
	status_text = agent.status_summary()
	is_active   = agent.is_active
	grid_pos    = agent.grid_pos

func add_log(entry: String) -> void:
	decision_log.push_front(entry)
	if decision_log.size() > LOG_MAX:
		decision_log.resize(LOG_MAX)

## Call each _process frame to smoothly animate bars.
func lerp_displays(delta: float) -> void:
	var speed := minf(delta * 8.0, 1.0)
	display_health  = lerpf(display_health,  health,  speed)
	display_stamina = lerpf(display_stamina, stamina, speed)
