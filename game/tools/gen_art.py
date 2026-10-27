#!/usr/bin/env python3
"""Generates every sprite sheet, background and UI texture for Iron Advance.

Run from the project root:  python3 tools/gen_art.py
All art is authored here as tiny ASCII part maps plus palettes, composited per
animation frame and given a dark outer outline, so it stays consistent and is
easy to tweak. One art pixel is drawn as 2x2 world units in game.
"""
import json, math, os, random
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
}
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
    'grunt':      dict(head='beret', torso='jackal', back='none', gun='rifle'),
    'shield':     dict(head='riot', torso='jackal', back='none', gun='pistol'),
    'nade':       dict(head='beret', torso='bomber', back='none', gun='none'),
    'mg':         dict(head='helmet', torso='jackal', back='none', gun='hmg'),
    'radio':      dict(head='helmet', torso='jackal', back='radio', gun='pistol'),
    'engineer':   dict(head='hardhat', torso='jackal', back='pack', gun='pistol'),
    'sapper':     dict(head='mask', torso='jackal', back='satchel', gun='none'),
    'mortarcrew': dict(head='helmet', torso='bomber', back='none', gun='none'),
    'para':       dict(head='helmet', torso='jackal', back='pack', gun='rifle'),
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
    F['idle'] = [(build_body(key, pal, 'stand', 0), (sx, sy), True),
                 (build_body(key, pal, 'stand', 0), (sx, sy), True),
                 (build_body(key, pal, 'stand2', 1), (sx, sy + 1), True),
                 (build_body(key, pal, 'stand2', 1), (sx, sy + 1), True)]
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
    # death: knocked back, then flat on the ground
    die = []
    base = build_body(key, pal, 'jump', 0, face='ouch', arms='hurt')
    for i, ang in enumerate([20, 45, 70, 90, 90]):
        im = settle(base.rotate(ang, resample=Image.NEAREST, center=(12, 14), expand=False), 1 if i == 3 else 0)
        die.append((im, (sx, sy), False))
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
    # muzzle flash: 3 frames 12x8
    mf = Image.new('RGBA', (36, 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(mf)
    Y, W, O = rgb('#ffd23a'), rgb('#ffffff'), rgb('#ff8a2a')
    d.polygon([(0, 3), (6, 0), (11, 3), (6, 7)], fill=O); d.polygon([(0, 3), (5, 1), (8, 3), (5, 6)], fill=Y); d.line([(0, 3), (5, 3)], fill=W)
    d.polygon([(12, 3), (16, 1), (21, 3), (16, 5)], fill=O); d.line([(12, 3), (17, 3)], fill=Y)
    d.polygon([(24, 3), (27, 2), (30, 3), (27, 4)], fill=Y)
    mf.save(os.path.join(OUT, 'sprites', 'muzzle.png'))
    # smoke puff: 6 frames 12x12
    sp = Image.new('RGBA', (72, 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(sp)
    for i in range(6):
        r = 2 + i
        g = 230 - i * 22
        c = (g, g, g - 6, 255)
        d.ellipse([i * 12 + 6 - r, 6 - r, i * 12 + 6 + r, 6 + r], fill=c)
        if i > 2:
            for k in range(0, 12, 2):
                for j in range(0, 12, 2):
                    if (k + j + i) % 4 == 0:
                        sp.putpixel((i * 12 + k, j), (0, 0, 0, 0))
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
THEMES = {
    'dusk':   dict(sky=['#1b2440', '#3a2f5e', '#7a3a5e', '#d0704a', '#f0b060'], sun='#ffd890', far='#5a3a5a', mid='#3a2a44', near='#24182c', haze='#e08a5a'),
    'jungle': dict(sky=['#0e2a30', '#1e4a4a', '#3a7a64', '#8ab07a', '#d8d8a0'], sun='#fff2c0', far='#2e5a4a', mid='#1e4234', near='#12281e', haze='#9ac08a'),
    'night':  dict(sky=['#05060e', '#0e1430', '#1e2450', '#3a3a70', '#6a5a8a'], sun='#e8eef8', far='#262a4a', mid='#181a34', near='#0c0e1e', haze='#4a4a7a'),
}

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

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

def backgrounds():
    for name, th in THEMES.items():
        W, H = 480, 270
        sky = gradient(W, H, th['sky'])
        d = ImageDraw.Draw(sky)
        if name == 'night':
            rnd = random.Random(3)
            for _ in range(120):
                x, y = rnd.randrange(W), rnd.randrange(150)
                sky.putpixel((x, y), rgb('#ffffff') if rnd.random() < 0.3 else rgb('#8a90c0'))
        cx, cy = 350, 120 if name != 'night' else 60
        r = 26 if name != 'night' else 14
        d.ellipse([cx - r - 10, cy - r - 10, cx + r + 10, cy + r + 10], fill=rgb(th['sun'])[:3] + (60,))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rgb(th['sun']))
        if name != 'night':
            for i in range(3):
                d.line([(cx - r, cy + 6 + i * 7), (cx + r, cy + 6 + i * 7)], fill=rgb(th['sky'][3]), width=2)
        sky.save(os.path.join(OUT, 'bg', f'{name}_sky.png'))
        # far mountains / mesas (tileable 512 wide)
        LW = 512
        rnd = random.Random(11)
        far = Image.new('RGBA', (LW, 160), (0, 0, 0, 0))
        d = ImageDraw.Draw(far)
        hts = []
        for x in range(LW):
            h = 70 + 30 * math.sin(x / LW * math.pi * 2 * 2) + 18 * math.sin(x / LW * math.pi * 2 * 5 + 1) + 8 * math.sin(x / LW * math.pi * 2 * 11)
            hts.append(int(h))
        for x, h in enumerate(hts):
            d.line([(x, 160 - h), (x, 159)], fill=rgb(th['far']))
            if x % 2 == 0 and hts[(x + 1) % LW] < h:
                d.point((x, 160 - h), fill=rgb(th['haze']))
        far.save(os.path.join(OUT, 'bg', f'{name}_far.png'))
        # mid: ruined city / jungle canopy / harbor cranes
        mid = Image.new('RGBA', (LW, 140), (0, 0, 0, 0))
        d = ImageDraw.Draw(mid)
        mc, lc = rgb(th['mid']), rgb(th['haze'])
        x = 0
        while x < LW:
            if name == 'jungle':
                w = rnd.randint(16, 30); h = rnd.randint(50, 100)
                d.rectangle([x + w // 2 - 2, 140 - h, x + w // 2 + 1, 139], fill=mc)
                for k in range(5):
                    a = -2.6 + k * 0.55
                    d.line([(x + w // 2, 140 - h), (x + w // 2 + math.cos(a) * 18, 140 - h + math.sin(a) * 10 + 8)], fill=mc, width=3)
                d.rectangle([x, 120 - rnd.randint(0, 20), x + w, 139], fill=mc)
            else:
                w = rnd.randint(18, 44); h = rnd.randint(30, 96)
                d.rectangle([x, 140 - h, x + w, 139], fill=mc)
                # broken tops and windows
                for k in range(rnd.randint(1, 4)):
                    bx = x + rnd.randint(0, w - 4)
                    d.rectangle([bx, 140 - h - rnd.randint(2, 8), bx + rnd.randint(2, 6), 140 - h], fill=mc)
                for wy in range(140 - h + 6, 132, 8):
                    for wx in range(x + 3, x + w - 3, 6):
                        if rnd.random() < (0.35 if name == 'night' else 0.15):
                            d.rectangle([wx, wy, wx + 1, wy + 2], fill=rgb('#ffd23a') if name == 'night' else lc)
                if name == 'night' and rnd.random() < 0.3:
                    cx0 = x + w // 2
                    d.line([(cx0, 140 - h), (cx0, 140 - h - 30)], fill=mc, width=2)
                    d.line([(cx0 - 20, 140 - h - 30), (cx0 + 26, 140 - h - 30)], fill=mc, width=2)
            x += w + rnd.randint(2, 14)
        mid.save(os.path.join(OUT, 'bg', f'{name}_mid.png'))
        # near: silhouettes of wrecks, palms, poles
        near = Image.new('RGBA', (LW, 110), (0, 0, 0, 0))
        d = ImageDraw.Draw(near)
        nc = rgb(th['near'])
        d.rectangle([0, 96, LW, 110], fill=nc)
        for x in range(0, LW, 2):
            d.line([(x, 96), (x, 96 - int(4 + 3 * math.sin(x / 9.0) + 2 * math.sin(x / 3.1)))], fill=nc)
        x = 10
        while x < LW - 40:
            kind = rnd.choice(['palm', 'wreck', 'pole', 'palm'])
            if kind == 'palm':
                h = rnd.randint(50, 80)
                for i in range(h):
                    d.point((x + int(math.sin(i / 14.0) * 4), 96 - i), fill=nc)
                    d.point((x + 1 + int(math.sin(i / 14.0) * 4), 96 - i), fill=nc)
                tx, ty = x + int(math.sin(h / 14.0) * 4), 96 - h
                for k in range(6):
                    a = -3.0 + k * 0.6
                    for s in range(16):
                        d.point((tx + int(math.cos(a) * s), ty + int(math.sin(a) * s * 0.6 + (s * s) / 30)), fill=nc)
                        d.point((tx + int(math.cos(a) * s), ty + 1 + int(math.sin(a) * s * 0.6 + (s * s) / 30)), fill=nc)
            elif kind == 'wreck':
                d.polygon([(x, 96), (x + 8, 80), (x + 34, 78), (x + 44, 96)], fill=nc)
                d.rectangle([x + 14, 70, x + 28, 80], fill=nc)
                d.line([(x + 28, 74), (x + 46, 66)], fill=nc, width=2)
            else:
                d.line([(x, 96), (x, 40)], fill=nc, width=2)
                d.line([(x - 8, 46), (x + 8, 46)], fill=nc)
                d.line([(x + 8, 46), (x + 60, 58)], fill=nc)
            x += rnd.randint(50, 110)
        near.save(os.path.join(OUT, 'bg', f'{name}_near.png'))

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

def main():
    os.makedirs(os.path.join(OUT, 'sprites'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'bg'), exist_ok=True)
    meta = {}
    for key in ('moss', 'hex', 'vee', 'rook'):
        pal = palette(SQUAD_PAL[key])
        fr = char_frames(key, pal)
        meta['sq_' + key] = write_sheet('sq_' + key, fr, gun_image(CHAR_STYLE[key]['gun'], pal))
    for key in ('grunt', 'shield', 'nade', 'mg', 'radio', 'engineer', 'sapper', 'mortarcrew', 'para'):
        pal = palette(ENEMY_PAL[key])
        fr = char_frames(key, pal)
        g = CHAR_STYLE[key]['gun']
        meta['en_' + key] = write_sheet('en_' + key, fr, gun_image(g, pal))
    meta['en_brute'] = brute_frames()
    pow_frames()
    boss_sheet()
    props()
    explosion_sheet()
    small_fx()
    backgrounds()
    ui()
    with open(os.path.join(OUT, 'sprites', 'meta.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('art generated')

if __name__ == '__main__':
    main()
