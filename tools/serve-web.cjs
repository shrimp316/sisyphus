// Local preview only. The /sisyphus/ prefix matches a GitHub project Pages URL.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../builds/web');
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.txt': 'text/plain; charset=utf-8', '.png': 'image/png' };
http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
  let pathname;
  try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
  catch { res.writeHead(400).end(); return; }
  if (pathname === '/' || pathname === '/sisyphus') { res.writeHead(302, { Location: '/sisyphus/' }).end(); return; }
  if (!pathname.startsWith('/sisyphus/')) { res.writeHead(404).end(); return; }
  let relative = pathname.slice('/sisyphus/'.length);
  if (!relative || relative.endsWith('/')) relative += 'index.html';
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  fs.stat(file, (error, stat) => {
    if (error || !stat.isFile()) { res.writeHead(404).end(); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(file)] || 'application/octet-stream', 'Content-Length': stat.size, 'Cache-Control': 'no-store' });
    if (req.method === 'HEAD') res.end();
    else fs.createReadStream(file).on('error', () => res.destroy()).pipe(res);
  });
}).listen(8765, '127.0.0.1', () => console.log('SISYPHUS preview: http://127.0.0.1:8765/sisyphus/'));
