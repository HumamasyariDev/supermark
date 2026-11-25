extends AnimatableBody3D
## W1 Stick Scaffold sc4: a wobbly plank that rocks +/- `amplitude_deg` about its long (local X) axis.

@export var amplitude_deg: float = 6.0
@export var period: float = 3.0

var _t := 0.0
var _base := Basis()


func _ready() -> void:
	sync_to_physics = true
	_base = basis


func _physics_process(delta: float) -> void:
	_t += delta
	var a := deg_to_rad(amplitude_deg) * sin(TAU * _t / period)
	basis = _base * Basis(Vector3.RIGHT, a)
