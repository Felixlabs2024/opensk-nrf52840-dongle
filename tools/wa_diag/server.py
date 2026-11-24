import http.server
import json
import os
import socket
import threading

BASE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(BASE, "diag.log")
PORT = 8765


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE, **kwargs)

    def _send_body(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0") or 0)
        body = self.rfile.read(n).decode("utf-8", "replace")
        try:
            parsed = json.loads(body)
            line = json.dumps(parsed, ensure_ascii=False)
            print("DIAG " + line, flush=True)
        except Exception:
            line = body
            print("DIAG-RAW " + body, flush=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
            f.flush()
        self._send_body(204, "")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", ""):
            path = "/index.html"
        name = path.lstrip("/").replace("/", os.sep)
        fp = os.path.join(BASE, name)
        if os.path.isfile(fp):
            with open(fp, "rb") as f:
                data = f.read()
            ctype = "text/html; charset=utf-8" if fp.endswith(".html") else "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send_body(404, "not found")

    def log_message(self, *args):
        pass


class ServerV4(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    address_family = socket.AF_INET


class ServerV6(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        super().server_bind()


def serve(server, label):
    print("LISTEN " + label, flush=True)
    server.serve_forever()


v4 = ServerV4(("127.0.0.1", PORT), Handler)
threading.Thread(target=serve, args=(v4, "127.0.0.1:" + str(PORT)), daemon=True).start()

try:
    v6 = ServerV6(("::1", PORT), Handler)
    threading.Thread(target=serve, args=(v6, "[::1]:" + str(PORT)), daemon=True).start()
except OSError as e:
    print("v6 bind skipped: %s" % e, flush=True)

print("SERVING http://localhost:%d" % PORT, flush=True)
threading.Event().wait()
