#!/usr/bin/env bash
# A release contains Python, static assets and the exact tested COBOL binary.
set -Eeuo pipefail
umask 077
APP_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
DEPLOY_ROOT=${LEDGER_DEPLOY_ROOT:-$(dirname -- "$APP_DIR")}
RELEASES_DIR=${LEDGER_RELEASES_DIR:-$DEPLOY_ROOT/releases}
CURRENT=$RELEASES_DIR/current
SERVICE=${LEDGER_SERVICE:-cobol-canary.service}
RUNTIME_ENV=${LEDGER_RUNTIME_ENV:-$(readlink -f -- "$CURRENT/runtime")}
PYTHON=${PYTHON:-$RUNTIME_ENV/bin/python}
HEALTH_URL=${LEDGER_HEALTH_URL:-http://127.0.0.1:9001/health}
[[ -x $PYTHON && -L $CURRENT && -d $RELEASES_DIR ]] || {
    echo 'Provision release directories/current and Python first; see docs/OPERATIONS.md.' >&2; exit 2;
}
cd -- "$APP_DIR"
[[ -z $(git status --porcelain) ]] || { echo 'Commit the release before deploying.' >&2; exit 2; }
exec 8>"$RELEASES_DIR/.deploy.lock"
flock -n 8 || { echo 'Another deployment is running.' >&2; exit 2; }
commit=$(git rev-parse HEAD)
release="$RELEASES_DIR/$(date -u +%Y%m%dT%H%M%S)-${commit:0:12}"
previous=$(readlink -f -- "$CURRENT")
[[ -f $previous/app.py && -x $previous/ledger.cgi ]] || exit 2
mkdir -m 700 -- "$release"
activated=0
committed=0
rollback() {
    code=$?
    trap - EXIT
    rm -f -- "$RELEASES_DIR/.current-next"
    if (( activated && ! committed )); then
        ln -s -- "$previous" "$RELEASES_DIR/.current-next"
        mv -Tf -- "$RELEASES_DIR/.current-next" "$CURRENT"
        sudo -n systemctl restart "$SERVICE"
        printf 'Rolled back to %s\n' "$previous" >&2
    fi
    if (( ! committed )); then rm -rf -- "$release"; fi
    exit "$code"
}
trap rollback EXIT
git archive "$commit" | tar -x -C "$release"
ln -s -- "$RUNTIME_ENV" "$release/runtime"
"$PYTHON" - "$release/requirements.txt" <<'PYVERSIONS'
import importlib.metadata, pathlib, sys
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if line and not line.startswith("#"):
        name, expected = line.split("==")
        actual = importlib.metadata.version(name)
        if actual != expected:
            raise SystemExit(f"Runtime mismatch: {name} {actual}, expected {expected}")
PYVERSIONS
cobc -x -free "$release/ledger.cbl" "$release/sha256.cbl" -o "$release/ledger.cgi"
cobc -x -free "$release/seed.cbl" -o "$release/seed"
"$PYTHON" -m py_compile "$release/app.py" "$release/security.py"
LEDGER_TEST_BIN="$release/ledger.cgi" "$PYTHON" -m pytest "$release/tests" -q
sudo -n /usr/local/sbin/cobol-ledger-backup
ln -s -- "$release" "$RELEASES_DIR/.current-next"
mv -Tf -- "$RELEASES_DIR/.current-next" "$CURRENT"
activated=1
sudo -n systemctl restart "$SERVICE"
healthy=0
for _attempt in {1..20}; do
    if curl --max-time 2 --fail --silent "$HEALTH_URL" > "$release/health.json"; then
        if "$PYTHON" -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["status"] != "ok")' "$release/health.json"; then
            healthy=1; break
        fi
    fi
    sleep 0.5
done
(( healthy )) || { echo 'New release failed readiness.' >&2; exit 1; }
curl --max-time 5 --fail --silent "${HEALTH_URL%/health}/" > "$release/smoke.html"
rg -q "name='csrf_token'" "$release/smoke.html"
rg -q '/static/app.css' "$release/smoke.html"
rm -f -- "$release/smoke.html"
committed=1
printf 'Deployed %s\nPrevious release: %s\n' "$release" "$previous"
