"""Compare extracted facts with the config tool's mock metadata.

python3 compare.py <export dir> <work dir>

Writes <work>/comparison.json (everything) and <work>/comparison.md (the report).
"""
import json
import os
import sys
from collections import Counter, defaultdict

EXPORT, WORK = sys.argv[1], sys.argv[2]
runs = json.load(open(os.path.join(WORK, 'runs.json')))

# Every interface that Essentials v3 defines is listed in each facts file's definedInterfaces;
# a mock-only name outside that set (and outside the plugin) is a v2 name or a tool-only marker.
ROUTING_V2 = {'IRoutingSink', 'IRoutingSinkWithSwitching', 'IRoutingSinkNoSwitching', 'IRoutingInputsOutputs',
              'IRoutingSinkWithSwitchingWithInputPort', 'IRoutingSinkWithInputPort'}


def flatten(schema, prefix='', out=None):
    """{path: type} for every property under $defs.propertiesConfig."""
    if out is None:
        out = {}
    if not isinstance(schema, dict):
        return out
    for name, prop in (schema.get('properties') or {}).items():
        path = f'{prefix}/{name}'
        out[path] = prop.get('type') if isinstance(prop, dict) else None
        if isinstance(prop, dict):
            flatten(prop, path, out)
            if isinstance(prop.get('items'), dict):
                flatten(prop['items'], f'{path}[]', out)
            if isinstance(prop.get('additionalProperties'), dict):
                flatten(prop['additionalProperties'], f'{path}{{}}', out)
    return out


def config_def(schema):
    if not isinstance(schema, dict):
        return None
    return (schema.get('$defs') or {}).get('propertiesConfig') or schema


def default_paths(value, prefix=''):
    if isinstance(value, dict):
        out = set()
        for k, v in value.items():
            out.add(f'{prefix}/{k}')
            out |= default_paths(v, f'{prefix}/{k}')
        return out
    return set()


results = {}
interface_buckets = defaultdict(Counter)  # bucket -> Counter(name)
for full, run in sorted(runs.items()):
    owner, repo = full.split('/')
    mock = json.load(open(os.path.join(EXPORT, owner, repo, f"{run['version']}.json")))
    facts_path = os.path.join(WORK, 'facts', f'{owner}__{repo}.json')
    # Facts files aren't versioned: one left by an earlier run belongs to another attempt
    ran = run.get('status') in ('ok', 'source-only') and os.path.exists(facts_path)
    facts = json.load(open(facts_path)) if ran else None
    # Denominators come from every mock typeName, whether or not it was extracted or matched
    mock_tns = mock['typeNames'].values()
    entry = results[full] = {'version': run['version'], 'status': run.get('status'),
                             'buildErrors': run.get('buildErrors'), 'typeNames': {},
                             'mock': {'typeNames': len(mock['typeNames']),
                                      'interfaces': sum(len(m.get('interfaces') or []) for m in mock_tns),
                                      'schemaProperties': sum(len(flatten(config_def(m.get('schema')))) for m in mock_tns),
                                      'ports': sum(len((m.get('routingPorts') or {}).get(s) or [])
                                                   for m in mock_tns for s in ('inputs', 'outputs'))},
                             'interfacesAvailable': False, 'schemasAvailable': False}
    if not facts:
        continue
    entry['interfacesAvailable'] = any(t.get('interfaces') is not None for t in facts['typeNames'].values())
    entry['schemasAvailable'] = any(t.get('schema') is not None for t in facts['typeNames'].values())
    defined = set(facts.get('definedInterfaces') or [])
    mock_types, real_types = set(mock['typeNames']), set(facts['typeNames'])
    # Essentials looks types up case-insensitively
    real_lower = {t.lower(): t for t in real_types}
    entry['mockOnlyTypeNames'] = sorted(t for t in mock_types if t.lower() not in real_lower)
    entry['codeOnlyTypeNames'] = sorted(t for t in real_types if t.lower() not in {m.lower() for m in mock_types})
    entry['minimumEssentialsVersion'] = facts.get('minimumEssentialsVersion')
    entry['warnings'] = facts.get('warnings')

    for type_name in sorted(mock_types):
        real_name = real_lower.get(type_name.lower())
        if not real_name:
            continue
        m, r = mock['typeNames'][type_name], facts['typeNames'][real_name]
        t = entry['typeNames'][type_name] = {'configClass': r.get('configClass'),
                                              'configClassSource': r.get('configClassSource')}
        if real_name != type_name:
            t['caseDiffers'] = real_name

        # Interfaces
        if r.get('interfaces') is not None:
            mock_ifs, real_ifs = set(m.get('interfaces') or []), set(r['interfaces'])
            missing = sorted(mock_ifs - real_ifs)
            buckets = {}
            for name in missing:
                if name in ROUTING_V2:
                    bucket = 'v2-routing-name'
                elif name in defined:
                    bucket = 'defined-not-implemented'
                else:
                    bucket = 'defined-nowhere'
                buckets[name] = bucket
                interface_buckets[bucket][name] += 1
            t['interfaces'] = {'matched': sorted(mock_ifs & real_ifs), 'mockOnly': buckets,
                               'codeOnly': sorted(real_ifs - mock_ifs)}

        # Schema
        if r.get('schema') is not None:
            mock_paths = flatten(config_def(m.get('schema')))
            real_paths = flatten(config_def(r['schema']))
            mock_lower = {p.lower(): p for p in mock_paths}
            real_lower_paths = {p.lower(): p for p in real_paths}
            t['schema'] = {
                'mockProperties': len(mock_paths),
                'matched': sum(1 for p in mock_lower if p in real_lower_paths),
                'mockOnly': sorted(mock_lower[p] for p in mock_lower if p not in real_lower_paths),
                'codeOnly': sorted(real_lower_paths[p] for p in real_lower_paths if p not in mock_lower),
                'typeMismatches': sorted(
                    f'{mock_lower[p]}: mock {mock_paths[mock_lower[p]]}, code {real_paths[real_lower_paths[p]]}'
                    for p in mock_lower if p in real_lower_paths
                    and mock_paths[mock_lower[p]] != real_paths[real_lower_paths[p]]),
                'mockDefaults': len(default_paths((config_def(m.get('schema')) or {}).get('default'))),
                'codeDefaults': len(default_paths((config_def(r['schema']) or {}).get('default'))),
            }

        # Routing ports
        ports = {}
        for side in ('inputs', 'outputs'):
            # Essentials looks port keys up case-insensitively; a case-only difference is listed
            # under differs, since the config tool matches tie-line ports exactly
            mp = {p['name'].lower(): p for p in ((m.get('routingPorts') or {}).get(side) or [])}
            rp = {p['name'].lower(): p for p in (r['routingPorts'].get(side) or [])}
            ports[side] = {
                'mock': len(mp), 'code': len(rp), 'matched': len(set(mp) & set(rp)),
                'mockOnly': sorted(mp[k]['name'] for k in set(mp) - set(rp)),
                'codeOnly': sorted(rp[k]['name'] for k in set(rp) - set(mp)),
                'differs': sorted(
                    f"{mp[k]['name']}: {f} mock {mp[k][f]}, code {rp[k][f]}"
                    for k in set(mp) & set(rp) for f in ('name', 'signalType', 'portConnectionType')
                    if mp[k][f] != rp[k][f]),
            }
        ports['unresolved'] = len(r['routingPorts'].get('unresolved') or [])
        t['routingPorts'] = ports

