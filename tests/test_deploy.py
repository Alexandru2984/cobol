"""Exercise real deployment control flow with disposable repos and fake services."""
import os
from pathlib import Path
import shutil
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("recovery_fails", [False, True])
def test_failed_readiness_rolls_back_or_preserves_recovery_gate(tmp_path, recovery_fails):
    source = tmp_path / "app"
    source.mkdir()
    (source / "data").mkdir()
    shutil.copy2(ROOT / "deploy.sh", source / "deploy.sh")
    for name in ("app.py", "security.py", "ledger.cbl", "sha256.cbl", "seed.cbl", "requirements.txt"):
        (source / name).touch()
    (source / "tests").mkdir()
    (source / "tests/.keep").touch()
    subprocess.run(["git", "init", "-q", str(source)], check=True)
    subprocess.run(["git", "-C", str(source), "add", "."], check=True)
    subprocess.run(["git", "-C", str(source), "-c", "user.name=Test", "-c", "user.email=test@example.test",
                    "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], check=True)
    releases = tmp_path / "releases"
    baseline = releases / "baseline"
    baseline.mkdir(parents=True)
    (baseline / "app.py").touch()
    (baseline / "ledger.cgi").write_text("#!/bin/sh\nexit 0\n")
    (baseline / "ledger.cgi").chmod(0o700)
    runtime = tmp_path / "runtime"
    (runtime / "bin").mkdir(parents=True)
    (runtime / "bin/python").write_text("#!/bin/sh\nexit 0\n")
    (runtime / "bin/python").chmod(0o700)
    (baseline / "runtime").symlink_to(runtime)
    (releases / "current").symlink_to(baseline)
    commands = tmp_path / "commands"
    commands.mkdir()
    scripts = {
        "sudo": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_DEPLOY_LOG"\nexit 0\n',
        "curl": "#!/bin/sh\nexit 22\n",
        "sleep": "#!/bin/sh\nexit 0\n",
        "cobc": '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\nif [ "$1" = -o ]; then\nshift\n'
                'printf \'#!/bin/sh\\nif [ "$LEDGER_RECOVER_ONLY" = 1 ] && [ "$TEST_RECOVERY_FAILS" = 1 ]; then exit 1; fi\\nexit 0\\n\' > "$1"\n'
                'chmod 700 "$1"\nexit 0\nfi\nshift\ndone\nexit 1\n',
    }
    for name, text in scripts.items():
        (commands / name).write_text(text)
        (commands / name).chmod(0o700)
    log = tmp_path / "calls.log"
    env = {**os.environ, "PATH": str(commands) + ":" + os.environ["PATH"], "LEDGER_DEPLOY_ROOT": str(tmp_path),
           "LEDGER_SERVICE": "isolated-test.service", "TEST_DEPLOY_LOG": str(log),
           "TEST_RECOVERY_FAILS": str(int(recovery_fails))}
    result = subprocess.run([str(source / "deploy.sh")], env=env, capture_output=True, text=True)
    assert result.returncode != 0
    marker = source / "data/.deploying"
    if recovery_fails:
        assert marker.exists()
        assert (releases / "current").resolve() != baseline
        assert "Recovery failed" in result.stderr
    else:
        assert not marker.exists()
        assert (releases / "current").resolve() == baseline
        assert "Rolled back" in result.stderr
        assert {p.name for p in releases.iterdir()} == {"baseline", "current", ".deploy.lock"}
