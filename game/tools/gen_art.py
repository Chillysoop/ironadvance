#!/usr/bin/env python3
"""Generates every sprite sheet, background and UI texture for Iron Advance.

Run from the project root:  python3 tools/gen_art.py
All art is authored here (Python 3 + Pillow + NumPy) as tiny ASCII part maps plus palettes, composited per
animation frame and given a dark outer outline, so it stays consistent and is
easy to tweak. One art pixel is drawn as 2x2 world units in game.
"""
import shutil, json, math, os, random
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'assets')
OUTLINE = (24, 16, 14, 255)

def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (255,)

# ---------------------------------------------------------------- palettes
BASE = {
    's': '#fcd0a0', 'S': '#e8a070', 'z': '#b46a44',          # skin
    'K': '#1c1410', 'W': '#ffffff', 'e': '#1c1410',          # black, white, eyes
    'g': '#a8acb4', 'G': '#6c7078', 'k': '#3c3e46',          # gun metal
    'w': '#c88a4a', 'T': '#8c5a2c',                          # wood
    'R': '#e03c30', 'Y': '#ffd23a', 'O': '#ff8a2a',          # accents
    'b': '#5a3a24', 'B': '#3a2416',                          # boots
    'x': '#c8b48c', 'X': '#8c784c',                          # straps / canvas
    'c': '#9cd8ff',                                          # glass glint
}
SQUAD_PAL = {
    'moss': {'h': '#9cb04c', 'H': '#748a34', 'j': '#4c5c20', 'u': '#8c9c5c', 'U': '#6a7a40', 'v': '#46522a', 'p': '#7a7a4c', 'P': '#5c5c34', 'q': '#3c3c22', 'f': '#5a3a20'},
    'hex':  {'h': '#f4f2ea', 'H': '#cccac0', 'j': '#8c8a84', 'u': '#4ca0a0', 'U': '#2f7a7a', 'v': '#1e5050', 'p': '#3c6a6a', 'P': '#2a4e4e', 'q': '#1a3434', 'f': '#3a2a1a'},
    'vee':  {'h': '#ff5a40', 'H': '#d63a2a', 'j': '#8c2418', 'u': '#c89c5c', 'U': '#a07a40', 'v': '#6a5028', 'p': '#6a5a3a', 'P': '#4e4228', 'q': '#322a18', 'f': '#7a3a1c'},
    'rook': {'h': '#6c9cf0', 'H': '#3c6ad0', 'j': '#22408c', 'u': '#6a8c4c', 'U': '#4c6a34', 'v': '#30461e', 'p': '#5a6a40', 'P': '#42502c', 'q': '#2a321a', 'f': '#2a1c10'},
    'bolt': {'h': '#ffc23a', 'H': '#e09a1c', 'j': '#8a5a10', 'u': '#4a5a78', 'U': '#36425a', 'v': '#222a3a', 'p': '#5a5048', 'P': '#423a34', 'q': '#2a2420', 'f': '#4a2e18'},
    'gears': {'h': '#ff9a3a', 'H': '#d6741c', 'j': '#8a4410', 'u': '#6a6e76', 'U': '#4e5258', 'v': '#30333a', 'p': '#4a4038', 'P': '#36302a', 'q': '#221e1a', 'f': '#3a2414'},
    'track': {'h': '#8a5a34', 'H': '#6a4224', 'j': '#3e2614', 'u': '#b8a87c', 'U': '#94845a', 'v': '#625638', 'p': '#4a5a3a', 'P': '#36442a', 'q': '#222c1a', 'f': '#2a1a10'},
    'finch': {'h': '#7fd0e8', 'H': '#4aa0c0', 'j': '#276880', 'u': '#d8c08a', 'U': '#b09a62', 'v': '#7a6a40', 'p': '#6a6e76', 'P': '#4e5258', 'q': '#30333a', 'f': '#2a1a10'},
    'kage': {'h': '#3a3a3a', 'H': '#262626', 'j': '#121212', 'u': '#4a4650', 'U': '#34303a', 'v': '#201c24', 'p': '#3a3a3a', 'P': '#262626', 'q': '#121212', 'f': '#2a1a10'},
    'volta': {'h': '#a07ad8', 'H': '#7a54b4', 'j': '#4a3078', 'u': '#e8e6dc', 'U': '#c0beb4', 'v': '#84827a', 'p': '#4a4a5a', 'P': '#34343e', 'q': '#202028', 'f': '#2a1a10'},
    'brass': {'h': '#d84a3a', 'H': '#a8322a', 'j': '#6a1e18', 'u': '#8a8a5a', 'U': '#6a6a40', 'v': '#46462a', 'p': '#5a5a3e', 'P': '#42422c', 'q': '#2a2a1a', 'f': '#2a1a10'},
    'sable': {'h': '#7ee0a0', 'H': '#4cb478', 'j': '#2a7a4c', 'u': '#6a3e90', 'U': '#4e2a6e', 'v': '#301a46', 'p': '#3e3448', 'P': '#2c2434', 'q': '#1c1622', 'f': '#2a1a10'},
}
SQUAD_KEYS = list(SQUAD_PAL.keys())
JACKAL = {'u': '#e0c890', 'U': '#bca064', 'v': '#8a7040', 'p': '#c0a46c', 'P': '#98804c', 'q': '#66542e', 'f': '#2a1c10'}
ENEMY_PAL = {
    'grunt':      dict(JACKAL, h='#d84a3a', H='#a8302a', j='#6a1c18'),
    'shield':     dict(JACKAL, h='#9aa2ae', H='#6c7480', j='#40464e'),
    'nade':       dict(JACKAL, h='#d84a3a', H='#a8302a', j='#6a1c18', u='#b8c07c', U='#929a58', v='#646a38'),
    'brute':      dict(JACKAL, h='#4a3428', H='#34241c', j='#1e140e', u='#c0503a', U='#943428', v='#5e2018', s='#e0a070', S='#c07a4c', z='#8a5030'),
    'mg':         dict(JACKAL, h='#d84a3a', H='#a8302a', j='#6a1c18'),
    'radio':      dict(JACKAL, h='#5a86c8', H='#3a5e9c', j='#223a66'),
    'engineer':   dict(JACKAL, h='#ffd23a', H='#d8a420', j='#8a6410'),
    'sapper':     dict(JACKAL, h='#3a3a3a', H='#262626', j='#121212', u='#8c7c58', U='#6a5c3c', v='#463c26'),
    'mortarcrew': dict(JACKAL, h='#8a6a3a', H='#6a4e26', j='#443018', u='#b8c07c', U='#929a58', v='#646a38'),
    'para':       dict(JACKAL, h='#d84a3a', H='#a8302a', j='#6a1c18'),
    'jetter':     dict(JACKAL, h='#3ab0a8', H='#24807a', j='#14504c'),
    'jsniper':    dict(JACKAL, h='#6a7a40', H='#4e5a2c', j='#2e361a', u='#8c8a5a', U='#6a6840', v='#46442a'),
    'flamer':     dict(JACKAL, h='#3a3a3a', H='#262626', j='#121212', u='#a8603a', U='#844428', v='#562a18'),
}

def palette(over):
    p = {k: rgb(v) for k, v in BASE.items()}
    for k, v in over.items():
        p[k] = rgb(v)
    return p

# ---------------------------------------------------------------- part maps (facing right)
# Heads are 10 wide, 8 tall, placed at (5, 3) on the 24x24 frame. '.' is empty.
HEADS = {
    'helmet': [
        "...hhhh...",
        "..hHHHHh..",
        ".hHHHHHHh.",
        ".jHHHHHHHj",
        ".jjjjjjjjj",
        "..zSSSeSS.",
        "..zSSSSSs.",
        "...zSSSz..",
    ],
    'shades': [
        "...hhhh...",
        "..hHHHHh..",
        ".hHHHHHHh.",
        ".jHHHHHHHj",
        ".jjjjjjjjj",
        "..zSSKKKKc",
        "..zSSSSSs.",
        "...zSSKz..",
    ],
    'boonie': [
        "...hhhh...",
        "..hHHHHh..",
        "..HHHHHHh.",
        "jjjjjjjjjj",
        ".zfSSSSSS.",
        "..zSSSeSS.",
        "..zjSjSjs.",
        "...zSSSz..",
    ],
    'medic': [
        "...hhhh...",
        "..hhRhhh..",
        ".hhRRRhhh.",
        ".HhhRhhhHH",
        ".jjjjjjjjj",
        "..zSSSeSS.",
        "..zSSSSSs.",
        "...zSSSz..",
    ],
    'bandana': [
        "...ffff...",
        "..fhhhhh..",
        ".fhhHhhhh.",
        "fjHHHHHHHj",
        "f.zSSSSSS.",
        "f.zSSSeSS.",
        "..zSSSSSs.",
        "...zSSSz..",
    ],
    'beret': [
        "..........",
        "...hhhhh..",
        "..hHHHHHH.",
        "..jHHHHjj.",
        "..zfffff..",
        "..zSSSeSS.",
        "..zSSSSSs.",
        "...zSKSz..",
    ],
    'hardhat': [
        "...hhhh...",
        "..hhhhhh..",
        ".hHHHHHHh.",
        "jjjjjjjjjj",
        "..zffSSS..",
        "..zSSSeSS.",
        "..zSSSSSs.",
        "...zSKSz..",
    ],
    'mask': [
        "...hhhh...",
        "..hHHHHh..",
        ".hHHHHHHh.",
        ".HHHHHHHH.",
        ".HHHWWeWH.",
        ".HHHHHHHH.",
        "..HHHHHHH.",
        "...jHHHj..",
    ],
    'riot': [
        "..hhhhh...",
        ".hHHHHHh..",
        "hHHHHHHHh.",
        "jHHHHcccc.",
        "jHHHHcSec.",
        "jjHHzSSSs.",
        "..zSSSSSs.",
        "...zSSSz..",
    ],
}
# Torsos: 10 wide, 6 tall at (5, 11): shoulders, chest, belt
TORSOS = {
    'vest': [
        "...uUUUu..",
        "..uUxUUUv.",
        "..uUUxUUv.",
        "..vUUUxUv.",
        "..vUUUUUv.",
        "...KKYKK..",
    ],
    'medic': [
        "...uUUUu..",
        "..uUUUUUv.",
        "..uUWRWUv.",
        "..vURRRUv.",
        "..vUWRWUv.",
        "...KKYKK..",
    ],
    'jackal': [
        "...uUUUu..",
        "..uUUUUUv.",
        "..uUKUUUv.",
        "..vUUUUUv.",
        "..vUUUUUv.",
        "...KKKKK..",
    ],
    'bomber': [
        "...uUUUu..",
        "..uUUUUUv.",
        "..uXGXGXv.",
        "..vUUUUUv.",
        "..vUUUUUv.",
        "...KKKKK..",
    ],
}
# Back items: drawn behind the body, 8 wide x 10 tall at (1, 6)
BACKS = {
    'none': [],
    'fueltank': [
        "........",
        "........",
        "........",
        "...KKK..",
        "..KRRRK.",
        "..KRYRK.",
        "..KRYRK.",
        "..KRRRK.",
        "..KRRRK.",
        "...KKK..",
    ],
    'pack': [
        "........",
        "........",
        "........",
        "........",
        "........",
        "...XXX..",
        "..XxxxX.",
        "..XxxxX.",
        "..XXXXX.",
        "...XXX..",
    ],
    'radio': [
        "....K...",
        "....K...",
        "....K...",
        "....K...",
        "....K...",
        "..GGGGG.",
        "..GkYkG.",
        "..GkkkG.",
        "..GGGGG.",
        "..kkkkk.",
    ],
    'ponytail': [
        "........",
        "........",
        "....fff.",
        "...fff..",
        "...ff...",
        "..ff....",
        "........",
        "........",
        "........",
        "........",
    ],
    'satchel': [
        "........",
        "........",
        "........",
        "........",
        "........",
        "...XXX..",
        "..XRXRX.",
        "..XXXXX.",
        "..XXXXX.",
        "........",
    ],
    'jetpack': [
        "........",
        "........",
        "........",
        "...g.g..",
        "..gGgGg.",
        "..GkGkG.",
        "..GkGkG.",
        "..GkGkG.",
        "..kOkOk.",
        "...Y.Y..",
    ],
}
# Legs: 12 wide, 7 tall at (4, 17). Front leg uses P/p, back leg q.
LEGS = {
    'stand': [
        "....pPPq....",
        "....pP.q....",
        "....pP.qq...",
        "....pP..q...",
        "...pP...q...",
        "...bBB.bBB..",
        "...BBBBBBBB.",
    ],
    'stand2': [
        "....pPPq....",
        "....pP.q....",
        "....pP.qq...",
        "....pP..q...",
        "...pP...q...",
        "...bBB.bBB..",
        "...BBBBBBBB.",
    ],
    'run0': [
        "....pPPq....",
        "...pPP.qq...",
        "..pPP...qq..",
        ".pP......q..",
        "bB.......bB.",
        "BB......bBBB",
        "............",
    ],
    'run1': [
        "....pPPq....",
        "....pPqq....",
        "...pPP.q....",
        "..pP...q....",
        "..bB..bBB...",
        ".BBB..BBB...",
        "............",
    ],
    'run2': [
        "....pPPq....",
        "....qPPp....",
        "....qPPp....",
        "...q..pP....",
        "..bB..bBB...",
        "..BB..BBB...",
        "............",
    ],
    'run3': [
        "....pPPq....",
        "....qpPP....",
        "...qq.pPp...",
        "..q....pP...",
        ".bB.....bB..",
        ".BB....bBBB.",
        "............",
    ],
    'jump': [
        "....pPPq....",
        "...pPPPqq...",
        "...pP..qq...",
        "....pP.qq...",
        "...bBB.bBB..",
        "...BBB.BBB..",
        "............",
    ],
    'crouch': [
        "...pPPPqq...",
        "..pPPPPPqq..",
        "..pP....qq..",
        "..bBB...bBB.",
        "..BBBB.BBBB.",
        "............",
        "............",
    ],
}

CHAR_STYLE = {
    'moss': dict(head='boonie', torso='vest', back='pack', gun='sniper'),
    'hex':  dict(head='medic', torso='medic', back='pack', gun='pistol'),
    'vee':  dict(head='bandana', torso='vest', back='ponytail', gun='launcher'),
    'rook': dict(head='shades', torso='vest', back='pack', gun='rifle'),
    'bolt': dict(head='hardhat', torso='vest', back='pack', gun='rifle'),
    'gears': dict(head='helmet', torso='vest', back='pack', gun='pistol'),
    'track': dict(head='beret', torso='vest', back='pack', gun='rifle'),
    'finch': dict(head='bandana', torso='vest', back='pack', gun='pistol'),
    'kage': dict(head='bandana', torso='vest', back='none', gun='pistol'),
    'volta': dict(head='helmet', torso='vest', back='pack', gun='pistol'),
    'brass': dict(head='beret', torso='vest', back='pack', gun='rifle'),
    'sable': dict(head='shades', torso='vest', back='pack', gun='pistol'),
    'grunt':      dict(head='beret', torso='jackal', back='none', gun='rifle'),
    'shield':     dict(head='riot', torso='jackal', back='none', gun='pistol'),
    'nade':       dict(head='beret', torso='bomber', back='none', gun='none'),
    'mg':         dict(head='helmet', torso='jackal', back='none', gun='hmg'),
    'radio':      dict(head='helmet', torso='jackal', back='radio', gun='pistol'),
    'engineer':   dict(head='hardhat', torso='jackal', back='pack', gun='pistol'),
    'sapper':     dict(head='mask', torso='jackal', back='satchel', gun='none'),
    'mortarcrew': dict(head='helmet', torso='bomber', back='none', gun='none'),
    'para':       dict(head='helmet', torso='jackal', back='pack', gun='rifle'),
    'jetter':     dict(head='helmet', torso='jackal', back='jetpack', gun='rifle'),
    'jsniper':    dict(head='boonie', torso='jackal', back='none', gun='sniper'),
    'flamer':     dict(head='mask', torso='jackal', back='fueltank', gun='hmg'),
}

