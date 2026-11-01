import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('group_sync', Path(__file__).parents[1] / 'files/group-sync.py')
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class ReconcileTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.saved = []

    def call(self, method, path, body):
        self.calls.append((method, path, body))

    def save(self, state):
        self.saved.append(dict(state['users']))

    def test_provisions_admins_and_writers_and_preserves_other_members(self):
        groups = {'frey_admins': [{'id': 'jim', 'email': 'jim@frey'}],
                  'notes': [{'id': 'ada', 'email': 'ada@frey'}]}
        state = {'users': {}}
        sync.reconcile(groups, 'provider', {}, 'space',
                       {'members': {'existing': {'role': 'read'}}},
                       state, self.call, self.save)
        creates = [body for method, path, body in self.calls if path == '/users']
        self.assertEqual({x['username']: x['admin'] for x in creates},
                         {'frey_jim': True, 'frey_ada': False})
        members = self.calls[-1][2]['members']
        self.assertEqual(members['existing'], {'role': 'read'})
        self.assertEqual(members['frey_ada'], {'role': 'write', 'runtimeApi': False})
        self.assertNotIn('frey_jim', members)
        self.assertEqual(len(self.saved), 2)

    def test_disables_removed_users_without_touching_local_admin(self):
        state = {'users': {'frey_old': 'old@frey'}}
        users = {'frey_old': {'admin': True, 'disabled': False,
                             'sso': {'providerId': 'p', 'expectedEmail': 'old@frey'}},
                 'note_admin': {'admin': True}}
        sync.reconcile({'notes': [], 'frey_admins': []}, 'p', users, 's',
                       {'members': {'frey_old': {'role': 'write'}, 'other': {'role': 'read'}}},
                       state, self.call, self.save)
        self.assertIn(('POST', '/users/frey_old/disabled', {'disabled': True}), self.calls)
        self.assertEqual(self.calls[-1][2]['members'], {'other': {'role': 'read'}})
        self.assertFalse(any('note_admin' in path for _, path, _ in self.calls))

    def test_collision_aborts_before_any_changes(self):
        groups = {'notes': [{'id': 'jim', 'email': 'jim@frey'}], 'frey_admins': []}
        with self.assertRaises(ValueError):
            sync.reconcile(groups, 'p', {'frey_jim': {}}, 's', {}, {'users': {}}, self.call, self.save)
        self.assertEqual(self.calls, [])

    def test_demotion_changes_admin_and_assigns_editor(self):
        groups = {'notes': [{'id': 'jim', 'email': 'jim@frey'}], 'frey_admins': []}
        users = {'frey_jim': {'admin': True, 'disabled': False,
                              'sso': {'providerId': 'p', 'expectedEmail': 'jim@frey'}}}
        sync.reconcile(groups, 'p', users, 's', {}, {'users': {'frey_jim': 'jim@frey'}},
                       self.call, self.save)
        self.assertIn(('PUT', '/users/frey_jim', {'admin': False}), self.calls)
        self.assertEqual(self.calls[-1][2]['members']['frey_jim']['role'], 'write')

    def test_changed_email_aborts_before_changes(self):
        groups = {'notes': [{'id': 'jim', 'email': 'new@frey'}], 'frey_admins': []}
        with self.assertRaises(ValueError):
            sync.reconcile(groups, 'p', {}, 's', {}, {'users': {'frey_jim': 'old@frey'}},
                           self.call, self.save)
        self.assertEqual(self.calls, [])

    def test_missing_group_fails_closed(self):
        with self.assertRaises(KeyError):
            sync.desired_users({'notes': []})

    def test_service_login_uses_central_login_and_keeps_session_in_memory(self):
        class Headers(dict):
            def get_all(self, name, default=None):
                return self.get(name, default)

        class Response:
            def __init__(self, headers, body=b''):
                self.headers, self.body = Headers(headers), body
            def read(self):
                return self.body
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass

        class Opener:
            def open(self, req, timeout):
                path = req.full_url.split(':3000', 1)[1]
                if path.startswith('/.auth/central/start'):
                    assert '%2F.dashboard' in path
                    return Response({'Location': 'https://silverbullet.hub.frey/.auth/central/login?attempt=abc',
                                     'Set-Cookie': ['sb_attempt_abc=binding; Path=/; Secure']})
                if path.startswith('/.auth/central/login'):
                    return Response({'Set-Cookie': ['sb_central_abc=central; Path=/; Secure']})
                if path.startswith('/.auth/central/context'):
                    self.assert_cookies(req)
                    return Response({}, json.dumps({'csrf': 'csrf-value'}).encode())
                if path == '/.auth/central/local':
                    self.assert_cookies(req)
                    data = json.loads(req.data)
                    assert data['username'] == 'note_admin' and data['csrf'] == 'csrf-value'
                    return Response({'Set-Cookie': ['auth_silverbullet_hub_frey=session; Path=/; Secure']}, b'{}')
                raise AssertionError(path)
            @staticmethod
            def assert_cookies(req):
                assert 'sb_central_abc=central' in req.get_header('Cookie')

        with patch.object(sync.urllib.request, 'build_opener', return_value=Opener()):
            cookie = sync.service_login('http://127.0.0.1:3000', 'silverbullet.hub.frey', 'secret')
        self.assertEqual(cookie, 'auth_silverbullet_hub_frey=session')


if __name__ == '__main__':
    unittest.main()
