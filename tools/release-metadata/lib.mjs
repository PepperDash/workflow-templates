// Turns metadata-extract's facts.json into pepperdash-metadata.json (schemas/ in this repo) and
// checks the result.
//
// Every rule here is deterministic. Where the code can't establish a field, the baseline (the
// nearest earlier release's document) carries it forward; what neither has is reported as a gap.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';

export const SCRIPT_VERSION = 'pepperdash-metadata@0.1.0';

const schemasDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'schemas');
const loadSchema = (name) => JSON.parse(readFileSync(join(schemasDir, `${name}.schema.json`), 'utf8'));
const metadataSchema = loadSchema('pepperdash-metadata.v1');
const formMetadataSchema = loadSchema('pepperdash-form-metadata.v1');
const catalogSchema = loadSchema('pepperdash-catalog.v1');

// The spec uses no formats of its own; the schemas they guard are checked by shape
const ajv = new Ajv({ allErrors: true, allowUnionTypes: true, validateFormats: false });
ajv.addSchema([metadataSchema, formMetadataSchema, catalogSchema]);
export const validateMetadata = ajv.getSchema(metadataSchema.$id);
export const validateFormMetadataSidecar = ajv.getSchema(formMetadataSchema.$id);

export const METADATA_SCHEMA_URL = metadataSchema.$id;
export const ASSET_TYPES = ['cpz', 'cplz', 'ch5z', 'zip'];
export const NO_DEVICE_KINDS = ['userInterface', 'touchpanelWrapper'];

/** Used when neither the code nor the baseline gives a schema: a device with no config properties */
const EMPTY_SCHEMA = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  $defs: { propertiesConfig: { $id: '#root', type: 'object', properties: {} } },
};

// Fields the extractor never produces; they come from the baseline only
const CARRIED_FIELDS = [
  'controlMethods',
  'controlPorts',
  'destinationListRoleSchema',
  'sourceListIconOptionsSchema',
  'audioControlPointsListMetaData',
  'childDeviceMetadata',
  'deviceKind',
  'catalog',
];

export function assetTypeOf(name) {
  const ext = name.split('.').pop()?.toLowerCase();
  return ASSET_TYPES.includes(ext) ? ext : null;
}

/** "epi-epson-projector" → "Epson Projector"; Essentials itself is "Essentials" */
export function labelFor(kind, repo) {
  if (kind === 'essentials') return 'Essentials';
  return repo
    .replace(/^epi-/i, '')
    .split(/[-_]+/)
    .filter(Boolean)
    .map((word) => word[0].toUpperCase() + word.slice(1))
    .join(' ');
}

/** "v4.0.0-x.5" → "4.0.0-x.5" */
export function versionOf(tag) {
  return tag.replace(/^v/, '');
}

const hasPorts = (ports) => Boolean(ports && (ports.inputs?.length || ports.outputs?.length));

/**
 * Ports from the code when it read every construction; otherwise the baseline's, which a person
 * or the agent completed. A device whose ports are added by helper classes shows no ports and
 * nothing unresolved, so an empty result defers to a baseline that has ports too.
 */
function choosePorts(facts, baseline) {
  const fromCode = { inputs: facts.routingPorts.inputs, outputs: facts.routingPorts.outputs };
  const complete = facts.routingPorts.unresolved.length === 0;
  if (complete && (hasPorts(fromCode) || !hasPorts(baseline?.routingPorts))) {
    return { ports: hasPorts(fromCode) ? fromCode : undefined, source: 'code' };
  }
  if (hasPorts(baseline?.routingPorts)) {
    return { ports: baseline.routingPorts, source: 'baseline' };
  }
  return { ports: hasPorts(fromCode) ? fromCode : undefined, source: 'code (partial)' };
}

/** Every $id in a schema: what a formMetadata schemaId may point at */
function schemaIds(node, ids = new Set()) {
  if (Array.isArray(node)) {
    node.forEach((n) => schemaIds(n, ids));
  } else if (node && typeof node === 'object') {
    if (typeof node.$id === 'string') ids.add(node.$id);
    Object.values(node).forEach((n) => schemaIds(n, ids));
  }
  return ids;
}

