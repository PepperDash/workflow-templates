// Turns metadata-extract's facts.json into pepperdash-metadata.json (schemas/ in this repo) and
// checks the result.
//
// Every rule here is deterministic. Where the code can't establish a field, the baseline (the
// nearest earlier release's document) carries it forward; what neither has is reported as a gap.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv';

export const SCRIPT_VERSION = 'pepperdash-metadata@0.2.0';

const schemasDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'schemas');
const loadSchema = (name) => JSON.parse(readFileSync(join(schemasDir, `${name}.schema.json`), 'utf8'));
const metadataSchema = loadSchema('pepperdash-metadata.v1');
const formMetadataSchema = loadSchema('pepperdash-form-metadata.v1');
const catalogSchema = loadSchema('pepperdash-catalog.v1');
const typeNamesSchema = loadSchema('pepperdash-type-names.v1');

// The spec uses no formats of its own; the schemas they guard are checked by shape
const ajv = new Ajv({ allErrors: true, allowUnionTypes: true, validateFormats: false });
ajv.addSchema([metadataSchema, formMetadataSchema, catalogSchema, typeNamesSchema]);
export const validateMetadata = ajv.getSchema(metadataSchema.$id);
export const validateFormMetadataSidecar = ajv.getSchema(formMetadataSchema.$id);
export const validateTypeNamesSidecar = ajv.getSchema(typeNamesSchema.$id);

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

const isObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

/** A node's patternProperties value schemas whose pattern matches the key, ignoring case as paths do */
function patternsMatching(node, key) {
  return Object.entries(node?.patternProperties ?? {})
    .filter(([pattern, value]) => {
      if (!isObject(value)) return false;
      try {
        return new RegExp(pattern, 'i').test(key);
      } catch {
        return false;
      }
    })
    .map(([, value]) => value);
}

/** The only one of a list, or undefined when there's none or it's ambiguous */
const only = (values) => (values.length === 1 ? values[0] : undefined);

/**
 * The value schema a dictionary key reaches: the one patternProperties schema whose pattern
 * matches it, else additionalProperties. Undefined when several patterns match.
 */
function dictionaryValueFor(node, key) {
  const matching = patternsMatching(node, key);
  if (matching.length) return only(matching);
  return isObject(node?.additionalProperties) ? node.additionalProperties : undefined;
}

/** One path segment down from a schema node, or undefined */
function stepInto(node, segment) {
  if (!isObject(node)) return undefined;
  // A segment that names a schema keyword only counts when the node has it; otherwise it may
  // still be a property, an array element's property or a dictionary key of that name
  if (segment === 'items' && isObject(node.items)) return node.items;
  if (segment === 'additionalproperties' && isObject(node.additionalProperties)) return node.additionalProperties;
  const patterns = Object.values(node.patternProperties ?? {}).filter(isObject);
  // With several patterns, "patternProperties" doesn't say which one: unresolved
  if (segment === 'patternproperties' && patterns.length) return only(patterns);
  const property = Object.entries(node.properties ?? {}).find(([name]) => name.toLowerCase() === segment)?.[1];
  if (isObject(property)) return property;
  // A path that leaves out an array's "items"
  if (isObject(node.items)) {
    const inItems = stepInto(node.items, segment);
    if (inItems) return inItems;
  }
  // A dictionary key: the mocks named the keys a dictionary is expected to hold (relays/raise),
  // where a schema built from a Dictionary<string, T> only describes its values
  return dictionaryValueFor(node, segment);
}

/**
 * The $id of the schema node a path reaches when it's walked through the schema: through arrays
 * whose "items" the path leaves out, and through dictionaries, whatever the path calls their values
 * (a key, "patternProperties" or "additionalProperties"). Undefined when the node has no $id.
 */
function walkToId(schema, id) {
  let node = schema?.$defs?.propertiesConfig;
  for (const segment of idPath(id).split('/').filter(Boolean)) {
    node = stepInto(node, segment);
    if (!node) return undefined;
  }
  return typeof node?.$id === 'string' ? node.$id : undefined;
}

