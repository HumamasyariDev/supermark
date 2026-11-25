#!/usr/bin/env python3
"""Build the Movie Maker showcase replays from verified movement-test cases.

The controller is deterministic in physics frames, so each segment re-runs a test: its absolute
events are offset to the segment start and its reactive events ("on": tag) are converted to absolute
frames from that test's own trace (game/tests/results/traces/<case>.jsonl). Run the movement tests
first. Output: game/tests/replays/showcase_moveset.json and showcase_profile.json.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
import run_movement_tests as T  # noqa: E402

ACTIONS = ['jump', 'crouch', 'attack', 'sniff', 'cam_center', 'interact']
JUMPS = {'jump', 'double_jump', 'triple_jump', 'long_jump', 'backflip', 'side_flip', 'wall_kick', 'rollout', 'bounce'}


def tag_frames(rows):
    tags = {}
    for i in range(1, len(rows)):
        a, b = rows[i - 1], rows[i]
        if b['g'] and not a['g']:
            tags.setdefault('land', []).append(b['f'])
        if b['s'] != a['s']:
            tags.setdefault('state:' + b['s'], []).append(b['f'])
            if b['s'] in JUMPS:
                tags.setdefault('jump:' + b['s'], []).append(b['f'])
    return tags


class Builder:
    def __init__(self):
        self.events = []
        self.f = 0
        self.first_start = None

    def _reset(self, start, pos=None):
        st = {'pos': pos or start['pos'], 'yaw_deg': start['yaw_deg']}
        if self.first_start is None:
            self.first_start = st
        self.events.append({'f': self.f, 'teleport': st['pos'], 'yaw_deg': st['yaw_deg']})
        self.events.append({'f': self.f, 'stick': [0, 0]})
        for a in ACTIONS:
            self.events.append({'f': self.f, 'release': a})
        return st

    def case(self, name, length=None, pre_roll=20, pos=None, mark=None, cam_turn=0):
        rep, _ = T.CASES[name]()
        _, rows = T.read_trace(T.TRACES / (name + '.jsonl'))
        tags = tag_frames(rows)
        st = rep.get('start', {'pos': [0, 0, 2], 'yaw_deg': 0})
        self._reset(st, pos)
        if mark:
            self.events.append({'f': self.f, 'mark': mark})
        if cam_turn:
            self.events.append({'f': self.f + 2, 'cam': [1 if cam_turn > 0 else -1, 0]})
            self.events.append({'f': self.f + 2 + abs(cam_turn), 'cam': [0, 0]})
        base = self.f + pre_roll
        for e in rep.get('events', []):
            e2 = dict(e)
            if 'on' in e2:
                lst = tags.get(e2.pop('on'), [])
                n = int(e2.pop('nth', 1))
                d = int(e2.pop('delay', 0))
                if len(lst) < n:
                    continue
                e2['f'] = lst[n - 1] + 1 + d
            e2['f'] = base + int(e2.get('f', 0))
            self.events.append(e2)
        self.f += pre_roll + (length or rep['end_frame'])

    def custom(self, start, events, length, mark=None):
        self._reset(start)
        if mark:
            self.events.append({'f': self.f, 'mark': mark})
        for e in events:
            e2 = dict(e)
            e2['f'] = self.f + int(e2.get('f', 0))
            self.events.append(e2)
        self.f += length

    def write(self, path):
        rep = {'fps': 60, 'steer': 'world', 'start': self.first_start, 'end_frame': self.f + 30, 'events': self.events}
        Path(path).write_text(json.dumps(rep, indent=1), encoding='utf-8')
        return self.f


def main():
    b = Builder()
    b.custom({'pos': [0.0, 0.0, 2.0], 'yaw_deg': 0}, [], 90, 'pre-roll (trimmed)')
    b.custom({'pos': [0.0, 0.0, 2.0], 'yaw_deg': 0}, [{'f': 2, 'cam': [1, 0]}, {'f': 70, 'cam': [0, 0]}], 420,
             'idle: breathing, blinks, a look around and a character beat')
    b.custom({'pos': [0.0, 0.0, 2.0], 'yaw_deg': 0}, [{'f': 2, 'cam': [1, 0]}, {'f': 62, 'cam': [0, 0]},
             {'f': 20, 'call': 'celebrate'}], 150, 'intro')
    b.custom({'pos': [-20.0, 0.0, 20.0], 'yaw_deg': -90}, [{'f': 2, 'cam': [1, 0]}, {'f': 34, 'cam': [0, 0]},
             {'f': 5, 'stick': [0.45, 0]}, {'f': 100, 'stick': [1, 0]}, {'f': 200, 'stick': [0, 0]}], 240, 'walk, run, brake')
    b.case('side_flip', 150, pre_roll=30, mark='run, skid, side somersault')
    b.case('triple_jump', 300, mark='single, double, triple jump')
    b.case('long_jump', 170, mark='long jump')
    b.case('wall_bonk', 170, mark='long jump into a wall: bonk and tumble')
    b.case('backflip', 150, mark='backflip')
    b.case('wall_kick', 150, pre_roll=45, mark='wall kicks (chimney camera zone)')
    b.case('ham_slam', 130, mark='Ham Slam')
    b.case('dive_slide', 200, mark='dive, belly slide, roll-out')
    b.case('punch_combo', 80, mark='jab, jab, kick')
    b.case('stomp', 80, mark='stomp')
    b.case('ledge_grab_climb', 170, mark='ledge grab and climb')
    b.case('pole', 200, mark='vine climb and pole jump')
    b.case('bounce_pad', 170, mark='bounce pad')
    b.custom({'pos': [-23.0, 0.0, 21.5], 'yaw_deg': 132.0}, [{'f': 20, 'press': 'sniff'}, {'f': 30, 'stick': [-0.66, -0.6]},
             {'f': 190, 'stick': [0, 0]}, {'f': 205, 'release': 'sniff'}], 220, 'Snout Sniff')
    b.custom({'pos': [14.0, 0.0, 6.5], 'yaw_deg': 0.0}, [{'f': 15, 'stick': [0, 0.85]}, {'f': 95, 'stick': [0, 0]}], 170,
             'hurt and knockback')
    b.case('moving_platform', 160, pre_roll=0, mark='moving platform')
    b.custom({'pos': [0.0, 0.0, 2.0], 'yaw_deg': 0}, [{'f': 20, 'call': 'top_hat'}, {'f': 30, 'call': 'celebrate'}], 150, 'top hat')
    n = b.write(HERE / 'replays' / 'showcase_moveset.json')
    print('showcase_moveset frames', n)

    p = Builder()
    p.case('jump_stand_full', 90, pos=[-11.0, 0.0, 13.0], mark='standing jump')
    p.case('jump_run_full', 160, pos=[-24.0, 0.0, 13.0], mark='running jump')
    p.case('long_jump', 160, pos=[-26.0, 0.0, 13.0], mark='long jump')
    p.case('backflip', 120, pos=[-8.0, 0.0, 13.0], mark='backflip')
    p.case('triple_jump', 280, pos=[-31.5, 0.0, 13.0], mark='triple jump chain')
    n = p.write(HERE / 'replays' / 'showcase_profile.json')
    print('showcase_profile frames', n)

    # Pose gallery for PoseCam (side view of the spawn): moves performed in place.
    g = Builder()
    sp = {'pos': [0.0, 0.0, 2.0], 'yaw_deg': 0.0}
    g.custom(sp, [{'f': 30, 'hold': 'jump', 'frames': 40}], 95, 'standing jump')
    g.custom(sp, [{'f': 15, 'hold': 'crouch', 'frames': 60}, {'f': 40, 'hold': 'jump', 'frames': 40}], 120, 'crouch and backflip')
    g.custom(sp, [{'f': 20, 'tap': 'attack'}, {'f': 32, 'tap': 'attack'}, {'f': 44, 'tap': 'attack'}], 90, 'jab, jab, kick')
    g.custom(sp, [{'f': 15, 'hold': 'jump', 'frames': 40}, {'f': 37, 'tap': 'crouch'}], 110, 'Ham Slam')
    g.custom(sp, [{'f': 10, 'press': 'sniff'}, {'f': 100, 'release': 'sniff'}], 110, 'Snout Sniff')
    g.custom(sp, [{'f': 10, 'call': 'celebrate'}], 110, 'celebrate')
    g.custom({'pos': [0.0, 0.0, 7.5], 'yaw_deg': 0.0}, [{'f': 5, 'stick': [0, 1]}, {'f': 95, 'stick': [0, 0]}], 120, 'run and brake')
    g.custom({'pos': [0.0, 0.0, 7.0], 'yaw_deg': 0.0}, [{'f': 5, 'stick': [0, 0.55]}, {'f': 110, 'stick': [0, 0]}], 130, 'walk')
    n = g.write(HERE / 'replays' / 'showcase_poses.json')
    print('showcase_poses frames', n)


if __name__ == '__main__':
    main()