FW = FH = 24  # frame size in art pixels

def stamp(img, rows, ox, oy, pal):
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '.' or ch == ' ':
                continue
            X, Y = ox + x, oy + y
            if 0 <= X < img.width and 0 <= Y < img.height and ch in pal:
                px[X, Y] = pal[ch]

def outline(img, col=OUTLINE):
    w, h = img.size
    src = img.load()
    out = img.copy()
    o = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                X, Y = x + dx, y + dy
                if 0 <= X < w and 0 <= Y < h and src[X, Y][3] and src[X, Y] != col:
                    o[x, y] = col
                    break
    return out

def settle(img, lift=0):
    """Shift a rotated frame so its lowest opaque pixel sits on the bottom row (minus lift)."""
    bb = img.getbbox()
    if not bb:
        return img
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.paste(img, (0, img.height - bb[3] - lift))
    return out

def flash_white(img):
    out = img.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if px[x, y][3]:
                px[x, y] = (255, 255, 255, 255)
    return out

def arm_rows(kind):
    """Arms baked into the body for poses where the gun layer is hidden."""
    return {
        'throw0': (["..SS", ".SSu", "SSu.", "Su.."], 2, 9),
        'throw1': (["SS..", "SSu.", ".uU.", "..U."], 13, 7),
        'throw2': (["....", "uUSS", "..SS", "...."], 13, 12),
        'cheer':  (["SS", "Su", "uU", "uU"], 13, 6),
        'hurt':   (["uS..", "..S.", "...S"], 13, 12),
        'climb':  (["SS", "uS", "uU"], 13, 7),
    }[kind]

def build_body(key, pal, legs='stand', bob=0, lean=0, arms=None, head_dy=0, face=None):
    st = CHAR_STYLE[key]
    img = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
    back = BACKS[st['back']]
    if back:
        stamp(img, back, 1 + lean, 6 + bob, pal)
    stamp(img, LEGS[legs], 4, 17, pal)
    stamp(img, TORSOS[st['torso']], 5 + lean, 11 + bob, pal)
    head = HEADS[st['head']]
    if face == 'ouch':
        head = [r for r in head]
        head[5] = head[5].replace('e', 'K')
        head[7] = head[7][:5] + 'K' + head[7][6:]
    elif face == 'blink':
        head = [r for r in head]
        head[5] = head[5].replace('e', 'z')
    stamp(img, head, 5 + lean, 3 + bob + head_dy, pal)
    if arms:
        rows, ax, ay = arm_rows(arms)
        stamp(img, rows, ax + lean, ay + bob, pal)
    return img

# Arm+gun layers, drawn at runtime on top of the body and rotated to the aim angle.
# Each is (rows, pivot_x, pivot_y): the pivot is the shoulder, placed on the body's shoulder point.
GUNS = {
    'rifle': ([
        "..........kk....",
        "SSuU.GGGGGGGGGGk",
        ".SSTwwGgggGGk...",
        "..TTT.SS.k......",
        "..TT............",
    ], 1, 1),
    'sniper': ([
        "......kkkk..........",
        "SSuU..GccG..........",
        ".SSwwwGGGGGGGGGGGGGk",
        "..TTT.SS..k.........",
        "..TT................",
    ], 1, 1),
    'pistol': ([
        "............",
        "SuUUSSGGGGk.",
        "......Sk....",
        "............",
    ], 1, 1),
    'launcher': ([
        "....GGGGGGGGGGGG",
        "GGGGgggggggggggRR",
        "SSuUGGSGGGGGGGGRR",
        "..KK..SK........",
    ], 2, 2),
    'hmg': ([
        "..........kkk.......",
        "SSuUkGGGGGGGGGGGGGGk",
        ".SSkkkkGGgGGG.......",
        "...kKKk.S..k........",
        "....KK..............",
    ], 1, 1),
    'ray': ([
        "...........cc....",
        "SSuU.GGGGGGGGGgcc",
        ".SSTwGGgggGGk.cc.",
        "..TTT.SS.k.......",
        "..TT.............",
    ], 1, 1),
    'none': ([
        "SS.",
        ".SS",
        "..S",
    ], 0, 0),
}

def gun_image(kind, pal):
    rows, px, py = GUNS[kind]
    w = max(len(r) for r in rows)
    img = Image.new('RGBA', (w + 2, len(rows) + 2), (0, 0, 0, 0))
    stamp(img, rows, 1, 1, pal)
    return outline(img), px + 1, py + 1

# shoulder point on the body frame (art px), before bob
SHOULDER = (10, 13)

ANIMS = ['idle', 'run', 'jump', 'hurt', 'die', 'throw', 'cheer', 'climb', 'crouch']

def char_frames(key, pal):
    """Returns dict anim -> list of (image, shoulder(x,y), gun_visible)."""
    F = {}
    sx, sy = SHOULDER
    # idle: a slow breath with a blink at the end of the cycle (12 frames, drawn ~10 ticks each)
    st0 = (build_body(key, pal, 'stand', 0), (sx, sy), True)
    st1 = (build_body(key, pal, 'stand2', 1), (sx, sy + 1), True)
    bl = (build_body(key, pal, 'stand', 0, face='blink'), (sx, sy), True)
    F['idle'] = [st0, st0, st0, st1, st1, st1, st0, st0, st0, st1, st1, bl]
    run = []
    for i, (lg, b) in enumerate([('run0', 0), ('run1', 1), ('run2', 1), ('run3', 0)] * 2):
        flip_legs = i >= 4
        img = build_body(key, pal, lg, b, lean=1)
        run.append((img, (sx + 1, sy + b), True))
    # second half of the cycle swaps leg tones for a believable stride
    F['run'] = run
    F['jump'] = [(build_body(key, pal, 'jump', -1), (sx, sy - 1), True),
                 (build_body(key, pal, 'jump', 0), (sx, sy), True)]
    F['hurt'] = [(build_body(key, pal, 'stand2', 0, lean=-1, arms='hurt', face='ouch'), (sx - 1, sy), False),
                 (build_body(key, pal, 'stand2', 1, lean=-1, arms='hurt', face='ouch'), (sx - 1, sy + 1), False)]
    F['throw'] = [(build_body(key, pal, 'stand', 0, lean=-1, arms='throw0'), (sx - 1, sy), False),
                  (build_body(key, pal, 'stand', 0, lean=0, arms='throw1'), (sx, sy), False),
                  (build_body(key, pal, 'stand2', 1, lean=1, arms='throw2'), (sx + 1, sy + 1), False),
                  (build_body(key, pal, 'stand', 0, lean=0), (sx, sy), True)]
    F['cheer'] = [(build_body(key, pal, 'stand', 0, arms='cheer'), (sx, sy), False),
                  (build_body(key, pal, 'jump', -2, arms='cheer'), (sx, sy - 2), False)]
    F['climb'] = [(build_body(key, pal, 'run1', 0, arms='climb'), (sx, sy), False),
                  (build_body(key, pal, 'run3', 1, arms='climb'), (sx, sy + 1), False)]
    F['crouch'] = [(build_body(key, pal, 'crouch', 2), (sx, sy + 2), True)]
    # death, Metal Slug style: the hit snaps them back, they fly arms up, slam flat, bounce once
    # and lie still (6 frames)
    die = []
    hit = build_body(key, pal, 'stand2', 0, lean=-1, arms='hurt', face='ouch')
    fly = build_body(key, pal, 'jump', 0, face='ouch', arms='cheer')
    flat = build_body(key, pal, 'jump', 0, face='ouch', arms='hurt')
    kick = build_body(key, pal, 'run1', 0, face='ouch', arms='cheer')
    for im, ang, lift in ((hit, 8, 0), (fly, 30, 5), (fly, 62, 4), (flat, 90, 0), (kick, 96, 2), (flat, 90, 0)):
        r = settle(im.rotate(ang, resample=Image.NEAREST, center=(12, 14), expand=False), lift)
        die.append((r, (sx, sy), False))
    F['die'] = die
    out = {}
    for a, fr in F.items():
        out[a] = [(outline(im), sh, gv) for im, sh, gv in fr]
    return out

def write_sheet(name, frames, gun):
    """frames: anim -> [(img, shoulder, gunvis)] ; sheet rows are animations."""
    cols = max(len(v) for v in frames.values())
    rows = len(ANIMS)
    sheet = Image.new('RGBA', (cols * FW, rows * 2 * FH), (0, 0, 0, 0))
    meta = {'frame': [FW, FH], 'anchor': [12, 24], 'anims': {}, 'flash_row_offset': rows}
    for r, a in enumerate(ANIMS):
        fr = frames.get(a) or frames['idle']
        meta['anims'][a] = {'row': r, 'n': len(fr), 'shoulder': [list(f[1]) for f in fr], 'gun': [f[2] for f in fr]}
        for c, (im, _, _) in enumerate(fr):
            sheet.paste(im, (c * FW, r * FH))
            sheet.paste(flash_white(im), (c * FW, (r + rows) * FH))
    sheet.save(os.path.join(OUT, 'sprites', name + '.png'))
    if gun:
        gimg, gpx, gpy = gun
        gimg.save(os.path.join(OUT, 'sprites', name + '_gun.png'))
        flash_white(gimg).save(os.path.join(OUT, 'sprites', name + '_gun_w.png'))
        meta['gun_pivot'] = [gpx, gpy]
    return meta

# ---------------------------------------------------------------- Sprite Fusion characters
# Bodies drawn by the Sprite Fusion generator (tools/sf_api.py, styled on our own frames) live in
# tools/sf_src/<name>/ as still.png plus idle.png / run.png strips. They are cleaned here, so this
# script still rebuilds every sheet with no network and no key: hard alpha, one shared palette per
# character (the generator leaves hundreds of near-duplicate colours), our outline colour, feet on
# the bottom row. The poses it doesn't animate are built from the still the way char_frames does.
SF_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sf_src')

def sf_strip(path, fw=FW):
    im = Image.open(path).convert('RGBA')
    return [im.crop((i * fw, 0, i * fw + fw, FH)) for i in range(im.width // fw)]

def sf_clean(frames, colors=20):
    arrs = [np.array(f.convert('RGBA')) for f in frames]
    for a in arrs:
        a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    # outline: anything near-black becomes our outline colour and stays out of the shared palette
    for a in arrs:
        dark = (a[..., 3] == 255) & (a[..., :3].astype(int).sum(-1) < 110)
        a[dark] = OUTLINE
    px = np.concatenate([a[(a[..., 3] == 255) & ~np.all(a == OUTLINE, -1)][:, :3] for a in arrs])
    strip = Image.fromarray(px.reshape(1, -1, 3).astype(np.uint8), 'RGB')
    pal = np.array(strip.quantize(colors, method=Image.Quantize.MEDIANCUT).convert('RGB')).reshape(-1, 3)
    pal = np.unique(pal, axis=0).astype(int)
    out = []
    for a in arrs:
        m = (a[..., 3] == 255) & ~np.all(a == OUTLINE, -1)
        c = a[m][:, :3].astype(int)
        a[m, :3] = pal[((c[:, None, :] - pal[None]) ** 2).sum(-1).argmin(1)]
        img = Image.fromarray(a, 'RGBA')
        bb = img.getbbox()
        if bb and bb[3] != FH:
            img = settle(img)
        out.append(img)
    return out

def sf_char(name):
    d = os.path.join(SF_SRC, name)
    still = Image.open(os.path.join(d, 'still.png')).convert('RGBA').crop((0, 0, FW, FH))
    idle = sf_strip(os.path.join(d, 'idle.png'))
    run = sf_strip(os.path.join(d, 'run.png'))
    clean = sf_clean([still] + idle + run)
    still, idle, run = clean[0], clean[1:1 + len(idle)], clean[1 + len(idle):]
    top0 = still.getbbox()[1]
    sx, sy = SHOULDER
    def sh(im, dx=0):
        # the gun rides the shoulder: follow the body's bob from the head's top row
        return (sx + dx, sy + im.getbbox()[1] - top0)
    def lift(im, dy):
        out = Image.new('RGBA', im.size, (0, 0, 0, 0))
        out.paste(im, (0, dy))
        return out
    def lean(im, dx):
        # shear the upper body by a pixel, feet stay planted
        out = im.copy()
        top = im.crop((0, 0, FW, 15))
        out.paste((0, 0, 0, 0), (0, 0, FW, 15))
        out.alpha_composite(top, (dx, 0))
        return out
    def crouch(im):
        out = Image.new('RGBA', im.size, (0, 0, 0, 0))
        out.alpha_composite(im.crop((0, 0, FW, 17)), (0, 2))
        out.alpha_composite(im.crop((0, 19, FW, FH)), (0, 19))
        return out
    F = {}
    F['idle'] = [(f, sh(f), True) for f in idle for _ in (0, 1)]
    F['run'] = [(f, sh(f, 1), True) for f in run]
    F['jump'] = [(lift(run[2], -1), (sx, sy - 1), True), (run[2], (sx, sy), True)]
    hurt = lean(still, -1)
    F['hurt'] = [(hurt, (sx - 1, sy), False), (lift(hurt, 1), (sx - 1, sy + 1), False)]
    F['throw'] = [(lean(still, -1), (sx - 1, sy), False), (still, (sx, sy), False),
                  (lean(still, 1), (sx + 1, sy), False), (still, (sx, sy), True)]
    F['cheer'] = [(still, (sx, sy), False), (lift(still, -2), (sx, sy - 2), False)]
    F['climb'] = [(run[1], sh(run[1]), False), (run[5 % len(run)], sh(run[5 % len(run)]), False)]
    F['crouch'] = [(crouch(still), (sx, sy + 2), True)]
    F['die'] = [(settle(hurt.rotate(ang, resample=Image.NEAREST, center=(12, 14)), up), (sx, sy), False)
                for ang, up in ((8, 0), (30, 5), (62, 4), (90, 0), (96, 2), (90, 0))]
    return F

def sf_vehicles():
    """Walker hull, bike and tank from Sprite Fusion (tools/sf_src/vehicles). Each gets a Jackal khaki
    version, an olive one for squad drivers and a white hit flash; world_view draws them in place of
    the old rectangles (walker legs stay procedural so they can stride)."""
    import colorsys
    for k in ('walker', 'bike', 'tank'):
        im = sf_clean([Image.open(os.path.join(SF_SRC, 'vehicles', k + '.png')).convert('RGBA')], 16)[0]
        im = im.crop(im.getbbox())
        im.save(os.path.join(OUT, 'sprites', 'veh_%s.png' % k))
        flash_white(im).save(os.path.join(OUT, 'sprites', 'veh_%s_w.png' % k))
        sq = im.copy()
        px = sq.load()
        for y in range(sq.height):
            for x in range(sq.width):
                r, g, b, a = px[x, y]
                if not a or (r, g, b, a) == OUTLINE:
                    continue
                h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                if 0.05 < h < 0.17 and s > 0.15:
                    # khaki armour -> squad olive, same shading
                    r2, g2, b2 = colorsys.hsv_to_rgb(0.2, min(1, s * 1.1), v * 0.8)
                    px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), 255)
        sq.save(os.path.join(OUT, 'sprites', 'veh_%s_sq.png' % k))

def sf_vharr():
    """Vharr structures from Sprite Fusion (tools/sf_src/vharr): hive pod, drop pod, gate, Skitter tunnel.
    world_view draws them with its own glow, swirl and smoke on top."""
    for k in ('hive', 'droppod', 'vgate', 'burrow'):
        im = sf_clean([Image.open(os.path.join(SF_SRC, 'vharr', k + '.png')).convert('RGBA')], 20)[0]
        im = im.crop(im.getbbox())
        im.save(os.path.join(OUT, 'sprites', 'vh_%s.png' % k))
        flash_white(im).save(os.path.join(OUT, 'sprites', 'vh_%s_w.png' % k))