/**
 * Points each formMetadata schemaId at the $id this release's schema actually uses for that
 * property, so a sidecar written against one $id convention keeps working when the schema uses
 * another: first by path, then by walking the schema through arrays and dictionaries. A schemaId
 * that matches nothing is left as it is, for the caller or the gate to deal with.
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
      : exact.get(idPath(meta.schemaId)) ??
        loose.get(idPath(meta.schemaId, { loose: true })) ??
        walkToId(schema, meta.schemaId);
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

  addFormMetadata(entry, sources, [
    ['sidecar', formSidecarEntry],
    ['baseline', baseline?.formMetadata],
  ]);

  const description = facts.description ?? baseline?.description;
  if (description) entry.description = description;

  return { entry, sources, gaps };
}

/**
 * Sets the entry's formMetadata from the first candidate that has one, its schemaIds pointed at the
 * entry's schema. Properties inherited from the baseline that still point at nothing are dropped and
 * listed in sources.droppedFormMetadata: nobody in the repo wrote them, so they shouldn't stop a
 * release, and a sidecar entry brings them back. Anything else that points at nothing stays for the
 * gate to fail on.
 */
function addFormMetadata(entry, sources, candidates) {
  const [source, formMetadata] = candidates.find(([, value]) => value) ?? [];
  if (!formMetadata) return;
  let { formMetadata: resolved, rewrites } = resolveSchemaIds(formMetadata, entry.schema);
  sources.formMetadata = source;
  if (rewrites.length) sources.schemaIdRewrites = rewrites;
  const properties = resolved.propertyMetadata?.properties;
  if (source === 'baseline' && properties) {
    const ids = schemaIds(entry.schema);
    const dropped = Object.entries(properties).filter(([, meta]) => !ids.has(meta?.schemaId));
    if (dropped.length) {
      sources.droppedFormMetadata = dropped.map(([name, meta]) => `${name} (${meta?.schemaId})`);
      const kept = Object.fromEntries(Object.entries(properties).filter(([, meta]) => ids.has(meta?.schemaId)));
      resolved = { ...resolved, propertyMetadata: { ...resolved.propertyMetadata, properties: kept } };
      if (!Object.keys(kept).length && Object.keys(resolved).length === 1 && Object.keys(resolved.propertyMetadata).length === 1) {
        delete sources.formMetadata;
        return;
      }
    }
  }
  entry.formMetadata = resolved;
}

/**
 * A typeName the repo declares in .pepperdash/type-names.json because no factory creates it (the
 * control systems Essentials runs on, say). The declaration is the whole entry; formMetadata still
 * comes from the form metadata sidecar first, and the baseline fills what the declaration leaves out.
 */
