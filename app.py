"""WSGI wrapper: expune binarul COBOL CGI (ledger.cgi) printr-un app Flask.

Fiecare request este tradus in variabile de mediu CGI si trimis catre
binarul compilat cu GnuCOBOL. Raspunsul (headere + body) este parsat
si returnat clientului. Configurare prin variabile de mediu:

    LEDGER_BIN  - calea catre binarul CGI (default: ledger.cgi de langa app.py)
    LEDGER_DIR  - working directory pentru binar; aici sta data/ (default: dirul app.py)
"""

from flask import Flask, request, Response, jsonify
import logging
import os
import subprocess

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
BIN_PATH = os.environ.get("LEDGER_BIN", os.path.join(BASE_DIR, "ledger.cgi"))
WORK_DIR = os.environ.get("LEDGER_DIR", BASE_DIR)
SUBPROCESS_TIMEOUT = 20  # secunde; sub timeout-ul gunicorn (30)

logger = logging.getLogger("ledger")
logging.basicConfig(level=logging.INFO)


@app.route("/health")
def health():
    """Endpoint pentru monitoring: verifica binarul si directorul de date."""
    checks = {
        "binary": os.access(BIN_PATH, os.X_OK),
        "data_dir": os.path.isdir(os.path.join(WORK_DIR, "data")),
    }
    ok = all(checks.values())
    return jsonify(status="ok" if ok else "degraded", checks=checks), (
        200 if ok else 503
    )


@app.route("/", methods=["GET", "POST"])
def index():
    env = os.environ.copy()
    env["REQUEST_METHOD"] = request.method
    env["QUERY_STRING"] = request.query_string.decode("utf-8")
    env["HTTP_COOKIE"] = request.headers.get("Cookie", "")
    # IP-ul real al clientului, setat de nginx; folosit in jurnalul de audit.
    env["REMOTE_ADDR"] = request.headers.get(
        "X-Real-IP", request.remote_addr or "-"
    )

    input_data = None
    if request.method == "POST":
        input_data = request.get_data()
        env["CONTENT_LENGTH"] = str(len(input_data))
    else:
        env["CONTENT_LENGTH"] = "0"

    try:
        process = subprocess.Popen(
            [BIN_PATH],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd=WORK_DIR,
        )
        stdout, stderr = process.communicate(
            input=input_data, timeout=SUBPROCESS_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        process.kill()
        logger.error("ledger.cgi timeout after %ss", SUBPROCESS_TIMEOUT)
        return "Eroare: backend-ul COBOL nu a raspuns la timp.", 504
    except OSError as e:
        logger.error("ledger.cgi could not be executed: %s", e)
        return "Eroare: backend-ul COBOL nu este disponibil.", 502

    if stderr:
        logger.warning("ledger.cgi stderr: %s", stderr.decode(errors="ignore").strip())
    if process.returncode != 0:
        logger.error("ledger.cgi exit code %s", process.returncode)
        return "Eroare: backend-ul COBOL a esuat.", 502

    raw_output = stdout.decode(errors="ignore")

    headers = []
    body = raw_output
    separator = None
    for sep in ("\r\n\r\n", "\n\n", "\n \n"):
        if sep in raw_output:
            separator = sep
            break
    if separator:
        head_part, body = raw_output.split(separator, 1)
        for line in head_part.replace("\r\n", "\n").split("\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                headers.append((k.strip(), v.strip()))

    status = 200
    content_type = "text/html; charset=utf-8"
    filtered_headers = []
    for k, v in headers:
        if k.lower() == "content-type":
            content_type = v
        elif k.lower() == "status":
            try:
                status = int(v.split()[0])
            except ValueError:
                pass
        else:
            filtered_headers.append((k, v))

    return Response(body, status=status, headers=filtered_headers,
                    content_type=content_type)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
