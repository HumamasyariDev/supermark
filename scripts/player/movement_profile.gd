class_name MovementProfile
extends Resource
## Every tuneable movement constant for Mr. Mak, with units.
## Units: metres, seconds, degrees, m/s, m/s^2. Fixed 60 Hz physics. Y up, forward = -Z.
## Collision capsule 1.25 m tall, radius 0.35 m, feet at the body origin.
##
## Provenance (night 01): reconciled with Docs/MOVEMENT_REFERENCE.md (REA workstream, measured reference
## facts at 1 u = 7.8125 mm, 30 Hz). Launch speeds include +0.234 m/s (+0.113 for the half-gravity long jump)
## so that this controller's 60 Hz integration reproduces the reference apex heights. Values marked
## "original" were not covered by the reference and are tuned by feel. Differences: Docs/DEVLOG.md.
## Conveniences that the reference does not have (coyote time, jump buffering, wall-cling,
## ledge-grab band) are marked "convenience" and can be set to zero.

@export_group("Input")
## Radial dead zone on the move stick (0..1). Controls.gd also sets 0.2 per action.
@export var stick_deadzone := 0.2
## Exponent applied to the remapped stick magnitude. Reference: deflection is squared (2.0).
@export var stick_curve := 2.0
## s. Convenience: a jump press is remembered this long before it can be used (landing, wall contact).
@export var jump_buffer_time := 0.2
## s. Convenience: jumping is still allowed this long after walking off a ledge.
@export var coyote_time := 0.067

@export_group("Ground run")
## m/s at full stick. Speed scales with stick magnitude.
@export var run_top_speed := 7.5
## m/s^2 acceleration near standstill.
@export var walk_accel := 7.7
## 0..1. Acceleration tapers linearly to (1 - accel_taper) x walk_accel at top speed.
## Reference: 7.73 -> 2.50 m/s^2 (taper 0.677): 90 % in about 1.33 s, top speed in about 1.6 s.
@export var accel_taper := 0.677
## m/s^2 gentle stop when the stick is released below brake_min_speed (reference 7.03).
@export var stop_decel := 7.03
## m/s^2 braking when the stick is released at or above brake_min_speed (reference: full run stops in 0.27 s).
@export var brake_decel := 28.125
## m/s. Releasing the stick at or above this speed brakes hard to a stop.
@export var brake_min_speed := 3.75
## 0..1. Forward speed kept when landing with the stick held (reference about 0.92).
@export var land_speed_keep := 0.92
## m/s^2 deceleration when moving faster than the stick asks for.
@export var overspeed_decel := 7.03
## deg/s facing turn rate while running.
@export var turn_rate_deg := 337.5
## deg/s facing turn rate below turn_slow_speed (small pivots feel immediate).
@export var turn_rate_slow_deg := 1080.0
## m/s. Below this speed the slow-speed turn rate applies.
@export var turn_slow_speed := 1.2
## m/s^2 along the slope per unit of sin(slope angle): uphill slows, downhill speeds up.
@export var slope_speed_factor := 4.0
## m/s. Ground speed below which the idle state is entered when the stick is released.
@export var stop_speed := 0.05

@export_group("Skid and side somersault")
## deg. A stick reversal sharper than this triggers a skid.
@export var skid_angle_deg := 100.0
## 0..1 of run_top_speed needed to skid instead of turning on the spot.
@export var skid_min_speed_ratio := 0.5
## m/s^2 deceleration during a skid.
@export var skid_decel := 28.125
## s. Safety cap on a skid.
@export var skid_max_time := 0.6
## m/s. Leaving a finished skid toward the stick starts at this speed (reference).
@export var skid_exit_speed := 1.875
## m/s vertical launch of the side somersault (jump during a skid).
@export var side_flip_velocity := 14.77
## m/s horizontal speed in the new direction.
@export var side_flip_speed := 1.9

