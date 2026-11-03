using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
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

var source = new SourceScanner(sourceDirs[0]);
source.Scan();

var facts = new Facts();
var assemblies = options.GetValueOrDefault("assembly") ?? [];
var inspectors = assemblies
    .Select(path => new AssemblyInspector(
        path,
        // A repo can build several assemblies that reference each other (Essentials does)
        (options.GetValueOrDefault("reference-dir") ?? [])
            .Concat(assemblies.Select(a => Path.GetDirectoryName(Path.GetFullPath(a))!))
            .Distinct(),
        options.GetValueOrDefault("assets")?.FirstOrDefault() ?? FindAssetsJson(path)))
    .ToList();

var schemas = new SchemaBuilder(source, facts.Warnings);
var versions = source.Factories.Select(f => f.MinimumEssentialsVersion).OfType<string>().Distinct().ToList();
facts.MinimumEssentialsVersion = versions.FirstOrDefault();
if (versions.Count > 1)
    facts.Warnings.Add($"factories set different minimum Essentials versions: {string.Join(", ", versions)}");

foreach (var factory in source.Factories)
{
    if (factory.TypeNames.Count == 0)
        facts.Warnings.Add($"{factory.Name}: no TypeNames found");

    var device = inspectors.Select(i => (inspector: i, type: i.FindType(factory.DeviceClass)))
        .FirstOrDefault(x => x.type is not null);
    if (inspectors.Count > 0 && device.type is null)
        facts.Warnings.Add($"{factory.Name}: device class {factory.DeviceClass} not found in the assembly");

    var configClass = factory.ConfigClass;
    var configSource = factory.ConfigClassSource;
    var configType = configClass is not null ? device.inspector?.FindType(configClass) : null;
    if (configType is null && device.type is not null)
    {
        configType = device.inspector!.ConfigFromConstructor(device.type);
        if (configType is not null)
        {
            configClass = configType.Name;
            configSource = "constructor-parameter";
        }
    }

    var ports = source.ReadRoutingPorts(factory.DeviceClass);
    foreach (var typeName in factory.TypeNames)
    {
        if (facts.TypeNames.ContainsKey(typeName))
        {
            facts.Warnings.Add($"{typeName} is registered by more than one factory; keeping the first");
            continue;
        }

        var entry = new TypeNameFacts
        {
            Factory = factory.Name,
            DeviceClass = factory.DeviceClass,
            ConfigClass = configClass,
            ConfigClassSource = configSource,
            Description = factory.Description,
            Interfaces = device.type is null ? null : device.inspector!.Interfaces(device.type),
        };
        try
        {
            entry.Schema = configType is null ? null : schemas.Build(configType, typeName);
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
