#!/usr/bin/env python3
"""Offline tests for frey-media-dns-upstream's upstream selection.

WHY THIS EXISTS

The logic under test only does anything interesting on networks that are hard
to produce on demand: one that blocks outbound port 53 to every public
resolver, and the same one recovering. Getting it wrong is expensive - it
takes DNS away from every service in the acquisition stack at once - and you
cannot tell from the Pi, because the host keeps resolving perfectly while the
containers resolve nothing.

So the template is rendered here and driven against stub `docker`, `nmcli` and
`logger` commands, which makes every branch reachable without a Pi, a
container, or a hostile network.

    scripts/test-media-dns-upstream.py

Needs jinja2, which Ansible already requires. Run from the repo root.
"""

import os
import shutil
import subprocess
import sys
import tempfile

try:
    from jinja2 import Environment, FileSystemLoader
except ImportError:  # pragma: no cover
    sys.exit("jinja2 is required (it ships with Ansible): pip install jinja2")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TPL_DIR = os.path.join(REPO, "roles", "media_acquisition", "templates")
TPL = "frey-media-dns-upstream.sh.j2"

PREFERRED = ["9.9.9.9", "1.1.1.1", "8.8.8.8"]
UPLINK = ["172.20.1.15", "172.20.1.16"]
CONTAINER = "frey-media-dns"

# Stubs for the three commands the script shells out to. Each one is tiny on
# purpose: the point is to control exactly which resolvers "answer".
DOCKER_STUB = r"""#!/usr/bin/env bash
# Stub docker. ANSWERING holds the addresses that resolve; everything else
# fails the way a blackholed port 53 does.
case "$1" in
  inspect)
    echo "${RESOLVER_RUNNING:-true}"
    exit 0
    ;;
  restart)
    echo restart >> "${CALL_LOG}"
    exit 0
    ;;
  exec)
    # exec <container> timeout <n> nslookup <name> <addr>
    # exec <container> sh -c 'kill -HUP ...'
    if [[ "$*" == *nslookup* ]]; then
      addr="${!#}"
      echo "probe ${addr}" >> "${CALL_LOG}"
      for ok in ${ANSWERING}; do
        [ "${ok}" = "${addr}" ] && exit 0
      done
      exit 1
    fi
    if [[ "$*" == *kill* ]]; then
      echo sighup >> "${CALL_LOG}"
      exit "${SIGHUP_EXIT:-0}"
    fi
    exit 0
    ;;
esac
exit 0
"""

NMCLI_STUB = r"""#!/usr/bin/env bash
# Stub nmcli. Reproduces the real `-g IP4.DNS` output shape, which separates
# values with " | " rather than newlines - the detail the script has to handle.
echo "${UPLINK_DNS}"
"""

LOGGER_STUB = "#!/usr/bin/env bash\nexit 0\n"


def render(tmp):
    """Render the template with every path pointed inside tmp."""
    env = Environment(
        loader=FileSystemLoader(TPL_DIR),
        keep_trailing_newline=True,
        trim_blocks=True,
    )
    env.filters["bool"] = lambda v: (
        v.strip().lower() in ("true", "yes", "on", "1") if isinstance(v, str) else bool(v)
    )
    ctx = {
        "media_acquisition": {
            "dns": {
                "address": "172.28.255.53",
                "upstreams": PREFERRED,
                "fallback_to_uplink": True,
                "probe_name": "cloudflare.com",
                # 1s, not 3: the stub answers instantly, and a real timeout
                # here would only make the suite slow.
                "probe_timeout_seconds": 1,
                "servers_file": "/etc/dnsmasq.servers",
            },
            "services": {"resolver": {"container_name": CONTAINER}},
        },
        "media": {"appdata_dir": os.path.join(tmp, "appdata")},
        "frey": {"base_dir": os.path.join(tmp, "frey")},
        "network_gateway": {"upstream": {"interface": "wlan1"}},
    }
    path = os.path.join(tmp, "frey-media-dns-upstream")
    with open(path, "w") as fh:
        fh.write(env.get_template(TPL).render(**ctx))
    os.chmod(path, 0o755)
    return path


def write_stubs(tmp):
    stub_dir = os.path.join(tmp, "bin")
    os.makedirs(stub_dir, exist_ok=True)
    for name, body in (
        ("docker", DOCKER_STUB),
        ("nmcli", NMCLI_STUB),
        ("logger", LOGGER_STUB),
    ):
        path = os.path.join(stub_dir, name)
        with open(path, "w") as fh:
            fh.write(body)
        os.chmod(path, 0o755)
    return stub_dir


