from flask import Flask, Response
import subprocess
import os

app = Flask(__name__)

@app.route("/")
def index():
    # Executăm binarul COBOL
    # Notă: Am compilat ledger.cgi anterior
    result = subprocess.run(["./ledger.cgi"], capture_output=True, text=True)
    
    # Binarul scoate 'Content-type: text/html\n\n' la început. 
    # Îl tăiem pentru a lăsa Flask să pună propriile headere sau îl folosim pe cel original.
    full_output = result.stdout
    parts = full_output.split("\n\n", 1)
    
    if len(parts) > 1:
        body = parts[1]
    else:
        body = full_output
        
    return Response(body, mimetype="text/html")

if __name__ == "__main__":
    app.run(port=8888)
