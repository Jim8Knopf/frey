#!/usr/bin/env python3
"""Regression tests for the captive-portal auto-accept decision logic.

    scripts/test-portal-logic.py

Runs offline: it renders `roles/network_gateway/templates/frey-uplink-portal.py.j2`
with a test context and exercises the rendered module. No Pi, no network, no
portal needed - which is the point, because the live portal cannot be used as
a test. Once the uplink is authorised every probe returns 'full', and the van
has usually driven away before anyone wants to retest.

What these cover is the half that matters: that a click-through page is
submitted correctly, and that everything else is REFUSED rather than guessed.
Pass a path to a rendered script to test that instead of the template:

    scripts/test-portal-logic.py /usr/local/sbin/frey-uplink-portal
"""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(
    HERE, os.pardir, "roles", "network_gateway", "templates", "frey-uplink-portal.py.j2"
)

# Mirrors roles/network_gateway/defaults/main.yml. Only the values the template
# actually interpolates; the logic under test does not depend on them.
CONTEXT = {
    "network_gateway": {
        "upstream": {
            "interface": "wlan1",
            "portal": {
                "state_dir": "/var/lib/frey/uplink-portal",
                "textfile_dir": "/opt/frey/metrics/textfile",
                "request_timeout_seconds": 10,
                "max_attempts_per_window": 3,
                "attempt_window_seconds": 1800,
                "keep_captures": 5,
                "allow_insecure_tls": True,
                "user_agent": "Mozilla/5.0 test",
                "allowlist": ["APNK Library"],
                "probes": [
                    {
                        "url": "http://connectivitycheck.gstatic.com/generate_204",
                        "expect_status": 204,
                        "expect_body": "",
                    }
                ],
            },
        }
    }
}


def load_module():
    if len(sys.argv) > 1:
        path = sys.argv[1]
        print("testing rendered script: %s" % path)
    else:
        try:
            from jinja2 import Environment, FileSystemLoader
        except ImportError:
            sys.exit("jinja2 missing: pass a rendered script path instead")
        folder, name = os.path.split(os.path.abspath(TEMPLATE))
        env = Environment(loader=FileSystemLoader(folder), keep_trailing_newline=True)
        # `to_json` is an Ansible filter, not a Jinja2 one.
        env.filters["to_json"] = json.dumps
        rendered = env.get_template(name).render(**CONTEXT)
        handle = tempfile.NamedTemporaryFile(
            "w", suffix=".py", delete=False, prefix="frey-portal-"
        )
        handle.write(rendered)
        handle.close()
        path = handle.name
        print("testing rendered template: %s" % TEMPLATE)

    spec = importlib.util.spec_from_file_location("frey_portal_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


portal = load_module()
failures = []


def check(name, cond, detail=""):
    if cond:
        print("  PASS  %s" % name)
    else:
        print("  FAIL  %s %s" % (name, detail))
        failures.append(name)


def forms_of(html):
    parser = portal.FormParser()
    parser.feed(html)
    return parser.forms


print("== 1. click-through: terms box + Accept, alongside a marketing box ==")
HTML_CLICK = """
<html><body><h1>Library Free WiFi</h1>
<form method="post" action="/auth/login">
  <input type="hidden" name="csrf_token" value="abc123">
  <input type="hidden" name="redirect_url" value="http://example.com/">
  <input type="checkbox" name="accept_terms" id="accept_terms" value="yes">
  <label for="accept_terms">I agree to the terms of use</label>
  <input type="checkbox" name="newsletter_optin" value="1">
  <label>Email me offers</label>
  <input type="submit" name="action" value="Accept and Connect">
</form></body></html>
"""
forms = forms_of(HTML_CLICK)
check("one form parsed", len(forms) == 1, "got %d" % len(forms))
form, reason = portal.choose_form(forms)
check("form chosen", form is not None, "reason=%s" % reason)
if form:
    data = dict(portal.build_post(form))
    check("hidden csrf preserved", data.get("csrf_token") == "abc123", data)
    check("hidden redirect preserved", data.get("redirect_url") == "http://example.com/", data)
    check("terms box ticked", data.get("accept_terms") == "yes", data)
    check("marketing box NOT ticked", "newsletter_optin" not in data, data)
    check("submit pressed", data.get("action") == "Accept and Connect", data)

print("== 2. credentialed login refused (rule 3) ==")
form, reason = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/login">
        <input type="text" name="username">
        <input type="password" name="password">
        <input type="submit" value="Sign in"></form></body></html>"""
    )
)
check("refused", form is None, "chose a form anyway")
check("reason mentions password", bool(reason and "password" in reason.lower()), reason)

print("== 3. required field it cannot fill refused ==")
form, reason = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/go">
        <input type="text" name="room_number" required>
        <input type="checkbox" name="agree" value="1">
        <input type="submit" name="ok" value="Accept"></form></body></html>"""
    )
)
check("refused", form is None, "chose a form anyway")
check("reason names the field", bool(reason and "room_number" in reason), reason)

print("== 4. voucher-style login refused even with no password field ==")
form, reason = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/go">
        <input type="text" name="voucher_code">
        <input type="submit" name="ok" value="Connect"></form></body></html>"""
    )
)
check("refused", form is None, "chose a form anyway")

print("== 5. page with no form ==")
form, reason = portal.choose_form(forms_of("<html><body><p>Hello</p></body></html>"))
check("refused", form is None)

print("== 6. Accept beside Decline: press only Accept ==")
form, reason = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/go">
        <input type="hidden" name="sid" value="s1">
        <button type="submit" name="choice" value="decline">Decline</button>
        <button type="submit" name="choice" value="accept">I Agree</button>
        </form></body></html>"""
    )
)
check("form chosen", form is not None, "reason=%s" % reason)
if form:
    pairs = portal.build_post(form)
    choices = [v for k, v in pairs if k == "choice"]
    check("exactly one choice submitted", len(choices) == 1, pairs)
    check("and it is the accepting one", bool(choices) and choices[0] == "accept", pairs)

print("== 7. accept wording carried by <button> text, not value ==")
form, reason = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/go">
        <input type="hidden" name="t" value="1">
        <button type="submit" name="go">Continue to the internet</button>
        </form></body></html>"""
    )
)
check("form chosen from button text", form is not None, "reason=%s" % reason)

print("== 8. portal's own pre-checked default preserved ==")
form, _ = portal.choose_form(
    forms_of(
        """<html><body><form method="post" action="/go">
        <input type="checkbox" name="remember_me" value="1" checked>
        <input type="submit" name="ok" value="Accept"></form></body></html>"""
    )
)
if form:
    data = dict(portal.build_post(form))
    check("pre-checked box kept", data.get("remember_me") == "1", data)

print("== 9. locating the portal from meta refresh and JS ==")
found = portal.META_REFRESH.search(
    '<html><head><meta http-equiv="refresh" '
    'content="0; url=http://portal.example/welcome"></head></html>'
)
check("meta refresh matched", bool(found))
check(
    "meta url extracted",
    bool(found) and found.group(1) == "http://portal.example/welcome",
    found.group(1) if found else None,
)
found = portal.JS_REDIRECT.search(
    '<html><script>window.location="https://portal.example/login?mac=1";</script></html>'
)
check("js redirect matched", bool(found))
check(
    "js url extracted",
    bool(found) and found.group(1) == "https://portal.example/login?mac=1",
    found.group(1) if found else None,
)

print()
if failures:
    print("FAILED: %d of the above" % len(failures))
    for name in failures:
        print("  - %s" % name)
    sys.exit(1)
print("ALL PASS")
