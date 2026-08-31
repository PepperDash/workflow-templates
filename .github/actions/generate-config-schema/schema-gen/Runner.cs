using System.Reflection;
using System.Runtime.Loader;
using NJsonSchema;
using NJsonSchema.Generation;
using NJsonSchema.NewtonsoftJson.Generation;

namespace SchemaGen;

public sealed record SchemaGenResult(int Ok, int Failed)
{
    public int ExitCode => (Ok == 0 && Failed > 0) ? 2 : 0;
}

public static class Runner
{
    /// <summary>
    /// Loads <paramref name="assemblyPath"/>, resolves each requested type by full
    /// or simple name, and writes &lt;TypeName&gt;.schema.json into <paramref name="outDir"/>.
    /// </summary>
    public static SchemaGenResult Run(
        string assemblyPath,
        IEnumerable<string> typeNames,
        string outDir,
        Action<string> log)
    {
        var wanted = typeNames
            .SelectMany(t => t.Split(new[] { ';', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        if (wanted.Length == 0)
        {
            log("- No config types requested; nothing to generate.");
            return new SchemaGenResult(0, 0);
        }

        if (string.IsNullOrEmpty(assemblyPath) || !File.Exists(assemblyPath))
        {
            log($"❌ Assembly not found: `{assemblyPath}`");
            return new SchemaGenResult(0, wanted.Length);
        }

        Directory.CreateDirectory(outDir);

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
            log($"❌ Failed to load `{Path.GetFileName(assemblyPath)}`: {ex.Message}");
            return new SchemaGenResult(0, wanted.Length);
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
        foreach (var name in wanted)
        {
            var type = allTypes.FirstOrDefault(t => t is not null &&
                (string.Equals(t.FullName, name, StringComparison.Ordinal) ||
                 string.Equals(t.Name, name, StringComparison.Ordinal) ||
                 string.Equals(t.Name, name.Split('.').Last(), StringComparison.Ordinal)));

            if (type is null)
            {
                log($"- ⚠️ `{name}` not found in {asm.GetName().Name}; skipped.");
                failed++;
                continue;
            }

            try
            {
                var json = generator.Generate(type).ToJson();
                var file = Path.Combine(outDir, type.Name + ".schema.json");
                File.WriteAllText(file, json);
                log($"- `{type.Name}.schema.json` from `{type.FullName}`");
                ok++;
            }
            catch (Exception ex)
            {
                log($"- ❌ `{name}`: {ex.Message}");
                failed++;
            }
        }

        log($"Generated {ok} schema(s), {failed} failed.");
        return new SchemaGenResult(ok, failed);
    }
}
