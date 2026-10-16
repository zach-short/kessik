"""Writes the app's Lottie animations to Kessik/Resources/Animations.

The shapes are drawn here in code, so a change to timing or color is an edit and a rerun:

    python3 Tools/make_animations.py

splash.json      the >_ mark from the app icon draws in, the cursor blinks once.
connecting.json  a key and a padlock with coral packets moving between them. Loops.
"""
import json
import math
import os

CORAL = [1.0, 0.38, 0.36, 1]
WHITE = [1, 1, 1, 1]
FPS = 60

OUT = os.path.join(os.path.dirname(__file__), "..", "Kessik", "Resources", "Animations")


# MARK: Lottie building blocks

def static(v):
    return {"a": 0, "k": v}


def ease(o=(0.25, 1), i=(0.5, 1)):
    """Cubic bezier easing for the segment that starts at a keyframe. Default is ease-out."""
    return {"o": {"x": [o[0]], "y": [o[1]]}, "i": {"x": [i[0]], "y": [i[1]]}}


def animated(frames):
    """frames: [(t, value, easing or None or "hold")]. The last keyframe's easing is ignored."""
    k = []
    for n, (t, v, e) in enumerate(frames):
        kf = {"t": t, "s": v if isinstance(v, list) else [v]}
        if n < len(frames) - 1:
            if e == "hold":
                kf["h"] = 1
            else:
                kf.update(e or ease((0, 0), (1, 1)))
        k.append(kf)
    return {"a": 1, "k": k}


def spatial(frames):
    """Linear position keyframes: frames is [(t, [x, y])]."""
    k = []
    for n, (t, (x, y)) in enumerate(frames):
        kf = {"t": t, "s": [x, y, 0]}
        if n < len(frames) - 1:
            kf.update({"o": {"x": 0, "y": 0}, "i": {"x": 1, "y": 1}, "to": [0, 0, 0], "ti": [0, 0, 0]})
        k.append(kf)
    return {"a": 1, "k": k}


def group(name, items, opacity=None):
    tr = {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]),
          "r": static(0), "o": opacity or static(100), "sk": static(0), "sa": static(0)}
    return {"ty": "gr", "nm": name, "it": items + [tr]}


def path(points, closed=False, tangents=None):
    n = len(points)
    ins, outs = ([[0, 0]] * n, [[0, 0]] * n) if tangents is None else tangents
    return {"ty": "sh", "ks": static({"i": ins, "o": outs, "v": points, "c": closed})}


def ellipse(center, size):
    return {"ty": "el", "p": static(center), "s": static([size, size]), "d": 1}


def rect(center, size, radius):
    return {"ty": "rc", "p": static(center), "s": static(size), "r": static(radius), "d": 1}


def stroke(color, width, opacity=100):
    return {"ty": "st", "c": static(color), "o": static(opacity), "w": static(width),
            "lc": 2, "lj": 2, "ml": 4}


def fill(color, opacity=100):
    return {"ty": "fl", "c": static(color), "o": static(opacity), "r": 1}


def trim(end):
    return {"ty": "tm", "s": static(0), "e": end, "o": static(0), "m": 1}


def radial_glow(center, radius, stops):
    """stops: [(offset, alpha)] of coral."""
    colors = [c for off, _ in stops for c in (off, *CORAL[:3])]
    alphas = [c for off, a in stops for c in (off, a)]
    return {"ty": "gf", "o": static(100), "r": 1, "t": 2,
            "s": static(center), "e": static([center[0] + radius, center[1]]),
            "h": static(0), "a": static(0),
            "g": {"p": len(stops), "k": static(colors + alphas)}}


def layer(index, name, shapes, op, opacity=None, position=None, scale=None, anchor=(0, 0)):
    ks = {"o": opacity or static(100), "r": static(0),
          "p": position or static([anchor[0], anchor[1], 0]),
          "a": static([anchor[0], anchor[1], 0]),
          "s": scale or static([100, 100, 100])}
    return {"ddd": 0, "ind": index, "ty": 4, "nm": name, "sr": 1, "ks": ks, "ao": 0,
            "shapes": shapes, "ip": 0, "op": op, "st": 0, "bm": 0}


def animation(name, w, h, op, layers):
    return {"v": "5.7.4", "fr": FPS, "ip": 0, "op": op, "w": w, "h": h, "nm": name,
            "ddd": 0, "assets": [], "layers": layers}


# MARK: Splash

