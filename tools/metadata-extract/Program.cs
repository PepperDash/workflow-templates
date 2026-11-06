using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using NuGet.Versioning;
using PepperDash.MetadataExtract;

// metadata-extract --source <repo> [--assembly <plugin.dll>]... [--reference-dir <dir>]...
//                  [--assets <obj/project.assets.json>] [--out facts.json]
//
// Without --assembly only the source is read: interfaces and schemas come back null.

var options = ParseArgs(args);
if (!options.TryGetValue("source", out var sourceDirs) || sourceDirs.Count != 1)
{
    Console.Error.WriteLine("usage: metadata-extract --source <repo> [--assembly <dll>]... [--reference-dir <dir>]... [--assets <project.assets.json>] [--out <file>]");
    return 2;
}

var facts = new Facts();
var assemblies = options.GetValueOrDefault("assembly") ?? [];
var assetsJson = assemblies.ToDictionary(
    path => path,
    path => options.GetValueOrDefault("assets")?.FirstOrDefault() ?? FindAssetsJson(path));
var inspectors = assemblies
    .Select(path => new AssemblyInspector(
        path,
        // A repo can build several assemblies that reference each other (Essentials does)
        (options.GetValueOrDefault("reference-dir") ?? [])
            .Concat(assemblies.Select(a => Path.GetDirectoryName(Path.GetFullPath(a))!))
            .Distinct(),
        assetsJson[path]))
    .ToList();

// The Essentials package the restore resolved the csproj's reference to
var dependencies = HighestFirst(assetsJson.Values.OfType<string>().Distinct()
    .SelectMany(AssemblyInspector.EssentialsPackageVersions));
facts.EssentialsDependencyVersion = dependencies.FirstOrDefault();
if (dependencies.Count > 1)
    facts.Warnings.Add($"the build resolved different Essentials versions (by project or framework): {string.Join(", ", dependencies)}");

var source = new SourceScanner(sourceDirs[0])
{
    ExternalConstant = (owner, field) => inspectors.Select(i => i.StringConstant(owner, field)).FirstOrDefault(v => v is not null),
};
source.Scan();

var portsByClass = new Dictionary<string, RoutingPortFacts>(StringComparer.Ordinal);
var schemas = new SchemaBuilder(source, facts.Warnings);
// The package needs the highest any of its factories asks for
var versions = HighestFirst(source.Factories.Select(f => f.MinimumEssentialsVersion).OfType<string>());
facts.MinimumEssentialsVersion = versions.FirstOrDefault();
if (versions.Count > 1)
    facts.Warnings.Add($"factories set different minimum Essentials versions: {string.Join(", ", versions)}");

foreach (var factory in source.Factories)
{
    if (factory.TypeNames.Count == 0)
        facts.Warnings.Add($"{factory.Name}: no TypeNames found");

    var device = FindDevice(factory.DeviceClass);
    if (inspectors.Count > 0 && device.type is null)
        facts.Warnings.Add($"{factory.Name}: device class {factory.DeviceClass} not found in the assembly");

    // Names found in source are kept without --assembly; only the schema needs the reflected type
    var configClass = factory.ConfigClass;
    var configSource = factory.ConfigClassSource;
    var configType = configClass is not null ? FindType(configClass, device.inspector) : null;
    if (configType is null && source.ConfigFromDeviceConstructor(factory.DeviceClass) is { } deserialized)
    {
        var deserializedType = FindType(deserialized, device.inspector);
        if (deserializedType is not null || configClass is null)
            (configClass, configSource, configType) = (deserialized, "device-constructor", deserializedType);
    }
    // Only a guess (a plugin class the constructor takes can be a service), so only when the source
    // names no config
    if (configClass is null && device.type is not null)
    {
        configType = device.inspector!.ConfigFromConstructor(device.type);
        if (configType is not null)
        {
            configClass = configType.Name;
            configSource = "constructor-parameter";
        }
    }

    foreach (var typeName in factory.TypeNames)
    {
        if (facts.TypeNames.ContainsKey(typeName))
        {
            facts.Warnings.Add($"{typeName} is registered by more than one factory; keeping the first");
            continue;
        }

        // The class this typeName's BuildDevice branch builds, when it's more specific than the factory's
        var deviceClass = factory.BranchDeviceClasses.GetValueOrDefault(typeName) ?? factory.DeviceClass;
        var built = deviceClass == factory.DeviceClass ? device : FindDevice(deviceClass);
        if (built.type is null && inspectors.Count > 0 && deviceClass != factory.DeviceClass)
        {
            facts.Warnings.Add($"{typeName}: device class {deviceClass} not found in the assembly; using {factory.DeviceClass}");
            deviceClass = factory.DeviceClass;
            built = device;
        }

        // This typeName's own BuildDevice branch deserializing its config beats one found elsewhere in
        // BuildDevice. Otherwise, when BuildDevice names no config, a more specific branch class may
        // deserialize its own
        var (typeConfigClass, typeConfigSource, typeConfigType) = (configClass, configSource, configType);
        if (factory.BranchConfigClasses.GetValueOrDefault(typeName) is { } branchConfig)
        {
            (typeConfigClass, typeConfigSource, typeConfigType) =
                (branchConfig, "build-device-branch", FindType(branchConfig, built.inspector));
        }
        else if (deviceClass != factory.DeviceClass && configSource is not ("deserialize-call" or "helper-call") &&
            source.ConfigFromDeviceConstructor(deviceClass) is { } own)
        {
            var ownType = FindType(own, built.inspector);
            if (ownType is not null || inspectors.Count == 0)
                (typeConfigClass, typeConfigSource, typeConfigType) = (own, "device-constructor", ownType);
        }

        var entry = new TypeNameFacts
        {
            Factory = factory.Name,
            DeviceClass = deviceClass,
            DeviceClassSource = deviceClass == factory.DeviceClass ? "factory" : "build-device-branch",
            ConfigClass = typeConfigClass,
            ConfigClassSource = typeConfigSource,
            Description = factory.Description,
            Interfaces = built.type is null ? null : built.inspector!.Interfaces(built.type),
        };
        var ports = PortsOf(deviceClass);
        try
        {
            entry.Schema = typeConfigType is null ? null : schemas.Build(typeConfigType, typeName);
        }
        catch (FileNotFoundException e)
        {
            facts.Warnings.Add($"{typeName}: no schema, missing reference: {e.Message}");
        }
        entry.RoutingPorts.Inputs.AddRange(ports.Inputs);
        entry.RoutingPorts.Outputs.AddRange(ports.Outputs);
        entry.RoutingPorts.Unresolved.AddRange(ports.Unresolved);
        facts.TypeNames[typeName] = entry;
    }
}
foreach (var inspector in inspectors)
    facts.DefinedInterfaces.UnionWith(inspector.DefinedInterfaces());
