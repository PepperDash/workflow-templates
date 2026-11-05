// node assemble.mjs --kind plugin --package-id <id> --tag <tag> --repo-url <url> --commit-sha <sha>
//                   --published-at <utc> --assets-dir <dir> [--facts facts.json] [--baseline <file>]
//                   [--form-sidecar <file>] [--label <label>] [--out pepperdash-metadata.json]
//                   [--summary summary.md]
//
// Writes the document and a Markdown summary, then exits 1 if the gate fails. The document is
// written either way, so a failed run can be inspected; the workflow only publishes on success.

import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { assemble, assetTypeOf, diff, gate, labelFor, NO_DEVICE_KINDS, summarize } from './lib.mjs';

const { values: args } = parseArgs({
  options: {
    kind: { type: 'string', default: 'plugin' },
    'package-id': { type: 'string' },
    label: { type: 'string' },
    tag: { type: 'string' },
    'repo-url': { type: 'string' },
    'commit-sha': { type: 'string' },
    'published-at': { type: 'string' },
    'assets-dir': { type: 'string' },
    facts: { type: 'string' },
    baseline: { type: 'string' },
    'form-sidecar': { type: 'string' },
    out: { type: 'string', default: 'pepperdash-metadata.json' },
    summary: { type: 'string', default: 'summary.md' },
  },
});

for (const required of ['package-id', 'tag', 'repo-url', 'commit-sha', 'published-at', 'assets-dir']) {
  if (!args[required]) {
    console.error(`--${required} is required`);
    process.exit(2);
  }
}
if (!NO_DEVICE_KINDS.includes(args.kind) && !args.facts) {
  console.error(`--facts is required for kind ${args.kind}`);
  process.exit(2);
}

const readJson = (path) => (path && existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : null);

/** The release's .cpz/.cplz/.ch5z/.zip files, by name */
function readAssets(dir) {
  return readdirSync(dir)
    .filter((name) => assetTypeOf(name) && statSync(join(dir, name)).isFile())
    .sort()
    .map((name) => {
      const bytes = readFileSync(join(dir, name));
      return {
        name,
        type: assetTypeOf(name),
        size: bytes.length,
        sha256: createHash('sha256').update(bytes).digest('hex'),
      };
    });
}

const facts = readJson(args.facts);
const baseline = readJson(args.baseline);
const formSidecar = readJson(args['form-sidecar']);
const repoUrl = args['repo-url'].replace(/\.git$/, '');

const { doc, report } = assemble({
  facts,
  baseline,
  formSidecar,
  release: {
    kind: args.kind,
    packageId: args['package-id'],
    label: args.label || labelFor(args.kind, repoUrl.split('/').pop()),
    tag: args.tag,
    repoUrl,
    commitSha: args['commit-sha'].toLowerCase(),
    publishedAt: args['published-at'],
    assets: readAssets(args['assets-dir']),
  },
});
const gateResult = gate({ doc, facts: facts ?? { typeNames: {} }, formSidecar });

writeFileSync(args.out, JSON.stringify(doc, null, 2) + '\n');
writeFileSync(args.summary, summarize({ doc, report, gateResult, changes: diff(baseline, doc) }));

for (const error of gateResult.errors) console.error(`error: ${error}`);
for (const warning of gateResult.warnings) console.error(`warning: ${warning}`);
process.exit(gateResult.errors.length ? 1 : 0);
