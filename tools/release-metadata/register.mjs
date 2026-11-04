// Register a release with each UDM environment, upload its files, and mark it complete:
//   node register.mjs --urls <base,base,...> --document pepperdash-metadata.json --assets-dir <dir>
// Withdraw a release (its GitHub release was deleted):
//   node register.mjs --urls <base,...> --withdraw --repo-url <url> --version <version>
//
// Each base is a UDM API root up to /api, e.g. https://<host>/apps/devmgmtapi/api. Calls carry a
// GitHub Actions OIDC token for audience pepperdash-udm, so the job needs `id-token: write`.
//
// The environments share one S3 bucket per org, so only the first register returns upload URLs;
// the others find the files already stored. Uploads are create-only: 412 means the object is
// already there (complete checks its bytes), 409 means a concurrent PUT to the same key (retry).
//
// [--summary <file>] appends a Markdown table of what happened. Exits 1 if any environment failed;
// the others are still attempted.

import { appendFileSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { gzipSync } from 'node:zlib';

const AUDIENCE = 'pepperdash-udm';
const RETRIES = 3;

const { values: args } = parseArgs({
  options: {
    urls: { type: 'string' },
    document: { type: 'string' },
    'assets-dir': { type: 'string' },
    withdraw: { type: 'boolean', default: false },
    'repo-url': { type: 'string' },
    version: { type: 'string' },
    summary: { type: 'string' },
  },
});

const bases = (args.urls ?? '').split(',').map((u) => u.trim().replace(/\/+$/, '')).filter(Boolean);
if (!bases.length) {
  console.error('--urls is required');
  process.exit(2);
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** A fresh token per call: they last about five minutes and uploads can be slow */
async function oidcToken() {
  const { ACTIONS_ID_TOKEN_REQUEST_URL: url, ACTIONS_ID_TOKEN_REQUEST_TOKEN: token } = process.env;
  if (!url || !token) throw new Error('no GitHub OIDC token available: the job needs permissions id-token: write');
  const response = await fetch(`${url}&audience=${AUDIENCE}`, { headers: { Authorization: `bearer ${token}` } });
  if (!response.ok) throw new Error(`OIDC token request failed: ${response.status}`);
  return (await response.json()).value;
}

async function call(method, url, body, { gzip = false } = {}) {
  const headers = { Authorization: `Bearer ${await oidcToken()}`, 'Content-Type': 'application/json' };
  let payload = body === undefined ? undefined : JSON.stringify(body);
  if (gzip && payload) {
    payload = gzipSync(payload);
    headers['Content-Encoding'] = 'gzip';
  }
  const response = await fetch(url, { method, headers, body: payload });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    // Not JSON (a proxy error page); the text is reported instead
  }
  if (!response.ok) {
    const detail = json?.error ? `${json.error}${json.details ? ` ${JSON.stringify(json.details)}` : ''}` : text.slice(0, 300);
    throw new Error(`${method} ${new URL(url).pathname}: ${response.status} ${detail}`);
  }
  return json;
}

/** PUT one file to its presigned URL with the signed headers. Returns 'uploaded' or 'already stored'. */
async function upload(target, assetsDir) {
  const bytes = readFileSync(join(assetsDir, target.name));
  // fetch sets Content-Length from the body (the same value that was signed) and won't take it as a header
  const headers = Object.fromEntries(Object.entries(target.headers).filter(([k]) => k.toLowerCase() !== 'content-length'));
  for (let attempt = 1; ; attempt++) {
    const response = await fetch(target.url, { method: target.method ?? 'PUT', headers, body: bytes });
    if (response.ok) return 'uploaded';
    if (response.status === 412) return 'already stored';
    if (response.status === 409 && attempt < RETRIES) {
      await sleep(2000 * attempt);
      continue;
    }
    throw new Error(`PUT ${target.name}: ${response.status} ${(await response.text()).slice(0, 300)}`);
  }
}

async function register(base, doc) {
  const registered = await call('POST', `${base}/v3/essentials/releases/register`, doc, { gzip: true });
  const uploads = [];
  for (const u of registered.uploads ?? []) {
    uploads.push(`${u.name} ${await upload(u, args['assets-dir'])}`);
  }
  if (registered.status === 'available' && !registered.uploads?.length) {
    return `already available (${registered.releaseId}); metadata refreshed`;
  }
  for (let attempt = 1; ; attempt++) {
    try {
      const completed = await call('POST', `${base}/v3/essentials/releases/${registered.releaseId}/complete`);
      return `${completed.status} (${registered.releaseId})${uploads.length ? `; ${uploads.join(', ')}` : '; no uploads needed'}`;
    } catch (err) {
      // 409: changed by a concurrent request; the service asks for a retry
      if (attempt >= RETRIES || !/: 409 /.test(err.message)) throw err;
      await sleep(2000 * attempt);
    }
  }
}

async function withdraw(base) {
  const result = await call('DELETE', `${base}/v3/essentials/releases`, {
    repoUrl: args['repo-url'],
    version: args.version,
  });
  return `${result?.status ?? 'withdrawn'} (${result?.releaseId ?? '?'})`;
}

const doc = args.withdraw ? null : JSON.parse(readFileSync(args.document, 'utf8'));
if (args.withdraw && (!args['repo-url'] || !args.version)) {
  console.error('--withdraw needs --repo-url and --version');
  process.exit(2);
}

const rows = [];
let failed = false;
for (const base of bases) {
  const host = new URL(base).host;
  try {
    const outcome = args.withdraw ? await withdraw(base) : await register(base, doc);
    rows.push(`| ${host} | ${outcome} |`);
    console.log(`${host}: ${outcome}`);
  } catch (err) {
    failed = true;
    rows.push(`| ${host} | **failed**: ${err.message} |`);
    console.error(`${host}: ${err.message}`);
  }
}

if (args.summary) {
  const title = args.withdraw ? `### Withdraw ${args.version} from Portal` : `### Register ${doc.version} with Portal`;
  appendFileSync(args.summary, [title, '', '| UDM | Result |', '|---|---|', ...rows, ''].join('\n') + '\n');
}
process.exit(failed ? 1 : 0);
