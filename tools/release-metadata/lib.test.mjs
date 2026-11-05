import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  assemble,
  assembleTypeName,
  assetTypeOf,
  diff,
  gate,
  idPath,
  labelFor,
  mergeSchemaText,
  resolveSchemaIds,
  summarize,
  versionOf,
} from './lib.mjs';

const schemaWith = (...names) => ({
  $schema: 'http://json-schema.org/draft-07/schema#',
  type: 'object',
  $defs: {
    propertiesConfig: {
      type: 'object',
      properties: Object.fromEntries(names.map((n) => [n, { $id: `#root/${n}`, type: 'string' }])),
    },
  },
});

const port = (name) => ({ name, label: name, signalType: 'audioVideo', portConnectionType: 'Hdmi' });

const facts = (overrides = {}) => ({
  factory: 'Factory',
  deviceClass: 'Device',
  description: null,
  interfaces: ['IRoutingSinkWithFeedback'],
  schema: schemaWith('host'),
  routingPorts: { inputs: [port('HdmiIn1')], outputs: [], unresolved: [] },
  ...overrides,
});

const formEntry = (schemaId) => ({
  propertyMetadata: {
    properties: { host: { schemaId, formElement: 'SelectInputText', items: { dataset: 'devices' } } },
  },
});

const release = {
  kind: 'plugin',
  packageId: 'PepperDash.Essentials.Plugins.Test',
  label: 'Test',
  tag: 'v1.2.0-beta.1',
  repoUrl: 'https://github.com/PepperDash/epi-test',
  commitSha: 'a'.repeat(40),
  publishedAt: '2026-11-04T12:00:00Z',
  assets: [{ name: 'epi-test.1.2.0-beta.1.cplz', type: 'cplz', size: 10, sha256: 'b'.repeat(64) }],
};

describe('assembleTypeName', () => {
  it('takes schema, interfaces and ports from the code', () => {
    const { entry, sources, gaps } = assembleTypeName(facts(), { interfaces: ['IOld'], schema: schemaWith('old') });
    assert.deepEqual(entry.interfaces, ['IRoutingSinkWithFeedback']);
    assert.ok(entry.schema.$defs.propertiesConfig.properties.host);
    assert.deepEqual(entry.routingPorts, { inputs: [port('HdmiIn1')], outputs: [] });
    assert.deepEqual(sources, {
      schema: 'code',
      descriptions: { code: 0, baseline: 0, missing: ['host'] },
      interfaces: 'code',
      routingPorts: 'code',
    });
    assert.deepEqual(gaps, []);
  });

  it('falls back to the baseline, then reports a gap', () => {
    const fromBaseline = assembleTypeName(facts({ schema: null, interfaces: null }), {
      schema: schemaWith('old'),
      interfaces: ['IOld'],
    });
    assert.deepEqual(fromBaseline.entry.interfaces, ['IOld']);
    assert.equal(fromBaseline.sources.schema, 'baseline');

    const empty = assembleTypeName(facts({ schema: null, interfaces: null }), undefined);
    assert.deepEqual(empty.entry.interfaces, []);
    assert.deepEqual(empty.gaps, ['schema', 'interfaces']);
  });

  it("uses the baseline's ports when the code couldn't read them all", () => {
    const baseline = { routingPorts: { inputs: [port('a'), port('b')], outputs: [] } };
    const unresolved = facts({ routingPorts: { inputs: [port('a')], outputs: [], unresolved: ['x.cs:1: new RoutingInputPort(k, ...)'] } });
    assert.equal(assembleTypeName(unresolved, baseline).sources.routingPorts, 'baseline');
    assert.deepEqual(assembleTypeName(unresolved, undefined).gaps, ['routingPorts (1 unresolved)']);

    // Ports added by helper classes: nothing found, nothing unresolved
    const none = facts({ routingPorts: { inputs: [], outputs: [], unresolved: [] } });
    assert.deepEqual(assembleTypeName(none, baseline).entry.routingPorts, baseline.routingPorts);
    assert.equal(assembleTypeName(none, undefined).entry.routingPorts, undefined);
  });

  it('carries UI hints forward and prefers the sidecar for formMetadata', () => {
    const baseline = {
      label: 'Old label',
      controlMethods: { tcpip: { label: 'TCP/IP' } },
      deviceKind: 'device',
      formMetadata: formEntry('#root/host'),
    };
    const { entry, sources } = assembleTypeName(facts({ description: 'From [Description]' }), baseline, formEntry('#root/propertiesConfig/host'));
    assert.equal(entry.label, 'Old label');
    assert.deepEqual(entry.controlMethods, baseline.controlMethods);
    assert.equal(entry.deviceKind, 'device');
    assert.equal(entry.description, 'From [Description]');
    assert.equal(sources.formMetadata, 'sidecar');
    assert.equal(entry.formMetadata.propertyMetadata.properties.host.schemaId, '#root/host');
  });
});

