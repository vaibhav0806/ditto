#!/bin/bash
set -euo pipefail

ditto_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-textedit}" in
  textedit) ditto_target=com.apple.TextEdit ;;
  chrome) ditto_target=com.google.Chrome ;;
  ghostty) ditto_target=com.mitchellh.ghostty ;;
  textedit-events) ditto_target=com.apple.TextEdit ;;
  *) printf '%s\n' 'Usage: run-native-e2e.sh [textedit|textedit-events|chrome|ghostty]' >&2; exit 2 ;;
esac
ditto_app="$ditto_root/build/Ditto.app"
ditto_result="$ditto_root/.build/e2e-${1:-textedit}.json"
# Only restart the executable built by this checkout, not similarly named apps.
python3 - "$ditto_app/Contents/MacOS/Ditto" <<'PY'
import os, signal, subprocess, sys
exe = sys.argv[1]
for line in subprocess.check_output(['ps', '-axo', 'pid=,args='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and (parts[1] == exe or parts[1].startswith(exe + ' ')):
        os.kill(int(parts[0]), signal.SIGTERM)
PY
rm -f "$ditto_result"
if [[ "${1:-textedit}" == textedit-events ]]; then
    open -n "$ditto_app" --args --native-e2e "$ditto_result" --e2e-app "$ditto_target" --e2e-event-query
else
    open -n "$ditto_app" --args --native-e2e "$ditto_result" --e2e-app "$ditto_target"
fi
python3 - "$ditto_result" <<'PY'
import json, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
for _ in range(160):
    if path.exists():
        result = json.loads(path.read_text())
        scenarios = result.get('scenarios', [])
        if scenarios and scenarios[-1].get('scenario') == 'runner':
            print(json.dumps(result, indent=2))
            sys.exit(0 if scenarios[-1]['result'] == 'pass' else 1)
    time.sleep(0.25)
print('E2E runner did not finish within 40 seconds', file=sys.stderr)
sys.exit(2)
PY
