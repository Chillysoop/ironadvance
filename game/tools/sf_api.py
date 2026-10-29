#!/usr/bin/env python3
"""Sprite Fusion API client for dev-time art requests (never shipped, never called by the game).

Needs SPRITE_FUSION_API_KEY in the environment. Results land in tools/sf_src/<name>/ next to a
manifest.json recording each request, so gen_art.py can rebuild sheets from them without the key.

  python3 tools/sf_api.py credits
  python3 tools/sf_api.py style NAME OUT.png "prompt" --size 24 --ref a.png --ref b.png
  python3 tools/sf_api.py edit NAME OUT.png "prompt" --ref base.png
  python3 tools/sf_api.py animate NAME OUT.png "prompt" --ref still.png --frames 8 --colors 20
  python3 tools/sf_api.py normal NAME OUT.png --ref sprite.png
  python3 tools/sf_api.py normals      # free: a normal map for every character sheet in meta.json

style and edit return several options: they are saved as OUT_0.png, OUT_1.png... so one can be picked
and renamed. animate saves its spritesheet strip. Every request costs 15 credits except normal.
"""
import argparse, base64, json, os, subprocess, sys, urllib.request

API = 'https://www.spritefusion.com/api/v1/'
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sf_src')

def key():
    k = os.environ.get('SPRITE_FUSION_API_KEY', '').strip()
    if not k:
        sys.exit('Set SPRITE_FUSION_API_KEY first.')
    return k

def call(path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': 'Bearer ' + key(), 'Content-Type': 'application/json'})
    return urllib.request.urlopen(req, timeout=600)

def data_url(p):
    return 'data:image/png;base64,' + base64.b64encode(open(p, 'rb').read()).decode()

def fetch(url, dest):
    # the media host refuses Python's default user agent, curl gets through
    subprocess.run(['curl', '-sS', '-m', '120', '-o', dest, url], check=True)

def generate(body):
    outs = []
    for line in call('generate', body):
        line = line.decode().strip()
        if not line.startswith('data:'):
            continue
        ev = json.loads(line[5:])
        if ev['type'] == 'output':
            outs.append(ev['asset'])
        elif ev['type'] == 'completed':
            if ev['status'] != 'succeeded':
                sys.exit('Generation failed: %s' % ev.get('error'))
            print('credits left:', ev['credits']['remaining'])
    return outs

def record(name, entry):
    d = os.path.join(SRC, name)
    os.makedirs(d, exist_ok=True)
    mp = os.path.join(d, 'manifest.json')
    m = json.load(open(mp)) if os.path.exists(mp) else []
    m.append(entry)
    with open(mp, 'w') as f:
        json.dump(m, f, indent=1)

def normal_map(src, dest):
    body = {'inputs': [{'data_url': data_url(src)}]}
    req = urllib.request.Request(API + 'normal-maps', data=json.dumps(body).encode(),
                                 headers={'Authorization': 'Bearer ' + key(), 'Content-Type': 'application/json'})
    open(dest, 'wb').write(urllib.request.urlopen(req, timeout=120).read())

def normals():
    # whole sheets go up as they are: the generator maps every frame in place and keeps the alpha,
    # so gen_art.py can check each one still fits its sheet
    sprites = os.path.join(os.path.dirname(SRC), '..', 'assets', 'sprites')
    out = os.path.join(SRC, 'normals')
    os.makedirs(out, exist_ok=True)
    for name in sorted(json.load(open(os.path.join(sprites, 'meta.json')))):
        normal_map(os.path.join(sprites, name + '.png'), os.path.join(out, name + '.png'))
        print(name)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('op', choices=['credits', 'style', 'edit', 'animate', 'normal', 'normals'])
    ap.add_argument('name', nargs='?')
    ap.add_argument('out', nargs='?')
    ap.add_argument('prompt', nargs='?', default='')
    ap.add_argument('--ref', action='append', default=[])
    ap.add_argument('--size', type=int)
    ap.add_argument('--frames', type=int, default=8)
    ap.add_argument('--colors', type=int, default=20)
    a = ap.parse_args()
    if a.op == 'credits':
        print(call('credits').read().decode())
        return
    if a.op == 'normals':
        normals()
        return
    d = os.path.join(SRC, a.name)
    os.makedirs(d, exist_ok=True)
    out = os.path.join(d, a.out)
    inputs = [{'data_url': data_url(r)} for r in a.ref]
    if a.op == 'normal':
        req = urllib.request.Request(API + 'normal-maps', data=json.dumps({'inputs': inputs}).encode(),
                                     headers={'Authorization': 'Bearer ' + key(), 'Content-Type': 'application/json'})
        open(out, 'wb').write(urllib.request.urlopen(req, timeout=120).read())
        record(a.name, {'op': 'normal', 'out': a.out, 'refs': a.ref})
        return
    body = {'operation': {'style': 'style-reference'}.get(a.op, a.op), 'prompt': a.prompt, 'inputs': inputs}
    if a.size and a.op == 'style':
        body['size'] = a.size
    if a.op == 'animate':
        body.update(output_frames=a.frames, colors=a.colors)
    outs = generate(body)
    files = []
    for i, asset in enumerate(outs):
        if a.op == 'animate':
            fn = out
            fetch(asset['spritesheetUrl'], fn)
        else:
            fn = out[:-4] + '_%d.png' % i
            fetch(asset['assetUrl'], fn)
        files.append(os.path.basename(fn))
        print(fn)
    record(a.name, {'op': a.op, 'prompt': a.prompt, 'refs': [os.path.relpath(r, d) for r in a.ref],
                    'size': a.size, 'outputs': files, 'asset_ids': [o['id'] for o in outs]})

if __name__ == '__main__':
    main()