def sf_icons():
    """16x16 UI icons from Sprite Fusion (tools/sf_src/icons), replacing the 8x8 ones ui() draws.
    Each is centred on a 16x16 canvas; anything taller keeps its bottom 16 rows. The 8x8 ones stay
    as ic8_* for the spots that draw icons smaller than 16 (energy pips, plates, inline coins)."""
    for f in sorted(os.listdir(os.path.join(SF_SRC, 'icons'))):
        if not f.endswith('.png'):
            continue
        im = sf_clean([Image.open(os.path.join(SF_SRC, 'icons', f)).convert('RGBA')], 10)[0]
        im = im.crop(im.getbbox())
        if im.height > 16:
            im = im.crop((0, im.height - 16, im.width, im.height))
        dest = os.path.join(OUT, 'ui', 'ic_' + f)
        Image.open(dest).save(os.path.join(OUT, 'ui', 'ic8_' + f))
        out = Image.new('RGBA', (16, 16), (0, 0, 0, 0))
        out.alpha_composite(im, ((16 - im.width) // 2, (16 - im.height) // 2))
        out.save(dest)

def sf_normals(meta):
    """G6: normal maps for the character sheets, made by Sprite Fusion from the sheets themselves
    (tools/sf_api.py normals, stored palette-quantised in tools/sf_src/normals). A map is only copied
    if its alpha still matches the sheet; a sheet redrawn since then prints a warning and draws flat
    until the maps are fetched again."""
    d = os.path.join(SF_SRC, 'normals')
    for k in sorted(meta):
        src = os.path.join(d, k + '.png')
        dest = os.path.join(OUT, 'sprites', k + '_n.png')
        if not os.path.exists(src):
            continue
        n = Image.open(src).convert('RGBA')
        s = Image.open(os.path.join(OUT, 'sprites', k + '.png')).convert('RGBA')
        if n.size != s.size or not np.array_equal(np.array(n)[..., 3] > 0, np.array(s)[..., 3] > 0):
            print('normal map out of date, skipped:', k)
            if os.path.exists(dest):
                os.remove(dest)
            continue
        shutil.copyfile(src, dest)  # keep the stored palette PNG, it is a third the size

# ---------------------------------------------------------------- big pieces: brute, POW, boss, MG nest
def brute_frames():
    pal = palette(ENEMY_PAL['brute'])
    head = [
        "....hhhhh...",
        "...hHHHHHh..",
        "..jHHHHHHHj.",
        "..zSSSSSSSS.",
        "..zSSSSKeSS.",
        "..zSSSSSSSs.",
        "..zzSKKKSs..",
        "...zzSSSz...",
    ]
    torso = [
        "..SSuUUUUuSS..",
        ".SSuUUUUUUUSS.",
        ".SSuUxUUUUUSS.",
        ".SSvUUxUUUUvSS",
        "..SvUUUxUUUvS.",
        "...vUUUUUUUv..",
        "....KKKYKKK...",
    ]
    legs = {
        'stand': ["....qPPPPq....", "....qPP.PPq...", "....qPP..PPq..", "...qPP...PPq..", "..bBBB...bBBB.", "..BBBBB..BBBBB"],
        'run0':  ["....qPPPPq....", "...qPP..PPq...", "..qPP....PPq..", ".bBB.....bBBB.", ".BBB....bBBBBB", ".............."],
        'run1':  ["....qPPPPq....", "....qPPPPq....", "....qPP.PP....", "...bBBB.bBB...", "...BBBB.BBBB..", ".............."],
    }
    machete = ["......W", ".....Wg", "....Wg.", "...Wg..", "..Wg...", ".Tk....", "TT....."]
    F = {}
    def body(lg, bob, swing=0, ouch=False):
        img = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
        stamp(img, legs[lg], 8, 26 - 6 + 1 - 1, pal)
        stamp(img, torso, 7, 13 + bob, pal)
        h = list(head)
        if ouch:
            h[4] = h[4].replace('e', 'K')
        stamp(img, h, 9, 5 + bob, pal)
        m = machete if swing == 0 else [r[::-1] for r in machete[::-1]]
        stamp(img, m, 19 if swing == 0 else 20, 9 + bob if swing == 0 else 15 + bob, pal)
        return outline(img)
    F['idle'] = [body('stand', 0), body('stand', 0), body('stand', 1), body('stand', 1)]
    F['run'] = [body('run0', 0), body('run1', 1), body('run0', 0), body('run1', 1)]
    F['jump'] = [body('run1', 0)]
    F['hurt'] = [body('stand', 1, ouch=True)]
    F['throw'] = [body('stand', 0, 1), body('stand', 0, 1)]
    F['cheer'] = [body('stand', 0)]
    F['climb'] = [body('run1', 0)]
    F['crouch'] = [body('stand', 1)]
    base = body('stand', 0, ouch=True)
    F['die'] = [settle(base.rotate(a, resample=Image.NEAREST, center=(16, 20)), 1 if a == 90 and i == 3 else 0) for i, a in enumerate((20, 45, 70, 90, 90))]
    cols = max(len(v) for v in F.values())
    rows = len(ANIMS)
    sheet = Image.new('RGBA', (cols * 32, rows * 2 * 32), (0, 0, 0, 0))
    meta = {'frame': [32, 32], 'anchor': [16, 32], 'anims': {}, 'flash_row_offset': rows}
    for r, a in enumerate(ANIMS):
        fr = F[a]
        meta['anims'][a] = {'row': r, 'n': len(fr), 'shoulder': [[16, 16]] * len(fr), 'gun': [False] * len(fr)}
        for c, im in enumerate(fr):
            sheet.paste(im, (c * 32, r * 32))
            sheet.paste(flash_white(im), (c * 32, (r + rows) * 32))
    sheet.save(os.path.join(OUT, 'sprites', 'en_brute.png'))
    return meta

def pow_frames():
    pal = palette({'u': '#f0ead8', 'U': '#cfc6ae', 'v': '#9a917a', 'p': '#8a6a46', 'P': '#6a4e30', 'q': '#4a3420', 'f': '#3a2a1a'})
    tied = [
        "....ffff....",
        "...fSSSSf...",
        "...zSSeSs...",
        "...zSSSSs...",
        "....zKKz....",
        "...uUUUUu...",
        "..xxxxxxxx..",
        "..uUUUUUUv..",
        "..xxxxxxxx..",
        "..vUUUUUUv..",
        "...pPPPPq...",
        "...pP..Pq...",
        "..BBB..BBB..",
    ]
    free = [
        "..S......S..",
        "..S.ffff.S..",
        "..SfSSSSfS..",
        "...zSSeSs...",
        "...zSSSSs...",
        "....zKKz....",
        "...uUUUUu...",
        "..uUUUUUUv..",
        "..vUUUUUUv..",
        "..vUUUUUUv..",
        "...pPPPPq...",
        "...pP..Pq...",
        "..BBB..BBB..",
    ]
    out = []
    for rows, dy in ((tied, 0), (tied, 1), (free, 0), (free, -2)):
        img = Image.new('RGBA', (FW, FH), (0, 0, 0, 0))
        stamp(img, rows, 6, 24 - len(rows) + dy - 1 + 1, pal)
        out.append(outline(img))
    sheet = Image.new('RGBA', (FW * 4, FH), (0, 0, 0, 0))
    for i, im in enumerate(out):
        sheet.paste(im, (i * FW, 0))
    sheet.save(os.path.join(OUT, 'sprites', 'pow.png'))

def boss_sheet():
    """Iron Boar: 64x40 art px tank, 2 frames of tread animation, plus cannon, plate and cracked variants."""
    W, H = 64, 40
    pal = {k: rgb(v) for k, v in {
        'a': '#c8a868', 'A': '#9c7c44', 'd': '#6a5228', 'D': '#46361a',
        'r': '#c05a40', 'R': '#94402c', 'Q': '#62281a',
        't': '#4a4440', 'T': '#2c2824', 'm': '#8a8a90', 'M': '#5c5c64',
        'W': '#ece6d8', 'K': '#18120e', 'Y': '#ffd23a', 'P': '#9fb4c9', 'p': '#6a7a8c',
    }.items()}
    def tank(phase, plate, cracked):
        img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        # treads
        d.rounded_rectangle([2, 30, 61, 39], 4, fill=pal['T'])
        d.rounded_rectangle([3, 31, 60, 38], 3, fill=pal['t'])
        for i in range(7):
            cx = 8 + i * 8
            d.ellipse([cx - 3, 31, cx + 3, 37], fill=pal['M'])
            d.ellipse([cx - 1, 33, cx + 1, 35], fill=pal['T'])
        for i in range(15):
            x = 4 + ((i * 4 + phase * 2) % 58)
            d.point((x, 30), fill=pal['m'])
            d.point((x, 39), fill=pal['M'])
        # hull
        d.polygon([(4, 30), (8, 20), (58, 20), (62, 30)], fill=pal['A'])
        d.line([(8, 20), (58, 20)], fill=pal['a'])
        d.line([(4, 29), (62, 29)], fill=pal['d'])
        for i in range(9):
            d.point((10 + i * 6, 24), fill=pal['D'])
        # boar face on the front plate (left side faces the squad)
        d.rectangle([6, 22, 12, 27], fill=pal['D'])
        d.point((8, 24), fill=pal['Y']); d.point((11, 24), fill=pal['Y'])
        d.line([(5, 28), (3, 25)], fill=pal['W']); d.line([(13, 28), (14, 25)], fill=pal['W'])
        # turret
        d.rectangle([22, 9, 50, 20], fill=pal['R'])
        d.line([(22, 9), (50, 9)], fill=pal['r'])
        d.line([(22, 20), (50, 20)], fill=pal['Q'])
        d.rectangle([40, 4, 46, 9], fill=pal['R']); d.line([(40, 4), (46, 4)], fill=pal['r'])
        # tusks / emblem
        d.rectangle([27, 12, 33, 16], fill=pal['W']); d.point((29, 14), fill=pal['K']); d.point((31, 14), fill=pal['K'])
        if plate:
            d.rectangle([14, 18, 54, 22], fill=pal['p'])
            d.line([(14, 18), (54, 18)], fill=pal['P'])
            for i in range(7):
                d.point((16 + i * 6, 20), fill=pal['K'])
        if cracked:
            for (x0, y0, x1, y1) in [(24, 10, 28, 16), (28, 16, 26, 20), (44, 22, 48, 27), (48, 27, 46, 29)]:
                d.line([(x0, y0), (x1, y1)], fill=pal['K'])
            d.point((36, 12), fill=pal['Y'])
        return outline(img)
    barrel = Image.new('RGBA', (30, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(barrel)
    d.rectangle([4, 2, 29, 5], fill=pal['M']); d.line([(4, 2), (29, 2)], fill=pal['m'])
    d.rectangle([0, 1, 5, 6], fill=pal['T'])
    barrel = outline(barrel)
    sheet = Image.new('RGBA', (W * 2, H * 4), (0, 0, 0, 0))
    for ph in range(2):
        sheet.paste(tank(ph, True, False), (ph * W, 0))
        sheet.paste(tank(ph, False, True), (ph * W, H))
        sheet.paste(flash_white(tank(ph, True, False)), (ph * W, H * 2))
        sheet.paste(flash_white(tank(ph, False, True)), (ph * W, H * 3))
    sheet.save(os.path.join(OUT, 'sprites', 'boss.png'))
    barrel.save(os.path.join(OUT, 'sprites', 'boss_barrel.png'))

def props():
    """Barrel, fuel tank, charge, sandbag nest, ladder, crates, card icons."""
    P = {k: rgb(v) for k, v in {
        'r': '#e04a3a', 'R': '#b8322a', 'Q': '#6a1c14', 'Y': '#ffd23a', 'y': '#c9a62a', 'K': '#18120e',
        'g': '#bfb08a', 'G': '#9a8456', 'H': '#6a5a38', 'm': '#8a8a90', 'M': '#5c5c64', 'W': '#ece6d8',
        'w': '#c88a4a', 'T': '#8c5a2c', 'o': '#5a3a20',
    }.items()}
    def mk(rows):
        w = max(len(r) for r in rows)
        img = Image.new('RGBA', (w + 2, len(rows) + 2), (0, 0, 0, 0))
        stamp(img, rows, 1, 1, P)
        return outline(img)
    barrel = mk([
        ".rrrrr.",
        "rRRRRRQ",
        "QQQQQQQ",
        "rRYYRRQ",
        "rRYKRRQ",
        "rRRRRRQ",
        "QQQQQQQ",
        "rRRRRRQ",
        ".QQQQQ.",
    ])
    fuel = mk([
        "..MMMMMMM..",
        ".mmmmmmmmM.",
        "YYYYYYYYYYy",
        "YWWWWWWWWWy",
        "YYYYYYYYYYy",
        "YKKYKKYKKYy",
        "YYYYYYYYYYy",
        "YYYYYYYYYYy",
        "yyyyyyyyyyy",
        "YYYYYYYYYYy",
        "YYYYYYYYYYy",
        "YKYKYKYKYKy",
        "YYYYYYYYYYy",
        "yyyyyyyyyyy",
        ".M.......M.",
    ])
    charge = mk([
        "...rK..",
        "...K...",
        "TTTTTTT",
        "TwwKwwT",
        "TTTTTTT",
    ])
    bag = mk([
        "..ggggg..ggggg..",
        ".gGGGGGggGGGGGH.",
        ".HHHHHHHHHHHHHH.",
        "gggggg.ggggg.ggg",
        "GGGGGGgGGGGGgGGH",
        "HHHHHHHHHHHHHHHH",
    ])
    crate = mk([
        "wwwwwwwwww",
        "wTTTTTTTTo",
        "wTwwTTwwTo",
        "wTTwwwwTTo",
        "wTTTwwTTTo",
        "wTTwwwwTTo",
        "wTwwTTwwTo",
        "wTTTTTTTTo",
        "oooooooooo",
    ])
    for n, im in (('barrel', barrel), ('fuel', fuel), ('charge', charge), ('sandbags', bag), ('crate', crate)):
        im.save(os.path.join(OUT, 'sprites', n + '.png'))
        flash_white(im).save(os.path.join(OUT, 'sprites', n + '_w.png'))

# ---------------------------------------------------------------- FX sheets
def explosion_sheet():
    """Metal Slug style fireball: 14 frames, 48x48 art px. White core -> yellow -> orange -> red -> smoke."""
    N, S = 14, 48
    rnd = random.Random(7)
    cols = [rgb(c) for c in ('#ffffff', '#fff6b0', '#ffd23a', '#ff9a2a', '#ff5a2a', '#c83224', '#6a2a22', '#3a2a2a', '#2a2222')]
    blobs = [(rnd.uniform(-1, 1) * 9, rnd.uniform(-1, 0.6) * 9, rnd.uniform(6, 13), rnd.uniform(0, 6.28)) for _ in range(9)]
    sheet = Image.new('RGBA', (S * N, S), (0, 0, 0, 0))
    for f in range(N):
        t = f / (N - 1)
        img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        px = img.load()
        grow = 0.35 + 0.65 * min(1, t * 2.2)
        rise = t * 10
        for y in range(S):
            for x in range(S):
                v = 0.0
                for bx, by, br, ph in blobs:
                    cx = S / 2 + bx * grow
                    cy = S / 2 + 4 + by * grow - rise * (0.6 + 0.4 * math.sin(ph))
                    r = br * grow * (1.15 - 0.25 * t)
                    d = math.hypot(x - cx, y - cy) / r
                    v = max(v, 1 - d)
                if v <= 0:
                    continue
                n = (math.sin(x * 1.7 + f) * math.cos(y * 1.3 - f * 0.7)) * 0.12
                v = v + n
                heat = v - t * 0.95
                if v < 0.08:
                    continue
                if heat > 0.55: c = cols[0]
                elif heat > 0.42: c = cols[1]
                elif heat > 0.28: c = cols[2]
                elif heat > 0.14: c = cols[3]
                elif heat > 0.02: c = cols[4]
                elif heat > -0.1: c = cols[5]
                elif heat > -0.25: c = cols[6]
                elif heat > -0.45: c = cols[7]
                else: c = cols[8]
                if t > 0.7 and ((x + y + f) % 2 == 0) and heat < -0.2:
                    continue  # dither out the dying smoke
                px[x, y] = c
        sheet.paste(img, (f * S, 0))
    sheet.save(os.path.join(OUT, 'sprites', 'explosion.png'))

def small_fx():
    # muzzle flash: 3 frames 16x12, a hot white core in a four-point star, then a cone, then sparks
    mf = Image.new('RGBA', (48, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(mf)
    Y, W, O, R = rgb('#ffd23a'), rgb('#ffffff'), rgb('#ff8a2a'), rgb('#e04a2a')
    d.polygon([(0, 6), (5, 0), (7, 4), (15, 6), (7, 8), (5, 11)], fill=R)
    d.polygon([(0, 6), (5, 2), (7, 5), (13, 6), (7, 7), (5, 10)], fill=O)
    d.polygon([(0, 6), (4, 3), (10, 6), (4, 9)], fill=Y)
    d.ellipse([1, 4, 6, 8], fill=W)
    d.polygon([(16, 6), (21, 3), (31, 6), (21, 9)], fill=O)
    d.polygon([(16, 6), (21, 4), (27, 6), (21, 8)], fill=Y)
    d.line([(16, 6), (22, 6)], fill=W)
    for (x, y) in ((34, 5), (37, 3), (38, 8), (41, 6), (44, 4)):
        d.point((x, y), fill=Y)
        d.point((x + 1, y), fill=O)
    mf.save(os.path.join(OUT, 'sprites', 'muzzle.png'))
    # smoke puff: 6 frames 16x16, a lumpy cloud lit from above that swells and breaks apart
    sp = Image.new('RGBA', (96, 16), (0, 0, 0, 0))
    lumps = [(0, 1, 1.0), (-3, 2, 0.75), (3, 2, 0.8), (-1, -2, 0.7), (2, -2, 0.6)]
    tones = [(246, 242, 232), (206, 202, 196), (150, 146, 144), (98, 94, 96)]
    rng = np.random.default_rng(7)
    noise = rng.random((16, 16))
    for i in range(6):
        cell = Image.new('L', (16, 16), 0)
        d = ImageDraw.Draw(cell)
        base = 2.4 + i * 0.55
        spread = 1 + i * 0.12
        for ox, oy, k in lumps:
            r = base * k
            cx, cy = 8 + ox * spread, 8 + oy * spread - i * 0.3
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        m = np.array(cell) > 0
        m &= noise > (0, 0, 0.08, 0.25, 0.45, 0.65)[i]  # breaks apart as it ages
        out = np.zeros((16, 16, 4), np.uint8)
        for y in range(16):
            for x in range(16):
                if not m[y, x]:
                    continue
                if y == 0 or not m[y - 1, x]:
                    t = 0
                elif y < 15 and not m[y + 1, x]:
                    t = 3 if i < 3 else 2
                elif y < 14 and not m[y + 2, x]:
                    t = 2
                else:
                    t = 1
                t = min(3, t + (1 if i >= 4 else 0))
                out[y, x] = (*tones[t], 255)
        sp.alpha_composite(Image.fromarray(out, 'RGBA'), (i * 16, 0))
    sp.save(os.path.join(OUT, 'sprites', 'puff.png'))
    # shell casing / spark / debris bits 3x3 etc. drawn in code; slash arc 3 frames 20x20
    sl = Image.new('RGBA', (60, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(sl)
    for i in range(3):
        d.arc([i * 20 + 1, 1, i * 20 + 18, 18], 300 - i * 40, 60 + i * 10, fill=W, width=2)
    sl.save(os.path.join(OUT, 'sprites', 'slash.png'))
    # parachute 24x16
    pc = Image.new('RGBA', (24, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(pc)
    d.pieslice([0, 0, 23, 16], 180, 360, fill=rgb('#e8d8a8'))
    for x in (4, 12, 19):
        d.line([(x, 1), (x, 8)], fill=rgb('#b8a070'))
    d.line([(1, 8), (10, 15)], fill=rgb('#dddddd')); d.line([(22, 8), (13, 15)], fill=rgb('#dddddd'))
    outline(pc).save(os.path.join(OUT, 'sprites', 'parachute.png'))

# ---------------------------------------------------------------- backgrounds (parallax, art px; drawn x2)
# Every layer is painted as a flat silhouette first, then lit by shade(): a warm rim on the
# sun side and along the tops, a dark core on the shadow side, and dithered haze toward the
# base so each layer sinks into the one behind it, like the Metal Slug backdrops.
THEMES = {
    'dusk': dict(sky=['#1b2440', '#3a2f5e', '#7a3a5e', '#d0704a', '#f0b060'], sun='#ffd890', haze='#e08a5a',
                 far2='#8a4a64', far='#5e3858', far_lit='#b8605e', mid='#3a2a44', mid_lit='#7e4250', near='#24182c', near_lit='#5e2a34',
                 win='#ffb060', fore='#120a12', fore_lit='#2e1620',
                 cloud=['#3a2a52', '#56386a', '#9a4a66', '#e08a5a', '#ffd890']),
    'jungle': dict(sky=['#0e2a30', '#1e4a4a', '#3a7a64', '#8ab07a', '#d8d8a0'], sun='#fff2c0', haze='#9ac08a',
                   far2='#4a7a64', far='#2e5a4a', far_lit='#5e8a5e', mid='#1e4234', mid_lit='#3e6a40', near='#12281e', near_lit='#2e4e2a',
                   win='#d8e0a0', fore='#06120a', fore_lit='#163018',
                   cloud=['#4a7a6a', '#6a9a80', '#9ac08a', '#d8e0b0', '#fff8d8']),
    'night': dict(sky=['#05060e', '#0e1430', '#1e2450', '#3a3a70', '#6a5a8a'], sun='#e8eef8', haze='#4a4a7a',
                  far2='#2e3258', far='#20244a', far_lit='#3a4478', mid='#181a34', mid_lit='#2e3460', near='#0c0e1e', near_lit='#1e2444',
                  win='#ffd23a', fore='#04040a', fore_lit='#121630',
                  cloud=['#0e1230', '#161c40', '#222a54', '#3a4678', '#7a88b8']),
}

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
BAYER_NP = (np.array(BAYER, dtype=np.float32) + 0.5) / 16.0

def gradient(w, h, stops):
    img = Image.new('RGBA', (w, h))
    px = img.load()
    cs = [rgb(c) for c in stops]
    for y in range(h):
        t = y / (h - 1) * (len(cs) - 1)
        i = min(int(t), len(cs) - 2)
        f = t - i
        # ordered dither between bands for that 16-bit look
        for x in range(w):
            th = (BAYER[y % 4][x % 4] + 0.5) / 16.0
            c = cs[i + 1] if f > th else cs[i]
            px[x, y] = c
    return img

def mix(a, b, f):
    a, b = rgb(a), rgb(b)
    return tuple(int(round(a[i] + (b[i] - a[i]) * f)) for i in range(3)) + (255,)

def hexc(c):
    return '#%02x%02x%02x' % c[:3]

def bayer_of(h, w):
    return np.tile(BAYER_NP, (h // 4 + 1, w // 4 + 1))[:h, :w]

def shade(img, body, lit, side=1, rim=2, dark=0.7):
    """Recolour a silhouette: lit tops and a `rim`-px lit edge on the sun side (side=+1 means the
    light comes from the right), a darker edge on the far side. Wraps horizontally (layers tile)."""
    a = np.array(img)
    m = a[..., 3] > 0
    out = np.zeros_like(a)
    b = np.array(rgb(body), dtype=np.uint8)
    out[m] = b
    above = np.vstack([np.zeros((1, m.shape[1]), bool), m[:-1]])
    lit_m = m & ~above
    for k in range(1, rim + 1):
        lit_m |= m & ~np.roll(m, -k * side, axis=1)
    shadow = m & ~np.roll(m, side, axis=1) & ~lit_m
    out[shadow] = (b * dark).astype(np.uint8)
    out[shadow, 3] = 255
    out[lit_m] = np.array(rgb(lit), dtype=np.uint8)
    return Image.fromarray(out, 'RGBA')

def haze(img, col, y0, strength=0.75, levels=3):
    """Dithered blend of every opaque pixel toward `col`, growing from row y0 to the bottom."""
    a = np.array(img).astype(np.float32)
    h, w = a.shape[:2]
    ys = np.clip((np.arange(h) - y0) / max(1, h - 1 - y0), 0, 1)[:, None] * levels
    lv = np.floor(ys + bayer_of(h, w))  # dithered step count
    f = np.clip(lv / levels, 0, 1) * strength
    c = np.array(rgb(col)[:3], dtype=np.float32)
    m = a[..., 3] > 0
    a[..., :3] = np.where(m[..., None], a[..., :3] + (c - a[..., :3]) * f[..., None], a[..., :3])
    return Image.fromarray(a.astype(np.uint8), 'RGBA')

def over(dst, src):
    dst.alpha_composite(src)
    return dst

def palm(d, x, base, h, col, lean=4, fronds=6, span=16):
    for i in range(h):
        sx = x + int(math.sin(i / 14.0) * lean)
        d.point((sx, base - i), fill=col)
        d.point((sx + 1, base - i), fill=col)
    tx, ty = x + int(math.sin(h / 14.0) * lean), base - h
    for k in range(fronds):
        a = -3.0 + k * (2.9 / max(1, fronds - 1)) * 1.05
        for s in range(span):
            px = tx + int(math.cos(a) * s)
            py = ty + int(math.sin(a) * s * 0.6 + (s * s) / 30)
            d.point((px, py), fill=col)
            d.point((px, py + 1), fill=col)
    d.ellipse([tx - 2, ty - 1, tx + 2, ty + 3], fill=col)

def sky_layer(name, th):
    W, H = 480, 270
    sky = gradient(W, H, th['sky'])
    d = ImageDraw.Draw(sky)
    rnd = random.Random(3)
    if name == 'night':
        for _ in range(160):
            x, y = rnd.randrange(W), rnd.randrange(170)
            sky.putpixel((x, y), rgb('#ffffff') if rnd.random() < 0.25 else rgb('#8a90c0'))
        # a faint milky band
        for _ in range(500):
            t = rnd.random()
            x = int(t * W)
            y = int(20 + t * 70 + rnd.gauss(0, 9))
            if 0 <= y < H:
                sky.putpixel((x, y), rgb('#2a3060'))
    cx, cy = 350, (120 if name != 'night' else 60)
    r = 26 if name != 'night' else 14
    # dithered halo rings around the sun / moon
    a = np.array(sky).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.sqrt((xx - cx) ** 2 + ((yy - cy) * 1.1) ** 2)
    glow = np.clip(1 - (dist - r) / (r * (3.2 if name != 'night' else 4.5)), 0, 1) ** 1.6
    lv = np.floor(glow * 4 + bayer_of(H, W)) / 4 * (0.55 if name != 'night' else 0.35)
    sc = np.array(rgb(th['sun'])[:3], dtype=np.float32)
    a[..., :3] = a[..., :3] + (sc - a[..., :3]) * lv[..., None]
    sky = Image.fromarray(a.astype(np.uint8), 'RGBA')
    d = ImageDraw.Draw(sky)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb(th['sun']))
    if name != 'night':
        # heat-shimmer bands cutting the sun, Metal Slug style
        for i in range(4):
            d.line([(cx - r - 2, cy + 4 + i * 6), (cx + r + 2, cy + 4 + i * 6)], fill=rgb(th['sky'][3]), width=1 + i // 2)
    else:
        for (ox, oy, rr) in ((-4, -3, 3), (5, 2, 2), (-2, 6, 2), (3, -6, 1)):
            d.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], fill=rgb('#c8d0e0'))
    # long flat cloud streaks low on the horizon
    for i in range(7):
        y = 150 + i * 12 + rnd.randint(-3, 3)
        x0 = rnd.randint(-40, W)
        ln = rnd.randint(60, 180)
        col = mix(th['sky'][min(4, 2 + i // 3)], th['sun'], 0.25 if name != 'night' else 0.1)
        d.line([(x0, y), (x0 + ln, y)], fill=col, width=1)
        d.line([(x0 + 10, y + 1), (x0 + ln - 14, y + 1)], fill=mix(hexc(col), th['sky'][1], 0.3), width=1)
    sky.save(os.path.join(OUT, 'bg', f'{name}_sky.png'))

def cloud_layer(name, th):
    """Tileable puffy clouds lit from the upper right: drawn drifting over the sky in game."""
    LW, H = 512, 120
    rnd = random.Random(21 if name != 'night' else 23)
    mask = Image.new('L', (LW * 2, H), 0)
    d = ImageDraw.Draw(mask)
    n = 7 if name != 'night' else 5
    for i in range(n):
        x = int((i + rnd.random() * 0.6) * LW / n)
        y = rnd.randint(18, 80)
        w = rnd.randint(50, 110)
        for k in range(rnd.randint(6, 11)):
            px = x + rnd.randint(0, w)
            pr = rnd.randint(7, 17) * (1.0 if abs(px - x - w / 2) < w / 3 else 0.7)
            py = y - pr * 0.5 + rnd.randint(-3, 3)
            for off in (0, LW):
                d.ellipse([px + off - pr, py - pr * 0.75, px + off + pr, py + pr * 0.75], fill=255)
        for off in (0, LW):
            d.rectangle([x + off - 6, y, x + off + w + 6, y + 4], fill=255)  # flat bellies
    m = np.array(mask)[:, :LW] | np.array(mask)[:, LW:]
    m = m > 0
    # distance-ish lighting: count empties up-right / down-left within a few px
    lit = np.zeros(m.shape, np.float32)
    for k in range(1, 6):
        up = np.vstack([np.zeros((k, LW), bool), m[:-k]])
        lit += (~up) * (1.0 / k)
        lit += (~np.roll(m, -k, axis=1)) * (0.5 / k)
        dn = np.vstack([m[k:], np.zeros((k, LW), bool)])
        lit -= (~dn) * (0.9 / k)
    tones = [rgb(c) for c in th['cloud']]
    v = np.clip((lit + 1.6) / 3.6, 0, 0.999) * len(tones)
    idx = np.clip(np.floor(v + bayer_of(H, LW) - 0.5), 0, len(tones) - 1).astype(int)
    out = np.zeros((H, LW, 4), np.uint8)
    pal = np.array(tones, np.uint8)
    out[m] = pal[idx[m]]
    img = Image.fromarray(out, 'RGBA')
    img.save(os.path.join(OUT, 'bg', f'{name}_clouds.png'))

def far_layer(name, th):
    LW, H = 512, 170
    img = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    def ridge(hts, body, lit, top_lit):
        lay = np.zeros((H, LW, 4), np.uint8)
        bb, ll, tl = (np.array(rgb(c), np.uint8) for c in (body, lit, top_lit))
        bay = bayer_of(H, LW)
        for x in range(LW):
            h = hts[x]
            slope = hts[(x + 1) % LW] - hts[x - 1]
            for y in range(H - h, H):
                depth = y - (H - h)
                c = bb
                if slope < -0.4:  # faces the sun on the right
                    if depth < 26 * min(1.0, -slope / 1.5) + 4 and bay[y, x] < 1 - depth / 30:
                        c = ll
                elif slope > 1.2 and depth < 3:
                    c = (bb * 0.85).astype(np.uint8)
                if depth == 0:
                    c = tl
                lay[y, x] = c
                lay[y, x, 3] = 255
        return Image.fromarray(lay, 'RGBA')
    hb = [int(84 + 20 * math.sin(x / LW * math.pi * 2 * 3 + 2) + 10 * math.sin(x / LW * math.pi * 2 * 7) + 4 * math.sin(x / LW * math.pi * 2 * 17)) for x in range(LW)]
    hf = [int(56 + 22 * math.sin(x / LW * math.pi * 2 * 2) + 13 * math.sin(x / LW * math.pi * 2 * 5 + 1) + 6 * math.sin(x / LW * math.pi * 2 * 11)) for x in range(LW)]
    back = ridge(hb, hexc(mix(th['far2'], th['haze'], 0.35)), hexc(mix(th['far_lit'], th['haze'], 0.45)), hexc(mix(th['far_lit'], th['sun'], 0.3)))
    back = haze(back, th['haze'], 40, 0.6)
    over(img, back)
    front = ridge(hf, th['far'], th['far_lit'], hexc(mix(th['far_lit'], th['sun'], 0.4)))
    d = ImageDraw.Draw(front)
    rnd = random.Random(5)
    fc = rgb(th['far'])
    for x in range(8, LW, 1):
        top = H - hf[x]
        if name == 'jungle' and x % 3 == 0:
            r = 2 + (x * 7) % 3
            d.ellipse([x - r, top - r, x + r, top + r], fill=fc)
        elif name != 'jungle' and rnd.random() < 0.012:
            # radio masts and pylons on the ridge
            d.line([(x, top), (x, top - 14)], fill=fc)
            d.line([(x - 3, top - 9), (x + 3, top - 9)], fill=fc)
            if name == 'night':
                d.point((x, top - 15), fill=rgb('#ff4d3d'))
    front = shade(front, th['far'], hexc(mix(th['far_lit'], th['sun'], 0.4)), rim=1) if name == 'jungle' else front
    front = haze(front, th['haze'], 90, 0.5)
    over(img, front)
    img.save(os.path.join(OUT, 'bg', f'{name}_far.png'))

def building(d, x, base, w, h, col, rnd, broken=True):
    top = base - h
    pts = [(x, base), (x, top + rnd.randint(0, 6))]
    if broken:
        k = x
        while k < x + w:
            k2 = min(x + w, k + rnd.randint(3, 8))
            pts.append((k, top + rnd.randint(0, 9)))
            pts.append((k2, top + rnd.randint(0, 9)))
            k = k2
    else:
        pts += [(x + w, top)]
    pts += [(x + w, top + rnd.randint(0, 6)), (x + w, base)]
    d.polygon(pts, fill=col)
    return top

def mid_layer(name, th):
    LW, H = 512, 150
    rnd = random.Random(11)
    img = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    # back row: smaller, hazier shapes
    back = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(back)
    bc = rgb(th['mid'])
    x = -10
    while x < LW:
        if name == 'jungle':
            r = rnd.randint(10, 22)
            cy = H - 40 - rnd.randint(0, 30)
            for k in range(3):
                d.ellipse([x + k * r * 0.6 - r, cy - r + k * 3, x + k * r * 0.6 + r, cy + r + k * 3], fill=bc)
            d.rectangle([x - r, cy, x + r * 2, H], fill=bc)
            x += r + rnd.randint(4, 16)
        else:
            w = rnd.randint(14, 30)
            building(d, x, H, w, rnd.randint(40, 90), bc, rnd, broken=name == 'dusk')
            x += w + rnd.randint(1, 8)
    back = shade(back, th['mid'], th['mid_lit'], rim=1)
    back = haze(back, th['haze'], 0, 0.42, levels=2)
    over(img, back)
    # front row
    fr = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(fr)
    mc = rgb(th['mid'])
    details = []  # (kind, x, y, w, h) painted after shading
    x = 0
    while x < LW - 20:
        if name == 'jungle':
            kind = rnd.choice(['tree', 'palm', 'tree', 'temple'] if x > 60 else ['tree', 'palm'])
            if kind == 'tree':
                r = rnd.randint(14, 24)
                tx = x + r
                ty = H - 50 - rnd.randint(0, 30)
                d.rectangle([tx - 2, ty, tx + 2, H], fill=mc)
                for k in range(5):
                    ox = rnd.randint(-r, r)
                    oy = rnd.randint(-r // 2, r // 3)
                    rr = rnd.randint(r // 2, r)
                    d.ellipse([tx + ox - rr, ty + oy - rr * 0.8, tx + ox + rr, ty + oy + rr * 0.8], fill=mc)
                details.append(('leaves', tx - r, ty - r, r * 2, int(r * 1.4)))
                x += r * 2 + rnd.randint(-4, 10)
            elif kind == 'palm':
                palm(d, x + 10, H, rnd.randint(70, 105), mc, lean=5, fronds=7, span=20)
                x += 26 + rnd.randint(0, 12)
            else:
                w = rnd.randint(46, 64)
                for k in range(5):
                    st = k * 5
                    d.rectangle([x + st, H - 14 - k * 12, x + w - st, H], fill=mc)
                d.rectangle([x + w // 2 - 5, H - 82, x + w // 2 + 5, H - 60], fill=mc)
                d.polygon([(x + w // 2 - 7, H - 82), (x + w // 2, H - 94), (x + w // 2 + 7, H - 82)], fill=mc)
                details.append(('door', x + w // 2 - 3, H - 22, 6, 10))
                x += w + rnd.randint(4, 12)
        elif name == 'night':
            kind = rnd.choice(['warehouse', 'crane', 'tank', 'block', 'warehouse'])
            if kind == 'warehouse':
                w = rnd.randint(50, 80)
                h = rnd.randint(30, 46)
                d.rectangle([x, H - h, x + w, H], fill=mc)
                for k in range(0, w, 12):
                    d.polygon([(x + k, H - h), (x + k + 12, H - h - 8), (x + k + 12, H - h)], fill=mc)
                details.append(('windows', x + 3, H - h + 6, w - 6, h - 12))
                x += w + rnd.randint(2, 10)
            elif kind == 'crane':
                cx0 = x + 10
                for y in range(H - 110, H, 6):
                    d.line([(cx0 - 4, y), (cx0 + 4, y + 6)], fill=mc)
                    d.line([(cx0 + 4, y), (cx0 - 4, y + 6)], fill=mc)
                d.line([(cx0 - 4, H - 110), (cx0 - 4, H)], fill=mc, width=2)
                d.line([(cx0 + 4, H - 110), (cx0 + 4, H)], fill=mc, width=2)
                d.rectangle([cx0 - 6, H - 118, cx0 + 10, H - 108], fill=mc)
                d.line([(cx0 - 20, H - 116), (cx0 + 60, H - 116)], fill=mc, width=3)
                d.line([(cx0, H - 130), (cx0 + 60, H - 116)], fill=mc)
                d.line([(cx0, H - 130), (cx0 - 20, H - 116)], fill=mc)
                d.line([(cx0 + 48, H - 116), (cx0 + 48, H - 80)], fill=mc)
                d.rectangle([cx0 + 44, H - 80, cx0 + 52, H - 74], fill=mc)
                details.append(('beacon', cx0, H - 131, 1, 1))
                x += 70
            elif kind == 'tank':
                w = rnd.randint(30, 44)
                h = rnd.randint(22, 34)
                d.rectangle([x, H - h, x + w, H], fill=mc)
                d.ellipse([x, H - h - 6, x + w, H - h + 6], fill=mc)
                x += w + rnd.randint(4, 12)
            else:
                w = rnd.randint(18, 34)
                h = rnd.randint(40, 96)
                building(d, x, H, w, h, mc, rnd, broken=False)
                details.append(('windows', x + 2, H - h + 6, w - 4, h - 10))
                x += w + rnd.randint(2, 8)
        else:
            kind = rnd.choice(['block', 'block', 'tower', 'block'])
            w = rnd.randint(18, 44)
            h = rnd.randint(36, 104)
            top = building(d, x, H, w, h, mc, rnd)
            if kind == 'tower' and w > 24:
                d.rectangle([x + w // 2 - 6, top - 16, x + w // 2 + 6, top - 6], fill=mc)
                d.line([(x + w // 2 - 5, top - 6), (x + w // 2 - 5, top + 2)], fill=mc)
                d.line([(x + w // 2 + 5, top - 6), (x + w // 2 + 5, top + 2)], fill=mc)
            details.append(('windows', x + 3, top + 10, w - 6, h - 14))
            if rnd.random() < 0.5:
                details.append(('hole', x + rnd.randint(2, max(3, w - 14)), top + rnd.randint(8, max(9, h // 2)), rnd.randint(6, 12), rnd.randint(5, 10)))
            x += w + rnd.randint(2, 12)
    fr = shade(fr, th['mid'], th['mid_lit'], rim=2)
    d = ImageDraw.Draw(fr)
    hole_col = (0, 0, 0, 0)
    dark = rgb(hexc(mix(th['mid'], '#000000', 0.35)))
    for kind, x0, y0, w, h in details:
        if kind == 'windows':
            for wy in range(y0, y0 + h - 4, 7):
                for wx in range(x0, x0 + w - 2, 5):
                    r = rnd.random()
                    if r < (0.28 if name == 'night' else 0.1):
                        d.rectangle([wx, wy, wx + 1, wy + 2], fill=rgb(th['win']))
                    elif r < 0.75:
                        d.rectangle([wx, wy, wx + 1, wy + 2], fill=dark)
        elif kind == 'hole':
            d.ellipse([x0, y0, x0 + w, y0 + h], fill=hole_col)
            for k in range(3):
                rx = x0 + 2 + k * (w // 3)
                d.line([(rx, y0 + h // 2), (rx + 1, y0 - 2)], fill=dark)
        elif kind == 'leaves':
            # little lit leaf clumps on the sun side of each crown
            lc = rgb(th['mid_lit'])
            dk = rgb(hexc(mix(th['mid'], '#000000', 0.25)))
            px = fr.load()
            for k in range(w * h // 18):
                lx = x0 + rnd.randint(0, w)
                ly = y0 + rnd.randint(0, h)
                if 0 <= lx < LW - 3 and 0 <= ly < H - 1 and px[lx, ly][3] and px[lx + 2, ly][3]:
                    c = lc if lx - x0 > w * 0.35 and rnd.random() < 0.7 else dk
                    d.line([(lx, ly + 1), (lx + 1, ly), (lx + 2, ly + 1)], fill=c)
        elif kind == 'door':
            d.rectangle([x0, y0, x0 + w, y0 + h], fill=dark)
        elif kind == 'beacon':
            d.point((x0, y0), fill=rgb('#ff4d3d'))
    fr = haze(fr, th['haze'], 80, 0.3)
    over(img, fr)
    img.save(os.path.join(OUT, 'bg', f'{name}_mid.png'))

def near_layer(name, th):
    LW, H = 512, 120
    rnd = random.Random(17)
    img = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    nc = rgb(th['near'])
    G = 106
    d.rectangle([0, G, LW, H], fill=nc)
    for x in range(0, LW, 2):
        d.line([(x, G), (x, G - int(4 + 3 * math.sin(x / 9.0) + 2 * math.sin(x / 3.1)))], fill=nc)
    poles = []
    kinds = {'dusk': ['palm', 'wreck', 'pole', 'wall', 'palm', 'pole'],
             'jungle': ['palm', 'bush', 'hut', 'palm', 'bush', 'pole'],
             'night': ['lamp', 'containers', 'fence', 'lamp', 'bollards', 'pole']}[name]
    x = 10
    while x < LW - 40:
        kind = rnd.choice(kinds)
        if kind == 'palm':
            palm(d, x, G, rnd.randint(52, 84), nc)
        elif kind == 'wreck':
            d.polygon([(x, G), (x + 6, G - 12), (x + 40, G - 14), (x + 48, G)], fill=nc)
            d.rectangle([x + 14, G - 24, x + 32, G - 14], fill=nc)
            d.line([(x + 30, G - 20), (x + 54, G - 30)], fill=nc, width=2)
            for k in range(6):
                d.ellipse([x + 4 + k * 7, G - 6, x + 10 + k * 7, G], fill=nc)
        elif kind == 'wall':
            w = rnd.randint(30, 50)
            pts = [(x, G), (x, G - rnd.randint(22, 34))]
            for k in range(1, 6):
                pts.append((x + w * k // 6, G - rnd.randint(8, 34)))
            pts += [(x + w, G - rnd.randint(10, 20)), (x + w, G)]
            d.polygon(pts, fill=nc)
        elif kind == 'pole':
            d.line([(x, G), (x, G - 62)], fill=nc, width=2)
            d.line([(x - 8, G - 56), (x + 9, G - 56)], fill=nc)
            d.line([(x - 6, G - 50), (x + 7, G - 50)], fill=nc)
            poles.append(x)
        elif kind == 'bush':
            for k in range(7):
                a = -2.9 + k * 0.45
                for s in range(22):
                    d.point((x + int(math.cos(a) * s), G - 6 + int(math.sin(a) * s * 0.9 + s * s / 40)), fill=nc)
                    d.point((x + int(math.cos(a) * s), G - 5 + int(math.sin(a) * s * 0.9 + s * s / 40)), fill=nc)
                    d.point((x + int(math.cos(a) * s) + 1, G - 5 + int(math.sin(a) * s * 0.9 + s * s / 40)), fill=nc)
        elif kind == 'hut':
            d.rectangle([x, G - 30, x + 30, G - 14], fill=nc)
            d.polygon([(x - 6, G - 30), (x + 15, G - 44), (x + 36, G - 30)], fill=nc)
            for px in (x + 2, x + 14, x + 27):
                d.line([(px, G - 14), (px, G)], fill=nc, width=2)
        elif kind == 'lamp':
            d.line([(x, G), (x, G - 58)], fill=nc, width=2)
            d.line([(x, G - 58), (x + 10, G - 60)], fill=nc, width=2)
            d.rectangle([x + 8, G - 60, x + 13, G - 57], fill=nc)
            d.point((x + 10, G - 56), fill=rgb(th['win']))
            d.point((x + 11, G - 56), fill=rgb(th['win']))
        elif kind == 'containers':
            for k in range(rnd.randint(1, 3)):
                w = rnd.randint(28, 40)
                ox = rnd.randint(-4, 6)
                d.rectangle([x + ox, G - 13 * (k + 1), x + ox + w, G - 13 * k - 1], fill=nc)
        elif kind == 'fence':
            for k in range(0, 44, 11):
                d.line([(x + k, G), (x + k, G - 26)], fill=nc)
            d.line([(x, G - 26), (x + 44, G - 26)], fill=nc)
            for k in range(0, 44, 3):
                d.line([(x + k, G - 26), (x + k + 6, G)], fill=nc)
        elif kind == 'bollards':
            for k in range(3):
                d.rectangle([x + k * 10, G - 8, x + k * 10 + 4, G], fill=nc)
                d.rectangle([x + k * 10 - 1, G - 9, x + k * 10 + 5, G - 7], fill=nc)
        x += rnd.randint(50, 100)
    # sagging wires between neighbouring poles (and across the wrap seam)
    for i in range(len(poles)):
        a = poles[i]
        b = poles[(i + 1) % len(poles)] + (LW if i == len(poles) - 1 else 0)
        for y0 in (56, 50):
            for k in range(b - a):
                f = k / max(1, b - a)
                sag = math.sin(f * math.pi) * 9
                d.point(((a + k) % LW, G - y0 + int(sag)), fill=nc)
    img = shade(img, th['near'], th['near_lit'], rim=1)
    img = haze(img, th['haze'], 80, 0.12, levels=2)
    img.save(os.path.join(OUT, 'bg', f'{name}_near.png'))

def fore_layer(name, th):
    """Very dark, close silhouettes that slide past the bottom of the screen faster than the world."""
    LW, H = 512, 48
    rnd = random.Random(29)
    img = Image.new('RGBA', (LW, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fc = rgb(th['fore'])
    d.rectangle([0, H - 8, LW, H], fill=fc)
    x = 0
    while x < LW:
        kind = rnd.choice(['grass', 'grass', 'rubble', 'post'] if name != 'jungle' else ['fern', 'grass', 'fern', 'grass'])
        if kind == 'grass':
            for k in range(rnd.randint(5, 12)):
                bx = x + rnd.randint(0, 22)
                h = rnd.randint(8, 26)
                lean = rnd.choice([-1, 1]) * rnd.random() * 0.5
                for s in range(h):
                    d.point((int(bx + lean * s * s / h), H - 8 - s), fill=fc)
                    d.point((int(bx + 1 + lean * s * s / h), H - 8 - s), fill=fc)
            x += rnd.randint(18, 40)
        elif kind == 'fern':
            for k in range(6):
                a = -2.8 + k * 0.5
                for s in range(26):
                    d.point((x + int(math.cos(a) * s), H - 8 + int(math.sin(a) * s * 1.1 + s * s / 30)), fill=fc)
                    d.point((x + int(math.cos(a) * s), H - 7 + int(math.sin(a) * s * 1.1 + s * s / 30)), fill=fc)
            x += rnd.randint(30, 50)
        elif kind == 'rubble':
            for k in range(rnd.randint(3, 6)):
                bx = x + rnd.randint(0, 30)
                r = rnd.randint(3, 8)
                d.polygon([(bx - r, H - 6), (bx - r + 2, H - 6 - r), (bx + r - 1, H - 7 - r // 2), (bx + r, H - 6)], fill=fc)
            x += rnd.randint(30, 50)
        else:
            d.rectangle([x, H - 34, x + 3, H], fill=fc)
            for k in range(0, 60, 2):  # barbed wire coil
                y = H - 26 + int(math.sin(k / 3.0) * 4)
                d.point((x + k, y), fill=fc)
                d.point((x + k + 1, y + (1 if k % 6 == 0 else 0)), fill=fc)
            x += rnd.randint(40, 70)
    img = shade(img, th['fore'], th['fore_lit'], rim=1)
    img.save(os.path.join(OUT, 'bg', f'{name}_fore.png'))

def backgrounds():
    for name, th in THEMES.items():
        sky_layer(name, th)
        cloud_layer(name, th)
        far_layer(name, th)
        mid_layer(name, th)
        near_layer(name, th)
        fore_layer(name, th)

# ---------------------------------------------------------------- title key art
def title_stage():
    """The title screen's stage: a rubble mound the squad stands on, framed by a wrecked tank
    and a broken tower, all black against a sunset that rims every edge facing the heroes."""
    W, H = 480, 270
    body, lit = '#150b13', '#f08a4a'
    def piece(draw_fn, side):
        img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(img))
        img = shade(img, body, lit, side=side, rim=1, dark=0.8)
        return haze(img, '#060306', 150, 0.75, levels=4)
    rnd = random.Random(41)
    def mound(d):
        tops = [(132, 214), (142, 204), (180, 204), (182, 194), (220, 194), (222, 186), (260, 186), (262, 194), (304, 194), (306, 204)]
        pts = [(96, 270), (104, 250), (112, 240), (122, 226)] + tops + [(318, 208), (330, 216), (338, 230), (352, 240), (366, 256), (378, 270)]
        d.polygon(pts, fill=rgb(body))
        # slabs and rubble jutting out of the slopes
        d.polygon([(110, 236), (98, 226), (126, 216), (132, 226)], fill=rgb(body))
        d.polygon([(318, 212), (346, 200), (352, 206), (330, 220)], fill=rgb(body))
        for k in range(14):
            x = rnd.choice([rnd.randint(100, 140), rnd.randint(310, 370)])
            y = 270 - int((abs(x - 240) - 60) * 0.6) - rnd.randint(-4, 6)
            r = rnd.randint(3, 7)
            d.polygon([(x - r, y), (x - r + 2, y - r), (x + r - 1, y - r + 2), (x + r, y + 1)], fill=rgb(body))
        for (x0, y0, x1, y1) in ((126, 222, 118, 208), (128, 222, 124, 206), (334, 214, 344, 196), (336, 216, 350, 204)):
            d.line([(x0, y0), (x1, y1)], fill=rgb(body))  # rebar
    def wreck(d):
        d.polygon([(0, 270), (0, 226), (16, 216), (88, 214), (108, 230), (112, 270)], fill=rgb(body))
        d.rectangle([22, 200, 66, 216], fill=rgb(body))
        d.polygon([(26, 200), (34, 192), (58, 192), (66, 200)], fill=rgb(body))
        d.line([(60, 202), (122, 170)], fill=rgb(body), width=4)
        d.rectangle([118, 166, 126, 174], fill=rgb(body))
        for k in range(6):
            d.ellipse([6 + k * 15, 244, 20 + k * 15, 258], fill=rgb(body))
        # broken wall behind it at the far edge
        pts = [(0, 270), (0, 108)]
        for x in range(4, 34, 5):
            pts.append((x, 108 + rnd.randint(0, 26)))
        pts += [(34, 150), (30, 270)]
        d.polygon(pts, fill=rgb(body))
        for (x0, y0) in ((6, 150), (18, 150), (6, 176), (18, 176)):
            d.rectangle([x0, y0, x0 + 6, y0 + 10], fill=(0, 0, 0, 0))
    def tower(d):
        pts = [(480, 270), (480, 62), (468, 58), (458, 70), (452, 64), (444, 80), (440, 110), (402, 116), (398, 124), (438, 126),
               (436, 168), (388, 172), (384, 180), (434, 182), (432, 226), (420, 270)]
        d.polygon(pts, fill=rgb(body))
        for x in range(400, 440, 7):
            d.line([(x, 116), (x - 2, 108)], fill=rgb(body))
        for (x0, y0) in ((450, 90), (464, 90), (450, 134), (464, 134), (450, 190), (464, 190)):
            d.rectangle([x0, y0, x0 + 7, y0 + 14], fill=(0, 0, 0, 0))
        palm(d, 470, 64, 0, rgb(body))
        for k in range(6):  # palm fronds spilling over the tower top
            a = -3.0 + k * 0.5
            for st in range(22):
                d.point((462 + int(math.cos(a) * st), 60 + int(math.sin(a) * st * 0.6 + st * st / 26)), fill=rgb(body))
                d.point((462 + int(math.cos(a) * st), 61 + int(math.sin(a) * st * 0.6 + st * st / 26)), fill=rgb(body))
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for fn, side in ((wreck, 1), (tower, -1), (mound, 1)):
        over(img, piece(fn, side))
    img.save(os.path.join(OUT, 'bg', 'title_stage.png'))

# ---------------------------------------------------------------- ambient life: critters and set dressing
def critters():
    """10x8 art-px frames, facing right. Rows: crow, gull, parrot (stand, peck, flap up, flap down),
    frog (sit, croak, hop, hop), rat (stand, sniff, run, run), butterfly (4 wing beats)."""
    bird = [
        ["..........", "......kk..", ".....kKEy.", "...kkKKK..", ".kkKKKKK..", "kKKKKKK...", ".....K....", "....KK...."],
        ["..........", "..........", "...kkk....", ".kkKKKK...", "kKKKKKKKk.", ".....KKKEy", ".....K....", "....KK...."],
        ["..k.......", "..kk...k..", "...kk.kk..", "....kKKEy.", "...kKKKK..", "..kKKKK...", "..........", ".........."],
        ["..........", "..........", ".....kkEy.", ".kkkKKKK..", "kKKKKKKK..", "...kkk....", "..kk......", ".........."],
    ]
    frog = [
        ["..........", "..........", "...E..E...", "..gggggg..", ".gGggggggg", "gGGgggggg.", ".gg.GG.gg.", ".........."],
        ["..........", "..........", "...E..E...", "..gggggg..", ".gGgggggyg", "gGGggggyy.", ".gg.GG.gg.", ".........."],
        ["..........", "....E..E..", "...gggggg.", "..gGgggggg", ".gGGggggg.", "gg..GG....", "g.........", ".........."],
        ["..........", "..........", "....E..E..", "...gggggg.", ".gGGgggggg", "gG..ggggg.", "......gg..", ".........."],
    ]
    rat = [
        ["..........", "..........", "......r...", "...rrrrrr.", "..rRRRRrrE", ".rRRRRRrrP", "t..r..r...", ".tt......."],
        ["..........", "..........", ".......r..", "...rrrrrrr", "..rRRRRrrE", ".rRRRRRr.P", "t..r..r...", ".tt......."],
        ["..........", "..........", "......r...", "...rrrrrr.", "..rRRRRrrE", "trRRRRRrrP", ".tr....r..", "..........."],
        ["..........", "..........", "......r...", "...rrrrrr.", "..rRRRRrrE", ".rRRRRRrrP", "t...rr....", ".t........"],
    ]
    fly = [
        ["..........", "..WW..WW..", ".WYWW.WYW.", "..WW..WW..", "....KK....", "...W..W...", "..........", ".........."],
        ["..........", "..........", "..WWWWWW..", "..WYWWYW..", "....KK....", "...WWWW...", "..........", ".........."],
        ["..........", "..........", "..........", "....WW....", "...WKKW...", "....WW....", "..........", ".........."],
        ["..........", "..........", "..WWWWWW..", "..WYWWYW..", "....KK....", "...WWWW...", "..........", ".........."],
    ]
    rows = [
        (bird, {'K': '#16141c', 'k': '#3a3a4e', 'E': '#e8e0d0', 'y': '#5a5a64'}, False),
        (bird, {'K': '#f2f0ea', 'k': '#b8bcc8', 'E': '#18120e', 'y': '#ffb23e'}, True),
        (bird, {'K': '#3aa04a', 'k': '#e04a3a', 'E': '#ffffff', 'y': '#ffd23a'}, True),
        (frog, {'g': '#6ab03a', 'G': '#3a7a2a', 'E': '#ffe36a', 'y': '#e8e0a0'}, True),
        (rat, {'r': '#7a6a5a', 'R': '#5a4a3e', 'E': '#ff4d3d', 'P': '#e8a0a0', 't': '#c08a80'}, True),
        (fly, {'W': '#ffd23a', 'Y': '#ff7a3d', 'K': '#2a1c10'}, False),
    ]
    sheet = Image.new('RGBA', (12 * 4, 10 * len(rows)), (0, 0, 0, 0))
    for r, (frames, pal, ol) in enumerate(rows):
        P = {k: rgb(v) for k, v in pal.items()}
        for i, rws in enumerate(frames):
            cell = Image.new('RGBA', (12, 10), (0, 0, 0, 0))
            stamp(cell, rws, 1, 1, P)
            if ol:
                cell = outline(cell)
            sheet.alpha_composite(cell, (i * 12, r * 10))
    sheet.save(os.path.join(OUT, 'sprites', 'critters.png'))

def decor():
    """Set dressing that stands on the ground but never blocks anything."""
    P = {k: rgb(v) for k, v in {
        'x': '#9a9660', 'X': '#74703e', 'Z': '#4e4a28', 'K': '#1e1810', 'Y': '#d8c890',
        'R': '#c0402e', 'r': '#8a2a1e', 'W': '#ece6d0', 'w': '#b8b09a', 'T': '#7a4e28', 't': '#5a3418',
        'M': '#4a4e58', 'm': '#7a808c', 'L': '#ffe8a0', 'G': '#5a6a3a', 'g': '#7a8a4a', 'B': '#3a3a42',
    }.items()}
    def mk(name, rows):
        w = max(len(r) for r in rows)
        img = Image.new('RGBA', (w + 2, len(rows) + 2), (0, 0, 0, 0))
        stamp(img, rows, 1, 1, P)
        outline(img).save(os.path.join(OUT, 'sprites', 'dc_' + name + '.png'))
    mk('tent', [
        "...........Y............",
        "..........xXZ...........",
        ".........xxXZZ..........",
        "........xxXXZZZ.........",
        ".......xxXXXZZZZ........",
        "......xxXXXKZZZZZ.......",
        ".....xxXXXKKKZZZZZ......",
        "....xxXXXKKKKKZZZZZ.....",
        "...xxXXXKKKKKKKZZZZZ....",
        "..xxXXXKKKKKKKKKZZZZZ...",
        ".xxXXXKKKKKKKKKKKZZZZZ..",
        "YxxXXKKKKKKKKKKKKKZZZZY.",
    ])
    mk('sign', [
        "WWWWWWWWWWWW",
        "WRRRRRRRRRRw",
        "WRRRWWWWRRRw",
        "WRRWWWWWWRRw",
        "WRRWKWWKWRRw",
        "WRRRWWWWRRRw",
        "WRRRWKWKRRRw",
        "WRRRRRRRRRRw",
        "wwwwwwwwwwww",
        ".....Tt.....",
        ".....Tt.....",
        ".....Tt.....",
        ".....Tt.....",
        ".....Tt.....",
    ])
    mk('lamp', [
        ".mMMMMm.",
        "mLLLLLLM",
        ".MMMMMM.",
        "...mM...",
    ] + ["...mM..."] * 26 + [
        "..mMMM..",
        ".mMMMMM.",
    ])
    mk('logs', [
        "..t....t....",
        ".tTt..tTt...",
        "TTTTTTTTTTt.",
        "tTTtTTTtTTTt",
        ".BBBBBBBBBB.",
    ])
    mk('drum', [
        ".rrrrrrr.",
        "rRRRRRRRr",
        "rrrrrrrrr",
        "rRRRRRRRr",
        "rRRrRRRRr",
        "rrrrrrrrr",
        "rRRRRRRRr",
        "rRRRRrRRr",
        ".rrrrrrr.",
    ])
    mk('flag', [
        "RRRRRRRRRRR",
        "RRRRWWWRRRr",
        "RRRWKWKWRRr",
        "RRRRWWWRRRr",
        "RRRRWKWRRRr",
        "rrrrrrrrrrr",
    ])
    mk('reeds', [
        "..Y.....Y...",
        "..G..Y..G...",
        "..G..G..G.Y.",
        ".gG..G.gG.G.",
        ".gG.gG.gGgG.",
        "gGGgGGgGGgGg",
    ])

# ---------------------------------------------------------------- UI textures (HUD frames, card frames, icons)
def ui():
    os.makedirs(os.path.join(OUT, 'ui'), exist_ok=True)
    U = {k: rgb(v) for k, v in {
        'K': '#0c0a08', 'd': '#2a2e34', 'D': '#1a1d22', 'm': '#4a505a', 'M': '#3a3f48', 'l': '#6c7480', 'L': '#9aa2ae',
        'r': '#c9a227', 'R': '#8a6a10', 'y': '#ffd23a', 'o': '#ff8a2a', 'g': '#62d26f', 'G': '#2a6a34', 'x': '#c8b48c', 'X': '#8c784c',
        'c': '#53d4e2', 'b': '#2a4a8a', 'W': '#ece6d8', 'e': '#ff4d3d', 'E': '#7a1c14',
    }.items()}
    # riveted metal panel, 9-slice friendly, 24x24
    p = Image.new('RGBA', (24, 24), U['K'])
    d = ImageDraw.Draw(p)
    d.rectangle([1, 1, 22, 22], fill=U['M'])
    d.rectangle([2, 2, 21, 21], fill=U['d'])
    d.line([(1, 1), (22, 1)], fill=U['l']); d.line([(1, 1), (1, 22)], fill=U['l'])
    d.line([(1, 22), (22, 22)], fill=U['D']); d.line([(22, 1), (22, 22)], fill=U['D'])
    for (x, y) in ((4, 4), (19, 4), (4, 19), (19, 19)):
        d.point((x, y), fill=U['L']); d.point((x + 1, y + 1), fill=U['D'])
    p.save(os.path.join(OUT, 'ui', 'panel.png'))
    # hazard-striped header strip 32x8 (tileable)
    hz = Image.new('RGBA', (32, 8), U['K'])
    for x in range(32):
        for y in range(1, 7):
            hz.putpixel((x, y), U['y'] if ((x + y) // 4) % 2 == 0 else U['K'])
    hz.save(os.path.join(OUT, 'ui', 'hazard.png'))
    # card frame 60x84: canvas/manila field card with a colored type band
    c = Image.new('RGBA', (60, 84), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    d.rounded_rectangle([0, 0, 59, 83], 4, fill=U['K'])
    d.rounded_rectangle([1, 1, 58, 82], 3, fill=U['X'])
    d.rounded_rectangle([2, 2, 57, 81], 3, fill=U['x'])
    for y in range(4, 80, 3):
        for x in range(4, 56, 5):
            if (x * 7 + y * 3) % 11 == 0:
                c.putpixel((x, y), U['X'])
    d.rectangle([3, 3, 56, 11], fill=U['W'])  # type band (tinted in game)
    d.rectangle([5, 30, 54, 31], fill=U['X'])
    c.save(os.path.join(OUT, 'ui', 'card.png'))
    # dog tag 40x22 for the roster
    t = Image.new('RGBA', (40, 22), (0, 0, 0, 0))
    d = ImageDraw.Draw(t)
    d.rounded_rectangle([0, 0, 39, 21], 6, fill=U['K'])
    d.rounded_rectangle([1, 1, 38, 20], 5, fill=U['L'])
    d.rounded_rectangle([2, 2, 37, 19], 5, fill=U['l'])
    d.ellipse([3, 8, 7, 12], fill=U['K'])
    t.save(os.path.join(OUT, 'ui', 'tag.png'))
    # icons 8x8: energy bolt, heart, flame (adrenaline), coin, skull, shield, radio, wind flag pole, star
    icons = {
        'bolt':  ["...yy...", "..yy....", ".yyyyy..", "...yy...", "..yy....", ".yy.....", "y.......", "........"],
        'heart': [".ee.ee..", "eWeeeee.", "eeeeeee.", "eeeeeee.", ".eeeee..", "..eee...", "...e....", "........"],
        'flame': ["...o....", "..oo....", "..ooo...", ".ooyoo..", ".oyyyo..", "ooyWyoo.", ".oyyyo..", "..ooo..."],
        'coin':  ["..yyyy..", ".yrrrry.", "yrryyrry", "yryrryry", "yryrryry", "yrryyrry", ".yrrrry.", "..yyyy.."],
        'skull': ["..WWWW..", ".WWWWWW.", "WKKWWKKW", "WKKWWKKW", "WWWKKWWW", ".WWWWWW.", "..WKWK..", "........"],
        'shield': ["LLLLLLL.", "LcccccL.", "LcccccL.", "LcccccL.", ".LcccL..", "..LcL...", "...L....", "........"],
        'radio': ["......K.", ".....K..", "MMMMMMM.", "MeeMWWM.", "MeeMWWM.", "MMMMMMM.", "K.....K.", "........"],
        'star':  ["...y....", "...y....", "yyyyyyy.", ".yyyyy..", "..yyy...", ".yy.yy..", "y.....y.", "........"],
        'up':    ["...g....", "..ggg...", ".ggggg..", "ggggggg.", "..ggg...", "..ggg...", "..ggg...", "........"],
        'card':  [".KKKKK..", ".KxxxK..", ".KWWWK..", ".KxxxK..", ".KxxxK..", ".KxxxK..", ".KKKKK..", "........"],
        'boot':  ["..KKK...", "..KXK...", "..KXK...", "..KXKK..", ".KXXXXK.", ".KKKKKK.", "........", "........"],
        'cross': ["..ggg...", "..ggg...", "ggggggg.", "ggggggg.", "ggggggg.", "..ggg...", "..ggg...", "........"],
    }
    for n, rows in icons.items():
        im = Image.new('RGBA', (8, 8), (0, 0, 0, 0))
        stamp(im, rows, 0, 0, U)
        im.save(os.path.join(OUT, 'ui', 'ic_' + n + '.png'))
    # siren bulb 10x10 off/on for the alert meter
    for n, col, hi in (('bulb_off', U['E'], U['M']), ('bulb_g', U['G'], U['g']), ('bulb_y', U['R'], U['y']), ('bulb_r', U['E'], U['e'])):
        im = Image.new('RGBA', (10, 12), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([1, 9, 8, 11], fill=U['m']); d.line([(1, 11), (8, 11)], fill=U['K'])
        d.pieslice([0, 0, 9, 17], 180, 360, fill=U['K'])
        d.pieslice([1, 1, 8, 16], 180, 360, fill=col if n == 'bulb_off' else hi)
        if n != 'bulb_off':
            d.point((3, 3), fill=U['W']); d.point((3, 4), fill=U['W'])
        im.save(os.path.join(OUT, 'ui', n + '.png'))


# ---------------------------------------------------------------- Vharr aliens
# Violet skin, ooze-green glow and pale bone, so they never read as Jackals at a glance.
# Drawn as shapes on a 32x32 frame, then lit from the upper left (a pale rim on top-left edges,
# a dark band on bottom-right ones) and outlined like everything else.
VHARR = {'a': '#b06ae0', 'A': '#7d3cb0', 'd': '#4a1f6e', 'L': '#e2b8ff', 'o': '#9df25c', 'O': '#5fbf2a',
         'n': '#e8dcc2', 'N': '#b8aa8c', 'g': '#a8acb4', 'G': '#6c7078', 'K': '#1c1410'}
AW = AH = 32

def vc(k):
    return rgb(VHARR[k])

def lit(img, body_cols):
    """Rim-light the shapes: pixels of a body colour with open space up-left get the light tone,
    with open space down-right get the dark tone. body_cols maps base colour -> (light, dark)."""
    src = img.load()
    out = img.copy()
    o = out.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if c[3] == 0 or c not in body_cols:
                continue
            hi, lo = body_cols[c]
            def empty(X, Y):
                return not (0 <= X < w and 0 <= Y < h) or src[X, Y][3] == 0
            if empty(x - 1, y) or empty(x, y - 1):
                o[x, y] = hi
            elif empty(x + 1, y) or empty(x, y + 1) or empty(x + 1, y + 1):
                o[x, y] = lo
    return out

SKIN = {vc('a'): (vc('L'), vc('A')), vc('A'): (vc('a'), vc('d')), vc('N'): (vc('n'), vc('G'))}

def canvas():
    img = Image.new('RGBA', (AW, AH), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)

def finish(img):
    return lit(img, SKIN)

def skitter_frame(step=0, air=False, dy=0):
    img, d = canvas()
    y0 = 23 + dy
    # legs first, behind the body
    for i, lx in enumerate((10, 13, 17, 20)):
        if air:
            d.line([(lx, y0 + 5), (lx - 2, y0 + 7)], fill=vc('d'))
        else:
            off = (1 if (i + step) % 2 else -1)
            d.line([(lx, y0 + 4), (lx + off, 31)], fill=vc('d'))
    d.ellipse([8, y0, 22, y0 + 7], fill=vc('A'))
    d.ellipse([9, y0 - 1, 20, y0 + 4], fill=vc('a'))        # carapace
    for px in (12, 16):
        d.line([(px, y0), (px - 1, y0 + 4)], fill=vc('A'))   # plate seams
    d.ellipse([19, y0 + 1, 25, y0 + 6], fill=vc('A'))       # head
    d.point((23, y0 + 2), fill=vc('o')); d.point((23, y0 + 3), fill=vc('O'))
    d.line([(25, y0 + 4), (26, y0 + 6)], fill=vc('n'))       # mandibles
    for sx in (11, 15, 18):
        d.point((sx, y0), fill=vc('N'))                      # bony spines
    return finish(img)

def squid_frame(w=0, dy=0, gun=True):
    img, d = canvas()
    y0 = 6 + dy
    for i, tx in enumerate((9, 12, 15, 18, 21, 24)):
        sway = ((i + w) % 3) - 1
        d.line([(tx, y0 + 14), (tx + sway, y0 + 19), (tx - sway, 30)], fill=vc('A'))
    d.ellipse([6, y0, 27, y0 + 17], fill=vc('a'))            # dome
    d.ellipse([9, y0 + 2, 18, y0 + 8], fill=vc('L'))         # sheen
    d.line([(8, y0 + 12), (26, y0 + 12)], fill=vc('A'))     # brow ridge
    d.ellipse([19, y0 + 7, 25, y0 + 12], fill=vc('n'))       # eye
    d.ellipse([21, y0 + 8, 24, y0 + 11], fill=vc('o'))
    d.point((23, y0 + 9), fill=vc('K'))
    if gun:
        d.rectangle([22, y0 + 15, 30, y0 + 17], fill=vc('g'))
        d.rectangle([29, y0 + 14, 31, y0 + 18], fill=vc('G'))
        d.point((31, y0 + 16), fill=vc('o'))
    return finish(img)

def blinker_frame(step=0, dy=0, claw=False):
    img, d = canvas()
    y = dy
    # legs
    lx = [(14, 17), (13, 19), (15, 16), (12, 20)][step % 4]
    d.line([(15, 19 + y), (lx[0], 25 + y), (lx[0] - 1, 31)], fill=vc('A'), width=2)
    d.line([(17, 19 + y), (lx[1], 25 + y), (lx[1] + 1, 31)], fill=vc('A'), width=2)
    # torso and bone collar
    d.polygon([(12, 9 + y), (21, 9 + y), (19, 20 + y), (14, 20 + y)], fill=vc('a'))
    d.line([(12, 10 + y), (21, 10 + y)], fill=vc('N'), width=2)
    for ry in (13, 15, 17):
        d.line([(14, ry + y), (19, ry + y)], fill=vc('A'))
    # arms: long, ending in glowing claws
    reach = 8 if claw else 0
    d.line([(20, 11 + y), (24 + reach // 2, 16 + y), (26 + reach, 20 + y - reach // 2)], fill=vc('A'), width=2)
    d.line([(13, 11 + y), (10, 17 + y), (11, 22 + y)], fill=vc('A'), width=2)
    for cx, cy in ((27 + reach, 21 + y - reach // 2), (11, 23 + y)):
        d.point((cx, cy), fill=vc('o')); d.point((cx + 1, cy), fill=vc('o')); d.point((cx, cy + 1), fill=vc('O'))
    # long skull, eyes forward
    d.ellipse([12, 0 + y, 22, 9 + y], fill=vc('a'))
    d.ellipse([14, 1 + y, 18, 4 + y], fill=vc('L'))
    d.line([(19, 4 + y), (22, 4 + y)], fill=vc('o'))
    d.point((22, 5 + y), fill=vc('O'))
    return finish(img)

def burrower_frame(open_=0, dy=0):
    """The Burrower reared up out of its hole: ringed segments, a bony maw."""
    img, d = canvas()
    segs = [(16, 27), (17, 22), (18, 17), (19, 12)]
    for i, (cx, cy) in enumerate(segs):
        r = 8 - i
        d.ellipse([cx - r, cy - r + dy, cx + r, cy + r + dy], fill=vc('A') if i % 2 else vc('a'))
        d.line([(cx - r + 1, cy + dy), (cx + r - 1, cy + dy)], fill=vc('d'))
    cx, cy = 20, 6 + dy
    d.ellipse([cx - 6, cy - 5, cx + 6, cy + 5], fill=vc('a'))
    # maw: bone teeth around a dark mouth, wider when open
    m = 2 + open_
    d.ellipse([cx - 1, cy - m, cx + 7, cy + m], fill=vc('K'))
    for t in range(-m, m + 1, 2):
        d.point((cx + 1, cy + t), fill=vc('n'))
        d.point((cx + 6, cy + t), fill=vc('n'))
    d.point((cx - 3, cy - 2), fill=vc('o'))
    return finish(img)

def grappler_frame(mouth=0, dy=0):
    """A squat, heavy frog-thing anchored on four splayed limbs."""
    img, d = canvas()
    d.line([(6, 26), (2, 31)], fill=vc('A'), width=2)
    d.line([(26, 26), (30, 31)], fill=vc('A'), width=2)
    d.line([(10, 28), (8, 31)], fill=vc('d'), width=2)
    d.line([(22, 28), (24, 31)], fill=vc('d'), width=2)
    d.ellipse([3, 9 + dy, 29, 30], fill=vc('A'))
    d.ellipse([5, 8 + dy, 27, 24 + dy], fill=vc('a'))
    for wx in (9, 15, 21):
        d.ellipse([wx, 12 + dy, wx + 3, 15 + dy], fill=vc('N'))   # warts
    d.line([(13, 20 + dy), (29, 20 + dy - mouth)], fill=vc('K'))
    if mouth:
        d.polygon([(14, 20 + dy), (29, 20 + dy - mouth), (29, 21 + dy + mouth)], fill=vc('K'))
        d.line([(16, 21 + dy), (28, 21 + dy)], fill=rgb('#e05a8a'))
    d.ellipse([20, 9 + dy, 25, 14 + dy], fill=vc('n'))
    d.ellipse([22, 10 + dy, 24, 13 + dy], fill=vc('o'))
    return finish(img)

def bloater_frame(step=0, dy=0):
    """A walking sac of ooze on stubby legs; the game scales it up as it swells."""
    img, d = canvas()
    lo = 1 if step % 2 else 0
    d.line([(11, 26), (10 - lo, 31)], fill=vc('d'), width=2)
    d.line([(20, 26), (21 + lo, 31)], fill=vc('d'), width=2)
    d.ellipse([4, 6 + dy, 27, 29 + dy], fill=vc('a'))
    d.ellipse([8, 8 + dy, 16, 14 + dy], fill=vc('L'))
    for px, py, r in ((19, 12, 2), (11, 20, 3), (21, 22, 2), (15, 25, 1)):
        d.ellipse([px - r, py - r + dy, px + r, py + r + dy], fill=vc('o'))
        d.point((px - r + 1, py - r + 1 + dy), fill=rgb('#d8ffb0'))
    d.ellipse([20, 15 + dy, 25, 19 + dy], fill=vc('n'))
    d.point((23, 17 + dy), fill=vc('K'))
    return finish(img)

def weaver_frame(step=0, dy=0, cast=False):
    """Dome Weaver: thin and robed, a crest that holds the emitter crystal."""
    img, d = canvas()
    d.polygon([(11, 14 + dy), (21, 14 + dy), (24, 31), (8, 31)], fill=vc('A'))   # robe
    d.line([(12, 18 + dy), (10, 31)], fill=vc('d'))
    d.line([(20, 18 + dy), (22, 31)], fill=vc('d'))
    d.line([(16, 16 + dy), (16, 31)], fill=vc('a'))
    d.ellipse([11, 5 + dy, 21, 15 + dy], fill=vc('a'))                           # head
    d.polygon([(13, 6 + dy), (16, -1 + dy if dy > 0 else 0), (19, 6 + dy)], fill=vc('N'))   # crest
    glow = vc('o') if (step % 2 or cast) else vc('O')
    d.ellipse([14, 1 + dy, 18, 5 + dy], fill=glow)
    d.line([(18, 10 + dy), (21, 10 + dy)], fill=vc('o'))                         # eye slit
    arm_y = 9 if cast else 18
    d.line([(20, 16 + dy), (25, arm_y + dy)], fill=vc('a'), width=2)
    d.point((26, arm_y - 1 + dy), fill=vc('o'))
    return finish(img)

def prism_frame(t=0, dy=0):
    """Prism Drone: a floating crystal with a silvered mirror face turned forward."""
    img, d = canvas()
    y = 4 + dy
    d.polygon([(14, y), (22, y + 10), (14, y + 24), (6, y + 10)], fill=vc('a'))     # crystal body
    d.polygon([(14, y + 2), (18, y + 10), (14, y + 20)], fill=vc('L'))
    d.polygon([(22, y + 4), (27, y + 10), (22, y + 18)], fill=rgb('#c9e8f0'))        # mirror
    d.line([(23, y + 6), (23, y + 15)], fill=rgb('#ffffff'))
    d.line([(26, y + 9), (26, y + 11)], fill=rgb('#8ff0ff'))
    d.ellipse([11, y + 8, 16, y + 13], fill=vc('o'))                                 # core
    d.point((13, y + 10), fill=rgb('#d8ffb0'))
    for k, fx in enumerate((8, 14, 20)):
        fy = y + 25 + ((k + t) % 2)
        d.line([(fx, fy), (fx, fy + 2)], fill=vc('o') if (k + t) % 2 else vc('O'))   # thruster motes
    return finish(img)

def warden_frame(step=0, dy=0, cast=False):
    """Gravity Warden: squat and armoured, a dark well-orb held in a ring of hands."""
    img, d = canvas()
    lo = 1 if step % 2 else 0
    d.line([(11, 24), (10 - lo, 31)], fill=vc('d'), width=3)
    d.line([(20, 24), (21 + lo, 31)], fill=vc('d'), width=3)
    d.ellipse([6, 10 + dy, 25, 28 + dy], fill=vc('A'))                               # body
    d.ellipse([8, 11 + dy, 23, 22 + dy], fill=vc('a'))
    d.rectangle([9, 18 + dy, 22, 20 + dy], fill=vc('N'))                             # bone belt
    d.ellipse([10, 2 + dy, 21, 12 + dy], fill=vc('a'))                               # head
    d.line([(16, 7 + dy), (21, 7 + dy)], fill=vc('o'))
    ox, oy = (24, 4 + dy) if cast else (25, 15 + dy)
    d.line([(20, 14 + dy), (ox - 2, oy + 2)], fill=vc('a'), width=2)
    d.ellipse([ox - 4, oy - 4, ox + 4, oy + 4], fill=vc('K'))                        # the orb
    d.arc([ox - 5, oy - 5, ox + 5, oy + 5], 200 + step * 40, 340 + step * 40, fill=rgb('#c47bff'))
    d.point((ox, oy), fill=rgb('#e2b8ff'))
    return finish(img)

def stalker_frame(step=0, dy=0, slash=False):
    """Phase Stalker: lean and hunched, one long blade arm."""
    img, d = canvas()
    lx = [(13, 19), (12, 20), (14, 18), (11, 21)][step % 4]
    d.line([(15, 19 + dy), (lx[0], 25 + dy), (lx[0] - 2, 31)], fill=vc('A'), width=2)
    d.line([(17, 19 + dy), (lx[1], 25 + dy), (lx[1] + 2, 31)], fill=vc('A'), width=2)
    d.polygon([(11, 8 + dy), (20, 6 + dy), (19, 20 + dy), (13, 20 + dy)], fill=vc('a'))   # hunched torso
    for ry in (11, 14, 17):
        d.line([(13, ry + dy), (18, ry + dy)], fill=vc('A'))
    d.polygon([(16, 1 + dy), (24, 4 + dy), (17, 8 + dy)], fill=vc('a'))                  # wedge head
    d.point((21, 4 + dy), fill=rgb('#8ff0ff')); d.point((22, 4 + dy), fill=rgb('#8ff0ff'))
    if slash:
        d.line([(19, 9 + dy), (25, 5 + dy)], fill=vc('A'), width=2)
        d.line([(25, 5 + dy), (31, 1 + dy)], fill=vc('n'), width=2)                      # blade raised
    else:
        d.line([(19, 10 + dy), (23, 16 + dy)], fill=vc('A'), width=2)
        d.line([(23, 16 + dy), (29, 22 + dy)], fill=vc('n'), width=2)                    # blade low
    d.line([(12, 10 + dy), (9, 17 + dy)], fill=vc('A'), width=2)
    return finish(img)

def overseer_frame(t=0, dy=0):
    """Overseer: a veined brain in a glass tank on a small saucer, trailing feeders."""
    img, d = canvas()
    y = 1 + dy
    for i, tx in enumerate((11, 16, 21)):
        sw = ((i + t) % 3) - 1
        d.line([(tx, y + 24), (tx + sw, y + 28), (tx - sw, 31)], fill=vc('A'))
    d.ellipse([5, y + 19, 27, y + 26], fill=vc('G'))                                  # saucer
    d.line([(7, y + 22), (25, y + 22)], fill=vc('g'))
    d.ellipse([7, y, 25, y + 21], fill=rgb('#3a6a78'))                                # glass tank
    d.ellipse([9, y + 4, 23, y + 17], fill=rgb('#ff8fd8'))                            # brain
    for vx, vy in ((12, 8), (16, 6), (19, 10), (14, 13), (18, 14)):
        d.point((vx, y + vy), fill=rgb('#c0408f'))
    d.line([(16, y + 5), (16, y + 16)], fill=rgb('#c0408f'))
    d.arc([7, y, 25, y + 21], 200, 260, fill=rgb('#d8f6ff'))                           # glass glint
    d.point((10, y + 4), fill=rgb('#ffffff'))
    d.point((22, y + 23), fill=vc('o') if t % 2 else vc('O'))
    return finish(img)

def queen_frame(open_=0, dy=0):
    """Burrow Queen: a huge armoured worm head reared out of the ground, crowned in bone."""
    img, d = canvas()
    for i, (cx, cy, r) in enumerate(((15, 28, 9), (16, 22, 9), (17, 16, 8))):
        d.ellipse([cx - r, cy - r + dy, cx + r, cy + r + dy], fill=vc('A') if i % 2 else vc('a'))
        d.arc([cx - r, cy - r + dy, cx + r, cy + r + dy], 200, 340, fill=vc('N'))   # plate rims
    cx, cy = 18, 9 + dy
    d.ellipse([cx - 9, cy - 7, cx + 9, cy + 7], fill=vc('a'))
    for sx, sy in ((10, 3), (14, 0), (18, -1), (22, 1)):
        d.polygon([(sx, sy + 5 + dy), (sx + 2, sy + dy), (sx + 4, sy + 5 + dy)], fill=vc('n'))   # bone crown
    m = 2 + open_
    d.ellipse([cx + 1, cy - m, cx + 12, cy + m + 1], fill=vc('K'))
    for t in range(-m, m + 1, 2):
        d.point((cx + 3, cy + t), fill=vc('n')); d.point((cx + 10, cy + t), fill=vc('n'))
    d.ellipse([cx - 6, cy - 4, cx - 2, cy], fill=vc('o'))
    d.point((cx - 4, cy - 2), fill=vc('K'))
    for px, py in ((12, 22), (20, 25), (14, 30)):
        d.point((px, py + dy), fill=vc('o'))                                           # ooze weeping between plates
    return finish(img)

def alien_sheet(name, F):
    """Writes a gunless 32x32 sheet from anim -> [image]; missing anims reuse idle."""
    for a in ANIMS:
        F.setdefault(a, F['idle'])
    cols = max(len(v) for v in F.values())
    rows = len(ANIMS)
    sheet = Image.new('RGBA', (cols * AW, rows * 2 * AH), (0, 0, 0, 0))
    meta = {'frame': [AW, AH], 'anchor': [16, 32], 'anims': {}, 'flash_row_offset': rows}
    for r, a in enumerate(ANIMS):
        fr = [outline(im) for im in F[a]]
        meta['anims'][a] = {'row': r, 'n': len(fr), 'shoulder': [[16, 16]] * len(fr), 'gun': [False] * len(fr)}
        for c, im in enumerate(fr):
            sheet.paste(im, (c * AW, r * AH))
            sheet.paste(flash_white(im), (c * AW, (r + rows) * AH))
    sheet.save(os.path.join(OUT, 'sprites', name + '.png'))
    return meta

def alien_frames():
    def dying(base):
        return [settle(base.rotate(a, resample=Image.NEAREST, center=(16, 22))) for a in (30, 60, 90, 120, 180)]
    def hurt(im):
        return [im.transform(im.size, Image.AFFINE, (1, 0, 1, 0, 1, 0), resample=Image.NEAREST)]
    meta = {}
    meta['en_skitter'] = alien_sheet('en_skitter', {
        'idle': [skitter_frame(0), skitter_frame(0), skitter_frame(1, dy=1), skitter_frame(1, dy=1)],
        'run': [skitter_frame(i % 2, dy=-(i % 2)) for i in range(6)],
        'jump': [skitter_frame(air=True, dy=-2), skitter_frame(air=True)],
        'hurt': hurt(skitter_frame(1)),
        'die': dying(skitter_frame(1)),
    })
    meta['en_squid'] = alien_sheet('en_squid', {
        'idle': [squid_frame(i, dy=(1 if i in (2, 3) else 0)) for i in range(4)],
        'run': [squid_frame(i) for i in range(6)],
        'hurt': hurt(squid_frame(1)),
        'die': dying(squid_frame(2, gun=False)),
    })
    meta['en_blinker'] = alien_sheet('en_blinker', {
        'idle': [blinker_frame(0), blinker_frame(0), blinker_frame(0, dy=1), blinker_frame(0, dy=1)],
        'run': [blinker_frame(i) for i in range(4)],
        'jump': [blinker_frame(3)],
        'throw': [blinker_frame(0, claw=True), blinker_frame(0, claw=True)],
        'hurt': hurt(blinker_frame(2)),
        'die': dying(blinker_frame(2)),
    })
    meta['en_burrower'] = alien_sheet('en_burrower', {
        'idle': [burrower_frame(0), burrower_frame(1), burrower_frame(0, dy=1), burrower_frame(1, dy=1)],
        'throw': [burrower_frame(3, dy=-2), burrower_frame(3)],
        'hurt': hurt(burrower_frame(2)),
        'die': dying(burrower_frame(0)),
    })
    meta['en_grappler'] = alien_sheet('en_grappler', {
        'idle': [grappler_frame(0), grappler_frame(0), grappler_frame(0, dy=1), grappler_frame(0, dy=1)],
        'run': [grappler_frame(0, dy=i % 2) for i in range(4)],
        'throw': [grappler_frame(3), grappler_frame(5)],
        'hurt': hurt(grappler_frame(2)),
        'die': dying(grappler_frame(2)),
    })
    meta['en_bloater'] = alien_sheet('en_bloater', {
        'idle': [bloater_frame(0), bloater_frame(0, dy=1), bloater_frame(0, dy=1), bloater_frame(0)],
        'run': [bloater_frame(i, dy=i % 2) for i in range(4)],
        'hurt': hurt(bloater_frame(1)),
        'die': dying(bloater_frame(0)),
    })
    meta['en_weaver'] = alien_sheet('en_weaver', {
        'idle': [weaver_frame(i, dy=(1 if i in (2, 3) else 0)) for i in range(4)],
        'run': [weaver_frame(i, dy=i % 2) for i in range(4)],
        'throw': [weaver_frame(0, cast=True), weaver_frame(1, cast=True)],
        'hurt': hurt(weaver_frame(0)),
        'die': dying(weaver_frame(0)),
    })
    meta['en_prism'] = alien_sheet('en_prism', {
        'idle': [prism_frame(i, dy=(1 if i in (2, 3) else 0)) for i in range(4)],
        'run': [prism_frame(i) for i in range(4)],
        'hurt': hurt(prism_frame(1)),
        'die': dying(prism_frame(0)),
    })
    meta['en_warden'] = alien_sheet('en_warden', {
        'idle': [warden_frame(i, dy=(1 if i in (2, 3) else 0)) for i in range(4)],
        'run': [warden_frame(i, dy=i % 2) for i in range(4)],
        'throw': [warden_frame(0, cast=True), warden_frame(1, cast=True)],
        'hurt': hurt(warden_frame(0)),
        'die': dying(warden_frame(0)),
    })
    meta['en_stalker'] = alien_sheet('en_stalker', {
        'idle': [stalker_frame(0), stalker_frame(0), stalker_frame(0, dy=1), stalker_frame(0, dy=1)],
        'run': [stalker_frame(i) for i in range(4)],
        'jump': [stalker_frame(3)],
        'throw': [stalker_frame(0, slash=True), stalker_frame(0, slash=True)],
        'hurt': hurt(stalker_frame(2)),
        'die': dying(stalker_frame(2)),
    })
    meta['en_overseer'] = alien_sheet('en_overseer', {
        'idle': [overseer_frame(i, dy=(1 if i in (2, 3) else 0)) for i in range(4)],
        'run': [overseer_frame(i) for i in range(4)],
        'hurt': hurt(overseer_frame(1)),
        'die': dying(overseer_frame(0)),
    })
    meta['en_queen'] = alien_sheet('en_queen', {
        'idle': [queen_frame(0), queen_frame(1), queen_frame(0, dy=1), queen_frame(1, dy=1)],
        'throw': [queen_frame(3, dy=-1), queen_frame(4)],
        'hurt': hurt(queen_frame(2)),
        'die': dying(queen_frame(0)),
    })
    return meta


# U3 soldier looks: every class in every headgear. Colors are swapped at runtime (Art.look_sheet).
LOOK_HEADS = ['helmet', 'boonie', 'bandana', 'beret', 'hardhat', 'shades']

def look_sheets(meta):
    for key in SQUAD_KEYS:
        pal = palette(SQUAD_PAL[key])
        for head in LOOK_HEADS:
            if head == CHAR_STYLE[key]['head']:
                continue
            vk = key + '_' + head
            CHAR_STYLE[vk] = dict(CHAR_STYLE[key], head=head)
            fr = char_frames(vk, pal)
            meta['sq_' + vk] = write_sheet('sq_' + vk, fr, gun_image(CHAR_STYLE[key]['gun'], pal))

def main():
    os.makedirs(os.path.join(OUT, 'sprites'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'bg'), exist_ok=True)
    meta = {}
    for key in SQUAD_KEYS:
        pal = palette(SQUAD_PAL[key])
        fr = char_frames(key, pal)
        meta['sq_' + key] = write_sheet('sq_' + key, fr, gun_image(CHAR_STYLE[key]['gun'], pal))
    look_sheets(meta)
    for key in ('grunt', 'shield', 'nade', 'mg', 'radio', 'engineer', 'sapper', 'mortarcrew', 'para', 'jetter', 'jsniper', 'flamer'):
        pal = palette(ENEMY_PAL[key])
        fr = char_frames(key, pal)
        g = CHAR_STYLE[key]['gun']
        meta['en_' + key] = write_sheet('en_' + key, fr, gun_image(g, pal))
    # the Gate Trooper's body comes from Sprite Fusion (tools/sf_src/gatetrooper), its stolen ray from here
    ray = palette(dict(ENEMY_PAL['grunt'], G='#4a2a78', g='#9a6ae0', k='#24163c', c='#9cff6a', w='#6a4aa0', T='#3a2460'))
    meta['en_gatetrooper'] = write_sheet('en_gatetrooper', sf_char('gatetrooper'), gun_image('ray', ray))
    # Shield Wall: a Sprite Fusion edit of the riot Jackal into heavy plate (tools/sf_src/wallshield)
    meta['en_wallshield'] = write_sheet('en_wallshield', sf_char('wallshield'), gun_image('pistol', palette(ENEMY_PAL['shield'])))
    sf_vehicles()
    sf_vharr()
    meta['en_brute'] = brute_frames()
    meta.update(alien_frames())
    pow_frames()
    boss_sheet()
    props()
    explosion_sheet()
    small_fx()
    backgrounds()
    title_stage()
    critters()
    decor()
    ui()
    sf_icons()
    sf_normals(meta)
    with open(os.path.join(OUT, 'sprites', 'meta.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('art generated')

if __name__ == '__main__':
    main()
