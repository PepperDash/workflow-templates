// node assemble.mjs --kind plugin --package-id <id> --tag <tag> --repo-url <url> --commit-sha <sha>
//                   --published-at <utc> --assets-dir <dir> [--facts facts.json] [--baseline <file>]
//                   [--form-sidecar <file>] [--type-names-sidecar <file>] [--label <label>]
//                   [--out pepperdash-metadata.json]
//                   [--summary summary.md] [--gaps gaps.json] [--agent agent.json]
//
// Writes the document and a Markdown summary, then exits 1 if the gate fails. The document is
// written either way, so a failed run can be inspected; the workflow only publishes on success.
// --gaps writes what nothing filled (agent.mjs's input); --agent fills those gaps from agent.mjs's
// answer, ignoring an answer that doesn't match its schema.

import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import {
  applyAgent,
  assemble,
  assetTypeOf,
  diff,
  findGaps,
  gate,
  labelFor,
  NO_DEVICE_KINDS,
  summarize,
  validateAgentOutput,
} from './lib.mjs';

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
    'type-names-sidecar': { type: 'string' },
    out: { type: 'string', default: 'pepperdash-metadata.json' },
    summary: { type: 'string', default: 'summary.md' },
    gaps: { type: 'string' },
    agent: { type: 'string' },
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
const typeNamesSidecar = readJson(args['type-names-sidecar']);
const repoUrl = args['repo-url'].replace(/\.git$/, '');

const assembled = assemble({
  facts,
  baseline,
  formSidecar,
  typeNamesSidecar,
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
const gaps = findGaps({ doc: assembled.doc, report: assembled.report, facts });
let { doc, report } = assembled;
let agent = null;
const agentWarnings = [];
if (args.agent) {
  const answer = readJson(args.agent);
  if (!answer?.result || !validateAgentOutput(answer.result)) {
    agentWarnings.push(`${args.agent} isn't a valid agent answer; nothing from it was used`);
  } else {
    ({ doc, report, ...agent } = applyAgent({ doc, report, gaps, result: answer.result, agent: answer.agent }));
  }
}
const gateResult = gate({ doc, facts: facts ?? { typeNames: {} }, formSidecar, typeNamesSidecar, report });
gateResult.warnings.push(...agentWarnings);

writeFileSync(args.out, JSON.stringify(doc, null, 2) + '\n');
writeFileSync(args.summary, summarize({ doc, report, gateResult, changes: diff(baseline, doc), agent }));
if (args.gaps) writeFileSync(args.gaps, JSON.stringify(gaps, null, 2) + '\n');

for (const error of gateResult.errors) console.error(`error: ${error}`);
for (const warning of gateResult.warnings) console.error(`warning: ${warning}`);
process.exit(gateResult.errors.length ? 1 : 0);
