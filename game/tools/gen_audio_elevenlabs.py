#!/usr/bin/env python3
"""Generates the game's sound effects, ambience beds and music with ElevenLabs.

Run from the game folder:   ELEVENLABS_API_KEY=sk_... python3 tools/gen_audio_elevenlabs.py
Options:
  --only=boom,music/title   just these entries (an SFX name, or music/<n>, ambience/<n>)
  --kind=sfx|ambience|music just one kind
  --force                   regenerate even if the prompt hasn't changed
  --dry-run                 list what would be made
  --reconvert               rebuild files from saved raw downloads (tools/.elevenlabs_raw) where present

The key is read from the ELEVENLABS_API_KEY environment variable only; never write it into a file.
Every file it makes is listed in tools/elevenlabs_lock.json with a hash of its prompt, so a rerun
only remakes entries whose prompt changed (or that are missing). Needs ffmpeg on PATH.

Outputs
  assets/sfx/<name>.wav, <name>_2.wav ...  mono 44.1 kHz, silence trimmed, peak -1 dB. Sfx picks a
                                           variant at random.
  assets/ambience/<name>.ogg               looping biome beds (Music.ambience)
  assets/music/<name>.ogg                  looping tracks and one-shot stings (Music.play / sting)
After a run, import the new files once:  godot --headless --path . --import
and then run this script with --loops to set loop=true on the music and ambience imports.

This replaces the old chiptune placeholders from tools/gen_sfx.py (still in git history); don't
run gen_sfx.py again or it will overwrite these files.
"""
import hashlib, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
LOCK = os.path.join(ROOT, 'tools', 'elevenlabs_lock.json')
RAW = os.path.join(ROOT, 'tools', '.elevenlabs_raw')
API = 'https://api.elevenlabs.io/v1'

# Shared flavour so the set sounds like one game: punchy, arcade, 90s run-and-gun.
STYLE = 'punchy 90s arcade run-and-gun game sound effect, crisp, dry, no music, no voice'

# name: (prompt, seconds, variants)
SFX = {
    # weapons
    'shot':     ('single rifle gunshot, sharp crack with short tail', 0.8, 3),
    'mg':       ('short burst of heavy machine gun fire, four rapid shots', 1.2, 3),
    'snipe':    ('powerful sniper rifle shot, loud crack and long echo', 1.5, 2),
    'rocket':   ('rocket launcher firing, whoosh of a rocket leaving the tube', 1.4, 2),
    'toss':     ('grenade thrown, quick whoosh of an object through the air', 0.6, 2),
    'boom':     ('medium grenade explosion, punchy blast with debris', 1.6, 3),
    'bigboom':  ('huge explosion, deep boom with rumble and falling rubble', 2.6, 3),
    'slash':    ('fast combat knife slash, sharp swish and hit', 0.6, 2),
    'flame':    ('flamethrower burst, roaring whoosh of fire', 1.6, 2),
    'zap':      ('tesla coil electric arc, crackling zap of lightning', 1.0, 2),
    'laser':    ('sci-fi alien laser beam firing, rising energy hum and zap', 1.2, 2),
    'ricochet': ('bullet ricochet off metal, high ping whine', 0.7, 3),
    'grapple':  ('grappling hook fired, metal hook launch and rope zipping', 0.9, 1),
    'beep':     ('land mine armed, two short electronic warning beeps', 0.6, 1),
    # bodies and the world
    'hurt':     ('soldier grunting in pain as he is hit, short male grunt', 0.6, 3),
    'scream':   ('enemy soldier death scream, short cartoonish arcade yell', 1.0, 3),
    'death':    ('heroic soldier falling, gasp and body thud on dirt', 1.4, 1),
    'alien_die':('alien creature death screech, wet gurgling shriek', 1.2, 3),
    'chitter':  ('small alien insect creature chittering and skittering', 1.0, 2),
    'roar':     ('giant monster boss roar, deep metallic growl', 2.4, 1),
    'thud':     ('heavy body slamming into the ground, dull thud', 0.6, 3),
    'bonk':     ('metal helmet bonk, comedic hollow clang', 0.5, 2),
    'land':     ('boots landing on dirt after a jump', 0.5, 3),
    'step':     ('single combat boot footstep on gravel', 0.3, 3),
    'splash':   ('body falling into deep water, big splash', 1.2, 2),
    'bubble':   ('sinking underwater, bubbles rising and a gurgle', 1.6, 1),
    'sizzle':   ('molten lava hissing and sizzling as it burns', 1.6, 1),
    'collapse': ('stone tower collapsing, crumbling bricks and heavy rubble crash', 2.8, 2),
    'crate':    ('wooden supply crate smashed open, wood crack and items rattling', 0.9, 2),
    'engine':   ('tank engine starting, diesel roar and clanking treads', 1.8, 1),
    'warp':     ('alien teleport, quick shimmering warp whoosh', 0.9, 2),
    'heal':     ('medkit used, soft bright healing chime with sparkle', 1.0, 1),
    'power':    ('power-up activated, rising energetic synth whoosh', 0.9, 2),
    'alarm':    ('military base alarm siren, two short wails', 1.6, 1),
    # interface
    'click':    ('soft UI button click, short tactile tick', 0.2, 1),
    'select':   ('UI select blip, bright short confirm tone', 0.3, 1),
    'deny':     ('UI error buzz, short low denied tone', 0.4, 1),
    'tick':     ('single clock tick, crisp mechanical', 0.2, 1),
    'coin':     ('coins collected, bright arcade money jingle', 0.6, 2),
    'buy':      ('cash register ka-ching, purchase confirmed', 0.8, 1),
    'levelup':  ('arcade level up fanfare, short triumphant rising chime', 1.6, 1),
    'start':    ('mission start, military snare roll and brass stab', 1.8, 1),
    'bad':      ('mission failed, low ominous brass sting', 1.8, 1),
    'ping':     ('radar ping, clean sonar blip', 0.6, 1),
    'draw':     ('playing card drawn from a deck, quick paper flick', 0.3, 2),
    'turn':     ('your turn, short military radio click and chirp', 0.6, 1),
}