@export_group("Gravity and air")
## m/s^2 downward.
@export var gravity := 28.125
## m/s maximum fall speed.
@export var terminal_velocity := 17.58
## m/s^2 gravity during the long jump (reference: half gravity).
@export var long_jump_gravity := 14.06
## m/s^2 forward steering from full stick in the air (about 1.5 reference units per frame).
@export var air_accel := 10.55
## m/s^2 drag that always pulls air forward speed toward zero.
@export var air_drag := 2.46
## m/s instant sideways drift at full stick, perpendicular to facing.
@export var air_side_speed := 2.34
## m/s. Air forward speed above this is slowed by air_overspeed_decel (normal jumps).
@export var air_max_speed := 7.5
## m/s^2 slowdown above the air speed cap.
@export var air_overspeed_decel := 7.03
## m/s. Maximum backward air speed from pulling the stick back.
@export var air_max_back_speed := 3.75
## m/s^2 correction when moving backwards faster than air_max_back_speed (reference).
@export var air_back_decel := 14.06
## deg/s facing turn in the air. 0 = facing is locked in the air (reference behaviour).
@export var air_turn_rate_deg := 0.0
## D039 (owner request, deliberate deviation on top of the reference air rules above): m/s cap and m/s^2 rate of a
## world-space sideways drift toward the stick that bends the trajectory (eases back to zero when the stick is
## released). The forward share is dropped, so forward arcs and distances stay the reference ones. 0 turns it off.
@export var air_steer_speed := 1.5
@export var air_steer_accel := 6.0
## D039: m/s^2 extra braking of forward air speed (never below zero) at full stick pulled back.
@export var air_brake_decel := 6.0
## D039: deg/s facing turn toward the stick (times stick magnitude) in the bounce state only (puff clouds, bouncy
## leaves, pads, stomps). Normal jumps keep the reference locked facing (air_turn_rate_deg 0).
@export var bounce_turn_rate_deg := 150.0
## D039: m/s^2 stop after touching down with the stick released (reference: walk-release braking, 0.44 m from a
## running jump). 60 gives about 0.2 m from a running jump and about 0.7 m from a full long jump.
@export var land_stop_decel := 60.0
## 0..1. Each 60 Hz tick while jump is released and rising faster than jump_cut_min_velocity, vertical
## speed is multiplied by this instead of applying gravity (reference: divided by 4 per 30 Hz frame).
## Applies to the single, double and long jumps and the wall kick.
@export var jump_cut_factor := 0.5
## m/s. The jump cut only applies while rising faster than this.
@export var jump_cut_min_velocity := 4.69

@export_group("Jumps")
## m/s single jump vertical launch.
@export var jump_velocity := 10.08
## Extra vertical m/s per m/s of forward speed (single and double jump).
@export var jump_speed_bonus := 0.25
## Forward speed is multiplied by this at takeoff of the single, double and triple jumps (reference 0.8).
@export var jump_forward_mult := 0.8
## s. Window after landing in which the next jump chains (reference effective window 0.15-0.3 s).
@export var chain_window := 0.25
## m/s forward speed needed to chain a double jump ("while moving").
@export var double_jump_min_speed := 1.0
## m/s double jump vertical launch.
@export var double_jump_velocity := 12.42
## m/s forward speed needed for the triple jump.
@export var triple_jump_min_speed := 4.69
## m/s triple jump vertical launch (forward somersault).
@export var triple_jump_velocity := 16.41
## m/s long jump vertical launch.
@export var long_jump_velocity := 7.15
## Long jump forward = min(speed x mult, max).
@export var long_jump_speed_mult := 1.5
## m/s long jump forward speed cap (also its air speed cap).
@export var long_jump_max_speed := 11.25
## m/s ground speed above which crouch + jump is a long jump (below: backflip).
@export var long_jump_min_speed := 2.34
## m/s backflip vertical launch.
@export var backflip_velocity := 14.77
## m/s backflip backward speed.
@export var backflip_back_speed := 3.75
## m/s vertical speed of a bounce from a stomp.
@export var stomp_bounce_velocity := 10.5

@export_group("Walls")
## s. Jump within this time of touching a wall in the air to wall kick (reference 2 + 5 frames = 0.233 s;
## the jump buffer before contact is a convenience on top).
@export var wall_kick_window := 0.233
## m/s wall kick vertical launch.
@export var wall_kick_velocity := 14.77
## m/s wall kick horizontal speed away from the wall.
@export var wall_kick_speed := 5.6
## m/s forward speed into the wall needed for a wall contact (kick chance).
@export var wall_contact_min_speed := 3.75
## deg. Maximum angle between facing and the wall's inward normal for a wall contact.
@export var wall_contact_max_angle_deg := 45.0
## m/s. Convenience: maximum slide-down speed while touching the wall during the kick window.
@export var wall_slide_speed := 2.5
## m/s. Horizontal speed away from the wall when the window passes without a kick.
@export var wall_release_speed := 1.2
## m/s. Head-on wall contact at or above this speed bonks Mak back (reference: 38 u/f = 8.9 m/s).
@export var wall_bonk_speed := 8.9
## m/s. Backward speed after a bonk (original value).
@export var wall_bonk_back_speed := 2.4
## m/s. Vertical speed is capped to this on a bonk so Mak drops away from the wall.
@export var wall_bonk_up := 1.5

