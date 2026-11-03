#!/usr/bin/env python3
"""A NAS plus a mesh directory (the Nextcloud side) on 127.0.0.1 for the
app's directory tests (cloud-api.md §2).

  python3 tool/dir_fixture.py [UNTRASHOS_DIR] [--nextcloud]

--nextcloud: the directory is a real Nextcloud 30 with the UntrashOS app
(UNTRASHOS_DIR/nextcloud/untrash) in Docker (sudo -n docker, host network,
container ut-nc-app on port 18081, removed at the end), joined with
`occ untrash:join`; as nextcloud/tests/test_nextcloud_docker.py does it.

The real untrash-mesh in its PC test mode (as tool/nas_fixture.py) creates
a mesh; the reference directory image/tests/mesh-directory-ref (the
stand-in for the Nextcloud app, same merge rules) joins it with a cloud
invitation and serves POST <dir>/v1/sync. Then an app invitation for the
Desk user "alice". Prints one JSON line:

  {"invitation", "sync", "dir_url", "nas_node", "cloud_node"}

Commands on stdin, one JSON answer line each:
  endpoints A,B      the NAS's own endpoints change (it pushes a new record)
  dirbook            the directory's address book
  nasbook            the NAS's address book
  stopnas            stop the NAS daemon (the app must find it through the directory)
EOF stops everything and removes the state.
"""
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
NEXTCLOUD = "--nextcloud" in sys.argv
OS = os.path.abspath(ARGS[0] if ARGS else os.path.expanduser("~/Projects/UntrashOS-v1.2/untrashos"))
NC, NC_PORT = "ut-nc-app", 18081
OCC = ["sudo", "-n", "docker", "exec", "-u", "www-data", NC, "php", "occ", "--no-ansi"]


