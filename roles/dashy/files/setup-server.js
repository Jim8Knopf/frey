// Serve only the public setup page and CA certificate; never expose a directory.
const http = require('http');
const fs = require('fs');
const routes = {
  '/setup': ['/setup/index.html', 'text/html; charset=utf-8'],
  '/setup/': ['/setup/index.html', 'text/html; charset=utf-8'],
  '/setup/frey-root-ca.crt': ['/public-ca/frey-root-ca.crt', 'application/x-x509-ca-cert'],
};
http.createServer((req, res) => {
  const route = routes[req.url.split('?')[0]];
  if (!route || !['GET', 'HEAD'].includes(req.method)) {
    res.writeHead(404).end();
    return;
  }
  fs.readFile(route[0], (err, data) => {
    if (err) { res.writeHead(503).end('Setup is unavailable'); return; }
    res.writeHead(200, { 'Content-Type': route[1], 'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'no-store', ...(route[1].startsWith('application/') ?
        { 'Content-Disposition': 'attachment; filename="frey-root-ca.crt"' } : {}) });
    res.end(req.method === 'HEAD' ? undefined : data);
  });
}).listen(8080, '0.0.0.0');
// Node is PID 1 in this container and must handle Docker's stop signal.
process.on('SIGTERM', () => process.exit(0));