/**
 * The property path an $id names, whichever convention wrote it: the extractor writes #root/avrKey,
 * older hand-written schemas #root/propertiesConfig/avrKey or #root/properties/avrKey. `loose`
 * also drops the "items" segments inside a path, which hand-written schemaIds often leave out.
 */
export function idPath(id, { loose = false } = {}) {
  const path = id.replace(/^#root/, '').replace(/^\/(propertiesConfig|properties)(?=\/)/, '').toLowerCase();
  // A trailing "items" stays: #root/roomKeys (the array) and #root/roomKeys/items (its elements) differ
  return loose ? path.replace(/\/items(?=\/)/g, '') : path;
}

/** path → $id, with null for a path two $ids share (they can't be told apart) */
function idsByPath(ids, options) {
  const byPath = new Map();
  for (const id of ids) {
    const path = idPath(id, options);
    byPath.set(path, byPath.has(path) ? null : id);
  }
  return byPath;
}

/**
 * Points each formMetadata schemaId at the $id this release's schema actually uses for that
 * property, so a sidecar written against one $id convention keeps working when the schema uses
 * another. A schemaId that matches nothing is left as it is, for the gate to report.
 */
export function resolveSchemaIds(formMetadata, schema) {
  const properties = formMetadata?.propertyMetadata?.properties;
  if (!properties) return { formMetadata, rewrites: [] };
  const ids = schemaIds(schema);
  const exact = idsByPath(ids);
  const loose = idsByPath(ids, { loose: true });
  const rewrites = [];
  const resolved = {};
  for (const [name, meta] of Object.entries(properties)) {
    // Not a string: the sidecar's schema check reports it
    if (typeof meta?.schemaId !== 'string') {
      resolved[name] = meta;
      continue;
    }
    const actual = ids.has(meta.schemaId)
      ? meta.schemaId
      : exact.get(idPath(meta.schemaId)) ?? loose.get(idPath(meta.schemaId, { loose: true }));
    if (actual && actual !== meta.schemaId) rewrites.push(`${name}: ${meta.schemaId} → ${actual}`);
    resolved[name] = actual ? { ...meta, schemaId: actual } : meta;
  }
  return {
    formMetadata: { ...formMetadata, propertyMetadata: { ...formMetadata.propertyMetadata, properties: resolved } },
    rewrites,
  };
}

const caseInsensitive = (object, key) =>
  object?.[key] ?? Object.entries(object ?? {}).find(([k]) => k.toLowerCase() === key.toLowerCase())?.[1];

/**
 * Copies the baseline's titles and descriptions onto a schema built from the code, property by
 * property. A `<summary>` in the code wins over the baseline's description; the code's titles are
 * only its property names spaced out, so a baseline title (hand-written, or the same) wins over them.
 * Returns the merged schema and, by property path, which descriptions came from where.
 */
export function mergeSchemaText(schema, baselineSchema) {
  const merged = structuredClone(schema);
  const descriptions = { code: 0, baseline: 0, missing: [] };
  const isSchema = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);
  // A schema's own properties, then those of the element schemas it contains, to any depth: arrays
  // (items, path "x[]") and dictionaries (additionalProperties, path "x{}") can nest each other
  const walk = (node, base, path) => {
    if (isSchema(node?.items)) walk(node.items, base?.items, `${path}[]`);
    if (isSchema(node?.additionalProperties)) {
      walk(node.additionalProperties, isSchema(base?.additionalProperties) ? base.additionalProperties : undefined, `${path}{}`);
    }
    for (const [name, property] of Object.entries(node?.properties ?? {})) {
      if (!property || typeof property !== 'object') continue;
      const baseProperty = caseInsensitive(base?.properties, name);
      const propertyPath = path ? `${path}.${name}` : name;
      if (typeof baseProperty?.title === 'string') property.title = baseProperty.title;
      if (property.description) {
        descriptions.code++;
      } else if (typeof baseProperty?.description === 'string' && baseProperty.description) {
        property.description = baseProperty.description;
        descriptions.baseline++;
      } else {
        descriptions.missing.push(propertyPath);
      }
      walk(property, baseProperty, propertyPath);
    }
  };
  walk(merged.$defs?.propertiesConfig, baselineSchema?.$defs?.propertiesConfig, '');
  return { schema: merged, descriptions };
}

