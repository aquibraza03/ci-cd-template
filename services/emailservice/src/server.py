import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


SERVICE_NAME = os.environ.get("SERVICE_NAME", "emailservice")
SERVICE_PORT = int(os.environ.get("SERVICE_PORT") or os.environ.get("PORT", "8080"))


def build_response(method, path, query=""):
    if method != "GET":
        return 405, {"error": "method_not_allowed"}

    if path == "/health":
        return 200, {"status": "ok", "service": SERVICE_NAME}

    if path == "/ready":
        return 200, {"status": "ready", "mode": "mock"}

    if path == "/":
        return 200, {
            "service": SERVICE_NAME,
            "mode": "mock",
            "protocol": "http",
            "sourceProtocol": "grpc",
        }

    if path == "/send":
        params = parse_qs(query)
        recipient = params.get("to", ["customer@example.com"])[0]
        order_id = params.get("order", ["demo-order"])[0]
        return 200, {
            "status": "accepted",
            "recipient": recipient,
            "orderId": order_id,
            "message": "Mock order confirmation email accepted",
        }

    return 404, {"error": "not_found"}


class EmailHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        status, payload = build_response("GET", parsed.path, parsed.query)
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print("%s - %s" % (SERVICE_NAME, fmt % args))


def main():
    server = ThreadingHTTPServer(("0.0.0.0", SERVICE_PORT), EmailHandler)
    print(f"{SERVICE_NAME} listening on 0.0.0.0:{SERVICE_PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
