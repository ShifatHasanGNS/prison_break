extends Resource
class_name GridTileData

const INTERACTABLE_NONE: int = 0
const INTERACTABLE_DOOR: int = 1
const INTERACTABLE_EXIT: int = 2
const INTERACTABLE_KEY: int = 3

@export var walkable: bool = true
@export var movement_cost: int = 1
@export var danger_level: float = 0.0
@export var visibility_block: bool = false
@export var interactable_type: int = INTERACTABLE_NONE
@export var visual_variant: int = 0
