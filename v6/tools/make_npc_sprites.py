"""Paints the prototype's NPC sprites into NPCs/, in the same style and pixel
density as the creatures (see make_creature_sprites.py). Front-facing, like
Veyl's front sprite. Two files per NPC: <id>.png and <id>_glow.png.

Pure Python, no dependencies:  python3 tools/make_npc_sprites.py
"""
import os, sys

sys.path.insert(0, os.path.dirname(__file__))
from make_creature_sprites import Sprite

OUT = os.path.join(os.path.dirname(__file__), "..", "NPCs")


def rowan():
    """Old forest warden: deep hood, grey beard, moss cloak, ember lantern staff."""
    s = Sprite(132, 240)
    cloak, cloak_dark, robe = "#2d3a2b", "#1c241c", "#4a3424"
    mantle, wood, metal = "#6e3420", "#3d2b1d", "#4a4650"

    # boots under the hem
    s.ellipse(50, 232, 10, 6, "#1a1512", rim=False)
    s.ellipse(76, 232, 10, 6, "#1a1512", rim=False)
    # cloak falls wide from the shoulders, robe showing down the front
    s.poly([(36, 78), (92, 78), (110, 228), (18, 228)], cloak, grain=0.1, top=1.1, bottom=0.65)
    s.poly([(52, 96), (74, 96), (82, 226), (46, 226)], robe, grain=0.08, top=1.05, bottom=0.7)
    s.poly([(18, 228), (30, 214), (44, 228)], cloak_dark)
    s.poly([(84, 228), (98, 212), (110, 228)], cloak_dark)
    # belt and pouch
    s.poly([(46, 146), (82, 146), (83, 154), (45, 154)], "#2a1d14", grain=0.02)
    s.ellipse(64, 150, 4, 4, "#8a6a3a", grain=0, rim=False)
    s.ellipse(40, 164, 8, 10, "#3b2a1c", grain=0.08)
    # left arm hangs inside the cloak; right arm reaches to the staff
    s.ellipse(32, 132, 11, 38, cloak_dark, grain=0.1)
    s.ellipse(30, 172, 7, 6, "#6b5444", grain=0.04)
    s.poly([(86, 92), (104, 104), (106, 128), (90, 126)], cloak, grain=0.1)
    # staff, with a caged ember lantern hanging from the crook
    s.stroke([(108, 236), (107, 140), (106, 60), (104, 34), (112, 22), (120, 30)], (5, 4), wood, grain=0.12)
    s.ellipse(105, 124, 7, 6, "#6b5444", grain=0.04)
    s.stroke([(120, 30), (120, 40)], 1.5, metal, grain=0)
    s.poly([(113, 42), (127, 42), (125, 62), (115, 62)], "#2a2622", grain=0.04)
    s.poly([(112, 40), (128, 40), (126, 44), (114, 44)], metal, grain=0.02)
    s.poly([(114, 61), (126, 61), (124, 65), (116, 65)], metal, grain=0.02)
    # mantle over the shoulders
    s.poly([(30, 76), (98, 76), (92, 102), (64, 110), (36, 102)], mantle, grain=0.1, top=1.15, bottom=0.75)
    # hood, with its tip falling back
    s.poly([(50, 18), (64, 4), (80, 18)], cloak)
    s.ellipse(64, 50, 30, 34, cloak, grain=0.1)
    s.ellipse(64, 56, 20, 23, "#0b0a0f", grain=0, rim=False)
    # grey beard spilling out of the hood
    s.poly([(50, 64), (78, 64), (74, 92), (64, 104), (54, 92)], "#8f8a80", grain=0.14, top=1.1, bottom=0.8)
    s.poly([(54, 62), (74, 62), (72, 68), (56, 68)], "#a39d92", grain=0.1)
    # eyes: tired, warm, and dimmer than Veyl's
    s.glow_slit(56, 52, 3.5, 1.4, "#ffc46a")
    s.glow_slit(72, 52, 3.5, 1.4, "#ffc46a")
    # lantern ember, and a few sparks from it
    s.glow_dot(120, 52, 5, 16, "#ff8a2a", hot="#fff1c4")
    for x, y in [(116, 28), (125, 20), (113, 12)]:
        s.glow_dot(x, y, 0.8, 3, "#ff8a2a")
    # stitched ember sigil on the mantle
    s.glow_line([(38, 88), (43, 83), (48, 88), (43, 93), (38, 88)], 0.5, 2.5, "#ff7a2a")
    s.save("rowan", OUT)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rowan()