class Case:
    """One run of the script against a chosen network."""

    def __init__(self, tmp, answering, seed=None, resolver_running="true", sighup_exit="0"):
        self.tmp = tmp
        self.servers = os.path.join(tmp, "appdata", "resolver", "servers.conf")
        self.metric = os.path.join(tmp, "frey", "metrics", "textfile", "media_dns.prom")
        self.call_log = os.path.join(tmp, "calls")

        os.makedirs(os.path.dirname(self.servers), exist_ok=True)
        os.makedirs(os.path.dirname(self.metric), exist_ok=True)
        with open(self.servers, "w") as fh:
            fh.write("# seed\n")
            for addr in seed if seed is not None else PREFERRED:
                fh.write("server=%s\n" % addr)
        open(self.call_log, "w").close()

        self.script = render(tmp)
        stub_dir = write_stubs(tmp)
        self.env = dict(os.environ)
        self.env.update(
            PATH=stub_dir + os.pathsep + "/usr/bin" + os.pathsep + "/bin",
            ANSWERING=" ".join(answering),
            UPLINK_DNS=" | ".join(UPLINK),
            RESOLVER_RUNNING=resolver_running,
            SIGHUP_EXIT=sighup_exit,
            CALL_LOG=self.call_log,
            FREY_MEDIA_DNS_STATE_DIR=os.path.join(tmp, "state"),
        )

    def run(self, arg="apply"):
        proc = subprocess.run(
            [self.script, arg], env=self.env, capture_output=True, text=True, timeout=120
        )
        return proc

    @property
    def inode(self):
        return os.stat(self.servers).st_ino

    def servers_listed(self):
        with open(self.servers) as fh:
            return [
                line.strip().split("=", 1)[1]
                for line in fh
                if line.startswith("server=")
            ]

    def mode(self):
        if not os.path.exists(self.metric):
            return None
        with open(self.metric) as fh:
            for line in fh:
                if line.startswith("frey_media_dns_upstream_mode") and line.rstrip().endswith(" 1"):
                    return line.split('mode="', 1)[1].split('"', 1)[0]
        return None

    def calls(self):
        with open(self.call_log) as fh:
            return [line.strip() for line in fh if line.strip()]


FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s %s" % (name, detail))
        FAILURES.append(name)


def case(title):
    print("\n%s" % title)


def test_preferred_reachable():
    case("public resolvers reachable -> prefer ours, change nothing")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=PREFERRED + UPLINK)
        before = c.inode
        proc = c.run()
        check("exits 0", proc.returncode == 0, proc.stderr)
        check("mode is preferred", c.mode() == "preferred", c.mode())
        check("upstreams are ours", c.servers_listed() == PREFERRED, c.servers_listed())
        check("no reload needed", "sighup" not in c.calls(), c.calls())
        check("inode preserved", c.inode == before)
        check(
            "uplink resolvers never consulted",
            not any(u in " ".join(c.calls()) for u in UPLINK),
            c.calls(),
        )


def test_port53_blocked():
    case("port 53 blocked to public resolvers -> fall back to the uplink's")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=UPLINK)
        before = c.inode
        proc = c.run()
        check("exits 0", proc.returncode == 0, proc.stderr)
        check("mode is uplink", c.mode() == "uplink", c.mode())
        check("upstreams are the uplink's", c.servers_listed() == UPLINK, c.servers_listed())
        check("resolver reloaded", "sighup" in c.calls(), c.calls())
        check(
            "rewritten in place, inode preserved (the bind mount follows it)",
            c.inode == before,
        )


def test_partial_uplink():
    case("only one uplink resolver answers -> write only the one that does")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=[UPLINK[1]])
        c.run()
        check("mode is uplink", c.mode() == "uplink", c.mode())
        check("only the answering one", c.servers_listed() == [UPLINK[1]], c.servers_listed())


def test_nothing_answers():
    case("nothing answers at all -> keep ours so recovery is automatic")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=[])
        proc = c.run()
        check("exits 0", proc.returncode == 0, proc.stderr)
        check("mode is none", c.mode() == "none", c.mode())
        check("preferred list retained", c.servers_listed() == PREFERRED, c.servers_listed())
        check("no pointless reload", "sighup" not in c.calls(), c.calls())


def test_recovery():
    case("network recovers while on the fallback -> go back to ours")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=PREFERRED + UPLINK, seed=UPLINK)
        c.run()
        check("mode is preferred", c.mode() == "preferred", c.mode())
        check("back on ours", c.servers_listed() == PREFERRED, c.servers_listed())
        check("resolver reloaded", "sighup" in c.calls(), c.calls())


def test_idempotent():
    case("second run changes nothing (the acceptance test for any change here)")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=UPLINK)
        c.run()
        first = c.servers_listed()
        open(c.call_log, "w").close()
        c.run()
        check("same upstreams", c.servers_listed() == first, c.servers_listed())
        check("no second reload", "sighup" not in c.calls(), c.calls())


def test_resolver_down():
    case("resolver container down -> do nothing, say so, exit 0")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=PREFERRED, resolver_running="false")
        proc = c.run()
        check("exits 0", proc.returncode == 0, proc.stderr)
        check("no probes attempted", c.calls() == [], c.calls())


def test_sighup_falls_back_to_restart():
    case("SIGHUP fails -> restart the container instead of leaving it stale")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=UPLINK, sighup_exit="1")
        c.run()
        check("restart attempted", "restart" in c.calls(), c.calls())


def test_status_is_readonly():
    case("status reports without changing anything")
    with tempfile.TemporaryDirectory() as tmp:
        c = Case(tmp, answering=UPLINK)
        before = c.servers_listed()
        proc = c.run("status")
        check("exits 0", proc.returncode == 0, proc.stderr)
        check("mentions the uplink resolvers", UPLINK[0] in proc.stdout, proc.stdout)
        check("upstreams untouched", c.servers_listed() == before, c.servers_listed())
        check("no reload", "sighup" not in c.calls(), c.calls())


def main():
    if shutil.which("bash") is None:
        sys.exit("bash is required")
    for test in (
        test_preferred_reachable,
        test_port53_blocked,
        test_partial_uplink,
        test_nothing_answers,
        test_recovery,
        test_idempotent,
        test_resolver_down,
        test_sighup_falls_back_to_restart,
        test_status_is_readonly,
    ):
        test()

    print()
    if FAILURES:
        print("%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