AMB_STYLE = 'seamless looping ambience background, no music, no voices'
AMBIENCE = {
    'camp':     'military base camp at dusk, distant generator hum, flags flapping, faraway radio chatter murmur',
    'jungle':   'dense tropical jungle, insects, exotic birds, distant monkeys',
    'palace':   'quiet japanese palace garden at night, crickets, gentle wind, faint wind chimes',
    'swamp':    'flooded river delta, frogs, light rain on water, insects',
    'desert':   'hot desert ruins, dry wind, sand blowing, distant hawk',
    'wind':     'high mountain pass, strong cold wind gusts',
    'snow':     'frozen lake, icy wind, creaking ice',
    'industry': 'oil refinery, pipes hissing, machinery hum, metal clanks',
    'warzone':  'besieged city, distant artillery booms and far gunfire, burning debris crackle',
    'train':    'armored train in motion, steady clacking rails and wind',
    'harbor':   'night harbor in rain, waves on piers, creaking ships, foghorn far away',
    'carrier':  'aircraft carrier deck at sea, strong ocean wind, distant jet engines',
    'cave':     'deep mine tunnel, dripping water, low rumble, creaking timbers',
    'volcano':  'active volcano, deep rumbling, bubbling lava, hissing vents',
    'hive':     'alien hive, organic pulsing, wet clicks, eerie low drone',
}

MUSIC_STYLE = ('instrumental video game soundtrack, 16-bit era arcade run-and-gun inspired, '
               'live drums, electric guitar, brass, synth bass, no vocals')
# name: (prompt, seconds, loop)
MUSIC = {
    'title':          ('heroic military march main theme, bold brass melody over driving snare, epic and adventurous', 90, True),
    'hq':             ('relaxed base camp theme between missions, laid-back funky bass and light drums, warm and confident', 90, True),
    'training':       ('upbeat boot camp drill theme, steady marching snare, playful but focused', 75, True),
    'battle_jungle':  ('tense jungle combat theme, tribal percussion, wah guitar, urgent brass hits', 100, True),
    'battle_desert':  ('hot desert battle theme, driving rock beat, middle eastern scale lead guitar', 100, True),
    'battle_steel':   ('industrial war theme for a refinery and fortress city fight, heavy chugging guitars, pounding drums', 100, True),
    'battle_night':   ('stealthy night operation theme, pulsing synth bass, tight hi-hats, suspense building into action', 100, True),
    'alien':          ('alien invasion battle theme, eerie synth pads, odd meter, driving drums, otherworldly', 100, True),
    'boss':           ('intense boss battle theme, fast double kick drums, shredding guitar, dramatic brass', 100, True),
    'ending':         ('triumphant war is over finale, slow heroic brass anthem, emotional and proud', 80, True),
    'victory':        ('short victory fanfare jingle, triumphant brass, ends on a held chord', 6, False),
    'defeat':         ('short defeat jingle, slow sad brass, ends on a low note', 6, False),
}


def key():
    k = os.environ.get('ELEVENLABS_API_KEY', '')
    if not k.startswith('sk_'):
        sys.exit('Set ELEVENLABS_API_KEY (it starts with sk_) in the environment.')
    return k


def post(path, body, tries=4):
    data = json.dumps(body).encode()
    for t in range(tries):
        req = urllib.request.Request(API + path, data=data, method='POST',
                                     headers={'xi-api-key': key(), 'Content-Type': 'application/json',
                                              'Accept': 'audio/mpeg'})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors='replace')[:400]
            if e.code in (429, 500, 502, 503) and t < tries - 1:
                time.sleep(2 ** (t + 1) * 2)
                continue
            raise SystemExit('ElevenLabs %s %s: %s' % (path, e.code, msg))
        except (urllib.error.URLError, TimeoutError):
            if t < tries - 1:
                time.sleep(2 ** (t + 1) * 2)
                continue
            raise


