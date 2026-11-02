#!/usr/bin/env python3
"""A stand-in UntrashOS NAS on 127.0.0.1 for the app's integration tests.

  python3 tool/nas_fixture.py [UNTRASHOS_DIR]

Runs the real untrash-mesh (UntrashOS repository) in its PC test mode: own
state directory, WireGuard faked as a JSON file, mesh addresses mapped to
local ports (ZT_MESH_ADDRMAP). Creates a mesh, makes an app invitation for
the Desk user "alice" and prints one JSON line:

  {"invitation", "sync", "join", "dir", "mesh", "nas_pub"}

Then it reads commands from stdin, one per line, and answers with one JSON
line each:
  status              untrash-mesh status
  addrmap {json}      map mesh addresses to "127.0.0.1:port" for the daemon
  remove <node>       remove a member (as the NAS admin)
  rename <name>       rename the NAS (a new node record)
EOF on stdin stops the daemon and removes the state.
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

OS = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                     os.path.expanduser("~/Projects/UntrashOS-v1.1/untrashos"))
TOOL = os.path.join(OS, "image/rootfs/usr/lib/untrash/untrash-mesh")


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    p = s.getsockname()[1]
    s.close()
    return p


def main():
    w = tempfile.mkdtemp(prefix="ut-app-nas-")
    sig = os.path.join(w, "zt-sig")
    subprocess.run(["gcc", "-O2", "-I" + os.path.join(OS, "third_party/tweetnacl"), "-o", sig,
                    os.path.join(OS, "slot/zt-sig.c"), os.path.join(OS, "third_party/tweetnacl/tweetnacl.c")], check=True)
    sync, join = free_port(), free_port()
    open(w + "/ep", "w").write("192.0.2.10:51820")
    open(w + "/hosts", "w").write("")
    open(w + "/addrmap", "w").write("{}")
    env = dict(os.environ, ZT_MESH_DIR=w + "/state", ZT_SIG=sig, ZT_MESH_FAKE_WG=w + "/wg.json",
               ZT_MESH_ADDRMAP=w + "/addrmap", ZT_MESH_JOIN_HOST="127.0.0.1", ZT_MESH_ENDPOINTS=w + "/ep",
               ZT_MESH_SYNC_PORT=str(sync), ZT_MESH_JOIN_PORT=str(join), ZT_MESH_HOSTS=w + "/hosts",
               ZT_MESH_TICK="0.5", ZT_UPNPC="/nonexistent/upnpc", ZT_FAKE_UPNP_STATE=w + "/router.json",
               ZT_MESH_SMB=w + "/smb.conf", ZT_MESH_PDATA=w + "/p-data", ZT_MESH_FAKE_MOUNT=w + "/mounts.json",
               ZT_MESH_FAKE_ACCOUNTS=w + "/accounts.json", ZT_MESH_FAKE_DRBD=w + "/drbd.json",
               ZT_MESH_HOST_MNT=w + "/no-host")

    def cli(*a):
        r = subprocess.run([TOOL] + list(a), env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            return json.loads(r.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            return {"error": r.stdout}

    cli("rename", "nas-one")
    st = cli("create", "Test Mesh")
    proc = subprocess.Popen([TOOL, "run"], env=env, stdout=open(w + "/log", "a"), stderr=subprocess.STDOUT)
    try:
        def wait_port(port):
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", port), 0.2).close()
                    return
                except OSError:
                    time.sleep(0.1)
        wait_port(sync)
        inv = cli("invite", "1", "alice")
        wait_port(join)                            # opened while an invitation is open
        me = json.load(open(w + "/state/mesh.json"))
        pub = open(w + "/state/node.pub", "rb").read().hex()
        print(json.dumps({"invitation": inv.get("invitation"), "sync": sync, "join": join, "dir": w,
                          "mesh": me["mesh"]["id"], "nas_pub": pub, "status": st}), flush=True)
        for line in sys.stdin:
            cmd, _, arg = line.strip().partition(" ")
            if cmd == "status":
                out = cli("status")
            elif cmd == "addrmap":
                open(w + "/addrmap", "w").write(arg)
                out = {"ok": True}
            elif cmd == "remove":
                out = cli("remove", arg)
            elif cmd == "rename":
                out = cli("rename", arg)
            elif cmd == "files":
                out = {n: json.load(open(os.path.join(w, "state", n))) for n in ("mesh.json", "book.json", "apps.json")
                       if os.path.exists(os.path.join(w, "state", n))}
            else:
                out = {"error": "unknown command"}
            print(json.dumps(out), flush=True)
    finally:
        proc.terminate()
        proc.wait(5)
        shutil.rmtree(w, ignore_errors=True)


if __name__ == "__main__":
    main()
