#!/usr/bin/env python3
"""Compile the production WebKit sandbox and verify requests against a local sink."""
import http.server
import pathlib
import subprocess
import tempfile
import threading
import urllib.request

root = pathlib.Path(__file__).resolve().parents[2]
requests = []


class Sink(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        requests.append(self.path)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"synthetic response")

    do_POST = do_GET

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(("localhost", 0), Sink)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    port = server.server_port
    with urllib.request.urlopen(f"http://localhost:{port}/positive-control") as response:
        assert response.read() == b"synthetic response"
    assert requests == ["/positive-control"]
    requests.clear()
    with tempfile.TemporaryDirectory(prefix="html-preview-", dir=root / "artifacts") as directory:
        binary = pathlib.Path(directory) / "sandbox-check"
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library",
            str(root / "apps/ios/MindFriendApp/Features/Chat/Markdown/HTMLPreviewSandbox.swift"),
            str(root / "scripts/tests/html_preview_sandbox.swift"), "-o", str(binary),
        ], check=True)
        subprocess.run([str(binary), str(port)], check=True, timeout=30)
    assert requests == ["/positive-webkit-control"], f"Unexpected WebKit requests: {requests!r}"
    print("PASS: WebKit positive control reached the listener; sandbox made zero requests")
finally:
    server.shutdown()
    server.server_close()
    thread.join()
