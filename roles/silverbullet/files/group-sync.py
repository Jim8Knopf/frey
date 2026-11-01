#!/usr/bin/env python3
"""Reconcile Frey directory groups with SilverBullet's supported admin API."""
import json
from http.cookies import SimpleCookie
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

BASE = Path(os.environ.get('FREY_BASE', '/opt/frey'))
ROOT = BASE / 'appdata/silverbullet-sync'
SERVICE_DOMAIN = os.environ.get('FREY_SERVICE_DOMAIN', 'hub.frey')
IDENTITY_NETWORK = os.environ.get('FREY_IDENTITY_NETWORK', 'identity_internal')
PROXY_NETWORK = os.environ.get('FREY_PROXY_NETWORK', 'frey_proxy')
SYNC_ADMIN = os.environ.get('FREY_NOTES_SYNC_ADMIN', 'note_admin')
STATE = ROOT / 'managed-users.json'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def address(container, network):
    fmt = '{{(index .NetworkSettings.Networks "' + network + '").IPAddress}}'
    value = subprocess.check_output(['docker', 'inspect', '-f', fmt, container], text=True).strip()
    if not re.fullmatch(r'[0-9.]+', value):
        raise ValueError('Container network address unavailable: ' + container)
    return value


def api(base, method, path, body=None, token=None, host=None, cookie=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if host:
        headers.update({'Host': host, 'X-Forwarded-Proto': 'https'})
    if cookie:
        headers['Cookie'] = cookie
    req = urllib.request.Request(base + path, method=method, headers=headers,
                                 data=None if body is None else json.dumps(body).encode())
    with OPENER.open(req, timeout=10) as response:
        if response.status == 204:
            return None
        return json.load(response)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def service_login(base, host, password):
    """Use SilverBullet's normal central-login flow, keeping cookies in memory."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    cookies = {}
    origin = 'https://' + host

    def request(method, path, body=None):
        headers = {'Host': host, 'X-Forwarded-Proto': 'https', 'Origin': origin,
                   'Content-Type': 'application/json'}
        if cookies:
            headers['Cookie'] = '; '.join(k + '=' + v for k, v in cookies.items())
        req = urllib.request.Request(base + path, method=method, headers=headers,
                                     data=None if body is None else json.dumps(body).encode())
        try:
            response = opener.open(req, timeout=10)
        except urllib.error.HTTPError as exc:
            if exc.code != 303:
                raise
            response = exc
        with response:
            for raw in response.headers.get_all('Set-Cookie', []):
                parsed = SimpleCookie()
                parsed.load(raw)
                cookies.update({k: v.value for k, v in parsed.items()})
            return response.headers, response.read()

    destination = urllib.parse.quote(origin + '/.dashboard', safe='')
    headers, _ = request('GET', '/.auth/central/start?destination=' + destination)
    attempt = urllib.parse.parse_qs(urllib.parse.urlparse(headers['Location']).query)['attempt'][0]
    query = '?attempt=' + urllib.parse.quote(attempt, safe='')
    request('GET', '/.auth/central/login' + query)
    _, body = request('GET', '/.auth/central/context' + query)
    context = json.loads(body)
    request('POST', '/.auth/central/local', {'attempt': attempt, 'csrf': context['csrf'],
            'username': SYNC_ADMIN, 'password': password})
    key = 'auth_' + re.sub(r'\W', '_', host)
    if key not in cookies:
        raise ValueError('SilverBullet did not issue a service session')
    return key + '=' + cookies[key]


def save_state(state):
    fd, name = tempfile.mkstemp(prefix='.managed-', dir=ROOT)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(state, f, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, STATE)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def directory_groups(base, password):
    session = api(base, 'POST', '/auth/simple/login',
                  {'username': 'authelia', 'password': password})
    result = api(base, 'POST', '/api/graphql',
                 {'query': 'query { groups { displayName users { id email } } }'}, session['token'])
    if result.get('errors'):
        raise ValueError('Directory query failed')
    groups = {g['displayName']: g['users'] for g in result['data']['groups']}
    if not {'notes', 'frey_admins'} <= groups.keys():
        raise ValueError('Required directory groups are missing; refusing to change permissions')
    return groups


def desired_users(groups):
    wanted = {}
    for group in ('notes', 'frey_admins'):
        for user in groups[group]:
            uid, email = user['id'], user['email']
            if not re.fullmatch(r'[a-zA-Z0-9_.-]+', uid) or not email or '@' not in email:
                raise ValueError('Invalid directory identity; refusing to change permissions')
            name = 'frey_' + uid.lower()
            if name in wanted and wanted[name]['email'].lower() != email.lower():
                raise ValueError('Conflicting directory identities; refusing to change permissions')
            record = wanted.setdefault(name, {'email': email, 'admin': False, 'notes': False})
            record['admin' if group == 'frey_admins' else 'notes'] = True
    emails = [u['email'].lower() for u in wanted.values()]
    if len(emails) != len(set(emails)):
        raise ValueError('Duplicate directory email; refusing to change permissions')
    return wanted


def reconcile(groups, provider, users, space_id, space, state, call, persist):
    wanted = desired_users(groups)
    managed = state.setdefault('users', {})
    # Never adopt or modify unrelated local or SSO users by name.
    for name, spec in wanted.items():
        if name in users and name not in managed:
            raise ValueError('SilverBullet account collision: ' + name)
        if name in managed and managed[name].lower() != spec['email'].lower():
            raise ValueError('Directory email changed for managed user: ' + name)
        for other, existing in users.items():
            sso = existing.get('sso') or {}
            if other != name and sso.get('providerId') == provider and sso.get('expectedEmail', '').lower() == spec['email'].lower():
                raise ValueError('Directory email already enrolled in another account: ' + other)
    for name in managed:
        if name in users:
            sso = users[name].get('sso') or {}
            if sso.get('providerId') != provider or sso.get('expectedEmail', '').lower() != managed[name].lower():
                raise ValueError('Managed account identity changed: ' + name)

    for name, spec in wanted.items():
        urlname = urllib.parse.quote(name, safe='')
        if name not in users:
            call('POST', '/users', {'username': name, 'loginMethod': 'sso',
                 'providerId': provider, 'expectedEmail': spec['email'],
                 'email': spec['email'], 'admin': spec['admin']})
            managed[name] = spec['email']
            try:
                persist(state)
            except OSError:
                # Do not leave an untracked account with administrator rights.
                call('POST', '/users/' + urlname + '/disabled', {'disabled': True})
                raise
            users[name] = {'admin': spec['admin'], 'disabled': False}
        if users[name].get('admin', False) != spec['admin']:
            call('PUT', '/users/' + urlname, {'admin': spec['admin']})
        if users[name].get('disabled', False):
            call('POST', '/users/' + urlname + '/disabled', {'disabled': False})

    # Revoke accounts we own when neither group contains them. Keep the account
    # so old references survive; the local recovery administrator is never owned.
    for name in set(managed) - set(wanted):
        if name in users and not users[name].get('disabled', False):
            call('POST', '/users/' + urllib.parse.quote(name, safe='') + '/disabled', {'disabled': True})

    members = dict(space.get('members') or {})
    before = dict(members)
    for name in managed:
        if name in wanted and wanted[name]['notes'] and not wanted[name]['admin']:
            members[name] = {'role': 'write', 'runtimeApi': False}
        else:
            members.pop(name, None)
    if members != before:
        call('PATCH', '/spaces/' + urllib.parse.quote(space_id, safe=''), {'members': members})


def main():
    if not (ROOT / 'admin-password').is_file():
        raise ValueError('SilverBullet sync credential is not provisioned')
    with open(BASE / 'appdata/identity/.identity-keys.json') as f:
        password = json.load(f)['authelia_ldap_password']
    groups = directory_groups('http://' + address('lldap', IDENTITY_NETWORK) + ':17170', password)
    password = (ROOT / 'admin-password').read_text().strip()
    server = 'http://' + address('silverbullet', PROXY_NETWORK) + ':3000'
    host = 'silverbullet.' + SERVICE_DOMAIN
    cookie = service_login(server, host, password)
    base = server + '/.dashboard/api/admin'
    def call(method, path, body=None):
        return api(base, method, path, body, host=host, cookie=cookie)
    try:
        status = call('GET', '/authentication')
        if not status.get('enabled') or not status.get('active'):
            raise ValueError('SilverBullet SSO is not active')
        if status['active']['issuer'] != 'https://auth.' + SERVICE_DOMAIN:
            raise ValueError('Unexpected SilverBullet identity provider')
        users = call('GET', '/users')
        spaces = call('GET', '/spaces')
        choices = [(key, value) for key, value in spaces.items() if value.get('name') == 'Notes']
        if len(choices) != 1:
            raise ValueError('Expected exactly one Notes space; no changes made')
        state = json.loads(STATE.read_text()) if STATE.exists() else {'users': {}}
        reconcile(groups, status['active']['providerId'], users, *choices[0], state, call, save_state)
    finally:
        api(server, 'POST', '/.auth/central/logout', {}, host=host, cookie=cookie)
    print('Frey notes group synchronization succeeded')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError, urllib.error.URLError) as exc:
        print('Frey notes group synchronization failed:', type(exc).__name__, str(exc), file=sys.stderr)
        sys.exit(1)
