#!/usr/bin/env python3
"""GitHub Actions Mesh Runner — HTTP command server with idle timeout.
Runs inside a GitHub Actions job. Exposes POST /exec for remote commands.
Self-terminates after 600s of idle time."""
import subprocess, json, time, os, threading
from http.server import HTTPServer, BaseHTTPRequestHandler

LAST_ACTIVE = time.time()
IDLE_TIMEOUT = 600  # 10 minutes

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        global LAST_ACTIVE
        if self.path == '/exec':
            try:
                length = int(self.headers.get('Content-Length', 0))
                body = json.loads(self.rfile.read(length))
                cmd = body.get('command', '')
                timeout = body.get('timeout', 300)
                
                result = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True, timeout=timeout
                )
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'stdout': result.stdout,
                    'stderr': result.stderr,
                    'exit_code': result.returncode
                }).encode())
                LAST_ACTIVE = time.time()
            except subprocess.TimeoutExpired:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'stdout': '',
                    'stderr': f'Command timed out after {timeout}s',
                    'exit_code': 124
                }).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'stdout': '',
                    'stderr': str(e),
                    'exit_code': 1
                }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'ok')
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *args):
        pass  # Silence access logs

def idle_monitor():
    """Terminate the process if no commands received within IDLE_TIMEOUT."""
    while True:
        time.sleep(30)
        idle_secs = time.time() - LAST_ACTIVE
        if idle_secs > IDLE_TIMEOUT:
            print(f"IDLE_TIMEOUT: {int(idle_secs)}s idle — shutting down runner")
            os._exit(0)

if __name__ == '__main__':
    threading.Thread(target=idle_monitor, daemon=True).start()
    server = HTTPServer(('0.0.0.0', 8080), Handler)
    print("Mesh runner ready — listening on :8080")
    server.serve_forever()