/**
 * One typeName's metadata from its facts, the baseline's entry and the form metadata sidecar.
 * Returns the entry and, per field, where it came from, plus what's missing.
 */
export function assembleTypeName(facts, baseline, formSidecarEntry) {
  const entry = {};
  const sources = {};
  const gaps = [];

  if (facts.schema) {
    const { schema, descriptions } = mergeSchemaText(facts.schema, baseline?.schema);
    entry.schema = schema;
    sources.schema = 'code';
    sources.descriptions = descriptions;
  } else if (baseline?.schema) {
    entry.schema = baseline.schema;
    sources.schema = 'baseline';
    // Merging a schema onto itself only counts what it has
    const { descriptions } = mergeSchemaText(baseline.schema);
    sources.descriptions = { code: 0, baseline: descriptions.code, missing: descriptions.missing };
  } else {
    entry.schema = EMPTY_SCHEMA;
    sources.schema = 'empty';
    gaps.push('schema');
  }

  if (baseline?.label !== undefined) entry.label = baseline.label;

  if (facts.interfaces) {
    entry.interfaces = facts.interfaces;
    sources.interfaces = 'code';
  } else if (baseline?.interfaces) {
    entry.interfaces = baseline.interfaces;
    sources.interfaces = 'baseline';
  } else {
    entry.interfaces = [];
    sources.interfaces = 'empty';
    gaps.push('interfaces');
  }

  const { ports, source } = choosePorts(facts, baseline);
  if (ports) entry.routingPorts = ports;
  sources.routingPorts = source;
  if (source === 'code (partial)') gaps.push(`routingPorts (${facts.routingPorts.unresolved.length} unresolved)`);

  for (const field of CARRIED_FIELDS) {
    if (baseline?.[field] !== undefined) entry[field] = baseline[field];
  }

  const formMetadata = formSidecarEntry ?? baseline?.formMetadata;
  if (formMetadata) {
    const { formMetadata: resolved, rewrites } = resolveSchemaIds(formMetadata, entry.schema);
    entry.formMetadata = resolved;
    sources.formMetadata = formSidecarEntry ? 'sidecar' : 'baseline';
    if (rewrites.length) sources.schemaIdRewrites = rewrites;
  }

  const description = facts.description ?? baseline?.description;
  if (description) entry.description = description;

  return { entry, sources, gaps };
}

/**
 * An entry by typeName. Essentials matches typeNames case-insensitively, so a key that differs
 * only in case is the same device type; the gate warns about it.
 */
function lookup(entries, typeName) {
  if (!entries) return undefined;
  if (entries[typeName]) return entries[typeName];
  const key = Object.keys(entries).find((k) => k.toLowerCase() === typeName.toLowerCase());
  return key ? entries[key] : undefined;
}

/**
 * The whole document. `release` holds what comes from GitHub and the caller: kind, packageId,
 * label, tag, repoUrl, commitSha, publishedAt and assets.
 */