describe('mergeSchemaText', () => {
  const withText = (schema, text) => {
    const copy = structuredClone(schema);
    for (const [name, value] of Object.entries(text)) Object.assign(copy.$defs.propertiesConfig.properties[name], value);
    return copy;
  };

  it("keeps the code's descriptions and fills the rest from the baseline", () => {
    const code = withText(schemaWith('host', 'port', 'extra'), {
      host: { title: 'Host', description: 'From the summary' },
      port: { title: 'Port' },
    });
    const baseline = withText(schemaWith('host', 'Port'), {
      host: { title: 'Host name', description: 'Old text' },
      Port: { title: 'TCP port', description: 'The port to connect to' },
    });
    const { schema, descriptions } = mergeSchemaText(code, baseline);
    const properties = schema.$defs.propertiesConfig.properties;
    assert.deepEqual(properties.host, { $id: '#root/host', type: 'string', title: 'Host name', description: 'From the summary' });
    // Matched without regard to case, as Essentials reads config
    assert.deepEqual(properties.port, { $id: '#root/port', type: 'string', title: 'TCP port', description: 'The port to connect to' });
    assert.deepEqual(descriptions, { code: 1, baseline: 1, missing: ['extra'] });
    // The facts aren't changed
    assert.equal(code.$defs.propertiesConfig.properties.port.description, undefined);
  });

  it('walks nested objects and array items', () => {
    const nested = (description) => ({
      $defs: { propertiesConfig: { properties: {
        monitor: { type: 'object', properties: { timeout: { type: 'integer', ...description } } },
        inputs: { type: 'array', items: { type: 'object', properties: { name: { type: 'string', ...description } } } },
      } } },
    });
    const { schema, descriptions } = mergeSchemaText(nested({}), nested({ description: 'Old' }));
    const properties = schema.$defs.propertiesConfig.properties;
    assert.equal(properties.monitor.properties.timeout.description, 'Old');
    assert.equal(properties.inputs.items.properties.name.description, 'Old');
    assert.deepEqual(descriptions.missing, ['monitor', 'inputs']);

    assert.deepEqual(mergeSchemaText(nested({}), undefined).descriptions.missing, ['monitor', 'monitor.timeout', 'inputs', 'inputs[].name']);
  });

  it('lists what has no description in the job summary', () => {
    const { doc, report } = assemble({
      facts: { typeNames: { thing: facts() } },
      baseline: null,
      formSidecar: null,
      release: { kind: 'plugin', packageId: 'P', label: 'P', tag: 'v1.0.0', repoUrl: 'https://github.com/o/r', commitSha: 'a'.repeat(40), publishedAt: '2026-01-01T00:00:00Z', assets: [] },
    });
    const markdown = summarize({ doc, report, gateResult: { errors: [], warnings: [] }, changes: null });
    assert.match(markdown, /\| `thing` \| code \| 0 code, 0 baseline, 1 missing \|/);
    assert.match(markdown, /- `thing`: `host`/);
  });
});

describe('resolveSchemaIds', () => {
  const schema = {
    $defs: {
      propertiesConfig: {
        properties: {
          roomKeys: { $id: '#root/roomKeys', items: { $id: '#root/roomKeys/items' } },
          partitions: {
            $id: '#root/partitions',
            items: { $id: '#root/partitions/items', properties: { deviceKey: { $id: '#root/partitions/items/deviceKey' } } },
          },
        },
      },
    },
  };
  const form = (schemaId) => ({
    propertyMetadata: { properties: { p: { schemaId, formElement: 'SelectInputText', items: { dataset: 'devices' } } } },
  });
  const resolved = (schemaId) => resolveSchemaIds(form(schemaId), schema).formMetadata.propertyMetadata.properties.p.schemaId;

  it('maps the hand-written conventions onto the schema\'s $ids', () => {
    assert.equal(resolved('#root/propertiesConfig/roomKeys'), '#root/roomKeys');
    assert.equal(resolved('#root/properties/roomKeys/items'), '#root/roomKeys/items');
    assert.equal(resolved('#root/propertiesConfig/partitions/deviceKey'), '#root/partitions/items/deviceKey');
  });

  it('leaves a missing or non-string schemaId for the gate instead of throwing', () => {
    const formMetadata = { propertyMetadata: { properties: { a: { formElement: 'TextInput' }, b: { schemaId: 7 } } } };
    const { formMetadata: out, rewrites } = resolveSchemaIds(formMetadata, schema);
    assert.deepEqual(out.propertyMetadata.properties, formMetadata.propertyMetadata.properties);
    assert.deepEqual(rewrites, []);
  });

  it('leaves a schemaId that matches nothing for the gate', () => {
    assert.equal(resolved('#root/propertiesConfig/missing'), '#root/propertiesConfig/missing');
    assert.deepEqual(resolveSchemaIds(form('#root/roomKeys'), schema).rewrites, []);
  });

  it('normalizes paths', () => {
    assert.equal(idPath('#root/propertiesConfig/a/items/b'), '/a/items/b');
    assert.equal(idPath('#root/propertiesConfig/a/items/b', { loose: true }), '/a/b');
    assert.equal(idPath('#root/a/items', { loose: true }), '/a/items');
  });
});