export function assembleDeclaredTypeName(declared, baseline, formSidecarEntry) {
  const { formMetadata: declaredForm, ...rest } = structuredClone(declared);
  const entry = { ...rest };
  const sources = { declared: true, schema: 'declared', interfaces: 'declared', routingPorts: 'declared' };
  for (const field of ['label', 'description', 'routingPorts', ...CARRIED_FIELDS]) {
    if (entry[field] === undefined && baseline?.[field] !== undefined) {
      entry[field] = baseline[field];
      if (field === 'routingPorts') sources.routingPorts = 'baseline';
    }
  }
  addFormMetadata(entry, sources, [
    ['sidecar', formSidecarEntry],
    ['declared', declaredForm],
    ['baseline', baseline?.formMetadata],
  ]);
  return { entry, sources, gaps: [] };
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
export function assemble({ facts, baseline, formSidecar, typeNamesSidecar, release }) {
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
  // Only from this build's restore: the csproj can change it between releases
  if (release.kind === 'plugin' && facts?.essentialsDependencyVersion) {
    doc.essentialsDependencyVersion = facts.essentialsDependencyVersion;
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
    // A declaration of a typeName a factory also has is the gate's to report; the code's wins
    for (const typeName of Object.keys(typeNamesSidecar?.typeNames ?? {}).sort()) {
      if (lookup(facts.typeNames, typeName)) continue;
      const { entry, sources, gaps } = assembleDeclaredTypeName(
        typeNamesSidecar.typeNames[typeName],
        lookup(baseline?.typeNames, typeName),
        lookup(formSidecar?.typeNames, typeName),
      );
      doc.typeNames[typeName] = entry;
      report[typeName] = { sources, gaps };
    }
  }
  return { doc, report };
}

// Bump when the agent's instructions or output change, so documents record which version filled them
export const PROMPT_VERSION = '1';

// A config property named like a reference to another part of the config (displayDeviceKey,
// roomKeys, externalSourceInputPort): the config tool can draw these as pickers
const REFERENCE_NAME = /[a-z0-9](Key|Keys|InputPort|InputPorts|OutputPort|OutputPorts)$/;

/** The schema node a property path ("monitor.pollInterval", "activeInputs[].key", "map{}.x") names */
export function schemaNodeAt(schema, path) {
  let node = schema?.$defs?.propertiesConfig;
  for (const segment of path.match(/[^.[\]{}]+|\[\]|\{\}/g) ?? []) {
    if (!node || typeof node !== 'object') return undefined;
    if (segment === '[]') node = node.items;
    else if (segment === '{}') node = node.additionalProperties;
    else node = node.properties?.[segment];
  }
  return node && typeof node === 'object' ? node : undefined;
}

/** Paths of the string and string-array properties named like references, at any depth */
function referenceProperties(schema) {
  const found = [];
  const isString = (p) => p?.type === 'string' || (p?.type === 'array' && p.items?.type === 'string');
  const walk = (node, path) => {
    if (node?.items && typeof node.items === 'object') walk(node.items, `${path}[]`);
    // Dictionary<string, T> values, as the extractor writes them
    if (node?.additionalProperties && typeof node.additionalProperties === 'object') {
      walk(node.additionalProperties, `${path}{}`);
    }
    for (const [name, property] of Object.entries(node?.properties ?? {})) {
      const propertyPath = path ? `${path}.${name}` : name;
      if (REFERENCE_NAME.test(name) && isString(property)) found.push(propertyPath);
      walk(property, propertyPath);
    }
  };
  walk(schema?.$defs?.propertiesConfig, '');
  return found;
}

/**
 * What the code, the sidecars and the baseline left empty, per typeName: what the agent is asked
 * to fill. Form hints are only asked for when nothing gave the typeName any formMetadata, so a
 * developer's sidecar is never added to.
 */
export function findGaps({ doc, report, facts }) {
  const gaps = [];
  for (const [typeName, entry] of Object.entries(doc.typeNames)) {
    const typeFacts = facts?.typeNames?.[typeName] ?? {};
    const sources = report[typeName]?.sources ?? {};
    // A declared typeName has no classes for the agent to read; the declaration is the whole entry
    if (sources.declared) continue;
    const gap = {
      typeName,
      factory: typeFacts.factory ?? null,
      deviceClass: typeFacts.deviceClass ?? null,
      configClass: typeFacts.configClass ?? null,
      label: entry.label === undefined,
      description: !entry.description,
      properties: sources.descriptions?.missing ?? [],
      unresolvedPorts: sources.routingPorts === 'code (partial)' ? typeFacts.routingPorts?.unresolved ?? [] : [],
      formCandidates: entry.formMetadata ? [] : referenceProperties(entry.schema),
    };
    if (gap.label || gap.description || gap.properties.length || gap.unresolvedPorts.length || gap.formCandidates.length) {
      gaps.push(gap);
    }
  }
  return gaps;
}

const definitions = metadataSchema.definitions;
const nullable = (schema) => ({ anyOf: [schema, { type: 'null' }] });
const agentPort = {
  type: 'object',
  additionalProperties: false,
  required: ['name', 'label', 'signalType', 'portConnectionType'],
  properties: {
    name: { type: 'string' },
    label: { type: 'string' },
    signalType: { enum: definitions.routingPort.properties.signalType.enum },
    portConnectionType: { enum: definitions.routingPort.properties.portConnectionType.enum },
  },
};

/**
 * What the agent returns, as a structured output: lists rather than objects keyed by name, since
 * structured outputs need every object closed. specifiedOptions is left out of the datasets because
 * it also needs the options themselves.
 */
export const AGENT_OUTPUT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['typeNames'],
  properties: {
    typeNames: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['typeName', 'label', 'description', 'propertyDescriptions', 'routingPorts', 'formMetadata'],
        properties: {
          typeName: { type: 'string' },
          label: nullable({ type: 'string' }),
          description: nullable({ type: 'string' }),
          propertyDescriptions: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['path', 'description'],
              properties: { path: { type: 'string' }, description: { type: 'string' } },
            },
          },
          routingPorts: nullable({
            type: 'object',
            additionalProperties: false,
            required: ['inputs', 'outputs'],
            properties: { inputs: { type: 'array', items: agentPort }, outputs: { type: 'array', items: agentPort } },
          }),
          formMetadata: {
            type: 'array',
            items: {
              type: 'object',
              additionalProperties: false,
              required: ['path', 'formElement', 'dataset'],
              properties: {
                path: { type: 'string' },
                formElement: { enum: definitions.formPropertyMetadata.properties.formElement.enum },
                dataset: {
                  enum: definitions.formPropertyMetadata.properties.items.properties.dataset.enum
                    .filter((d) => d !== 'specifiedOptions'),
                },
              },
            },
          },
        },
      },
    },
  },
};
export const validateAgentOutput = ajv.compile(AGENT_OUTPUT_SCHEMA);