export function assemble({ facts, baseline, formSidecar, release }) {
  const version = versionOf(release.tag);
  const doc = {
    $schema: METADATA_SCHEMA_URL,
    specVersion: 1,
    kind: release.kind,
    packageId: release.packageId,
    label: release.label,
    version,
    tag: release.tag,
    // A hyphen in build metadata (+build-main) doesn't make it a prerelease
    prerelease: version.split('+')[0].includes('-'),
    repoUrl: release.repoUrl,
    commitSha: release.commitSha,
    publishedAt: release.publishedAt,
    generator: { script: SCRIPT_VERSION, prompt: null, agent: null, reusedFrom: null },
    assets: release.assets,
    typeNames: {},
  };
  // A requirement the code no longer shows (set through a helper, say) still holds
  const minimum = facts?.minimumEssentialsVersion ?? baseline?.minimumEssentialsVersion;
  if (release.kind === 'plugin' && minimum) {
    doc.minimumEssentialsVersion = minimum;
  }

  const report = {};
  if (!NO_DEVICE_KINDS.includes(release.kind)) {
    for (const typeName of Object.keys(facts.typeNames).sort()) {
      const { entry, sources, gaps } = assembleTypeName(
        facts.typeNames[typeName],
        lookup(baseline?.typeNames, typeName),
        lookup(formSidecar?.typeNames, typeName),
      );
      doc.typeNames[typeName] = entry;
      report[typeName] = { sources, gaps };
    }
  }
  return { doc, report };
}

function describeErrors(errors) {
  return (errors ?? []).map((e) => {
    const detail = e.keyword === 'additionalProperties' ? ` (${e.params.additionalProperty})` : '';
    return `${e.instancePath || '/'} ${e.message}${detail}`;
  });
}

/** The checks that must pass before anything is published. Errors fail the build. */
export function gate({ doc, facts, formSidecar }) {
  const errors = [];
  // What the extractor couldn't read (a property left out for a missing reference, say)
  const warnings = (facts.warnings ?? []).map((w) => `metadata-extract: ${w}`);

  if (!validateMetadata(doc)) {
    errors.push(...describeErrors(validateMetadata.errors).map((e) => `pepperdash-metadata.json: ${e}`));
  }

  if (!NO_DEVICE_KINDS.includes(doc.kind)) {
    const expected = Object.keys(facts.typeNames).sort().join(',');
    const actual = Object.keys(doc.typeNames).sort().join(',');
    if (expected !== actual) errors.push("typeNames differ from the factories' TypeNames");
    if (Object.keys(facts.typeNames).length === 0) warnings.push('no factory TypeNames found');
  }

  if (formSidecar) {
    if (!validateFormMetadataSidecar(formSidecar)) {
      errors.push(...describeErrors(validateFormMetadataSidecar.errors).map((e) => `.pepperdash/form-metadata.json: ${e}`));
    }
    const released = Object.keys(doc.typeNames);
    for (const typeName of Object.keys(formSidecar.typeNames ?? {})) {
      if (doc.typeNames[typeName]) continue;
      const match = released.find((t) => t.toLowerCase() === typeName.toLowerCase());
      if (match) {
        warnings.push(`.pepperdash/form-metadata.json: ${typeName} is spelt ${match} in the factory; rename the key`);
      } else {
        errors.push(`.pepperdash/form-metadata.json: ${typeName} is not a typeName in this release`);
      }
    }
  }

  for (const [typeName, entry] of Object.entries(doc.typeNames)) {
    const properties = entry.formMetadata?.propertyMetadata?.properties ?? {};
    const ids = schemaIds(entry.schema);
    for (const [property, meta] of Object.entries(properties)) {
      if (!ids.has(meta?.schemaId)) {
        errors.push(`${typeName}: formMetadata ${property} points at ${meta.schemaId}, which isn't in this release's schema`);
      }
    }
  }

  return { errors, warnings };
}

const sorted = (values) => [...(values ?? [])].sort();
const portNames = (ports, side) => sorted((ports?.[side] ?? []).map((p) => p.name));
const schemaProperties = (schema) => sorted(Object.keys(schema?.$defs?.propertiesConfig?.properties ?? {}));

function listChange(before, after) {
  const added = after.filter((x) => !before.includes(x));
  const removed = before.filter((x) => !after.includes(x));
  return added.length || removed.length ? { added, removed } : null;
}

