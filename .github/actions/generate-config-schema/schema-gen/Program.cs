using System.Reflection;
using System.Runtime.Loader;
using NJsonSchema;
using NJsonSchema.Generation;
using NJsonSchema.NewtonsoftJson.Generation;

// SchemaGen --assembly <path-to-plugin.dll> --types "A;B;Ns.C" --out <dir> [--summary <path>]
//
// Loads the built plugin assembly, resolves each requested config type by full
// name or simple name, and writes <TypeName>.schema.json (JSON Schema draft-07,
// Newtonsoft attribute aware) into the output directory.
//
// Exit codes: 0 = ok (incl. "nothing requested"), 2 = every requested type failed.

var opts = ParseArgs(args);

string? assemblyPath = opts.GetValueOrDefault("assembly");
string typesRaw = opts.GetValueOrDefault("types") ?? "";
string outDir = opts.GetValueOrDefault("out") ?? "schemas";
string? summaryPath = opts.GetValueOrDefault("summary") ?? Environment.GetEnvironmentVariable("GITHUB_STEP_SUMMARY");

void Summary(string line)
{
    Console.WriteLine(line);
    if (!string.IsNullOrEmpty(summaryPath))
    {
        try { File.AppendAllText(summaryPath, line + "\n"); } catch { /* best effort */ }
    }
}

Summary("## Generate config schema");

var typeNames = typesRaw
    .Split(new[] { ';', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    .Distinct(StringComparer.OrdinalIgnoreCase)
    .ToArray();

if (typeNames.Length == 0)
{
    Summary("- No config types were requested (no `ToObject<T>()` call sites found). Nothing to generate.");
    return 0;
}

if (string.IsNullOrEmpty(assemblyPath) || !File.Exists(assemblyPath))
{
    Summary($"❌ Assembly not found: `{assemblyPath}`");
    return 2;
}

Directory.CreateDirectory(outDir);

// Probe the assembly's own folder for dependencies.
var probeDir = Path.GetDirectoryName(Path.GetFullPath(assemblyPath))!;
AssemblyLoadContext.Default.Resolving += (ctx, name) =>
{
    var candidate = Path.Combine(probeDir, name.Name + ".dll");
    return File.Exists(candidate) ? ctx.LoadFromAssemblyPath(candidate) : null;
};

Assembly asm;
try
{
    asm = AssemblyLoadContext.Default.LoadFromAssemblyPath(Path.GetFullPath(assemblyPath));
}
catch (Exception ex)
{
    Summary($"❌ Failed to load `{Path.GetFileName(assemblyPath)}`: {ex.Message}");
    return 2;
}

Type?[] allTypes;
try { allTypes = asm.GetTypes(); }
catch (ReflectionTypeLoadException ex) { allTypes = ex.Types; }

var settings = new NewtonsoftJsonSchemaGeneratorSettings
{
    SchemaType = SchemaType.JsonSchema,
    FlattenInheritanceHierarchy = true,
    GenerateAbstractProperties = true,
};
var generator = new JsonSchemaGenerator(settings);

int ok = 0, failed = 0;
foreach (var wanted in typeNames)
{
    var type = allTypes.FirstOrDefault(t => t is not null &&
        (string.Equals(t.FullName, wanted, StringComparison.Ordinal) ||
         string.Equals(t.Name, wanted, StringComparison.Ordinal) ||
         string.Equals(t.Name, wanted.Split('.').Last(), StringComparison.Ordinal)));

    if (type is null)
    {
        Summary($"- ⚠️ `{wanted}` not found in {asm.GetName().Name}; skipped.");
        failed++;
        continue;
    }

    try
    {
        var schema = generator.Generate(type);
        var json = schema.ToJson();
        var file = Path.Combine(outDir, type.Name + ".schema.json");
        File.WriteAllText(file, json);
        Summary($"- `{type.Name}.schema.json` ({new FileInfo(file).Length} bytes) from `{type.FullName}`");
        ok++;
    }
    catch (Exception ex)
    {
        Summary($"- ❌ `{wanted}`: {ex.Message}");
        failed++;
    }
}

Summary($"\nGenerated **{ok}** schema(s), **{failed}** failed.");
return (ok == 0 && failed > 0) ? 2 : 0;

static Dictionary<string, string> ParseArgs(string[] args)
{
    var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    for (int i = 0; i < args.Length; i++)
    {
        if (!args[i].StartsWith("--")) continue;
        var key = args[i][2..];
        var val = (i + 1 < args.Length && !args[i + 1].StartsWith("--")) ? args[++i] : "true";
        d[key] = val;
    }
    return d;
}
