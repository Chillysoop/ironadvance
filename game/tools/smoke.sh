#!/bin/bash
# Runs the test scenarios and fails if any check fails, a scenario errors, or one doesn't finish.
#
#   game/tools/smoke.sh            the smoke set (about 10 minutes): run it before every merge
#   game/tools/smoke.sh --all      every scenario except the long autoplay ones (about 1.5 hours)
#   game/tools/smoke.sh gate hq    just these scenarios
#
# Needs godot 4.3 on PATH (or GODOT=/path/to/godot) and xvfb-run. Each scenario gets its own
# user:// folder, so scenarios can't trip over each other's saves. Logs go to $OUT (default /tmp/ia-smoke).
cd "$(dirname "$0")/.." || exit 2
GODOT=${GODOT:-godot}
OUT=${OUT:-/tmp/ia-smoke}
SMOKE="runsave settings pause draft recruits identity ending wardeep company aliens3 bcalls xcalls tcalls camp hub doc story gear events10 hq gate tags drill vehicles reinforce field biomes2 stranded bp3 variety boarkits orders rares fork seeds biomebosses segments3 vpicks vpicks2 audit"
SMOKE="$SMOKE tour guided"  # guided: a bot that only clicks what boot camp highlights  # the UI tour: every screen and the game menu
LONG="playtest campaignplay campsweep trailer campaign pinball survey bot bakefog"
if [ "$1" = "--all" ]; then
  LIST=$(sed -n '/^\tmatch scenario:/,/^\t\t_:/p' tools/test_runner.gd | grep -oP '^\t\t"[a-z0-9_]+"' | tr -d '\t"')
  for l in $LONG; do LIST=$(echo "$LIST" | grep -vx "$l"); done
elif [ $# -gt 0 ]; then
  LIST="$*"
else
  LIST=$SMOKE
fi
mkdir -p "$OUT"
bad=0
for sc in $LIST; do
  rm -rf "$OUT/xdg-$sc"; mkdir -p "$OUT/xdg-$sc" "$OUT/shots-$sc"
  t0=$(date +%s)
  XDG_DATA_HOME="$OUT/xdg-$sc" timeout ${TIMEOUT:-900} xvfb-run -a "$GODOT" --rendering-driver opengl3 --path . -- --iatest --scenario=$sc --out="$OUT/shots-$sc" > "$OUT/$sc.log" 2>&1
  p=$(grep -c " PASS " "$OUT/$sc.log"); f=$(grep -c " FAIL " "$OUT/$sc.log")
  d=$(grep -c "^\[test\] done" "$OUT/$sc.log"); e=$(grep -c "SCRIPT ERROR\|Parse Error" "$OUT/$sc.log")
  ok=OK
  if [ "$f" -gt 0 ] || [ "$d" -eq 0 ] || [ "$e" -gt 0 ]; then ok=FAILED; bad=$((bad + 1)); fi
  printf "%-12s %-6s pass %3d  fail %d  %4ds\n" "$sc" "$ok" "$p" "$f" $(( $(date +%s) - t0 ))
  if [ "$ok" = FAILED ]; then
    grep -E " FAIL |SCRIPT ERROR|Parse Error" "$OUT/$sc.log" | head -5 | sed 's/^/    /'
    [ "$d" -eq 0 ] && echo "    (never finished: hang or crash, see $OUT/$sc.log)"
  fi
done
echo "$bad scenario(s) failed"
[ "$bad" -eq 0 ]