/** What changed since the baseline, per typeName, for the job summary */
export function diff(baseline, doc) {
  if (!baseline) return null;
  const before = Object.keys(baseline.typeNames ?? {});
  const after = Object.keys(doc.typeNames);
  const changed = {};
  for (const typeName of after.filter((t) => before.includes(t))) {
    const b = baseline.typeNames[typeName];
    const a = doc.typeNames[typeName];
    const fields = Object.fromEntries(
      Object.entries({
        interfaces: listChange(sorted(b.interfaces), sorted(a.interfaces)),
        inputs: listChange(portNames(b.routingPorts, 'inputs'), portNames(a.routingPorts, 'inputs')),
        outputs: listChange(portNames(b.routingPorts, 'outputs'), portNames(a.routingPorts, 'outputs')),
        properties: listChange(schemaProperties(b.schema), schemaProperties(a.schema)),
      }).filter(([, change]) => change),
    );
    if (Object.keys(fields).length) changed[typeName] = fields;
  }
  return {
    baselineVersion: baseline.version,
    added: after.filter((t) => !before.includes(t)),
    removed: before.filter((t) => !after.includes(t)),
    changed,
  };
}

/** Markdown for $GITHUB_STEP_SUMMARY */
export function summarize({ doc, report, gateResult, changes }) {
  const lines = [`## pepperdash-metadata.json for ${doc.tag}`, ''];
  if (gateResult.errors.length) {
    lines.push('**Gate failed**', '', ...gateResult.errors.map((e) => `- ${e}`), '');
  } else {
    lines.push('Gate passed.', '');
  }
  if (gateResult.warnings.length) lines.push(...gateResult.warnings.map((w) => `- Warning: ${w}`), '');

  const typeNames = Object.keys(report);
  if (typeNames.length) {
    lines.push(
      '| typeName | schema | descriptions | interfaces | routingPorts | formMetadata | gaps |',
      '|---|---|---|---|---|---|---|',
    );
    for (const typeName of typeNames) {
      const { sources, gaps } = report[typeName];
      const d = sources.descriptions;
      const descriptions = d ? `${d.code} code, ${d.baseline} baseline, ${d.missing.length} missing` : '–';
      lines.push(`| \`${typeName}\` | ${sources.schema} | ${descriptions} | ${sources.interfaces} | ${sources.routingPorts} | ${sources.formMetadata ?? '–'} | ${gaps.join(', ') || '–'} |`);
    }
    lines.push('');
    const missing = typeNames.filter((t) => report[t].sources.descriptions?.missing.length);
    if (missing.length) {
      // A /// <summary> on the config property fills these in the next release
      lines.push('<details><summary>Config properties with no description (add a <code>/// &lt;summary&gt;</code> to each)</summary>', '');
      for (const typeName of missing) {
        lines.push(`- \`${typeName}\`: ${report[typeName].sources.descriptions.missing.map((p) => `\`${p}\``).join(', ')}`);
      }
      lines.push('', '</details>', '');
    }
    const rewrites = typeNames.flatMap((t) => (report[t].sources.schemaIdRewrites ?? []).map((r) => `- \`${t}\` ${r}`));
    if (rewrites.length) lines.push('formMetadata schemaIds pointed at this schema\'s $ids:', '', ...rewrites, '');
  }

  if (changes) {
    lines.push(`### Changes since ${changes.baselineVersion}`, '');
    if (changes.added.length) lines.push(`- Added: ${changes.added.map((t) => `\`${t}\``).join(', ')}`);
    if (changes.removed.length) lines.push(`- Removed: ${changes.removed.map((t) => `\`${t}\``).join(', ')}`);
    for (const [typeName, fields] of Object.entries(changes.changed)) {
      const parts = Object.entries(fields).map(([field, { added, removed }]) =>
        `${field} ${[...added.map((x) => `+${x}`), ...removed.map((x) => `-${x}`)].join(' ')}`);
      lines.push(`- \`${typeName}\`: ${parts.join('; ')}`);
    }
    if (!changes.added.length && !changes.removed.length && !Object.keys(changes.changed).length) {
      lines.push('No changes.');
    }
  } else {
    lines.push('No baseline: this is the first release with metadata on this line of history.');
  }
  return lines.join('\n') + '\n';
}
