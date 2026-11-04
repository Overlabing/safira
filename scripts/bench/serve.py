#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Antonin Carlin
"""Serves the frozen pages on 127.0.0.1 and logs every request, so a run can show that the pages and their files
were fetched and that nothing failed.

    python3 -I scripts/bench/serve.py <fixtures folder> <log file> [port]

Prints the port on the first line (0 asks the system for a free one), then serves until it is killed. The log is a CSV:
unix time, status, bytes, path.
"""
import functools
import http.server
import os
import sys
import time
import urllib.parse


class Handler(http.server.SimpleHTTPRequestHandler):
    log_file = None

    def log_message(self, format, *args):  # noqa: A002
        pass

    def log_request(self, code="-", size="-"):
        with open(self.log_file, "a") as log:
            log.write(f"{time.time():.3f},{code},{size},{self.path}\n")

    def translate_path(self, path):
        # wget saves `load.php?lang=en` under that exact name, with an extension added when it knew the type.
        local = super().translate_path(urllib.parse.unquote(path.split("#", 1)[0]).replace("?", "\0", 1)).replace("\0", "?")
        if not os.path.exists(local):
            for suffix in (".css", ".html", ".js"):
                if os.path.exists(local + suffix):
                    return local + suffix
        return local

    def guess_type(self, path):
        if "only=scripts" in path or "modules=startup" in path:
            return "text/javascript"
        if "only=styles" in path:
            return "text/css"
        return super().guess_type(path)

    def do_POST(self):
        # Analytics beacons of the copied pages: absorbed, so they do not count as failures of the server.
        self.send_response(204)
        self.end_headers()

    def end_headers(self):
        self.send_header("Cache-Control", "max-age=3600")
        super().end_headers()


def main():
    root, log_file = sys.argv[1], sys.argv[2]
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    Handler.log_file = log_file
    open(log_file, "w").write("time,status,bytes,path\n")
    handler = functools.partial(Handler, directory=root)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()


main()
