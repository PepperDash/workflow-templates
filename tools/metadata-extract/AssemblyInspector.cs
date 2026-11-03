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

    /// <summary>Every interface outside System.*, by simple name without generic arity</summary>
    public List<string> Interfaces(Type type)
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
            Warnings.Add($"{type.Name}: interfaces incomplete, missing reference: {e.Message}");
            return [];
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
                .FirstOrDefault(t => t.Assembly == Assembly && t.IsClass && !t.IsAbstract);
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
    public IEnumerable<string> DefinedInterfaces()
    {
        var assemblies = new List<Assembly> { Assembly };
        foreach (var reference in Assembly.GetReferencedAssemblies())
        {
            try
            {
                assemblies.Add(_context.LoadFromAssemblyName(reference));
            }
            catch (FileNotFoundException)
            {
                // Not resolvable here; its interfaces just aren't listed
            }
        }

        foreach (var assembly in assemblies)
        {
            Type[] types;
            try
            {
                types = assembly.GetTypes();
            }
            catch (ReflectionTypeLoadException e)
            {
                types = e.Types.OfType<Type>().ToArray();
            }
            foreach (var type in types.Where(t => t.IsInterface && t.IsPublic))
                yield return type.IsGenericType ? type.Name[..type.Name.IndexOf('`')] : type.Name;
        }
    }

    public void Dispose() => _context.Dispose();

    /// <summary>
    /// The plugin's deps.json omits Essentials and its dependencies (they're ExcludeAssets=runtime),
    /// so resolve them from the restore's project.assets.json and the NuGet package folder.
    /// </summary>
    private static IEnumerable<string> ProjectAssetsAssemblies(string assetsJsonPath)
    {
        var nugetDir = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (string.IsNullOrWhiteSpace(nugetDir))
            nugetDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");

        using var stream = File.OpenRead(assetsJsonPath);
        using var doc = JsonDocument.Parse(stream);
        if (!doc.RootElement.TryGetProperty("targets", out var targets))
            yield break;

        foreach (var target in targets.EnumerateObject())
        {
            foreach (var lib in target.Value.EnumerateObject())
            {
                var slash = lib.Name.LastIndexOf('/');
                if (slash < 0)
                    continue;
                var packageId = lib.Name[..slash].ToLowerInvariant();
                var version = lib.Name[(slash + 1)..];
                var packageDir = Path.Combine(nugetDir, packageId, version);
                foreach (var kind in new[] { "compile", "runtime" })
                {
                    if (!lib.Value.TryGetProperty(kind, out var assets))
                        continue;
                    foreach (var asset in assets.EnumerateObject())
                    {
                        if (!asset.Name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase))
                            continue;
                        var path = Path.Combine(nugetDir, packageId, version, asset.Name.Replace('/', Path.DirectorySeparatorChar));
                        if (File.Exists(path))
                            yield return path;
                    }
                }
                // Some packages (the Crestron SDK) ship assemblies outside the folders NuGet lists
                if (Directory.Exists(packageDir))
                    foreach (var path in Directory.EnumerateFiles(packageDir, "*.dll", SearchOption.AllDirectories).Order(StringComparer.Ordinal))
                        yield return path;
            }
        }
    }
}
