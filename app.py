from flask import Flask, request, Response
import subprocess
import os

app = Flask(__name__)

# Calea absolută este critică
BIN_PATH = "/home/micu/cobol/ledger.cgi"

@app.route("/", methods=["GET", "POST"])
def index():
    # Asiguram acces la binarele GnuCOBOL in mediu (calea /usr/bin)
    env = os.environ.copy()
    env["REQUEST_METHOD"] = request.method
    env["QUERY_STRING"] = request.query_string.decode("utf-8")
    env["HTTP_COOKIE"] = request.headers.get("Cookie", "")
    
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
            cwd="/home/micu/cobol"
        )
        stdout, stderr = process.communicate(input=input_data)
        
        raw_output = stdout.decode(errors="ignore")
        
        headers = []
        body = raw_output
        if "\n\n" in raw_output:
            head_part, body = raw_output.split("\n\n", 1)
            for line in head_part.split("\n"):
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers.append((k.strip(), v.strip()))
        
        return Response(body, headers=headers, mimetype="text/html")
    except Exception as e:
        return f"Eroare COBOL: {str(e)}", 500
