import http.client
import importlib.util
import json
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch

files = Path(__file__).parents[1] / 'files'
sys.path.insert(0, str(files))
config = {'token': 'private-token', 'origin': 'https://wifi.hub.frey', 'uplink': 'wlan1', 'downstream': 'wlan0'}
spec = importlib.util.spec_from_file_location('wifi_server', files / 'server.py')
server = importlib.util.module_from_spec(spec)
with patch.object(Path, 'read_text', return_value=json.dumps(config)):
    spec.loader.exec_module(server)


class ServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        cls.thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.thread.join()

    def request(self, method, path, headers=None, body=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.http.server_port, timeout=2)
        connection.request(method, path, body=body, headers=headers or {})
        result = connection.getresponse()
        status = result.status
        result.read()
        connection.close()
        return status

    def test_direct_backend_access_is_denied(self):
        with patch.object(server, 'saved_networks') as get:
            self.assertEqual(self.request('GET', '/api/networks'), 403)
            get.assert_not_called()

    def test_foreign_origin_cannot_connect(self):
        headers = {'X-Frey-Wifi-Token': 'private-token', 'Origin': 'https://evil.invalid', 'Content-Type': 'application/json'}
        with patch.object(server, 'connect_saved') as connect:
            self.assertEqual(self.request('POST', '/api/connect', headers, '{"uuid":"x"}'), 403)
            connect.assert_not_called()

    def test_authorized_request_is_scoped(self):
        headers = {'X-Frey-Wifi-Token': 'private-token', 'Origin': config['origin'], 'Content-Type': 'application/json'}
        with patch.object(server, 'connect_saved') as connect:
            self.assertEqual(self.request('POST', '/api/connect', headers, '{"uuid":"x"}'), 200)
            connect.assert_called_once_with('x', 'wlan1', 'wlan0')


if __name__ == '__main__':
    unittest.main()
