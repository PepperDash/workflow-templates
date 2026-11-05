"""Clone, build and extract the newest mock version of every package.

python3 run_all.py <export dir> <work dir> [--only owner/repo,...] [--overrides overrides.json]

Writes <work>/facts/<owner>__<repo>.json and <work>/runs.json (what happened per repo).

--overrides is a JSON file kept outside this (public) repo, so no private repo names are committed:
  {
    "pinned":      { "owner/repo": "version" },  // branch prereleases don't sort by date: the version to use
    "tagOverride": { "owner/repo": "vX.Y.Z" }    // mock-only version with no tag: compare against this tag
  }
"""
import glob
import json
import os
import sys

EXPORT, WORK = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[sys.argv.index('--only') + 1].split(',')) if '--only' in sys.argv else None
OVERRIDES = json.load(open(sys.argv[sys.argv.index('--overrides') + 1])) if '--overrides' in sys.argv else {}
PINNED = OVERRIDES.get('pinned', {})
TAG_OVERRIDE = OVERRIDES.get('tagOverride', {})

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from build_and_extract import build_and_extract, run  # noqa: E402

def newest_versions():
    """{owner/repo: (version, packageId)} using the last version file the export wrote per repo."""
    out = {}
    for owner in sorted(os.listdir(EXPORT)):
        if owner == 'sidecars' or not os.path.isdir(os.path.join(EXPORT, owner)):
            continue
        for repo in sorted(os.listdir(os.path.join(EXPORT, owner))):
            docs = [json.load(open(f)) for f in glob.glob(os.path.join(EXPORT, owner, repo, '*.json'))]
            # The mocks list versions oldest first; the export doesn't keep order, so sort semver-ish
            def key(d):
                # Build metadata (+build.5) doesn't affect precedence
                core, _, pre = d['version'].split('+')[0].partition('-')
                ids = [(0, int(x), '') if x.isdigit() else (1, 0, x) for x in pre.split('.')] if pre else []
                return ([int(x) for x in core.split('.')], 0 if pre else 1, ids)
            docs.sort(key=key)
            out[f'{owner}/{repo}'] = (docs[-1]['version'], docs[-1]['packageId'])
            pinned = PINNED.get(f'{owner}/{repo}')
            if pinned:
                out[f'{owner}/{repo}'] = (pinned, docs[-1]['packageId'])
    return out

os.makedirs(os.path.join(WORK, 'repos'), exist_ok=True)
os.makedirs(os.path.join(WORK, 'facts'), exist_ok=True)
# --only updates the earlier runs instead of replacing them
runs_path = os.path.join(WORK, 'runs.json')
runs = json.load(open(runs_path)) if ONLY and os.path.exists(runs_path) else {}
for full, (version, package_id) in newest_versions().items():
    if ONLY and full not in ONLY:
        continue
    owner, repo = full.split('/')
    record = runs[full] = {'version': version, 'packageId': package_id}
    # An earlier run's facts must not stand in for this attempt if it fails
    facts_path = os.path.join(WORK, 'facts', f'{owner}__{repo}.json')
    if os.path.exists(facts_path):
        os.remove(facts_path)
    if full in TAG_OVERRIDE:
        record['comparedAgainstTag'] = TAG_OVERRIDE[full]
    # Keyed by what's checked out, so changing a tagOverride clones the new tag
    repo_dir = os.path.join(WORK, 'repos', f'{owner}__{repo}@{TAG_OVERRIDE.get(full, version)}')
    if not os.path.isdir(repo_dir):
        for tag in ([TAG_OVERRIDE[full]] if full in TAG_OVERRIDE else [f'v{version}', version]):
            code, out = run(['gh', 'repo', 'clone', full, repo_dir, '--', '-q', '--depth', '1', '--branch', tag])
            if code == 0:
                record['tag'] = tag
                break
        else:
            record['status'] = 'no-tag'
            record['detail'] = out.strip().splitlines()[-1:] if out else []
            print(f'{full}@{version}: no tag')
            continue

    built = build_and_extract(repo_dir, facts_path)
    record.update({k: v for k, v in built.items() if k != 'packageId'})
    print(f"{full}@{version}: {record['status']} ({len(record['assemblies'])} assemblies{', build errors' if 'buildErrors' in record else ''})")

json.dump(runs, open(os.path.join(WORK, 'runs.json'), 'w'), indent=2)
