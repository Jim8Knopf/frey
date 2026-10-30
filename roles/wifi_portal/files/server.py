"""Admin-only web interface for selecting an existing uplink profile."""
import hmac
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from uplink import UplinkError, connect_saved, saved_networks

CONFIG = json.loads(Path('/etc/frey-wifi-portal.json').read_text())
CONNECT_LOCK = threading.Lock()

PAGE = b'''<!doctype html><html lang="en"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Frey Wi-Fi</title><style>body{font:16px system-ui;background:#202938;color:#eee;max-width:42em;margin:3em auto;padding:0 1em}button{padding:.7em 1em;border:0;border-radius:.4em;background:#8cc4ca;color:#142029;cursor:pointer}li{margin:1em 0;display:flex;justify-content:space-between;gap:1em}#message{min-height:2em}</style><h1>Wi-Fi uplink</h1><p>Select a saved network. FreyHub stays available while the uplink changes.</p><ul id="networks"></ul><p id="message" role="status"></p><button onclick="load()">Refresh</button><p><a href="https://dashy.hub.frey/">Back to Frey</a></p><script>
const list=document.getElementById('networks'),message=document.getElementById('message');
async function load(){list.replaceChildren();message.textContent='Loading saved networks...';try{const r=await fetch('/api/networks',{cache:'no-store'});if(!r.ok)throw Error();const networks=await r.json();message.textContent=networks.length?'':'No saved uplink networks found.';for(const n of networks){const li=document.createElement('li'),name=document.createElement('span'),btn=document.createElement('button');name.textContent=n.ssid;btn.textContent='Connect';btn.onclick=()=>connect(n.uuid,n.ssid);li.append(name,btn);list.append(li)}}catch{message.textContent='Could not load networks.'}}
async function connect(uuid,ssid){message.textContent='Connecting to '+ssid+'...';try{const r=await fetch('/api/connect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({uuid})});message.textContent=r.ok?'Connected to '+ssid+'.':'Connection failed. Check that the network is in range.'}catch{message.textContent='Connection failed.'}}load();</script></html>'''


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def authorized(self):
        # Only the proxy knows this token; it overwrites client-supplied values
        # after Authelia has approved the request. Direct bridge access fails.
        return hmac.compare_digest(self.headers.get('X-Frey-Wifi-Token', ''), CONFIG['token'])

    def reply(self, status, body, content_type='text/plain; charset=utf-8'):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.authorized():
            return self.reply(403, b'Forbidden')
        if self.path == '/':
            return self.reply(200, PAGE, 'text/html; charset=utf-8')
        if self.path == '/api/networks':
            try:
                data = saved_networks(CONFIG['uplink'], CONFIG['downstream'])
                return self.reply(200, json.dumps(data).encode(), 'application/json')
            except UplinkError:
                return self.reply(503, b'NetworkManager unavailable')
        return self.reply(404, b'Not found')

    def do_POST(self):
        if not self.authorized() or self.headers.get('Origin') != CONFIG['origin']:
            return self.reply(403, b'Forbidden')
        if self.path != '/api/connect' or self.headers.get_content_type() != 'application/json':
            return self.reply(404, b'Not found')
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 1024:
                raise ValueError('Invalid length')
            request = json.loads(self.rfile.read(length))
            if not CONNECT_LOCK.acquire(blocking=False):
                return self.reply(409, b'Another connection is in progress')
            try:
                connect_saved(request['uuid'], CONFIG['uplink'], CONFIG['downstream'])
            finally:
                CONNECT_LOCK.release()
        except (KeyError, ValueError, TypeError, UplinkError):
            return self.reply(400, b'Could not connect')
        return self.reply(200, b'Connected')


if __name__ == '__main__':
    ThreadingHTTPServer((CONFIG['listen'], CONFIG['port']), Handler).serve_forever()