@export_group("Ledges")
## m. A ledge top between these heights above the feet can be grabbed in the air (convenience band).
## m. Convenience (fix r1, not in the reference): an airborne wall contact whose top is at most this far above the
## feet sets Mak on top (a quick visual hop-up) instead of a wall slide, hang and climb. 0 turns it off.
@export var ledge_vault_max := 0.5
@export var ledge_grab_min_height := 0.78
@export var ledge_grab_max_height := 1.25
## m/s. Ledges are only grabbed while the vertical speed is below this (falling or near apex).
@export var ledge_grab_max_rise := 0.0
## m. Feet sit this far below the ledge top while hanging.
@export var ledge_hang_drop := 1.0
## s. Time to climb up from a hang (stick toward the wall).
@export var ledge_climb_time := 0.42
## s. Faster climb when jump is pressed while hanging.
@export var ledge_climb_fast_time := 0.26
## s. No regrab for this long after dropping from a ledge.
@export var ledge_regrab_cooldown := 0.35
## s. Hanging time before stick input climbs or lets go (reference 10 frames).
@export var ledge_hang_delay := 0.33
## m. A hang needs at least this much air under the hanging feet (original: no ground-level hangs on crates).
@export var ledge_min_drop_clearance := 0.3

@export_group("Ham Slam (ground pound)")
## s. Whole hover-and-spin phase before the drop (reference about 0.5 s).
@export var slam_spin_time := 0.5
## m/s upward speed at the start of the hover, falling linearly to zero over slam_rise_time (reference 0.86 m rise).
@export var slam_rise_velocity := 5.16
@export var slam_rise_time := 0.333
## m/s drop speed at the start of the fall; normal gravity then accelerates it to terminal velocity.
@export var slam_drop_speed := 11.72
## s. Recovery on the ground after the impact (jump allowed after slam_jump_after).
@export var slam_land_time := 0.32
@export var slam_jump_after := 0.12
## m. Radius of the slam shockwave hitbox.
@export var slam_radius := 1.6

@export_group("Dive and belly slide")
## m/s forward boost on a dive.
@export var dive_boost := 3.52
## m/s dive speed cap.
@export var dive_max_speed := 11.25
## m/s ground speed needed for attack to dive instead of punching (reference 6.8 with stick > 75 %).
@export var dive_min_speed := 6.8
## m/s air speed needed for attack to dive instead of a jump kick (reference 6.56).
@export var dive_min_speed_air := 6.56
## m/s small hop when diving from the ground.
@export var dive_hop_velocity := 4.9
## m/s^2 belly slide friction on flat ground.
@export var belly_slide_friction := 5.5
## m/s. The belly slide ends (get-up) below this speed (REA round 2: a dive slide stops below 8 u/f).
@export var belly_slide_stop_speed := 1.875
## deg/s steering while belly sliding.
@export var slide_turn_rate_deg := 90.0
## m/s vertical hop of the recovery roll (jump during the slide).
@export var rollout_velocity := 7.27
## s. Getting up when the slide stops by itself.
@export var slide_getup_time := 0.3

@export_group("Attacks")
## s durations of jab, second jab and kick when no follow-up is pressed
## (REA round 2: jab 4 + 10 frames, second jab 3 + 13 frames, kick 26 frames at 30 Hz).
@export var punch_time := 0.467
@export var punch2_time := 0.533
@export var kick_time := 0.867
## s active hit window of the first jab (REA round 2: from its 3rd frame to the 1st recovery frame).
@export var strike_active_from := 0.067
@export var strike_active_to := 0.167
## s active hit window of the second jab (REA round 2: its 2nd frame to the 1st recovery frame).
@export var punch2_active_from := 0.033
@export var punch2_active_to := 0.133
## s active hit window of the kick (REA round 2: its first 8 frames).
@export var kick_active_to := 0.267
## s. Strike phase of each jab; attack pressed after it starts the next strike at once
## (REA round 2: jab 4 frames, second jab 3 frames). Earlier presses are buffered (our convenience).
@export var punch_strike_time := 0.133
@export var punch2_strike_time := 0.1
## m/s forward lunge on the first frame of a strike (REA round 2: 10 u/f).
@export var strike_lunge := 2.34
## m/s lunge per 30 Hz frame of a strike (REA round 2: 10, 7, 5, 3, 2, 1, 1, 0 u/f; 0.23 m in total).
## Our adaptation: the table restarts on every strike of the combo, not only the first jab.
@export var strike_lunge_table := PackedFloat32Array([2.344, 1.641, 1.172, 0.703, 0.469, 0.234, 0.234, 0.0])
## s. Jump kick duration; hits during the first part.
@export var jump_kick_time := 0.4
@export var jump_kick_active_to := 0.25
## m/s vertical speed set by the jump kick (reference 20 u/f).
@export var jump_kick_velocity := 4.9

