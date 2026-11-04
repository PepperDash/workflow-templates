# metadata-extract

Reads an Essentials or plugin repo and writes `facts.json`: everything about its device types that can be established from code without running it. The release metadata workflow turns the facts into `pepperdash-metadata.json` (spec: `docs/pepperdash-metadata.md` in portal-essentials-config-tool) and leaves only the gaps to the AI agent.

It works in two halves. Neither runs any code from the repo being read.

| Half | Reads | Gives |
|---|---|---|
| Source ([Roslyn](https://github.com/dotnet/roslyn) syntax only) | the repo's `.cs` files, outside `bin`, `obj` and test folders | each factory's `TypeNames` and `MinimumEssentialsFrameworkVersion`; its device class, and the more specific class `BuildDevice` builds for a typeName when it branches on it; its config class (from `ToObject<T>()`/`DeserializeObject<T>()` in `BuildDevice`, directly or in a helper it calls, or else in the device constructor); routing ports with literal or constant keys; property defaults; `/// <summary>` text; `[Description]` |
| Assembly ([MetadataLoadContext](https://learn.microsoft.com/dotnet/standard/assembly/inspect-contents-using-metadataloadcontext)) | the built DLLs, resolving references from their output folders and the restore's `obj/project.assets.json` | every interface each device implements, including those inherited from Essentials base classes; the config class from the device constructor when the factory doesn't name it; the config schema from the real property types; every interface the assemblies define; the values of `const` strings the source uses as port keys (`RoutingPortNames.HdmiIn1`) |

Without `--assembly`, only the source half runs and `interfaces` and `schema` are `null`.

## Usage

```bash
dotnet build tools/metadata-extract -c Release
dotnet tools/metadata-extract/bin/Release/net8.0/metadata-extract.dll \
  --source <repo> \
  --assembly <repo>/src/bin/Release/net8/Plugin.dll \
  [--assembly <another.dll>]... [--reference-dir <dir>]... [--assets <obj/project.assets.json>] \
  [--out facts.json]
```

Build the plugin first (the release workflow already has). `--assets` defaults to the nearest `obj/project.assets.json` above each assembly.

## facts.json

```jsonc
{
  "tool": "metadata-extract@0.1.0",
  "minimumEssentialsVersion": "3.0.0",
  "typeNames": {
    "epsonProjector": {
      "factory": "DeviceFactory",
      "deviceClass": "EpsonProjector",
      "deviceClassSource": "factory",            // factory | build-device-branch
      "configClass": "PropsConfig",
      "configClassSource": "helper-call",      // deserialize-call | helper-call | constructor-parameter | device-constructor
      "description": null,
      "interfaces": ["IHasPowerControl", "IRoutingSinkWithFeedback", "..."],
      "schema": { /* draft-07, with $defs.propertiesConfig, #root/... $ids and a default */ },
      "routingPorts": {
        "inputs": [{ "name": "Hdmi", "label": "Hdmi", "signalType": "video", "portConnectionType": "Hdmi" }],
        "outputs": [],
        "unresolved": []                          // port constructions it couldn't read, as file:line: code
      }
    }
  },
  "definedInterfaces": ["IBasicVolumeWithFeedback", "..."],
  "warnings": []
}
```

Rules it applies, matching the spec and the config tool's existing schemas:

- JSON property names are the `[JsonProperty]` name, otherwise the C# name in camelCase (`EnableBridgeComms` becomes `enableBridgeComms`).
- Enums are string schemas listing the member names. `ControlPropertiesConfig` properties are left out of the form (the config tool edits them through `controlMethods`) and become `control: { method: "" }` in the default.
- The device class is the factory's generic argument, unless `BuildDevice` (or a plugin method it calls) picks a class by typeName: an `if` on `==`, `Equals`, `StartsWith` or `Contains`, a `switch`, or a `{ "typeName", ... => new X(...) }` lookup table. The first matching branch wins, as at runtime, and `X` must derive from the factory's device class or the method's return type. Interfaces and ports are then read from `X`.
- Port constructions are `new RoutingInputPort...`/`new RoutingOutputPort...`, including subclasses such as `RoutingInputPortWithVideoStatuses`, in the device class and the plugin classes it derives from.
- Port `name` and `label` are the key exactly as the code passes it, since config tie lines reference ports by key. `signalType` and `portConnectionType` follow the spec's mappings, and an unknown connection type becomes `None`.

## Known gaps

- Routing ports whose keys come from loops, interpolation, `static readonly` fields or enumeration classes (`DeviceInputEnum.Hdmi1.Name`) are listed as `unresolved`. Ports added by helper classes (NVX's `HdmiInput1Port.AddRoutingPort(this)`) aren't found at all. Both are left to the agent.
- Defaults set in device code (`config.X > 0 ? config.X : Default`) or in Essentials' own config classes aren't found.
- 3-series (Compact Framework) projects can't build on Linux or macOS, so they get the source half only.
- Control system types (`cp4`, `rmc4`, ...) aren't registered by factories, so they don't appear.

## Validation against the config tool's mocks

`validation/` checks the extractor against the hand-written mock metadata in portal-essentials-config-tool. Run `pnpm metadata:export` there first, then:

```bash
python3 tools/metadata-extract/validation/run_all.py <config-tool>/release-metadata-export <work dir> [--only owner/repo,...] [--overrides <file>]
python3 tools/metadata-extract/validation/compare.py <config-tool>/release-metadata-export <work dir>
```

`run_all.py` clones each package's newest mocked version at its tag, builds it and extracts it, using your own `gh` login. `--overrides` names a JSON file of pinned versions and tag substitutions (format in the script's docstring); keep it outside this repo, because this repo is public and the file names private repos. Private repos need access, and the builds run each repo's MSBuild, so only point it at repos you trust. `compare.py` writes `comparison.md` and `comparison.json`, and sorts every mock-only interface into one of three groups: defined but not implemented by that device, a v2 routing name, or defined nowhere.
