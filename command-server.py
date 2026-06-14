#!/usr/bin/env python3
"""GitHub Actions Mesh Runner — HTTP command server with idle timeout.
Runs inside a GitHub Actions job. Exposes POST /exec for remote commands.
Self-terminates after 600s idle, announcing departure to mesh registry."""
import subprocess, json, time, os, threading, urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

LAST_ACTIVE = time.time()
IDLE_TIMEOUT = 600  # 10 minutes

# Set by the workflow environment
NODE_ID = os.environ.get('RUNNER_NODE_ID', '')
REGISTRY_URL = os.environ.get('REGISTRY_URL', 'https://devblock-mesh-registry.devblocktechnologies.workers.dev')
REGISTRATION_TOKEN = os.environ.get('REGISTRATION_TOKEN', '')

def cleanup():
    """Announce shutdown to mesh registry so Sage removes us from the mesh."""
    print(f"CLEANUP: deregistering {NODE_ID} from mesh...")
    try:
        # 1. Mark registration as processed (removes from KV)
        req = urllib.request.Request(
            f"{REGISTRY_URL}/processed/{NODE_ID}", method='POST'
        )
        req.add_header('X-Registration-Token', REGISTRATION_TOKEN)
        urllib.request.urlopen(req, timeout=10)
        print("  -> /processed OK")
    except Exception as e:
        print(f"  -> /processed failed: {e}")

    try:
        # 2. Send deregister marker so health check removes us from mesh.json
        deregister_payload = json.dumps({
            "node_id": NODE_ID,
            "action": "deregister",
            "hostname": os.environ.get('HOSTNAME', 'gh-runner'),
            "os": "github-actions",
            "arch": "x86_64",
            "role": "compute",
            "provider": "github-actions",
            "capabilities": [],
            "access": {"type": "http"},
            "provisioned": False,
            "notes": f"Runner self-terminated {time.strftime('%Y-%m-%dT%H:%M:%SZ')}"
        }).encode()
        req2 = urllib.request.Request(
            f"{REGISTRY_URL}/register", data=deregister_payload, method='POST'
        )
        req2.add_header('Content-Type', 'application/json')
        req2.add_header('X-Registration-Token', REGISTRATION_TOKEN)
        urllib.request.urlopen(req2, timeout=10)
        print("  -> deregister OK")
    except Exception as e:
        print(f"  -> deregister failed: {e}")

    # 3. Wait a moment for requests to land, then exit
    time.sleep(2)

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
                    'stdout': result.stdout, 'stderr': result.stderr,
                    'exit_code': result.returncode
                }).encode())
                LAST_ACTIVE = time.time()
            except subprocess.TimeoutExpired:
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'stdout': '', 'stderr': f'Command timed out after {timeout}s',
                    'exit_code': 124
                }).encode())
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({
                    'stdout': '', 'stderr': str(e), 'exit_code': 1
                }).encode())
        elif self.path == '/shutdown':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'shutting down')
            threading.Thread(target=self._delayed_shutdown).start()
        else:
            self.send_response(404)
            self.end_headers()

    def _delayed_shutdown(self):
        time.sleep(1)
        cleanup()
        os._exit(0)

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
        pass

def idle_monitor():
    """Terminate after IDLE_TIMEOUT seconds of inactivity."""
    while True:
        time.sleep(30)
        idle_secs = time.time() - LAST_ACTIVE
        if idle_secs > IDLE_TIMEOUT:
            print(f"IDLE_TIMEOUT: {int(idle_secs)}s idle — cleaning up")
            cleanup()
            os._exit(0)

if __name__ == '__main__':
    threading.Thread(target=idle_monitor, daemon=True).start()
    server = HTTPServer(('0.0.0.0', 8080), Handler)
    print(f"Mesh runner {NODE_ID} ready — listening on :8080")
    server.serve_forever()
