"""W2 critique round 1 re-check (feel lens): geometry and controller-math checks that need no Godot slot.

Reads the level JSON plus the runtime overrides copied from w2_camera.gd / w2_life.gd / w2_play.gd (fix round 1)
and writes Docs/progress/critique/w2/r1_feel/geometry_r1b.json. Run from the entity folder:
    python game/tests/critique_w2/r1_feel/geometry_r1b.py
"""
import json, math, os

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
LEVEL = json.load(open(os.path.join(ENT, "game", "assets", "environment", "w2", "w2_level.json"), encoding="utf-8"))
P = {p["id"]: p for p in LEVEL["platforms"]}
SPL = LEVEL["terrain"]["stalk"]["spline"]
OUT = os.path.join(ENT, "Docs", "progress", "critique", "w2", "r1_feel", "geometry_r1b.json")


def stalk_c(y):
    for a, b in zip(SPL, SPL[1:]):
        if y <= b[1] or b is SPL[-1]:
            t = max(0.0, min(1.0, (y - a[1]) / max(b[1] - a[1], 1e-3)))
            return [a[i] + (b[i] - a[i]) * t for i in range(3)]


# --- 1. camera ring coverage (w2_camera.gd: CH1 y0 1,5,9,13,17 h4; CH2 y0 25.5,29.5,33.5 h4; r 7.5)
RINGS = [(y, y + 4.0) for y in (1.0, 5.0, 9.0, 13.0, 17.0)] + [(y, y + 4.0) for y in (25.5, 29.5, 33.5)]
ring_rows = []
for pid in ["L01", "L03", "L05", "L08", "L09", "BL1", "L11", "L12", "L13", "M01", "M03", "M04", "M06", "M07", "M08", "BL2"]:
    p = P[pid]["pos"]
    c = stalk_c(p[1] + 1.0)
    r = math.hypot(p[0] - c[0], p[2] - c[2])
    feet = p[1]
    in_y = any(lo <= feet + 0.3 and feet + 0.3 <= hi for lo, hi in RINGS)
    ring_rows.append({"leaf": pid, "feet_y": feet, "r_axis": round(r, 2), "covered": bool(in_y and r < 7.5)})

# --- 2. Leaf Bouncer catch box vs the short-jump fall line (w2_life.gd _fix1_setup)
box = {"x": [-47, -20], "y": [37.5, 40.5], "z": [-44, -12]}
start = [-15.06, 44.05, -9.17]
lb1 = P["LB1"]["pos"]
d = [lb1[0] - start[0], lb1[2] - start[2]]
n = math.hypot(*d)
u = [d[0] / n, d[1] / n]
uc = P["UC"]["pos"]
# march from start toward LB1 until outside UC's ellipse
s = 0.0
while ((start[0] + u[0] * s - uc[0]) / 6.0) ** 2 + ((start[2] + u[1] * s - uc[2]) / 4.5) ** 2 <= 1.0:
    s += 0.05
rim = [round(start[0] + u[0] * s, 2), round(start[2] + u[1] * s, 2)]
short_falls = []
for extra in (0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0):
    x, z = start[0] + u[0] * (s + extra), start[2] + u[1] * (s + extra)
    caught = box["x"][0] <= x <= box["x"][1] and box["z"][0] <= z <= box["z"][1]
    over_island = ((x - 0) / 22) ** 2 + ((z - 14) / 22) ** 2 <= 1.0
    # CatchCloudHopper (w2_life.gd): AABB (-40, 15, -24) size (32, 4.5, 26) -> respawn at the Cloud Landing hop start (y 24)
    hopper = -40 <= x <= -8 and -24 <= z <= 2
    short_falls.append({"past_rim_m": extra, "x": round(x, 2), "z": round(z, 2), "caught_by_leafbouncer_box": caught,
                        "caught_by_cloudhopper_box_y15_19": hopper, "over_island": over_island})

# --- 3. E04 crow relocation (w2_play.gd: pos (-3.6, 24.6, -4.2), notice 6 m)
e04 = [-3.6, 24.6, -4.2]
crow = {k: round(math.dist(e04, P[k]["pos"]), 2) for k in ("L13", "M01", "M02", "M03")}
crow["CP2"] = round(math.dist(e04, [-4, 24, -12]), 2)

# --- 4. Leaf Bouncer controller math (movement_profile.gd: air_accel 10.55, air_drag 2.46, cap 7.5; g 28)
vb, g = P["LB1"]["bounce_velocity_g28"], 28.0
dy = 0.6
t_air = (vb + math.sqrt(vb * vb - 2 * g * dy)) / g


def travel(v0, stick, dt=1 / 60.0):
    v, x, t = v0, 0.0, 0.0
    while t < t_air:
        v = max(0.0, v - 2.46 * dt) + 10.55 * stick * dt
        v = min(v, 7.5)
        x += v * dt
        t += dt
    return round(x, 2)


lb = {"air_time_s": round(t_air, 2), "spacing_m": 6.4, "pad_r": 1.2,
      "travel_no_stick_m": travel(4.2, 0.0), "travel_half_stick_m": travel(4.2, 0.5), "travel_full_stick_m": travel(4.2, 1.0),
      "crosswind_angle_to_chain_deg": None, "drift_base_m": round(1.2 * t_air, 2), "drift_gust_m": round(2.5 * t_air, 2)}
chain = [P["LB5"]["pos"][0] - P["LB1"]["pos"][0], P["LB5"]["pos"][2] - P["LB1"]["pos"][2]]
cn = math.hypot(*chain)
wind = [0.7071, -0.7071]
lb["crosswind_angle_to_chain_deg"] = round(math.degrees(math.acos(abs(chain[0] / cn * wind[0] + chain[1] / cn * wind[1]))), 1)

# --- 5. Puff chain
puff = {"vanish_s": P["PUFF04"]["vanish"]["after_touch_s"], "frames": round(P["PUFF04"]["vanish"]["after_touch_s"] * 60),
        "PUFF06_PUFF07_dxz": round(math.hypot(P["PUFF07"]["pos"][0] - P["PUFF06"]["pos"][0], P["PUFF07"]["pos"][2] - P["PUFF06"]["pos"][2]), 2),
        "PUFF06_PUFF07_dy": P["PUFF07"]["pos"][1] - P["PUFF06"]["pos"][1]}

# --- 6. Void fall from the castle bank (kill_y -15, terminal 17.6, g 28)
h = 50 - (-15)
t_term = 17.6 / 28.0
d_term = 0.5 * 28 * t_term ** 2
fall = {"from_y": 50, "kill_y": -15, "seconds": round(t_term + (h - d_term) / 17.6, 2)}

res = {"camera_rings": ring_rows, "leaf_bouncer_catch": {"box": box, "rim_exit": rim, "short_falls": short_falls},
       "e04_distances_m": crow, "leaf_bouncer_math": lb, "puff_chain": puff, "bank_void_fall": fall}
json.dump(res, open(OUT, "w"), indent=1)
print(json.dumps(res, indent=1))
