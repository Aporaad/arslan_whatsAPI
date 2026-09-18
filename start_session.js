const http = require('http');

const API_KEY = 'owa_k1_a5cd0b890f65d909f7bbbf7b2c2171d1b19578839f284e00cca2155682534f27';
const SESSION_ID = '4bbbed0b-1a14-4092-bff2-9c9c565cf941';

function request(options, data) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let body = '';
      res.on('data', (chunk) => body += chunk);
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(body) });
        } catch {
          resolve({ statusCode: res.statusCode, body });
        }
      });
    });
    req.on('error', reject);
    if (data) {
      req.write(typeof data === 'string' ? data : JSON.stringify(data));
    }
    req.end();
  });
}

async function main() {
  console.log('--- 1. Linking session to arslanhook ---');
  const linkRes = await request({
    hostname: '127.0.0.1',
    port: 2785,
    path: '/arslanhook/link',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, { sessionId: SESSION_ID });
  console.log('Link response:', linkRes);

  console.log('--- 2. Starting session ---');
  const startRes = await request({
    hostname: '127.0.0.1',
    port: 2785,
    path: `/api/sessions/${SESSION_ID}/start`,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': API_KEY
    }
  });
  console.log('Start response:', startRes);
}

main().catch(console.error);