def nextcloud_up():
    """Nextcloud 30 with the UntrashOS app, SQLite, admin password only for this throwaway container."""
    subprocess.run(["sudo", "-n", "docker", "rm", "-f", NC], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["sudo", "-n", "docker", "run", "-d", "--name", NC, "--network", "host", "-e", "SQLITE_DATABASE=nc",
                    "-e", "NEXTCLOUD_ADMIN_USER=admin", "-e", "NEXTCLOUD_ADMIN_PASSWORD=untrash-test-admin",
                    "-e", "NEXTCLOUD_TRUSTED_DOMAINS=127.0.0.1 localhost",
                    "-v", os.path.join(OS, "nextcloud/untrash") + ":/untrash-app:ro", "--entrypoint", "sh",
                    "nextcloud:30-apache", "-c",
                    "sed -i 's/^Listen 80$/Listen %d/' /etc/apache2/ports.conf && "
                    "sed -i 's/:80>/:%d>/' /etc/apache2/sites-enabled/000-default.conf && "
                    "exec /entrypoint.sh apache2-foreground" % (NC_PORT, NC_PORT)],
                   check=True, stdout=subprocess.DEVNULL)
    import urllib.request
    for _ in range(100):
        try:
            if b'"installed":true' in urllib.request.urlopen("http://127.0.0.1:%d/status.php" % NC_PORT, timeout=3).read():
                break
        except OSError:
            pass
        time.sleep(3)
    else:
        raise SystemExit("nextcloud did not come up")
    subprocess.run(["sudo", "-n", "docker", "exec", NC, "sh", "-c",
                    "cp -r /untrash-app /var/www/html/custom_apps/untrash && chown -R www-data: /var/www/html/custom_apps/untrash"],
                   check=True)
    subprocess.run(OCC + ["config:system:set", "overwrite.cli.url", "--value", "http://127.0.0.1:%d" % NC_PORT],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(OCC + ["app:enable", "untrash"], check=True, stdout=subprocess.DEVNULL)
TOOL = os.path.join(OS, "image/rootfs/usr/lib/untrash/untrash-mesh")
REF = os.path.join(OS, "image/tests/mesh-directory-ref")


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


def jf(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return {}


def main():
    w = tempfile.mkdtemp(prefix="ut-app-dir-")
    procs = []
    try:
        sig = os.path.join(w, "zt-sig")
        subprocess.run(["gcc", "-O2", "-I" + os.path.join(OS, "third_party/tweetnacl"), "-o", sig,
                        os.path.join(OS, "slot/zt-sig.c"), os.path.join(OS, "third_party/tweetnacl/tweetnacl.c")],
                       check=True)
        sync, join, dport = free_port(), free_port(), free_port()
        n = w + "/nas"
        os.makedirs(n)
        open(n + "/ep", "w").write("192.0.2.10:51820")
        open(n + "/hosts", "w").write("")
        open(n + "/addrmap", "w").write("{}")
        env = dict(os.environ, ZT_MESH_DIR=n + "/state", ZT_SIG=sig, ZT_MESH_FAKE_WG=n + "/wg.json",
                   ZT_MESH_ADDRMAP=n + "/addrmap", ZT_MESH_JOIN_HOST="127.0.0.1", ZT_MESH_ENDPOINTS=n + "/ep",
                   ZT_MESH_SYNC_PORT=str(sync), ZT_MESH_JOIN_PORT=str(join), ZT_MESH_HOSTS=n + "/hosts",
                   ZT_MESH_TICK="0.5", ZT_MESH_DIR_EVERY="1", ZT_UPNPC="/nonexistent/upnpc",
                   ZT_FAKE_UPNP_STATE=n + "/router.json", ZT_MESH_SMB=n + "/smb.conf", ZT_MESH_PDATA=n + "/p-data",
                   ZT_MESH_FAKE_MOUNT=n + "/mounts.json", ZT_MESH_FAKE_ACCOUNTS=n + "/accounts.json",
                   ZT_MESH_FAKE_DRBD=n + "/drbd.json", ZT_MESH_HOST_MNT=n + "/no-host")
        c = w + "/cloud"
        os.makedirs(c)
        open(c + "/hosts", "w").write("")
        open(c + "/addrmap", "w").write("{}")
        dir_url = "http://127.0.0.1:%d/" % dport
        cenv = dict(os.environ, ZT_MESH_DIR=c + "/state", ZT_SIG=sig, ZT_MESH_DIR_URL=dir_url,
                    ZT_MESH_FAKE_WG=c + "/wg.json", ZT_MESH_HOSTS=c + "/hosts", ZT_MESH_ADDRMAP=c + "/addrmap",
                    ZT_MESH_KIND="cloud", ZT_DIR_TEST_YOU="198.51.100.7")

        def cli(e, *a, tool=TOOL):
            r = subprocess.run([tool] + list(a), env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                return json.loads(r.stdout.strip().splitlines()[-1])
            except (ValueError, IndexError):
                return {"error": r.stdout}

        def spawn(cmd, e, log):
            procs.append(subprocess.Popen(cmd, env=e, stdout=open(log, "a"), stderr=subprocess.STDOUT))
            return procs[-1]

        cli(env, "rename", "nas-one")
        st = cli(env, "create", "Test Mesh")
        nas = spawn([TOOL, "run"], env, n + "/log")
        wait_port(sync)
        if NEXTCLOUD:
            nextcloud_up()
            inv = cli(env, "invite-cloud", "1", "[]")
            wait_port(join)
            r = subprocess.run(OCC + ["untrash:join", inv["invitation"], "--name", "nc-test"],
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            assert r.returncode == 0, r.stdout
            ncs = json.loads(subprocess.run(OCC + ["untrash:status"], stdout=subprocess.PIPE, text=True).stdout)
            dir_url = "http://127.0.0.1:%d/index.php/apps/untrash/mesh" % NC_PORT
            mine = [k for k, m in (json.load(open(n + "/state/mesh.json"))["roster"]["members"]).items()
                    if m.get("kind") == "cloud"]
            sc = {"node": mine[0] if mine else None, "status": ncs}
        else:
            inv = cli(env, "invite-cloud", "1", json.dumps(["Photos"]))
            wait_port(join)
            cli(cenv, "rename", "nextcloud")
            sc = cli(cenv, "join", inv["invitation"], tool=REF)
            assert sc.get("node"), sc
            spawn([REF, "run", str(dport)], cenv, c + "/log")
            wait_port(dport)
        app = cli(env, "invite", "1", "alice")
        print(json.dumps({"invitation": app.get("invitation"), "sync": sync, "dir_url": dir_url,
                          "nas_node": st.get("node"), "cloud_node": sc["node"], "dir": w}), flush=True)
        for line in sys.stdin:
            cmd, _, arg = line.strip().partition(" ")
            if cmd == "endpoints":
                open(n + "/ep", "w").write(arg)
                out = {"ok": True}
            elif cmd == "dirbook":
                out = jf(c + "/state/book.json")
            elif cmd == "nasbook":
                out = jf(n + "/state/book.json")
            elif cmd == "stopnas":
                nas.terminate()
                nas.wait(5)
                out = {"ok": True}
            else:
                out = {"error": "unknown command"}
            print(json.dumps(out), flush=True)
    finally:
        if NEXTCLOUD:
            subprocess.run(["sudo", "-n", "docker", "rm", "-f", NC], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
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