@export_group("Crouch, slopes and sniff")
## m/s crouch walk at full stick.
@export var crouch_walk_speed := 1.6
## m/s^2 deceleration of the crouch slide (crouch pressed while running).
@export var crouch_slide_decel := 7.0
## m/s. Crouch pressed above this speed starts a crouch slide instead of a crouch.
@export var crouch_slide_min_speed := 3.0
## m. Capsule height while crouching (standing up needs room for the full capsule).
@export var crouch_capsule_height := 0.85
## deg. Floors steeper than this make Mak slide (floor_max_angle stays 60 so contact is stable)
## (REA round 2: normal ground turns slippery above 38 deg; slippery ground 20, very slippery 10).
@export var steep_slope_angle := 38.0
## m/s^2 per unit sin(angle) down a steep slope while sliding (REA round 2: 7 u/f^2 x steepness).
@export var slope_slide_accel := 49.2
## m/s^2 linear friction while sliding on a steep slope (REA round 2: none; the slide loses a share instead).
@export var slope_slide_friction := 0.0
## 1/s exponential speed loss while slope sliding (REA round 2: speed x 0.92 per 30 Hz frame).
@export var slope_slide_drag := 2.5
## 1/s change of that loss with the stick along the slide: forward lowers it, back raises it
## (REA round 2: +/- 0.02 per frame at full stick).
@export var slope_slide_stick_drag := 0.64
## deg/s turn of the slide direction at full sideways stick (REA round 2: 0.05 rad per frame).
@export var slope_slide_turn_deg := 86.0
## m/s slope slide speed cap (REA round 2: 100 u/f).
@export var slope_slide_max_speed := 23.4
## deg. The slope slide keeps going on floors steeper than this (REA round 2: 15 deg for normal ground);
## on flatter floors Mak gets up and runs on with his speed (our design; the reference slides on to 4 u/f).
@export var slide_flat_angle := 15.0
## s. Jump is ignored for this long after a slope slide starts (REA round 2: 5 frames).
@export var slide_jump_delay := 0.167
## m/s Snout Sniff walking speed at full stick.
@export var sniff_walk_speed := 1.6
## m. Snout Sniff search radius.
@export var sniff_radius := 40.0

@export_group("Climbing")
## m/s up and down a vine or pole.
@export var climb_up_speed := 1.9
@export var climb_down_speed := 3.6
## deg/s around a pole.
@export var climb_orbit_rate_deg := 140.0
## m/s jumping off a pole: vertical and away.
@export var pole_jump_velocity := 14.77
@export var pole_jump_speed := 5.6
## s. No regrab after leaving a pole.
@export var pole_regrab_cooldown := 0.4

@export_group("Damage and respawn")
## m/s horizontal knockback away from the damage source, held through the air phase
## (REA round 2: 16 u/f; a hit from the front throws Mak backwards facing the source, from behind forwards).
@export var knockback_speed := 3.75
## m/s default upward knockback (hazards may override with meta knockback_up).
@export var knockback_up := 6.5
## s invulnerability after the hurt state ends; Mak is also untouchable during it
## (REA round 2: 30 frames after the knockback).
@export var invulnerable_time := 1.0
## s whole hurt state, hit to standing (REA round 2: 1 damage 24 frames, 2-3 damage 30, 4 or more 80).
@export var hurt_time_soft := 0.8
@export var hurt_time_medium := 1.0
@export var hurt_time_hard := 2.667
## 0..1 knockback speed kept per 30 Hz frame after touching down (REA round 2: x 0.9 per frame).
@export var knockback_ground_keep := 0.9
## s lying on the ground after a bonk landing (no damage).
@export var hurt_land_time := 0.4
## s before a local fallback respawn when nobody handled a fall-out or a death.
@export var fallback_respawn_delay := 1.4

@export_group("Collision and platforms")
## m. Automatic step-up height for stairs and small ledges.
@export var step_height := 0.36
## m. Floor snap distance (keeps contact on ramps and stairs going down).
@export var floor_snap := 0.32
## deg. Maximum floor angle for stable contact (steeper floors are walls).
@export var floor_max_angle_deg := 60.0
## m/s^2 decay of inherited platform or knockback momentum on the ground and in the air.
@export var external_ground_decel := 18.0
@export var external_air_decel := 0.6
## 0..1 share of wind zone velocity applied on the ground (air = 1).
@export var wind_ground_factor := 0.5
## 1/s smoothing rate of wind changes.
@export var wind_smoothing := 6.0

@export_group("Feedback")
## m/s impact speed above which landing counts as heavy (land_heavy sound, big dust).
@export var heavy_land_speed := 12.0
