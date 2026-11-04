// register.mjs against a local stand-in for the GitHub OIDC endpoint, UDM and S3
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';

const script = fileURLToPath(new URL('./register.mjs', import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'register-test-'));
writeFileSync(join(dir, 'a.cplz'), 'aaaa');
writeFileSync(join(dir, 'b.cpz'), 'bbbbbb');
const doc = { version: '1.0.0', repoUrl: 'https://github.com/PepperDash/epi-test', assets: [] };
writeFileSync(join(dir, 'doc.json'), JSON.stringify(doc));

let requests = [];
let putStatuses = {};
let server;
let base;

function handler(req, res) {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    const body = Buffer.concat(chunks);
    const url = new URL(req.url, base);
    requests.push({ method: req.method, path: url.pathname, headers: req.headers, body });
    const json = (status, value) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(value));
    };

    if (url.pathname === '/oidc') return json(200, { value: `token-for-${url.searchParams.get('audience')}` });
    if (url.pathname.startsWith('/s3/')) {
      const name = url.pathname.slice(4);
      const queue = putStatuses[name] ?? [200];
      const status = queue.length > 1 ? queue.shift() : queue[0];
      res.writeHead(status);
      return res.end();
    }
    const env = url.pathname.split('/')[1];
    if (env === 'down') return json(503, { error: 'Release asset buckets are not configured in this environment' });
    if (url.pathname.endsWith('/v3/essentials/releases/register')) {
      return json(201, {
        releaseId: `${env}-1`,
        sourceId: 's1',
        status: 'pending',
        uploads:
          env === 'first'
            ? ['a.cplz', 'b.cpz'].map((name) => ({
                name,
                method: 'PUT',
                url: `${base}/s3/${name}`,
                headers: { 'Content-Length': '4', 'If-None-Match': '*', 'x-amz-checksum-sha256': `sum-${name}` },
                expiresAt: '',
              }))
            : [],
      });
    }
    if (url.pathname.endsWith('/complete')) return json(200, { releaseId: `${env}-1`, version: '1.0.0', status: 'available' });
    if (req.method === 'DELETE') return json(200, { releaseId: `${env}-1`, version: '1.0.0', status: 'withdrawn' });
    json(404, { error: 'not found' });
  });
}

function runScript(args) {
  return new Promise((resolve) => {
    execFile(
      process.execPath,
      [script, ...args],
      { env: { ...process.env, ACTIONS_ID_TOKEN_REQUEST_URL: `${base}/oidc?x=1`, ACTIONS_ID_TOKEN_REQUEST_TOKEN: 'request-token' } },
      (error, stdout, stderr) => resolve({ code: error?.code ?? 0, stdout, stderr }),
    );
  });
}

describe('register.mjs', () => {
  before(async () => {
    server = createServer(handler);
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => server.close());

  it('registers with each environment, uploads once and completes', async () => {
    requests = [];
    putStatuses = { 'a.cplz': [409, 200], 'b.cpz': [412] };
    const summary = join(dir, 'summary.md');
    const result = await runScript([
      '--urls', `${base}/first/, ${base}/second`,
      '--document', join(dir, 'doc.json'),
      '--assets-dir', dir,
      '--summary', summary,
    ]);
    assert.equal(result.code, 0, result.stderr);

    const register = requests.find((r) => r.path === '/first/v3/essentials/releases/register');
    assert.equal(register.headers['content-encoding'], 'gzip');
    assert.equal(register.headers.authorization, 'Bearer token-for-pepperdash-udm');
    assert.deepEqual(JSON.parse(gunzipSync(register.body)), doc);

    const puts = requests.filter((r) => r.method === 'PUT');
    // a.cplz: 409 then retried; b.cpz: 412, already stored
    assert.deepEqual(puts.map((r) => r.path), ['/s3/a.cplz', '/s3/a.cplz', '/s3/b.cpz']);
    assert.equal(puts[0].headers['if-none-match'], '*');
    assert.equal(puts[0].headers['x-amz-checksum-sha256'], 'sum-a.cplz');
    assert.equal(puts[0].body.toString(), 'aaaa');

    assert.ok(requests.some((r) => r.path === '/first/v3/essentials/releases/first-1/complete'));
    assert.ok(requests.some((r) => r.path === '/second/v3/essentials/releases/second-1/complete'));
    assert.match(readFileSync(summary, 'utf8'), /a\.cplz uploaded, b\.cpz already stored/);
  });

  it('tries every environment and fails if any did', async () => {
    requests = [];
    putStatuses = {};
    const result = await runScript(['--urls', `${base}/down,${base}/second`, '--document', join(dir, 'doc.json'), '--assets-dir', dir]);
    assert.equal(result.code, 1);
    assert.match(result.stderr, /503 Release asset buckets are not configured/);
    assert.ok(requests.some((r) => r.path === '/second/v3/essentials/releases/second-1/complete'));
  });

  it('withdraws by repoUrl and version', async () => {
    requests = [];
    const result = await runScript([
      '--urls', `${base}/first`,
      '--withdraw', '--repo-url', 'https://github.com/PepperDash/epi-test', '--version', '1.0.0',
    ]);
    assert.equal(result.code, 0, result.stderr);
    const call = requests.find((r) => r.method === 'DELETE');
    assert.equal(call.path, '/first/v3/essentials/releases');
    assert.deepEqual(JSON.parse(call.body), { repoUrl: 'https://github.com/PepperDash/epi-test', version: '1.0.0' });
  });
});
