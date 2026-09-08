"""Exercise the probe with a fake curl; never contact a controller."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="unifibar-probe-") as temporary:
    curl = Path(temporary) / "curl"
    curl.write_text('''#!/usr/bin/env python3
import sys
args = sys.argv[1:]
assert args[0] == "--disable"
assert "--globoff" in args
assert "--proto" in args and args[args.index("--proto") + 1] == "=https"
assert "--connect-timeout" in args and "--max-time" in args
assert "-k" not in args and "-sk" not in args and "--insecure" not in args
assert "--header" in args and args[args.index("--header") + 1] == "@-"
assert not any("synthetic-key" in arg for arg in args)
assert sys.stdin.read() == "X-API-KEY: synthetic-key\\n"
url = args[-1]
if url.endswith("rogueap"):
    assert "POST" in args and '{"within":24}' in args
else:
    assert url.endswith(("rest/dynamicdns", "stat/portforward"))
print('{"fixture":true}\\n__HTTP_CODE__200')
''')
    curl.chmod(0o755)
    env = {**os.environ, "PATH": f"{temporary}:{os.environ['PATH']}", "UNIFIBAR_API_KEY": "synthetic-key"}
    def run(args, key="synthetic-key"):
        return subprocess.run(["bash", str(ROOT / "Scripts/probe_endpoints.sh"), *args],
                              env={**env, "UNIFIBAR_API_KEY": key}, capture_output=True, text=True, timeout=10)
    result = run(["https://fixture.invalid"])
    assert result.returncode == 0, result.stderr
    assert result.stdout.count("HTTP 200") == 3
    result = run(["https://{fixture.invalid,other.invalid}"])
    assert result.returncode == 0, result.stderr
    for args, key in [([], "synthetic-key"), (["http://fixture.invalid"], "synthetic-key"),
                      (["https://"], "synthetic-key"), (["https://user:pass@fixture.invalid"], "synthetic-key"),
                      (["https://fixture.invalid?x=y"], "synthetic-key"),
                      (["https://fixture.invalid", "extra"], "synthetic-key"),
                      (["https://fixture.invalid"], "injected\r\nheader"), (["https://fixture.invalid"], "")]:
        assert run(args, key).returncode == 2, args
print("PASS: probe TLS, bounded requests, private header transport, endpoints and invalid inputs")