/**
 * Fills the gaps from the agent's answer and nothing else: a field the agent answers that wasn't a
 * gap, or a property path it invents, is ignored. Ports are only added (by name), never replaced.
 * Returns the new document, the report updated to match it, and what was filled, as
 * "typeName: field" strings.
 */
export function applyAgent({ doc, report = {}, gaps, result, agent }) {
  const out = structuredClone(doc);
  const outReport = structuredClone(report);
  const filled = [];
  const answers = new Map((result?.typeNames ?? []).map((t) => [t.typeName, t]));
  for (const gap of gaps) {
    const answer = answers.get(gap.typeName);
    const entry = out.typeNames[gap.typeName];
    if (!answer || !entry) continue;
    const note = (field) => filled.push(`${gap.typeName}: ${field}`);
    const sources = outReport[gap.typeName]?.sources ?? {};

    if (gap.label && answer.label?.trim()) {
      entry.label = answer.label.trim();
      note('label');
    }
    if (gap.description && answer.description?.trim()) {
      entry.description = answer.description.trim();
      note('description');
    }

    const wanted = new Set(gap.properties);
    const described = new Set();
    for (const { path, description } of answer.propertyDescriptions ?? []) {
      const node = wanted.has(path) ? schemaNodeAt(entry.schema, path) : undefined;
      if (node && !node.description && description.trim()) {
        node.description = description.trim();
        described.add(path);
      }
    }
    if (described.size) {
      note(`${described.size} property description${described.size === 1 ? '' : 's'}`);
      if (sources.descriptions) {
        sources.descriptions = {
          ...sources.descriptions,
          agent: described.size,
          missing: sources.descriptions.missing.filter((p) => !described.has(p)),
        };
      }
    }

    if (gap.unresolvedPorts.length && answer.routingPorts) {
      const ports = { inputs: [...(entry.routingPorts?.inputs ?? [])], outputs: [...(entry.routingPorts?.outputs ?? [])] };
      let added = 0;
      for (const side of ['inputs', 'outputs']) {
        const names = new Set(ports[side].map((p) => p.name.toLowerCase()));
        for (const port of answer.routingPorts[side]) {
          if (!port.name || names.has(port.name.toLowerCase())) continue;
          ports[side].push(port);
          names.add(port.name.toLowerCase());
          added++;
        }
      }
      if (added) {
        entry.routingPorts = ports;
        note(`${added} routing port${added === 1 ? '' : 's'}`);
        sources.routingPorts = 'code + agent';
        const gapList = outReport[gap.typeName]?.gaps;
        if (gapList) outReport[gap.typeName].gaps = gapList.filter((g) => !g.startsWith('routingPorts'));
      }
    }

    if (gap.formCandidates.length && answer.formMetadata?.length) {
      const properties = {};
      for (const { path, formElement, dataset } of answer.formMetadata) {
        const node = gap.formCandidates.includes(path) ? schemaNodeAt(entry.schema, path) : undefined;
        // Keyed by property name, as the config tool reads it
        const name = path.split(/[.[\]{}]+/).filter(Boolean).pop();
        if (!node?.$id || properties[name]) continue;
        properties[name] = { schemaId: node.$id, formElement, items: { dataset } };
      }
      if (Object.keys(properties).length) {
        entry.formMetadata = { propertyMetadata: { properties } };
        note(`formMetadata for ${Object.keys(properties).join(', ')}`);
        sources.formMetadata = 'agent';
      }
    }
  }
  if (filled.length) out.generator = { ...out.generator, prompt: PROMPT_VERSION, agent };
  return { doc: out, report: outReport, filled };
}