def splash():
    op = 84
    # The >_ mark from the app icon, on a 400 x 400 canvas.
    chevron = [[106, 131], [188, 200], [106, 269]]
    cursor = [[219, 267], [293, 267]]
    width = 33

    draw_chevron = animated([(8, 0, ease()), (34, 100, None)])
    draw_cursor = animated([(30, 0, ease()), (44, 100, None)])
    blink = animated([(0, 100, "hold"), (56, 0, "hold"), (66, 100, None)])

    def glyph(points, draw):
        # Faint wide strokes under the solid one fall off like the icon's bloom, and a light
        # thin stroke on top gives it the icon's lit center. Lottie draws the last group first.
        def line(name, color, w, opacity=100):
            return group(name, [path(points), trim(draw), stroke(color, w, opacity)])
        return [
            line("hot", [1, 0.68, 0.64, 1], 14, 45),
            line("core", CORAL, width),
            line("bloom 1", CORAL, width + 10, 16),
            line("bloom 2", CORAL, width + 24, 9),
            line("bloom 3", CORAL, width + 42, 5),
        ]

    return animation("splash", 400, 400, op, [
        layer(1, "cursor", glyph(cursor, draw_cursor), op, opacity=blink),
        layer(2, "chevron", glyph(chevron, draw_chevron), op),
        layer(3, "glow", [group("glow", [
            ellipse([200, 200], 380),
            radial_glow([200, 200], 190, [(0, 0.30), (0.45, 0.10), (1, 0)]),
        ])], op,
            anchor=(200, 200),
            opacity=animated([(0, 0, ease()), (48, 100, None)]),
            scale=animated([(0, [70, 70, 100], ease()), (48, [100, 100, 100], None)])),
    ])


# MARK: Connecting

def connecting():
    op = 90
    line_start, line_end, y = 108, 290, 60
    soft = 70  # opacity of the white line work, close to Theme.textSecondary

    key = group("key", [
        ellipse([44, y], 26),
        ellipse([44, y], 8),
        path([[57, y], [92, y]]),
        path([[80, y], [80, y + 8]]),
        path([[88, y], [88, y + 6]]),
        stroke(WHITE, 4, soft),
    ])

    k = 6.6  # bezier handle for a 12 pt quarter circle
    shackle = path(
        [[304, 54], [304, 44], [316, 32], [328, 44], [328, 54]],
        tangents=([[0, 0], [0, 0], [-k, 0], [0, -k], [0, 0]],
                  [[0, 0], [0, -k], [k, 0], [0, 0], [0, 0]]))
    lock = group("lock", [shackle, rect([316, 70], [40, 32], 7), stroke(WHITE, 4, soft)])

    # The keyhole brightens as each packet arrives, every third of the loop.
    pulse = []
    for t in range(0, op + 1, 2):
        since = t % (op // 3)
        pulse.append((t, 45 + 55 * math.exp(-since / 7), None))
    keyhole = group("keyhole", [
        ellipse([316, 67], 8),
        rect([316, 73], [3.5, 8], 1.5),
        fill(CORAL),
    ], opacity=animated(pulse))

    track = group("track", [
        *[ellipse([x, y], 4) for x in range(line_start, line_end + 1, 13)],
        fill(WHITE, 28),
    ])

    def packet(index, phase):
        # Moves linearly across the line once per loop, fading in and out at the ends. The jump
        # from the end back to the start happens while it is invisible.
        moves, fades = [], []
        for t in range(0, op + 1, 2):
            u = (t / op + phase) % 1.0
            moves.append((t, [line_start + u * (line_end - line_start), y]))
            fades.append((t, 100 * max(0.0, min(1.0, u / 0.12, (1 - u) / 0.12)), None))
        return layer(index, f"packet {index}", [
            group("halo", [ellipse([0, 0], 24), fill(CORAL, 18)]),
            group("ring", [ellipse([0, 0], 14), fill(CORAL, 40)]),
            group("core", [ellipse([0, 0], 8), fill(CORAL)]),
            group("hot", [ellipse([0, 0], 3), fill(WHITE, 80)]),
        ], op, opacity=animated(fades), position=spatial(moves))

    return animation("connecting", 360, 120, op, [
        packet(1, 0.0),
        packet(2, 1 / 3),
        packet(3, 2 / 3),
        layer(4, "lock", [keyhole, lock], op),
        layer(5, "key", [key], op),
        layer(6, "track", [track], op),
    ])


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for anim in (splash(), connecting()):
        target = os.path.join(OUT, f"{anim['nm']}.json")
        with open(target, "w") as f:
            json.dump(anim, f, separators=(",", ":"))
        print(os.path.relpath(target), os.path.getsize(target), "bytes")