facts.Warnings.AddRange(inspectors.SelectMany(i => i.Warnings).Distinct());

var json = JsonSerializer.Serialize(facts, new JsonSerializerOptions
{
    WriteIndented = true,
    PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
});
if (options.GetValueOrDefault("out")?.FirstOrDefault() is { } outPath)
    File.WriteAllText(outPath, json + "\n");
else
    Console.WriteLine(json);

foreach (var inspector in inspectors)
    inspector.Dispose();
return 0;

(AssemblyInspector? inspector, Type? type) FindDevice(string className) =>
    inspectors.Select(i => (inspector: (AssemblyInspector?)i, type: i.FindType(className)))
        .FirstOrDefault(x => x.type is not null);

// A config class can live in a different assembly from its device: look in the device's first
Type? FindType(string className, AssemblyInspector? preferred) =>
    preferred?.FindType(className)
    ?? inspectors.Where(i => i != preferred).Select(i => i.FindType(className)).FirstOrDefault(t => t is not null);

RoutingPortFacts PortsOf(string className)
{
    if (!portsByClass.TryGetValue(className, out var ports))
        portsByClass[className] = ports = source.ReadRoutingPorts(className);
    return ports;
}

// SemVer order, prereleases below their release ("3.0.1-beta.10" above "3.0.1-beta.2", "3.0.1" above
// both); a version NuGet can't parse sorts as 0.0.0
static List<string> HighestFirst(IEnumerable<string> versions) =>
    versions.Distinct()
        .OrderByDescending(v => NuGetVersion.TryParse(v, out var parsed) ? parsed : new NuGetVersion(0, 0, 0), VersionComparer.VersionRelease)
        .ToList();

static Dictionary<string, List<string>> ParseArgs(string[] args)
{
    var result = new Dictionary<string, List<string>>(StringComparer.Ordinal);
    for (var i = 0; i < args.Length; i++)
    {
        if (!args[i].StartsWith("--", StringComparison.Ordinal) || i + 1 >= args.Length)
            throw new ArgumentException($"unexpected argument '{args[i]}'");
        var key = args[i][2..];
        if (!result.TryGetValue(key, out var values))
            result[key] = values = new();
        values.Add(args[++i]);
    }
    return result;
}

// bin/<Config>/<tfm>/plugin.dll -> obj/project.assets.json in the project folder
static string? FindAssetsJson(string assemblyPath)
{
    for (var dir = Path.GetDirectoryName(Path.GetFullPath(assemblyPath)); dir is not null; dir = Path.GetDirectoryName(dir))
    {
        var candidate = Path.Combine(dir, "obj", "project.assets.json");
        if (File.Exists(candidate))
            return candidate;
    }
    return null;
}
