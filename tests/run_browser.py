"""Run the optional real-browser smoke suite against disposable COBOL data."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen

root = Path(__file__).resolve().parents[1]
artifacts = Path(os.environ.get("LEDGER_SCREENSHOT_DIR", str(root / "artifacts"))).resolve()
artifacts.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="ledger-browser-") as scratch:
    work = Path(scratch)
    (work / "data").mkdir(mode=0o700)
    subprocess.run(["cobc", "-x", "-free", "-I", str(root), str(root / "ledger.cbl"), str(root / "sha256.cbl"),
                    "-o", str(work / "ledger.cgi")], check=True)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "PYTHONPATH": str(root), "LEDGER_BIN": str(work / "ledger.cgi"),
           "LEDGER_DIR": str(work), "LEDGER_USER": "tester", "LEDGER_PASS": "test-only-password",
           "LEDGER_CSRF_SECRET": "browser-test-only-secret-at-least-32-bytes",
           "LEDGER_PUBLIC_ORIGIN": base}
    env.pop("LEDGER_PASSWORD_HASH", None)
    env.pop("LEDGER_PASS_HASH", None)
    with (work / "server.log").open("w") as log:
        server = subprocess.Popen([sys.executable, "-c",
            f"from app import app; app.run(host='127.0.0.1',port={port})"],
            cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(50):
                if server.poll() is not None:
                    raise RuntimeError((work / "server.log").read_text())
                try:
                    with urlopen(base + "/health", timeout=0.3) as response:
                        if response.status == 200:
                            break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("Disposable server did not become ready")
            subprocess.run(["node", str(root / "tests/browser_smoke.cjs")], check=True,
                env={**os.environ, "LEDGER_TEST_URL": base, "LEDGER_SCREENSHOT_DIR": str(artifacts)})
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
print(f"Browser screenshots: {artifacts}")
