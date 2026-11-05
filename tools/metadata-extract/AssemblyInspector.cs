using System.Reflection;
using System.Text.Json;

namespace PepperDash.MetadataExtract;

/// <summary>
/// Reads the built plugin with MetadataLoadContext: types are inspected, never loaded for
/// execution, so no plugin code runs. Gives what only the compiled assembly knows: every
/// interface a device implements (including those inherited from Essentials base classes) and
/// the real types of its config properties.
/// </summary>
public sealed class AssemblyInspector : IDisposable
{
    private readonly MetadataLoadContext _context;
    private readonly List<Type> _types;

    public Assembly Assembly { get; }
    public List<string> Warnings { get; } = new();

    public AssemblyInspector(string assemblyPath, IEnumerable<string> referenceDirs, string? assetsJson)
    {
        // First wins: the plugin's own output, then the reference dirs, then NuGet packages, then the runtime
        var byName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        void Add(IEnumerable<string> paths)
        {
            foreach (var path in paths)
                byName.TryAdd(Path.GetFileName(path), path);
        }

        Add(Directory.GetFiles(Path.GetDirectoryName(Path.GetFullPath(assemblyPath))!, "*.dll"));
        foreach (var dir in referenceDirs)
            Add(Directory.GetFiles(dir, "*.dll", SearchOption.TopDirectoryOnly));
        if (assetsJson is not null && File.Exists(assetsJson))
            Add(ProjectAssetsAssemblies(assetsJson));
        Add(Directory.GetFiles(Path.GetDirectoryName(typeof(object).Assembly.Location)!, "*.dll"));

        _context = new MetadataLoadContext(new PathAssemblyResolver(byName.Values));
        Assembly = _context.LoadFromAssemblyPath(Path.GetFullPath(assemblyPath));
        try
        {
            _types = Assembly.GetTypes().ToList();
        }
        catch (ReflectionTypeLoadException e)
        {
            _types = e.Types.OfType<Type>().ToList();
            Warnings.Add($"{e.LoaderExceptions.Length} types in {Assembly.GetName().Name} could not be resolved; "
                + "a reference assembly is probably missing");
        }
    }

    public Type? FindType(string simpleName)
    {
        var matches = _types.Where(t => t.Name == simpleName && !t.IsNested).ToList();
        if (matches.Count > 1)
            Warnings.Add($"{matches.Count} classes are named {simpleName}; using {matches[0].FullName}");
        return matches.FirstOrDefault() ?? _types.FirstOrDefault(t => t.Name == simpleName);
    }

    /// <summary>
    /// Every interface outside System.*, by simple name without generic arity; null when a missing
    /// reference makes the list unknowable, which isn't the same as a device with none
    /// </summary>
    public List<string>? Interfaces(Type type)
    {
        try
        {
            return type.GetInterfaces()
                .Where(i => i.Namespace is not null && !i.Namespace.StartsWith("System", StringComparison.Ordinal))
                .Select(i => i.IsGenericType ? i.Name[..i.Name.IndexOf('`')] : i.Name)
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToList();
        }
        catch (FileNotFoundException e)
        {
            Warnings.Add($"{type.Name}: interfaces unknown, missing reference: {e.Message}");
            return null;
        }
    }

    /// <summary>
    /// When the factory doesn't name its config class, the device constructor usually takes it:
    /// the first parameter whose type is a non-abstract class from the plugin itself.
    /// </summary>
    public Type? ConfigFromConstructor(Type device)
    {
        try
        {
            return device.GetConstructors()
                .OrderByDescending(c => c.GetParameters().Length)
                .SelectMany(c => c.GetParameters())
                .Select(p => p.ParameterType)
                // DeviceConfig is the raw config; in Essentials itself it's in the assembly being read
                .FirstOrDefault(t => t.Assembly == Assembly && t.IsClass && !t.IsAbstract && t.Name != "DeviceConfig");
        }
        catch (FileNotFoundException e)
        {
            Warnings.Add($"{device.Name}: constructor parameters unreadable, missing reference: {e.Message}");
            return null;
        }
    }

    /// <summary>
    /// Every public interface the plugin and the assemblies it references define, so a name in
    /// hand-written metadata can be told apart from one that exists nowhere in code.
    /// </summary>
    public IEnumerable<string> DefinedInterfaces() =>
        WithReferences().SelectMany(TypesOf)
            .Where(t => t.IsInterface && t.IsPublic)
            .Select(t => t.IsGenericType ? t.Name[..t.Name.IndexOf('`')] : t.Name);

