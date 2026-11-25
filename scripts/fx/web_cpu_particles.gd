extends CPUParticles3D
## Web-only adapter for ParticleProcessMaterial's CPU-supported subset.
## The draw mesh, curves, alpha order and emitter parameters remain authored.
## Turbulence and radial velocity stay on GPU; the CPU converter omits them.

var process_material: ParticleProcessMaterial


static func supported(material: ParticleProcessMaterial) -> bool:
	return material != null and not material.turbulence_enabled \
		and is_zero_approx(material.radial_velocity_min) and is_zero_approx(material.radial_velocity_max)


func setup(source: GPUParticles3D) -> void:
	process_material = source.process_material
	# GPU and CPU enum values differ (GPU also has reverse lifetime). The
	# engine converter casts the enum directly, so map the authored order here.
	var view_sorted := source.draw_order == GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	source.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	convert_from_particles(source)
	draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH if view_sorted else CPUParticles3D.DRAW_ORDER_INDEX
	position = source.position
	cast_shadow = source.cast_shadow
	# Godot 4.7's converter copies the ring radii but omits its axis.
	emission_ring_axis = process_material.emission_ring_axis
	sync_scale()


func sync_scale() -> void:
	var pm := process_material
	if pm == null:
		return
	scale_amount_min = pm.scale_min
	scale_amount_max = pm.scale_max
	initial_velocity_min = pm.initial_velocity_min
	initial_velocity_max = pm.initial_velocity_max
	emission_sphere_radius = pm.emission_sphere_radius
	emission_ring_radius = pm.emission_ring_radius
	emission_ring_inner_radius = pm.emission_ring_inner_radius
	emission_box_extents = pm.emission_box_extents
	gravity = pm.gravity
	damping_min = pm.damping_min
	damping_max = pm.damping_max
