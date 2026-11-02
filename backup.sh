#!/usr/bin/env bash
# Consistent ISAM snapshot; coordinates with every CGI request through flock.
set -Eeuo pipefail
umask 077
APP_DIR=${LEDGER_APP_DIR:-/srv/canary/cobol.micutu.com/app}
BACKUP_DIR=${LEDGER_BACKUP_DIR:-/srv/backups/cobol-ledger}
RETENTION_DAYS=${LEDGER_BACKUP_RETENTION_DAYS:-14}
[[ $RETENTION_DAYS =~ ^[1-9][0-9]*$ ]] || exit 2
[[ -d $APP_DIR/data && ! -L $APP_DIR/data/.ledger.lock ]] || exit 2
mkdir -p -- "$BACKUP_DIR"
# Resolve the destination before checking that backups are outside the data tree.
BACKUP_DIR=$(cd -- "$BACKUP_DIR" && pwd -P)
DATA_DIR=$(cd -- "$APP_DIR/data" && pwd -P)
case "$BACKUP_DIR/" in "$DATA_DIR/"*) echo 'Backup destination must be outside data/' >&2; exit 2;; esac
stamp=$(date -u +'%Y-%m-%dT%H%M%S-%NZ')
name="cobol-ledger-${stamp}.tar.gz"
staging=$(mktemp -d "${BACKUP_DIR}/.snapshot.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
exec 9>>"$DATA_DIR/.ledger.lock"
if (( EUID == 0 )); then
    chown --reference="$DATA_DIR" "/proc/$$/fd/9"
fi
flock -x -w 30 9
for database in ledger.dat ledger.dat.1 sessions.dat lockout.dat; do
    if [[ -e $DATA_DIR/$database ]]; then
        [[ -f $DATA_DIR/$database && ! -L $DATA_DIR/$database ]] || exit 2
        db5.3_verify -q "$DATA_DIR/$database"
    fi
done
# Python's tarfile avoids GNU tar/openat2 incompatibility with RestrictSUIDSGID.
python3 - "$APP_DIR" "$staging/$name" <<'PYSNAPSHOT'
from pathlib import Path
import sys, tarfile
app = Path(sys.argv[1])
def include(member):
    if member.name == "data/.ledger.lock" or member.name == "data/backups" or member.name.startswith("data/backups/"):
        return None
    if not (member.isfile() or member.isdir()):
        raise RuntimeError("Snapshot refuses links and special files")
    return member
with tarfile.open(sys.argv[2], "w:gz") as archive:
    archive.add(app / "data", arcname="data", filter=include)
PYSNAPSHOT
flock -u 9
gzip -t "$staging/$name"
python3 - "$staging/$name" "$staging" <<'PYEXTRACT'
import sys, tarfile
with tarfile.open(sys.argv[1]) as archive:
    archive.extractall(sys.argv[2], filter="data")
PYEXTRACT
for database in ledger.dat ledger.dat.1 sessions.dat lockout.dat; do
    if [[ -f $staging/data/$database ]]; then
        db5.3_verify -q "$staging/data/$database"
    fi
done
(cd -- "$staging" && sha256sum "$name" > "$name.sha256")
mv -- "$staging/$name" "$BACKUP_DIR/$name"
mv -- "$staging/$name.sha256" "$BACKUP_DIR/$name.sha256"
find "$BACKUP_DIR" -xdev -maxdepth 1 -type f \
    \( -name 'cobol-ledger-*.tar.gz' -o -name 'cobol-ledger-*.tar.gz.sha256' \) \
    -mtime +"$RETENTION_DAYS" -delete
printf 'Verified backup: %s/%s\n' "$BACKUP_DIR" "$name"
