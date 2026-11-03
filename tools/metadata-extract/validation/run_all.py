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
import re
import subprocess
import sys

EXPORT, WORK = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[sys.argv.index('--only') + 1].split(',')) if '--only' in sys.argv else None
OVERRIDES = json.load(open(sys.argv[sys.argv.index('--overrides') + 1])) if '--overrides' in sys.argv else {}
PINNED = OVERRIDES.get('pinned', {})
TAG_OVERRIDE = OVERRIDES.get('tagOverride', {})
# Build the tool first: dotnet build tools/metadata-extract -c Release
EXTRACTOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'bin', 'Release', 'net8.0', 'metadata-extract.dll')

def run(cmd, cwd=None, timeout=900):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout + p.stderr

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
                core, _, pre = d['version'].partition('-')
                ids = [(0, int(x), '') if x.isdigit() else (1, 0, x) for x in pre.split('.')] if pre else []
                return ([int(x) for x in core.split('.')], 0 if pre else 1, ids)
            docs.sort(key=key)
            out[f'{owner}/{repo}'] = (docs[-1]['version'], docs[-1]['packageId'])
            pinned = PINNED.get(f'{owner}/{repo}')
            if pinned:
                out[f'{owner}/{repo}'] = (pinned, docs[-1]['packageId'])
    return out

def projects(repo_dir):
    found = [p for p in glob.glob(os.path.join(repo_dir, '**', '*.csproj'), recursive=True)
             if not re.search(r'[\\/](tests?|[^\\/]*\.Tests?)[\\/]|Tests?\.csproj$', p, re.I)]
    four = [p for p in found if '4series' in os.path.basename(p).lower()
            or re.search(r'<TargetFrameworks?>[^<]*net(6|8|9)', open(p, encoding='utf-8', errors='ignore').read())]
    return four or found

def output_dll(project):
    text = open(project, encoding='utf-8', errors='ignore').read()
    m = re.search(r'<AssemblyName>([^<$]+)</AssemblyName>', text)
    name = m.group(1).strip() if m else os.path.splitext(os.path.basename(project))[0]
    # OutputPath varies (src/4Series/bin/...), so look anywhere under the project's folder
    hits = sorted((h for h in glob.glob(os.path.join(os.path.dirname(project), '**', 'bin', 'Release', '**', f'{name}.dll'), recursive=True)
                   if os.sep + 'obj' + os.sep not in h),
                  key=os.path.getmtime)
    return hits[-1] if hits else None

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
    if full in TAG_OVERRIDE:
        record['comparedAgainstTag'] = TAG_OVERRIDE[full]
    repo_dir = os.path.join(WORK, 'repos', f'{owner}__{repo}@{version}')
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

    dlls, build_errors = [], []
    for project in projects(repo_dir):
        code, out = run(['dotnet', 'build', project, '-c', 'Release', '-nologo', '-v', 'q'])
        if code != 0:
            build_errors.append({'project': os.path.relpath(project, repo_dir),
                                 'errors': sorted({l.strip() for l in out.splitlines() if ': error ' in l})[:8]})
            continue
        dll = output_dll(project)
        if dll:
            dlls.append(dll)
    record['projects'] = [os.path.relpath(p, repo_dir) for p in projects(repo_dir)]
    record['assemblies'] = [os.path.relpath(d, repo_dir) for d in dlls]
    if build_errors:
        record['buildErrors'] = build_errors

    facts_path = os.path.join(WORK, 'facts', f'{owner}__{repo}.json')
    cmd = ['dotnet', EXTRACTOR, '--source', repo_dir, '--out', facts_path]
    for dll in dlls:
        cmd += ['--assembly', dll]
    code, out = run(cmd)
    record['status'] = 'ok' if code == 0 and dlls else ('source-only' if code == 0 else 'extract-failed')
    if code != 0:
        record['detail'] = out.strip().splitlines()[-5:]
    print(f"{full}@{version}: {record['status']} ({len(dlls)} assemblies{', build errors' if build_errors else ''})")

json.dump(runs, open(os.path.join(WORK, 'runs.json'), 'w'), indent=2)
