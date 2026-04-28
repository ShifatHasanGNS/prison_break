extends Resource
class_name FuzzyConfig

@export var dist_close: float = 3.0
@export var dist_medium: float = 8.0
@export var dist_far: float = 15.0

@export var vis_low: float = 0.2
@export var vis_medium: float = 0.5
@export var vis_high: float = 0.8

@export var noise_quiet: float = 2.0
@export var noise_medium: float = 5.0
@export var noise_loud: float = 8.0

@export var threat_low: float = 2.0
@export var threat_medium: float = 5.0
@export var threat_high: float = 8.0

@export var w_patrol: float = 1.0
@export var w_investigate: float = 1.2
@export var w_chase: float = 1.5
@export var w_intercept: float = 1.3
