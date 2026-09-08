#!/usr/bin/env python3
"""Opt-in direct-host checks; stdlib only. No real controller, credentials or app launch.

Resources are UUID-scoped, never execution isolation. Exit 2 retains unavailable
protected-backend cleanup. Ordinary Scripts/check.sh never invokes this file.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-synthetic-native-checks", action="store_true", required=True)
    parser.add_argument("--only", choices=["storage", "transport", "ui", "all"], default="all")
    args = parser.parse_args()
    if os.uname().sysname != "Darwin":
        parser.error("native fixtures require macOS")
    os.umask(0o077)
    if not (ROOT / ".build").resolve().is_relative_to(ROOT):
        parser.error(".build must resolve inside this repository")
    run_id = str(uuid.uuid4())
    state = ROOT / ".build" / ("remaining-native-" + run_id)
    state.mkdir(mode=0o700)
    print(state, flush=True)
    records = []

    def run(command, label, timeout=60, accepted=(0,)):
        path = state / (label + ".log")
        started = time.monotonic()
        with path.open("w") as log:
            process = subprocess.Popen(list(map(str, command)), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                process.terminate()  # This Popen object owns the child; never match process names.
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                code = 124
        records.append(dict(command=list(map(str, command)), log=path.name, exit=code,
                            seconds=round(time.monotonic() - started, 2), pid=process.pid))
        print(f"{label}: exit {code}", flush=True)
        if code not in accepted:
            raise RuntimeError(f"{label} failed: {path.read_text()[-6000:]}")
        return path.read_text(), code

    binary = state / "native-audit"
    sources = sorted(p for p in (ROOT / "Sources/UniFiBar").rglob("*.swift") if "App" not in p.relative_to(ROOT / "Sources/UniFiBar").parts)
    fixtures = sorted((ROOT / "Tests/NativeAudit").glob("*.swift"))
    def hashes():
        return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in [*sources, *fixtures, Path(__file__).resolve()]}
    source_hashes = hashes()
    (state / "source-hashes.json").write_text(json.dumps(source_hashes, indent=2) + "\n")
    run(["swiftc", "-parse-as-library", "-swift-version", "6", "-module-name", "NativeAudit", *sources, *fixtures,
         "-o", binary], "compile", timeout=180)
    cmd = [binary, "--synthetic-native-audit"]
    blocked = False
    failures = []
    try:
        if args.only in ("storage", "all"):
            try:
                for mode in ["create", "restart"]:
                    run([*cmd, "storage-" + mode, run_id], "storage-" + mode)
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    futures = [pool.submit(run, [*cmd, "storage-pin-race", run_id, n], f"storage-race-{n}") for n in (4, 5)]
                    outputs = [future.result()[0] for future in futures]
                if sum("WINNER=" in output for output in outputs) != 1:
                    raise RuntimeError("cross-process pin race did not have exactly one winner")
                with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                    futures = [pool.submit(run, [*cmd, "storage-credential-writer", run_id, n], f"storage-credential-{n}") for n in (6, 7)]
                    outputs = [future.result()[0] for future in futures]
                if not any("WRITE_VERIFIED=" in output for output in outputs):
                    raise RuntimeError("no credential writer verified its write")
                run([*cmd, "storage-credential-read", run_id], "storage-credential-read")
                for mode in ["race-read", "intent", "intent-read"]:
                    run([*cmd, "storage-" + mode, run_id], "storage-" + mode)
            except Exception as error:
                failures.append(str(error))
            finally:
                try:
                    _, code = run([*cmd, "storage-cleanup", run_id], "storage-cleanup", accepted=(0, 2))
                    blocked |= code == 2
                except Exception as error:
                    failures.append(str(error))
        if args.only in ("transport", "all"):
            transport(state, run, cmd, run_id, failures)
        if args.only in ("ui", "all"):
            try:
                run([*cmd, "ui", run_id], "ui", timeout=60)
            except Exception as error:
                failures.append(str(error))
            finally:
                try:
                    run([*cmd, "ui-cleanup", run_id], "ui-cleanup")
                except Exception as error:
                    failures.append(str(error))
    finally:
        unchanged = source_hashes == hashes()
        if not unchanged:
            failures.append("source changed during native checks; rerun before claiming final-source verification")
        (state / "results.json").write_text(json.dumps(dict(id=run_id, commands=records, failures=failures,
            protected_cleanup_blocked=blocked, source_unchanged=unchanged), indent=2) + "\n")
    for failure in failures:
        print(failure)
    return 1 if failures else 2 if blocked else 0


class Server:
    """One loopback listener, at most four handlers and 64 requests, bounded I/O."""
    def __init__(self, cert, key):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        self.context = context
        self.socket = socket.socket()
        self.socket.bind(("127.0.0.1", 0))
        self.socket.listen(4)
        self.socket.settimeout(0.2)
        self.port = self.socket.getsockname()[1]
        self.cross_port = self.port
        self.stop = threading.Event()
        self.requests = []
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)
        self.thread = threading.Thread(target=self.serve)
        self.thread.start()

    def serve(self):
        count = 0
        while not self.stop.is_set() and count < 64:
            try:
                conn, _ = self.socket.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            count += 1
            self.pool.submit(self.handle, conn)

    def handle(self, raw):
        raw.settimeout(5)
        try:
            with self.context.wrap_socket(raw, server_side=True) as conn:
                data = b""
                while b"\r\n\r\n" not in data and len(data) <= 16384:
                    chunk = conn.recv(1024)
                    if not chunk:
                        return
                    data += chunk
                lines = data.decode("ascii").split("\r\n")
                path = lines[0].split()[1]
                headers = dict(line.split(": ", 1) for line in lines[1:] if ": " in line)
                self.requests.append(dict(path=path, key=headers.get("X-API-KEY")))
                if path in ("/same-origin", "/cross-origin", "/downgrade"):
                    scheme = "http" if path == "/downgrade" else "https"
                    port = self.port if path == "/same-origin" else self.cross_port
                    conn.sendall(f"HTTP/1.1 302 Found\r\nLocation: {scheme}://127.0.0.1:{port}/ok\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode())
                elif path in ("/timeout", "/cancel"):
                    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n200\r\n" + b"x" * 512 + b"\r\n")
                    self.stop.wait(6)
                elif path in ("/chunked", "/oversized", "/exact-limit"):
                    body = b"fixture-ok" if path == "/chunked" else b"x" * (1024 if path == "/exact-limit" else 1025)
                    conn.sendall(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
                    for i in range(0, len(body), 256):
                        chunk = body[i:i + 256]
                        conn.sendall(f"{len(chunk):x}\r\n".encode() + chunk + b"\r\n")
                    conn.sendall(b"0\r\n\r\n")
                elif path.startswith("/proxy/network/integration/v1/sites?"):
                    body = json.dumps(dict(data=[dict(id="fixture-site", internalReference="default")],
                                           count=1, offset=0, limit=200, totalCount=1)).encode()
                    conn.sendall(f"HTTP/1.1 200 OK\r\nContent-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode() + body)
                else:
                    body = b"x" * 1025 if path == "/declared-oversized" else b"fixture-ok"
                    length = 4 if path == "/understated" else 1025 if path == "/declared-oversized" else len(body)
                    conn.sendall(f"HTTP/1.1 200 OK\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n".encode() + body)
        except (OSError, ssl.SSLError):
            pass  # Expected rejected TLS/cancelled sockets; Swift asserts exact policy outcomes.
        finally:
            raw.close()

    def close(self):
        self.stop.set()
        self.socket.close()
        self.thread.join(timeout=8)
        self.pool.shutdown(wait=True)
        if self.thread.is_alive():
            raise RuntimeError("fixture listener did not stop")
        probe = socket.socket()
        probe.settimeout(1)
        try:
            if probe.connect_ex(("127.0.0.1", self.port)) == 0:
                raise RuntimeError("fixture port still listening")
        finally:
            probe.close()


def transport(state, run, cmd, run_id, failures):
    servers = []
    try:
        for name in ("valid", "bad-host", "expired", "sink"):
            folder = state / name
            folder.mkdir()
            config = folder / "openssl.cnf"
            config.write_text(f"""[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=fixture.invalid
[ext]
subjectAltName={"DNS:wrong.invalid" if name == "bad-host" else "IP:127.0.0.1"}
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
[ca]
default_ca=local
[local]
database={folder}/index
serial={folder}/serial
new_certs_dir={folder}
default_md=sha256
policy=policy
x509_extensions=ext
[policy]
commonName=supplied
""")
            key, cert = folder / "key.pem", folder / "cert.pem"
            run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                 "-days", "2", "-config", config], "cert-" + name)
            if name == "expired":
                (folder / "index").touch()
                (folder / "serial").write_text("01\n")
                csr = folder / "request.pem"
                run(["openssl", "req", "-new", "-key", key, "-out", csr, "-config", config], "expired-csr")
                old = folder / "old.pem"
                run(["openssl", "ca", "-batch", "-selfsign", "-keyfile", key, "-cert", cert,
                     "-in", csr, "-out", old, "-startdate", "20000101000000Z", "-enddate", "20010101000000Z",
                     "-config", config], "expired-sign")
                cert = old
            servers.append(Server(cert, key))
        valid, wrong, expired, sink = servers
        valid.cross_port = sink.port
        modes = ["valid", "continuity", "mismatch", "default-reject", "bad-host", "denied-bad-host", "approved-bad-host", "slow-approved-bad-host", "expired", "same-origin",
                 "cross-origin", "downgrade", "chunked", "understated", "oversized", "declared-oversized", "exact-limit", "cancel", "timeout"]
        for mode in modes:
            server = wrong if mode.endswith("bad-host") else expired if mode == "expired" else valid
            before = len(server.requests)
            try:
                run([*cmd, "transport-" + mode, run_id, server.port], "transport-" + mode, timeout=15)
            except Exception as error:
                failures.append(str(error))
            if mode in ("bad-host", "denied-bad-host", "expired") and len(server.requests) != before:
                failures.append(f"{mode} received a request before certificate approval")
        if sink.requests:
            failures.append("redirect destination received requests/keys")
        if not valid.requests or any(request["key"] != "synthetic-loopback-only" for request in valid.requests):
            failures.append("accepted fixture request lost/changed its synthetic API key")
        if len(wrong.requests) != 5 or any(request["key"] != "synthetic-loopback-only" for request in wrong.requests) or expired.requests:
            failures.append("only approved name mismatch and its pinned reconnection may receive requests/keys")
    finally:
        cleanup = []
        for server in servers:
            server.close()
            cleanup.append(dict(port=server.port, listener_closed=True, requests=server.requests))
        (state / "loopback.json").write_text(json.dumps(cleanup, indent=2) + "\n")
        # Synthetic private keys are disposable and never added to system trust/Keychain.
        for path in state.glob("*/key.pem"):
            path.unlink()


if __name__ == "__main__":
    raise SystemExit(main())
