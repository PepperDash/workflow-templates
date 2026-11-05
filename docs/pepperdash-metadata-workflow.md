# pepperdash-metadata.yml

Generates `pepperdash-metadata.json` for one GitHub release, attaches it to the release, and registers the release and its files with Portal. Portal's config tool reads the document to offer the release's device types, config forms and routing ports.

The document's format is defined by [`schemas/pepperdash-metadata.v1.schema.json`](../schemas/pepperdash-metadata.v1.schema.json).

## Adding it to a plugin

Add a job after the 4-series build. The calling job must grant both permissions: the reusable workflow can't raise them.

```yaml
  metadata:
    needs: [getVersion, build-4Series]
    if: needs.getVersion.outputs.newVersion == 'true'
    uses: PepperDash/workflow-templates/.github/workflows/pepperdash-metadata.yml@main
    permissions:
      contents: write   # attach pepperdash-metadata.json to the release
      id-token: write   # GitHub OIDC token for UDM
    with:
      tag: ${{ needs.getVersion.outputs.tag }}
```

To withdraw a release from Portal when its GitHub release is deleted:

```yaml
on:
  release:
    types: [deleted]

jobs:
  withdraw:
    uses: PepperDash/workflow-templates/.github/workflows/pepperdash-metadata.yml@main
    permissions:
      contents: read
      id-token: write
    with:
      tag: ${{ github.event.release.tag_name }}
      mode: withdraw
```

| Input | Default | |
|---|---|---|
| `tag` | required | The release tag |
| `kind` | `plugin` | `essentials`, `plugin`, `userInterface` or `touchpanelWrapper`. The UI kinds have no device types, so nothing is built |
| `package-id` | the csproj `<PackageId>`, else its `<AssemblyName>`, else its file name | The repo name for UI kinds |
| `label` | the repo name without `epi-`, title-cased | Portal admins can rename it |
| `mode` | `publish` | `withdraw` removes the release from Portal's catalog; its files are kept |

## What it does

**`tools`** finds the commit this workflow file was loaded from (`@main`, `@v1` or a branch, from the `job_workflow_sha` claim of its OIDC token). The other jobs run this repo's tools from that same commit, so a caller can't run tools from a ref other than the workflow UDM trusts.

**`extract`** builds the repo and runs [`tools/metadata-extract`](../tools/metadata-extract/README.md), which reads the factories, device classes, config classes and routing ports from the source and the built DLLs. Building runs the repo's own MSBuild code, so this job has read-only permissions and no OIDC token.

**`publish`** runs no code from the repo:

1. Downloads the release's `.cpz`, `.cplz`, `.ch5z` and `.zip` files and hashes them.
2. Finds the **baseline**: the newest release published before this one that has a `pepperdash-metadata.json` and whose commit is an ancestor of this one. Going by ancestry means a feature-branch prerelease never becomes the baseline for `main`, or the other way round.
3. Assembles the document ([`tools/release-metadata`](../tools/release-metadata)):
   - `schema`, `interfaces` and `routingPorts` come from the code. Where the code gives nothing (a schema it couldn't build, ports whose keys it couldn't read), the baseline's value is kept.
   - Each config property's `description` is its `/// <summary>` in the code, otherwise the baseline's. Its `title` is the baseline's, otherwise one made from the property name (`warmupTimeMs` → "Warmup Time Ms"), since the code has nowhere to write one.
   - `label`, `controlMethods`, `controlPorts`, `deviceKind`, `catalog` and the other UI hints come from the baseline.
   - `formMetadata` comes from the repo's `.pepperdash/form-metadata.json`, otherwise the baseline. Each `schemaId` is pointed at the matching property's `$id` in this release's schema, so a sidecar written as `#root/propertiesConfig/x` still matches a schema that uses `#root/x`.
4. **Gate.** Any error fails the job before anything is published:
   - the document doesn't validate against the v1 schema
   - its typeNames differ from the factories' `TypeNames`
   - a `.pepperdash/form-metadata.json` typeName isn't in the release (a key that differs only in case is a warning, since Essentials ignores case)
   - a `formMetadata` `schemaId` matches no property in this release's schema, for example because the property was renamed
5. Attaches `pepperdash-metadata.json` to the release, replacing an earlier copy.
6. Registers the release with each UDM in `PEPPERDASH_UDM_URLS`, uploads its files, and marks it complete.

The job summary lists, for each typeName, where each field came from and what's missing, including the config properties that have no description anywhere, then what changed since the baseline.

## Portal registration

`PEPPERDASH_UDM_URLS` is an organization Actions variable: a comma-separated list of UDM API roots, each ending in `/api`. With no value, the document is still generated and attached, and registration is skipped with a notice.

Every call carries a GitHub Actions OIDC token for the audience `pepperdash-udm`, so no secret is involved. UDM checks that:

- the token was issued to a repo in an allowed organization,
- it came from this workflow (`job_workflow_ref`), so each environment's `GITHUB_OIDC_ALLOWED_WORKFLOW_REFS` must allow `PepperDash/workflow-templates/.github/workflows/pepperdash-metadata.yml@`,
- its repository matches the document's `repoUrl`.

The environments share one file bucket per GitHub organization. The first environment to register a version gets upload URLs and stores the files, and the others find them already there. Uploads are create-only: a version's files can't be replaced, so a changed file needs a new version.

Re-running the workflow is safe. Registering a version that's already available with the same files refreshes its metadata.

## Running the tools locally

```bash
dotnet build tools/metadata-extract -c Release
python3 tools/metadata-extract/build_and_extract.py <repo> facts.json --build-json build.json

cd tools/release-metadata && npm ci && npm test
node assemble.mjs --package-id <id> --tag <tag> --repo-url https://github.com/<owner>/<repo> \
  --commit-sha <sha> --published-at <utc> --assets-dir <dir> --facts facts.json [--baseline <file>] \
  [--form-sidecar <repo>/.pepperdash/form-metadata.json]
```

## Not done yet

- The AI agent step that fills what the code can't give (ports built in loops or by helper classes, defaults set in code). Until then those gaps carry forward from the baseline or appear in the job summary.
- Matching each typeName's category and models against Portal's reference data (`.pepperdash/catalog.json`); `catalog` is carried from the baseline.
- Skipping the extract job when nothing changed since the baseline.