def ffmpeg(args):
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y'] + args, check=True)


def peak_db(path):
    out = subprocess.run(['ffmpeg', '-hide_banner', '-i', path, '-af', 'volumedetect', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    for line in out.splitlines():
        if 'max_volume' in line:
            return float(line.split(':')[1].split()[0])
    return 0.0


def to_sfx_wav(mp3, dst):
    with tempfile.TemporaryDirectory() as td:
        trim = os.path.join(td, 't.wav')
        ffmpeg(['-i', mp3, '-ac', '1', '-ar', '44100', '-af',
                'silenceremove=start_periods=1:start_threshold=-45dB,'
                'areverse,silenceremove=start_periods=1:start_threshold=-50dB,areverse,'
                'afade=t=in:st=0:d=0.02:curve=tri,areverse,afade=t=in:st=0:d=0.004', trim])
        pk = peak_db(trim)
        if pk < -60:
            raise RuntimeError('%s came out silent after trimming (peak %.1f dB)' % (dst, pk))
        gain = -1.0 - pk
        ffmpeg(['-i', trim, '-af', 'volume=%.2fdB' % gain, '-c:a', 'pcm_s16le', dst])


def to_ogg(mp3, dst, q=5):
    ffmpeg(['-i', mp3, '-ar', '44100', '-c:a', 'libvorbis', '-q:a', str(q), dst])


def h(*parts):
    return hashlib.sha1(json.dumps(parts).encode()).hexdigest()[:12]


def jobs():
    # The API rejects durations under 0.5 s; short cues ask for 0.5 s and the silence trim shortens them.
    for n, (p, d, v) in SFX.items():
        for i in range(v):
            fn = n if i == 0 else '%s_%d' % (n, i + 1)
            yield ('sfx', n, fn, 'assets/sfx/%s.wav' % fn, h(p, d, i, STYLE),
                   lambda p=p, d=d: post('/sound-generation', {'text': '%s, %s' % (p, STYLE),
                                                                'duration_seconds': max(0.5, d), 'prompt_influence': 0.5}),
                   to_sfx_wav)
    for n, p in AMBIENCE.items():
        yield ('ambience', 'ambience/' + n, n, 'assets/ambience/%s.ogg' % n, h(p, AMB_STYLE),
               lambda p=p: post('/sound-generation', {'text': '%s, %s' % (p, AMB_STYLE), 'duration_seconds': 22,
                                                     'loop': True, 'model_id': 'eleven_text_to_sound_v2'}),
               lambda a, b: to_ogg(a, b, 4))
    for n, (p, sec, loop) in MUSIC.items():
        yield ('music', 'music/' + n, n, 'assets/music/%s.ogg' % n, h(p, sec, MUSIC_STYLE),
               lambda p=p, sec=sec: post('/music', {'prompt': '%s. %s' % (p, MUSIC_STYLE),
                                                   'music_length_ms': sec * 1000, 'force_instrumental': True}),
               to_ogg)


def set_loops():
    for kind in ('music', 'ambience'):
        d = os.path.join(ROOT, 'assets', kind)
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if not f.endswith('.ogg.import'):
                continue
            n = f[:-len('.ogg.import')]
            loop = kind == 'ambience' or MUSIC.get(n, ('', 0, True))[2]
            path = os.path.join(d, f)
            s = open(path).read()
            s = s.replace('loop=false', 'loop=%s' % ('true' if loop else 'false'))
            s = s.replace('loop=true', 'loop=%s' % ('true' if loop else 'false'))
            open(path, 'w').write(s)
            print('loop', kind, n, loop)


def main():
    args = sys.argv[1:]
    if '--loops' in args:
        return set_loops()
    only = next((a.split('=', 1)[1].split(',') for a in args if a.startswith('--only=')), None)
    kind = next((a.split('=', 1)[1] for a in args if a.startswith('--kind=')), None)
    force, dry = '--force' in args, '--dry-run' in args
    reconv = '--reconvert' in args
    force = force or reconv
    lock = json.load(open(LOCK)) if os.path.exists(LOCK) else {}
    todo = [j for j in jobs() if (not kind or j[0] == kind) and (not only or j[1] in only or j[2] in only)]
    todo = [j for j in todo if force or lock.get(j[3]) != j[4] or not os.path.exists(os.path.join(ROOT, j[3]))]
    print('%d files to make' % len(todo))
    for kd, _n, fn, rel, hh, call, conv in todo:
        print(' ', kd, rel)
        if dry:
            continue
        dst = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        # Raw downloads are kept (git-ignored) so a conversion fix can rerun with --reconvert for free.
        mp3 = os.path.join(RAW, rel + '.mp3')
        os.makedirs(os.path.dirname(mp3), exist_ok=True)
        if not (reconv and os.path.exists(mp3)):
            open(mp3, 'wb').write(call())
        conv(mp3, dst)
        lock[rel] = hh
        json.dump(lock, open(LOCK, 'w'), indent=1, sort_keys=True)


if __name__ == '__main__':
    main()