json.dump({'packages': results, 'interfaceBuckets': {k: dict(v) for k, v in interface_buckets.items()}},
          open(os.path.join(WORK, 'comparison.json'), 'w'), indent=2)

# Report
lines = ['# Extracted metadata vs mock metadata', '']
statuses = Counter(r['status'] for r in results.values())
lines.append('Runs: ' + ', '.join(f'{v} {k}' for k, v in sorted(statuses.items())))
lines.append('')
lines.append('Denominators count every mock typeName. n/a: the run produced no interfaces or schemas to compare '
             '(no facts, or source only), so those count as unmatched in the totals.')
lines.append('')
lines.append('| Package | Version | Status | typeNames matched / mock | Interfaces matched / mock | Schema props matched / mock | Ports matched / mock (unresolved) |')
lines.append('|---|---|---|---|---|---|---|')
totals = Counter()
for full, r in results.items():
    tn, mock = r['typeNames'], r['mock']
    ifm = sum(len(t.get('interfaces', {}).get('matched', [])) for t in tn.values())
    sm = sum(t.get('schema', {}).get('matched', 0) for t in tn.values())
    pm = sum(t['routingPorts'][s]['matched'] for t in tn.values() for s in ('inputs', 'outputs'))
    pun = sum(t['routingPorts']['unresolved'] for t in tn.values())
    totals.update(tn=len(tn), tnmock=mock['typeNames'], ifm=ifm, ifmock=mock['interfaces'],
                  sm=sm, smock=mock['schemaProperties'], pm=pm, pmock=mock['ports'])
    ifs = f"{ifm}/{mock['interfaces']}" if r['interfacesAvailable'] else f"n/a ({mock['interfaces']})"
    schema = f"{sm}/{mock['schemaProperties']}" if r['schemasAvailable'] else f"n/a ({mock['schemaProperties']})"
    lines.append(f"| {full} | {r['version']} | {r['status']} | {len(tn)}/{mock['typeNames']} | {ifs} | {schema} | {pm}/{mock['ports']} ({pun}) |")
lines.append(f"| **Total** | | | {totals['tn']}/{totals['tnmock']} | {totals['ifm']}/{totals['ifmock']} | {totals['sm']}/{totals['smock']} | {totals['pm']}/{totals['pmock']} |")
lines.append('')
lines.append('## Mock-only interfaces')
for bucket, names in sorted(interface_buckets.items()):
    lines.append(f'### {bucket}')
    for name, count in names.most_common():
        lines.append(f'- `{name}` on {count} typeNames')
    lines.append('')
open(os.path.join(WORK, 'comparison.md'), 'w').write('\n'.join(lines) + '\n')
print('\n'.join(lines))
