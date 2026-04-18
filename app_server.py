import http.server
import os

class MyCGIHandler(http.server.CGIHTTPRequestHandler):
    def is_cgi(self):
        # Interpretăm orice fișier .cgi ca fiind un CGI
        if self.path.endswith(".cgi"):
            # Setăm cgi_info corect pentru ca serverul să-l poată executa
            self.cgi_info = os.path.dirname(self.path), os.path.basename(self.path)
            return True
        return False

# Asigurăm drepturi de execuție
os.chmod("ledger.cgi", 0o755)

port = 8001
server = http.server.HTTPServer(('', port), MyCGIHandler)
print(f"Ledger of Ages porneste la http://localhost:{port}/ledger.cgi")
server.serve_forever()
