import http.server
import os

class CGIHandler(http.server.CGIHTTPRequestHandler):
    def is_cgi(self):
        if self.path.endswith(".cgi"):
            self.cgi_info = '', self.path[1:]
            return True
        return False

# Ne asigurăm că fișierele CGI au drept de execuție
os.chmod("ledger.cgi", 0o755)
os.chmod("hello.cgi", 0o755)

port = 8080
print(f"Server pornit la http://localhost:{port}")
http.server.HTTPServer(('', port), CGIHandler).serve_forever()
