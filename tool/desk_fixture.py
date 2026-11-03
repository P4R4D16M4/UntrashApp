#!/usr/bin/env python3
"""A stand-in UntrashOS Desk + UntrashMesh on 127.0.0.1 for the app's tests.

  python3 tool/desk_fixture.py [UNTRASHOS_DIR]

Uses the UntrashOS Desk test root (image/tests/test-desk-host.py: users
admin/alice/bob, password "test-passwort", system commands only recorded)
and runs the real untrash-desk and untrash-mesh daemons on free local ports.
The admin creates a mesh and pairs the app for alice (or UT_FIXTURE_USER)
through the Desk API, as an admin would in the browser. Prints one JSON line:

  {"invitation", "desk", "sync", "dir"}

Commands on stdin, one JSON answer line each:
  signin <user> <mode>   the user sets the sign-in (password|app|both)
  login-app <user>       a new browser asks to sign in without password
  login <user>           a new browser signs in with the password
  poll <id>              that browser's request state and /api/me
EOF stops everything and removes the test root.
"""
import importlib.machinery
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import types

OS = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                     os.path.expanduser("~/Projects/UntrashOS-v1.2/untrashos"))
TESTS = os.path.join(OS, "image/tests")
LIB = os.path.join(OS, "image/rootfs/usr/lib/untrash")


def load_desk_test():
    sys.path.insert(0, TESTS)
    loader = importlib.machinery.SourceFileLoader("desk_host", os.path.join(TESTS, "test-desk-host.py"))
    mod = types.ModuleType("desk_host")
    mod.__file__ = loader.path
    loader.exec_module(mod)
    return mod


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def wait_port(port, tries=150):
    for _ in range(tries):
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close()
            return True
        except OSError:
            time.sleep(0.1)
    return False


def main():
    t = load_desk_test()
    w = tempfile.mkdtemp(prefix="ut-app-desk-")
    procs = []
    try:
        r, stick = t.build_root(w)
        desk, sync, join = free_port(), free_port(), free_port()
        env = dict(t.env_for(r, stick, desk), ZT_MESH_SYNC_PORT=str(sync), ZT_MESH_JOIN_PORT=str(join),
                   ZT_MESH_TICK="0.5", ZT_UPNPC="/nonexistent/upnpc")
        log = open(w + "/log", "a")
        procs.append(subprocess.Popen([sys.executable, os.path.join(LIB, "untrash-desk")], env=env,
                                      stdout=log, stderr=subprocess.STDOUT))
        if not wait_port(desk):
            raise SystemExit("desk did not start: " + open(w + "/log").read()[-2000:])
        admin = t.Client(desk)
        assert admin.req("/api/login", {"user": "admin", "password": t.PW})[0] == 200
        st, mj = admin.req("/api/mesh/create", {"name": "Test Mesh"})
        assert st == 200, mj
        procs.append(subprocess.Popen([os.path.join(LIB, "untrash-mesh"), "run"], env=env,
                                      stdout=log, stderr=subprocess.STDOUT))
        wait_port(sync)
        st, pj = admin.req("/api/mesh/pair", {"user": os.environ.get("UT_FIXTURE_USER", "alice"), "hours": 1})
        assert st == 200, pj
        print(json.dumps({"invitation": pj["invitation"], "desk": desk, "sync": sync, "dir": w}), flush=True)

        browsers = {}
        for line in sys.stdin:
            cmd, *a = line.split()
            try:
                if cmd == "signin":
                    c = t.Client(desk)
                    c.req("/api/login", {"user": a[0], "password": t.PW})
                    out = c.req("/api/signin", {"mode": a[1], "password": t.PW})[1]
                elif cmd == "login-app":
                    c = t.Client(desk)
                    out = c.req("/api/login/app", {"user": a[0]})[1]
                    browsers[out["id"]] = c
                elif cmd == "login":
                    c = t.Client(desk)
                    out = c.req("/api/login", {"user": a[0], "password": t.PW})[1]
                    if "second" in out:
                        browsers[out["second"]] = c
                elif cmd == "poll":
                    c = browsers[a[0]]
                    out = {"state": c.req("/api/login/app?id=" + a[0])[1].get("state"),
                           "me": c.req("/api/me")[1]}
                    if not isinstance(out["me"], dict):
                        out["me"] = {}
                else:
                    out = {"error": "unknown command"}
            except Exception as e:                  # noqa: BLE001 - reported to the test
                out = {"error": repr(e)}
            print(json.dumps(out), flush=True)
    finally:
        for p in procs:
            p.terminate()
        for p in procs:
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()
        shutil.rmtree(w, ignore_errors=True)


if __name__ == "__main__":
    main()