describe('assemble and gate', () => {
  const extracted = { minimumEssentialsVersion: '3.0.0', typeNames: { testDevice: facts() } };

  it('produces a document that passes the gate', () => {
    const { doc } = assemble({ facts: extracted, baseline: null, formSidecar: null, release });
    assert.equal(doc.version, '1.2.0-beta.1');
    assert.equal(doc.prerelease, true);
    assert.equal(doc.minimumEssentialsVersion, '3.0.0');
    assert.deepEqual(gate({ doc, facts: extracted, formSidecar: null }), { errors: [], warnings: [] });
  });

  it('matches sidecar typeNames case-insensitively, with a warning', () => {
    const formSidecar = { typeNames: { TestDevice: formEntry('#root/host') } };
    const { doc } = assemble({ facts: extracted, baseline: null, formSidecar, release });
    assert.ok(doc.typeNames.testDevice.formMetadata);
    const result = gate({ doc, facts: extracted, formSidecar });
    assert.deepEqual(result.errors, []);
    assert.match(result.warnings[0], /TestDevice is spelt testDevice/);
  });

  it('fails on a sidecar typeName or schemaId that the release lacks', () => {
    const formSidecar = { typeNames: { testDevice: formEntry('#root/gone'), otherDevice: formEntry('#root/host') } };
    const { doc } = assemble({ facts: extracted, baseline: null, formSidecar, release });
    const { errors } = gate({ doc, facts: extracted, formSidecar });
    assert.equal(errors.length, 2);
    assert.match(errors[0], /otherDevice is not a typeName/);
    assert.match(errors[1], /points at #root\/gone/);
  });

  it('fails a document the schema rejects', () => {
    const { doc } = assemble({ facts: extracted, baseline: null, formSidecar: null, release: { ...release, commitSha: 'not-a-sha' } });
    assert.match(gate({ doc, facts: extracted, formSidecar: null }).errors[0], /commitSha/);
  });

  it('reads a hyphen in build metadata as part of a stable version', () => {
    const { doc } = assemble({ facts: extracted, baseline: null, formSidecar: null, release: { ...release, tag: 'v1.2.3+build-main' } });
    assert.equal(doc.version, '1.2.3+build-main');
    assert.equal(doc.prerelease, false);
  });

  it("keeps the baseline's minimum Essentials version when the code shows none", () => {
    const baseline = { minimumEssentialsVersion: '2.0.0', typeNames: {} };
    const unknown = { ...extracted, minimumEssentialsVersion: null };
    assert.equal(assemble({ facts: unknown, baseline, formSidecar: null, release }).doc.minimumEssentialsVersion, '2.0.0');
    assert.equal(assemble({ facts: extracted, baseline, formSidecar: null, release }).doc.minimumEssentialsVersion, '3.0.0');
  });

  it("passes the extractor's warnings on as gate warnings", () => {
    const warned = { ...extracted, warnings: ['TestConfig.Port: left out of the schema, missing reference: Crestron'] };
    const { doc } = assemble({ facts: warned, baseline: null, formSidecar: null, release });
    const { errors, warnings } = gate({ doc, facts: warned, formSidecar: null });
    assert.deepEqual(errors, []);
    assert.deepEqual(warnings, ['metadata-extract: TestConfig.Port: left out of the schema, missing reference: Crestron']);
  });

  it('gives UI kinds no typeNames', () => {
    const { doc } = assemble({ facts: null, baseline: null, formSidecar: null, release: { ...release, kind: 'userInterface' } });
    assert.deepEqual(doc.typeNames, {});
    assert.equal(doc.minimumEssentialsVersion, undefined);
    assert.deepEqual(gate({ doc, facts: { typeNames: {} }, formSidecar: null }).errors, []);
  });
});

describe('diff', () => {
  it('lists what changed since the baseline', () => {
    const { doc } = assemble({ facts: { typeNames: { a: facts(), b: facts() } }, baseline: null, formSidecar: null, release });
    const baseline = {
      version: '1.1.0',
      typeNames: { a: { interfaces: ['IOld'], schema: schemaWith('host'), routingPorts: { inputs: [port('HdmiIn1')], outputs: [] } }, c: {} },
    };
    assert.deepEqual(diff(baseline, doc), {
      baselineVersion: '1.1.0',
      added: ['b'],
      removed: ['c'],
      changed: { a: { interfaces: { added: ['IRoutingSinkWithFeedback'], removed: ['IOld'] } } },
    });
    assert.equal(diff(null, doc), null);
  });
});

describe('helpers', () => {
  it('derive labels, versions and asset types', () => {
    assert.equal(labelFor('plugin', 'epi-epson-projector'), 'Epson Projector');
    assert.equal(labelFor('essentials', 'Essentials'), 'Essentials');
    assert.equal(versionOf('v4.0.0-feature-x.5'), '4.0.0-feature-x.5');
    assert.equal(assetTypeOf('a.CPLZ'), 'cplz');
    assert.equal(assetTypeOf('a.nupkg'), null);
  });
});
