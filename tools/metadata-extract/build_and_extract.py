"""Build a repo's plugin projects and run metadata-extract on what they produce.

python3 build_and_extract.py <repo dir> <facts.json> [--build-json <file>]

Picks the 4-series projects (by name or a net6/8/9 target) outside test folders, falling back to
every project, builds each in Release and passes the DLLs it produced to the extractor. A project
that fails to build is skipped; with none built, only the source half runs.

--build-json writes { packageId, projects, assemblies, buildErrors } for the caller.
Exits non-zero only if the extractor itself fails.
"""
import glob
import json
import os
import re
import subprocess
import sys

# Build the tool first: dotnet build tools/metadata-extract -c Release
EXTRACTOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bin', 'Release', 'net8.0', 'metadata-extract.dll')


def run(cmd, cwd=None, timeout=900):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        # A failure like any other, so one slow repo doesn't end the batch
        return 124, f'timed out after {timeout}s: {" ".join(cmd)}'
    return p.returncode, p.stdout + p.stderr


def read(path):
    return open(path, encoding='utf-8', errors='ignore').read()


def projects(repo_dir):
    found = [p for p in glob.glob(os.path.join(repo_dir, '**', '*.csproj'), recursive=True)
             if not re.search(r'[\\/](tests?|[^\\/]*\.Tests?)[\\/]|Tests?\.csproj$', p, re.I)]
    four = [p for p in found if '4series' in os.path.basename(p).lower()
            or re.search(r'<TargetFrameworks?>[^<]*net(6|8|9)', read(p))]
    return sorted(four or found)


def output_dll(project):
    m = re.search(r'<AssemblyName>([^<$]+)</AssemblyName>', read(project))
    name = m.group(1).strip() if m else os.path.splitext(os.path.basename(project))[0]
    # OutputPath varies (src/4Series/bin/...), so look anywhere under the project's folder
    hits = sorted((h for h in glob.glob(os.path.join(os.path.dirname(project), '**', 'bin', 'Release', '**', f'{name}.dll'), recursive=True)
                   if os.sep + 'obj' + os.sep not in h),
                  key=os.path.getmtime)
    return hits[-1] if hits else None


def package_id(project_paths):
    """The first <PackageId>, else NuGet's default: the first project's <AssemblyName>, else its file name"""
    for p in project_paths:
        m = re.search(r'<PackageId>([^<$]+)</PackageId>', read(p))
        if m:
            return m.group(1).strip()
    if not project_paths:
        return None
    m = re.search(r'<AssemblyName>([^<$]+)</AssemblyName>', read(project_paths[0]))
    return m.group(1).strip() if m else os.path.splitext(os.path.basename(project_paths[0]))[0]


def build_and_extract(repo_dir, facts_path):
    record = {'projects': [], 'assemblies': []}
    dlls, build_errors = [], []
    found = projects(repo_dir)
    for project in found:
        code, out = run(['dotnet', 'build', project, '-c', 'Release', '-nologo', '-v', 'q'])
        if code != 0:
            build_errors.append({'project': os.path.relpath(project, repo_dir),
                                 'errors': sorted({l.strip() for l in out.splitlines() if ': error ' in l})[:8]})
            continue
        dll = output_dll(project)
        if dll:
            dlls.append(dll)
    record['packageId'] = package_id(found)
    record['projects'] = [os.path.relpath(p, repo_dir) for p in found]
    record['assemblies'] = [os.path.relpath(d, repo_dir) for d in dlls]
    if build_errors:
        record['buildErrors'] = build_errors

    cmd = ['dotnet', EXTRACTOR, '--source', repo_dir, '--out', facts_path]
    for dll in dlls:
        cmd += ['--assembly', dll]
    code, out = run(cmd)
    record['status'] = 'ok' if code == 0 and dlls else ('source-only' if code == 0 else 'extract-failed')
    if code != 0:
        record['detail'] = out.strip().splitlines()[-5:]
    return record


if __name__ == '__main__':
    repo, facts = sys.argv[1], sys.argv[2]
    result = build_and_extract(repo, facts)
    if '--build-json' in sys.argv:
        json.dump(result, open(sys.argv[sys.argv.index('--build-json') + 1], 'w'), indent=2)
    print(json.dumps(result, indent=2))
    sys.exit(1 if result['status'] == 'extract-failed' else 0)
