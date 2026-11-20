"""Render the real templates to prove the Subsonic bypass is narrow and guarded.

Four things have to hold at once for `subsonic_bypass` to be safe, and three of
them live in different files from the flag. They are asserted together here
because any one of them alone is not a safe configuration:

  * only /rest/ skips the session check, and only on Navidrome's host
  * the web interface stays behind Authelia for frey_admins
  * Navidrome's router still blanks a client-supplied Remote-User, ahead of
    forward auth, so a bypassed request cannot name itself an SSO user
  * the account can hold a password at all, and failed logins are rate limited
"""
from pathlib import Path
import unittest

from ansible.template import Templar, trust_as_template
from ansible.utils.vars import combine_vars
import yaml

ROOT = Path(__file__).resolve().parents[1]

SUBSONIC_RESOURCE = '^/rest([/?].*)?$'


def trusted(value):
    if isinstance(value, str):
        return trust_as_template(value)
    if isinstance(value, dict):
        return {k: trusted(v) for k, v in value.items()}
    if isinstance(value, list):
        return [trusted(v) for v in value]
    return value


class NavidromeSubsonicTest(unittest.TestCase):
    def setUp(self):
        paths = [ROOT / f'roles/{role}/defaults/main.yml' for role in ('identity', 'media_library')]
        paths += sorted(p for p in (ROOT / 'inventory/group_vars/all').glob('*.yml')
                        if p.name != 'secrets.yml')
        self.variables = {}
        for path in paths:
            self.variables = combine_vars(self.variables, yaml.safe_load(path.read_text()), merge=True)
        self.variables.update(
            identity_secrets={},
            media_secrets={'jellystat_postgres_password': 'test', 'jellystat_jwt_secret': 'test'})

    def render(self, path):
        return Templar(variables=trusted(self.variables)).template(
            trust_as_template((ROOT / path).read_text()))

    def authelia_access_control(self):
        # The rendered file is deliberately NOT valid YAML as a whole: every
        # secret is an Authelia `{{ secret "..." }}` directive its own config
        # filter resolves at startup. Only the access-control section is
        # parsed, which is the part this flag touches.
        rendered = self.render('roles/identity/templates/authelia-configuration.yml.j2')
        section = []
        for line in rendered.splitlines():
            if section and line and not line.startswith((' ', '#', '-')):
                break
            if line.startswith('access_control:') or section:
                section.append(line)
        return yaml.safe_load('\n'.join(section))['access_control']

    def compose(self):
        return yaml.safe_load(self.render('roles/media_library/templates/docker-compose.yml.j2'))

    def navidrome_rules(self):
        return [rule for rule in self.authelia_access_control()['rules']
                if rule['domain'] == 'navidrome.hub.frey']

    # -- the bypass itself ----------------------------------------------------

    def test_subsonic_bypass_precedes_the_policy_that_would_swallow_it(self):
        # Authelia stops at the first matching rule. Behind the host-wide
        # policy this rule is dead configuration that still reads as if it
        # works, so the ORDER is the assertion, not the presence.
        rules = self.navidrome_rules()
        bypass = next(i for i, r in enumerate(rules) if r['policy'] == 'bypass')
        policy = next(i for i, r in enumerate(rules) if r['policy'] != 'bypass')
        self.assertLess(bypass, policy)
        self.assertEqual(rules[bypass]['resources'], [SUBSONIC_RESOURCE])

    def test_the_web_interface_stays_behind_sso_for_admins_only(self):
        guarded = [r for r in self.navidrome_rules() if r['policy'] != 'bypass']
        self.assertEqual(len(guarded), 1)
        self.assertEqual(guarded[0]['policy'], 'one_factor')
        self.assertEqual(guarded[0]['subject'], ['group:frey_admins'])

    def test_no_other_service_is_given_the_subsonic_exemption(self):
        self.assertEqual(self.authelia_access_control()['default_policy'], 'deny')
        for rule in self.authelia_access_control()['rules']:
            if rule['domain'] == 'navidrome.hub.frey':
                continue
            self.assertNotIn(SUBSONIC_RESOURCE, rule.get('resources', []))

    def test_api_bypass_alone_would_not_cover_rest(self):
        # The reason this flag exists: /rest/ is not /api, /feed or /ping.
        services = self.variables['identity_services']
        self.assertNotIn('api_bypass', services['navidrome'])
        sonarr = [r for r in self.authelia_access_control()['rules']
                  if r['domain'] == 'sonarr.hub.frey' and r['policy'] == 'bypass']
        self.assertNotIn(SUBSONIC_RESOURCE, sonarr[0]['resources'])

    # -- what keeps it safe ---------------------------------------------------

    def test_rest_is_https_only_and_strips_client_identity_headers(self):
        protect = Templar(variables=trusted(self.variables)).template(
            trust_as_template('{{ identity_protect }}'))
        self.assertIn('navidrome', protect)

        labels = dict(label.split('=', 1) for label in self.compose()['services']['navidrome']['labels'])
        middlewares = labels['traefik.http.routers.navidrome.middlewares'].split(',')
        self.assertIn('drop-remote-user@file', middlewares)
        self.assertIn('authelia@file', middlewares)
        # Blanked BEFORE Authelia is asked, or Authelia's own answer would be
        # the thing being overwritten.
        self.assertLess(middlewares.index('drop-remote-user@file'),
                        middlewares.index('authelia@file'))
        # Plain HTTP must redirect, never serve: the exempt route would
        # otherwise carry a Subsonic password in cleartext.
        self.assertEqual(labels['traefik.http.routers.navidrome-http.middlewares'],
                         'to-canonical@file')

    def test_navidrome_is_reachable_only_from_traefiks_pinned_address(self):
        navidrome = self.compose()['services']['navidrome']
        self.assertIn('ND_EXTAUTH_TRUSTEDSOURCES=172.31.250.2/32', navidrome['environment'])
        self.assertEqual(list(navidrome['networks']), ['frey_navidrome_proxy'])
        self.assertNotIn('ports', navidrome)

    def test_failed_subsonic_logins_are_rate_limited(self):
        environment = self.compose()['services']['navidrome']['environment']
        limit = next(v for v in environment if v.startswith('ND_AUTHREQUESTLIMIT='))
        self.assertGreater(int(limit.split('=', 1)[1]), 0)
        self.assertIn('ND_AUTHWINDOWLENGTH=20s', environment)

    # -- the password the client needs ----------------------------------------

    def test_user_editing_follows_the_bypass_in_both_directions(self):
        self.assertIn('ND_ENABLEUSEREDITING=true',
                      self.compose()['services']['navidrome']['environment'])

        self.variables['identity_services']['navidrome'].pop('subsonic_bypass')
        self.assertIn('ND_ENABLEUSEREDITING=false',
                      self.compose()['services']['navidrome']['environment'])
        self.assertEqual([r for r in self.navidrome_rules() if r['policy'] == 'bypass'], [])

    def test_media_library_still_renders_with_identity_switched_off(self):
        self.variables['identity_services'] = {}
        navidrome = self.compose()['services']['navidrome']
        self.assertIn('ND_ENABLEUSEREDITING=false', navidrome['environment'])


if __name__ == '__main__':
    unittest.main()