function describeErrors(errors) {
  return (errors ?? []).map((e) => {
    const detail = e.keyword === 'additionalProperties' ? ` (${e.params.additionalProperty})` : '';
    return `${e.instancePath || '/'} ${e.message}${detail}`;
  });
}

/** The checks that must pass before anything is published. Errors fail the build. */
export function gate({ doc, facts, formSidecar, typeNamesSidecar, report = {} }) {
  const errors = [];
  // What the extractor couldn't read (a property left out for a missing reference, say)
  const warnings = (facts.warnings ?? []).map((w) => `metadata-extract: ${w}`);

  if (!validateMetadata(doc)) {
    errors.push(...describeErrors(validateMetadata.errors).map((e) => `pepperdash-metadata.json: ${e}`));
  }

  if (!NO_DEVICE_KINDS.includes(doc.kind)) {
    const factoryNames = Object.keys(facts.typeNames);
    const declaredNames = Object.keys(typeNamesSidecar?.typeNames ?? {});
    // Essentials matches typeNames ignoring case, so these would be two entries for one device type
    declaredNames.forEach((typeName, i) => {
      const earlier = declaredNames.slice(0, i).find((t) => t.toLowerCase() === typeName.toLowerCase());
      if (earlier) errors.push(`.pepperdash/type-names.json: ${typeName} and ${earlier} differ only in case; keep one`);
    });
    for (const typeName of declaredNames) {
      const factory = factoryNames.find((t) => t.toLowerCase() === typeName.toLowerCase());
      if (factory) errors.push(`.pepperdash/type-names.json: ${typeName} is also a factory TypeName (${factory}); remove the declaration`);
    }
    const expected = [...factoryNames, ...declaredNames.filter((d) => !lookup(facts.typeNames, d))].sort().join(',');
    const actual = Object.keys(doc.typeNames).sort().join(',');
    if (expected !== actual) errors.push("typeNames differ from the factories' TypeNames and .pepperdash/type-names.json");

    // An empty extraction would otherwise publish, and become the next release's baseline
    const extracted = Object.entries(facts.typeNames);
    const unread = extracted.filter(([, entry]) => entry.interfaces == null).map(([typeName]) => typeName);
    if (extracted.length === 0) {
      errors.push('metadata-extract found no factory TypeNames');
    } else if (unread.length === extracted.length) {
      errors.push("metadata-extract couldn't read the built assemblies: no typeName has interfaces or a schema");
    } else if (unread.length) {
      warnings.push(`metadata-extract couldn't read the interfaces of ${unread.sort().join(', ')}`);
    }
  }

  if (typeNamesSidecar && !validateTypeNamesSidecar(typeNamesSidecar)) {
    errors.push(...describeErrors(validateTypeNamesSidecar.errors).map((e) => `.pepperdash/type-names.json: ${e}`));
  }

  for (const [typeName, { sources }] of Object.entries(report)) {
    if (sources?.droppedFormMetadata?.length) {
      warnings.push(`${typeName}: left out the baseline's formMetadata for ${sources.droppedFormMetadata.join(', ')}, which points at nothing in this release's schema; add it to .pepperdash/form-metadata.json to keep it`);
    }
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
export function summarize({ doc, report, gateResult, changes, agent }) {
  const lines = [`## pepperdash-metadata.json for ${doc.tag}`, ''];
  if (gateResult.errors.length) {
    lines.push('**Gate failed**', '', ...gateResult.errors.map((e) => `- ${e}`), '');
  } else {
    lines.push('Gate passed.', '');
  }
  if (gateResult.warnings.length) lines.push(...gateResult.warnings.map((w) => `- Warning: ${w}`), '');
  if (agent?.filled.length) {
    lines.push(`<details><summary>Filled by the AI agent (${doc.generator.agent}, prompt ${doc.generator.prompt})</summary>`, '');
    lines.push(...agent.filled.map((f) => `- ${f}`), '', '</details>', '');
  }

  const typeNames = Object.keys(report);
  if (typeNames.length) {
    lines.push(
      '| typeName | schema | descriptions | interfaces | routingPorts | formMetadata | gaps |',
      '|---|---|---|---|---|---|---|',
    );
    for (const typeName of typeNames) {
      const { sources, gaps } = report[typeName];
      const d = sources.descriptions;
      const descriptions = d
        ? `${d.code} code, ${d.baseline} baseline, ${d.agent ? `${d.agent} agent, ` : ''}${d.missing.length} missing`
        : '–';
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
