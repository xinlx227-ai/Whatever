const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const page = fs.readFileSync(path.join(__dirname, 'index.html'));
http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(page);
}).listen(4173, '127.0.0.1', () => console.log('Prototype: http://127.0.0.1:4173/?variant=A'));
