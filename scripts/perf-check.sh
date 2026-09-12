#!/usr/bin/env bash
# Runtime regression check for the resident app: launch build/MicroKeys.app,
# sample resident memory and CPU for a while, then run the system `leaks`
# tool twice and require the leak count not to grow. Fails (exit 1) when any
# threshold is exceeded. Not part of `make test` because it needs the GUI
# app running for a minute; run it before a release:
#
#   make perf                 # 60 s
#   DURATION=300 make perf    # longer soak
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build/MicroKeys.app"
DURATION="${DURATION:-60}"        # seconds to soak
MAX_RSS_MB="${MAX_RSS_MB:-80}"    # idle resident memory ceiling
MAX_RSS_GROWTH_MB="${MAX_RSS_GROWTH_MB:-5}"
MAX_CPU_PCT="${MAX_CPU_PCT:-1.0}" # average CPU over the soak
MAX_LEAK_GROWTH="${MAX_LEAK_GROWTH:-0}"

[ -d "$APP" ] || { echo "no $APP - run 'make app' first" >&2; exit 2; }
pkill -x MicroKeys 2>/dev/null && sleep 1

open "$APP"
sleep 4
PID="$(pgrep -x MicroKeys)" || { echo "MicroKeys did not start" >&2; exit 1; }
echo "pid $PID, soaking for ${DURATION}s"

rss_mb() { ps -o rss= -p "$PID" | awk '{printf "%.1f", $1/1024}'; }
cpu_s()  { ps -o time= -p "$PID" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3 }'; }

FAIL=0
START_RSS="$(rss_mb)"; START_CPU="$(cpu_s)"
LEAKS_BEFORE="$(leaks "$PID" 2>/dev/null | sed -n 's/^Process [0-9]*: \([0-9]*\) leaks.*/\1/p')"
echo "t=0s   RSS=${START_RSS} MB  leaks=${LEAKS_BEFORE:-?}"

STEP=10; ELAPSED=0
while [ "$ELAPSED" -lt "$DURATION" ]; do
    sleep "$STEP"; ELAPSED=$((ELAPSED + STEP))
    kill -0 "$PID" 2>/dev/null || { echo "MicroKeys died during the soak" >&2; exit 1; }
    echo "t=${ELAPSED}s  RSS=$(rss_mb) MB"
done

END_RSS="$(rss_mb)"; END_CPU="$(cpu_s)"
LEAKS_AFTER="$(leaks "$PID" 2>/dev/null | sed -n 's/^Process [0-9]*: \([0-9]*\) leaks.*/\1/p')"
CPU_PCT="$(awk -v a="$START_CPU" -v b="$END_CPU" -v d="$DURATION" 'BEGIN{printf "%.2f", (b-a)/d*100}')"
GROWTH="$(awk -v a="$START_RSS" -v b="$END_RSS" 'BEGIN{printf "%.1f", b-a}')"
LEAK_GROWTH=$(( ${LEAKS_AFTER:-0} - ${LEAKS_BEFORE:-0} ))

pkill -x MicroKeys

echo
echo "resident memory : ${END_RSS} MB (limit ${MAX_RSS_MB}), growth ${GROWTH} MB (limit ${MAX_RSS_GROWTH_MB})"
echo "average CPU     : ${CPU_PCT}% (limit ${MAX_CPU_PCT})"
echo "leaks           : ${LEAKS_BEFORE:-?} -> ${LEAKS_AFTER:-?} (growth limit ${MAX_LEAK_GROWTH})"

awk -v v="$END_RSS" -v m="$MAX_RSS_MB" 'BEGIN{exit !(v>m)}' && { echo "FAIL: resident memory above limit"; FAIL=1; }
awk -v v="$GROWTH" -v m="$MAX_RSS_GROWTH_MB" 'BEGIN{exit !(v>m)}' && { echo "FAIL: resident memory grew during the soak"; FAIL=1; }
awk -v v="$CPU_PCT" -v m="$MAX_CPU_PCT" 'BEGIN{exit !(v>m)}' && { echo "FAIL: idle CPU above limit"; FAIL=1; }
if [ -z "$LEAKS_BEFORE" ] || [ -z "$LEAKS_AFTER" ]; then
    echo "WARN: 'leaks' produced no count (tool missing or not permitted); leak check skipped"
elif [ "$LEAK_GROWTH" -gt "$MAX_LEAK_GROWTH" ]; then
    echo "FAIL: leak count grew by $LEAK_GROWTH"; FAIL=1
fi

[ "$FAIL" -eq 0 ] && echo "PASS"
exit "$FAIL"
