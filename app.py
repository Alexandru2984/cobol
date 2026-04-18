from flask import Flask, request, Response
import subprocess
import os

app = Flask(__name__)

# Calea absolută către binarul nostru
BIN_PATH = "/home/micu/cobol/ledger.cgi"
# Ne asigurăm că directorul de date există
os.makedirs("/home/micu/cobol/data", exist_ok=True)

@app.route("/", methods=["GET", "POST"])
def index():
    # Pregătim variabilele de mediu pentru CGI
    env = os.environ.copy()
    env["REQUEST_METHOD"] = request.method
    
    # Dacă este POST, trimitem datele către binar
    input_data = None
    if request.method == "POST":
        input_data = request.get_data()
        env["CONTENT_LENGTH"] = str(len(input_data))
    else:
        env["CONTENT_LENGTH"] = "0"

    # Executăm binarul COBOL
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
        
        if stderr:
            print(f"COBOL Error: {stderr.decode()}")

        # Extragem body-ul (sărim peste header-ul 'Content-type: text/html\n\n')
        output = stdout.decode(errors="ignore")
        parts = output.split("\n\n", 1)
        body = parts[1] if len(parts) > 1 else output
        
        return Response(body, mimetype="text/html")
    except Exception as e:
        return f"Eroare Server (COBOL Wrapper): {str(e)}", 500

if __name__ == "__main__":
    app.run(port=8888)