    /// <summary>
    /// The value of a const string field (RoutingPortNames.HdmiIn1) in the plugin or the assemblies
    /// it references. A const's value is stored in metadata, so reading it runs nothing; static
    /// readonly fields are set by code and can't be read.
    /// </summary>
    public string? StringConstant(string? owner, string field)
    {
        _constants ??= WithReferences().SelectMany(TypesOf)
            .SelectMany(t => Safe(() => t.GetFields(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)) ?? [])
            .Where(f => f.IsLiteral && Safe<string>(() => f.FieldType.FullName) == "System.String")
            .GroupBy(f => (f.DeclaringType!.Name, f.Name))
            .ToDictionary(g => g.Key, g => g.First().GetRawConstantValue() as string);

        if (owner is not null)
            return _constants.GetValueOrDefault((owner, field));
        // Unqualified: only when exactly one type defines it
        var matches = _constants.Where(c => c.Key.Item2 == field).Take(2).ToList();
        return matches.Count == 1 ? matches[0].Value : null;
    }

    private Dictionary<(string, string), string?>? _constants;

    /// <summary>
    /// The plugin and what it references, transitively (Plugin -> BaseLibrary -> Contracts). The
    /// framework's own references aren't followed: they add nothing a plugin config names.
    /// </summary>
    private IEnumerable<Assembly> WithReferences()
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Assembly.GetName().Name ?? "" };
        var pending = new Queue<Assembly>([Assembly]);
        while (pending.TryDequeue(out var assembly))
        {
            yield return assembly;
            if (IsFramework(assembly.GetName().Name))
                continue;
            foreach (var reference in assembly.GetReferencedAssemblies())
            {
                if (reference.Name is null || !seen.Add(reference.Name))
                    continue;
                try
                {
                    pending.Enqueue(_context.LoadFromAssemblyName(reference));
                }
                catch (FileNotFoundException)
                {
                    // Not resolvable here; what it defines just isn't available
                }
            }
        }
    }

    private static bool IsFramework(string? name) =>
        name is null or "mscorlib" or "netstandard" ||
        name.StartsWith("System", StringComparison.Ordinal) || name.StartsWith("Microsoft", StringComparison.Ordinal);

    private static Type[] TypesOf(Assembly assembly)
    {
        try
        {
            return assembly.GetTypes();
        }
        catch (ReflectionTypeLoadException e)
        {
            return e.Types.OfType<Type>().ToArray();
        }
    }

    private static T? Safe<T>(Func<T?> read) where T : class
    {
        try
        {
            return read();
        }
        catch (FileNotFoundException)
        {
            return null;
        }
    }

    public void Dispose() => _context.Dispose();

    /// <summary>
    /// The plugin's deps.json omits Essentials and its dependencies (they're ExcludeAssets=runtime),
    /// so resolve them from the restore's project.assets.json and the NuGet package folder.
    /// </summary>
    private static IEnumerable<string> ProjectAssetsAssemblies(string assetsJsonPath)
    {
        using var stream = File.OpenRead(assetsJsonPath);
        using var doc = JsonDocument.Parse(stream);
        if (!doc.RootElement.TryGetProperty("targets", out var targets))
            yield break;

        // The folders the restore used (RestorePackagesPath, globalPackagesFolder, fallback folders),
        // then the default global packages folder
        var folders = new List<string>();
        if (doc.RootElement.TryGetProperty("packageFolders", out var packageFolders))
            folders.AddRange(packageFolders.EnumerateObject().Select(f => f.Name));
        var nugetDir = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (string.IsNullOrWhiteSpace(nugetDir))
            nugetDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
        folders.Add(nugetDir);

        foreach (var target in targets.EnumerateObject())
        {
            foreach (var lib in target.Value.EnumerateObject())
            {
                var slash = lib.Name.LastIndexOf('/');
                if (slash < 0)
                    continue;
                var packageId = lib.Name[..slash].ToLowerInvariant();
                var version = lib.Name[(slash + 1)..];
                // The first folder that has the package, as NuGet resolves it
                var packageDir = folders.Select(f => Path.Combine(f, packageId, version)).FirstOrDefault(Directory.Exists);
                if (packageDir is null)
                    continue;
                foreach (var kind in new[] { "compile", "runtime" })
                {
                    if (!lib.Value.TryGetProperty(kind, out var assets))
                        continue;
                    foreach (var asset in assets.EnumerateObject())
                    {
                        if (!asset.Name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                            continue;
                        var path = Path.Combine(packageDir, asset.Name.Replace('/', Path.DirectorySeparatorChar));
                        if (File.Exists(path))
                            yield return path;
                    }
                }
                // Some packages (the Crestron SDK) ship assemblies outside the folders NuGet lists
                foreach (var path in Directory.EnumerateFiles(packageDir, "*.dll", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
                    yield return path;
            }
        }
    }
}
