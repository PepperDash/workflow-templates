using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace PepperDash.MetadataExtract;

public sealed record FactoryInfo(
    string Name,
    string DeviceClass,
    List<string> TypeNames,
    string? Description,
    string? ConfigClass,
    string? ConfigClassSource,
    string? MinimumEssentialsVersion,
    /// <summary>TypeNames whose BuildDevice branch builds a more specific class than DeviceClass</summary>
    Dictionary<string, string> BranchDeviceClasses);

/// <summary>A literal default from a property initializer or a parameterless constructor</summary>
public sealed record DefaultValue(JsonNode? Value, string? EnumMember);

/// <summary>
/// Reads the repo's C# source as syntax only: nothing is compiled or run. Finds what exists only
/// in code: TypeNames and the minimum Essentials version (assigned in factory constructors), which
/// class each factory builds and deserializes its config into, literal routing ports, property
/// defaults and doc comments.
/// </summary>
public sealed class SourceScanner
{
    // Essentials' own factories derive from EssentialsDeviceFactory<T>; plugins from the plugin variants
    private static readonly string[] FactoryBases =
        ["EssentialsPluginDeviceFactory", "EssentialsPluginDevelopmentDeviceFactory", "EssentialsDeviceFactory"];

    private static readonly Regex ExcludedPath = new(
        @"[\\/](bin|obj|\.git|tests?|[^\\/]*\.Tests?)[\\/]", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private readonly string _root;
    private readonly Dictionary<string, List<ClassDeclarationSyntax>> _classes = new(StringComparer.Ordinal);

    public List<FactoryInfo> Factories { get; } = new();
    /// <summary>Keyed "ClassName.PropertyName"</summary>
    public Dictionary<string, DefaultValue> Defaults { get; } = new(StringComparer.Ordinal);
    /// <summary>Doc comment summaries, keyed "ClassName" or "ClassName.PropertyName"</summary>
    public Dictionary<string, string> Summaries { get; } = new(StringComparer.Ordinal);
    /// <summary>Resolves a const string defined outside the repo, by owning type (if written) and field name</summary>
    public Func<string?, string, string?>? ExternalConstant { get; set; }

    public SourceScanner(string root)
    {
        _root = Path.GetFullPath(root);
    }

    public void Scan()
    {
        var files = Directory.EnumerateFiles(_root, "*.cs", SearchOption.AllDirectories)
            .Where(f => !ExcludedPath.IsMatch(f[_root.Length..].Replace('\\', '/') + "/"))
            .Order(StringComparer.Ordinal);

        foreach (var file in files)
        {
            var tree = CSharpSyntaxTree.ParseText(File.ReadAllText(file), path: Path.GetRelativePath(_root, file));
            foreach (var cls in tree.GetRoot().DescendantNodes().OfType<ClassDeclarationSyntax>())
            {
                var name = cls.Identifier.ValueText;
                if (!_classes.TryGetValue(name, out var list))
                    _classes[name] = list = new();
                list.Add(cls);
            }
        }

        // A plugin may add its own generic base (NvxBaseDeviceFactory<T> : EssentialsPluginDeviceFactory<T>);
        // its subclasses are factories too
        var factoryBases = new HashSet<string>(FactoryBases, StringComparer.Ordinal);
        for (var added = true; added;)
        {
            added = false;
            foreach (var (name, declarations) in _classes)
            {
                if (!factoryBases.Contains(name) && declarations.Any(c => c.TypeParameterList is not null &&
                        GenericBases(c).Any(g => factoryBases.Contains(g.Identifier.ValueText))))
                    added = factoryBases.Add(name) || added;
            }
        }

        foreach (var (name, declarations) in _classes)
        {
            foreach (var cls in declarations)
            {
                ReadDefaultsAndSummaries(name, cls);
                // Generic bases (Factory<T>) describe no device of their own
                if (cls.TypeParameterList is not null)
                    continue;
                var factory = ReadFactory(name, cls, factoryBases);
                if (factory is not null)
                    Factories.Add(factory);
            }
        }
    }

    public IReadOnlyList<ClassDeclarationSyntax> Declarations(string className) =>
        _classes.TryGetValue(className, out var list) ? list : [];

    private static IEnumerable<GenericNameSyntax> GenericBases(ClassDeclarationSyntax cls) =>
        (cls.BaseList?.Types ?? default)
            .Select(t => t.Type)
            .Select(t => t is QualifiedNameSyntax q ? q.Right : t)
            .OfType<GenericNameSyntax>();

    private FactoryInfo? ReadFactory(string name, ClassDeclarationSyntax cls, HashSet<string> factoryBases)
    {
        var deviceClass = GenericBases(cls)
            .Where(g => factoryBases.Contains(g.Identifier.ValueText))
            .Select(g => RightmostName(g.TypeArgumentList.Arguments[0]))
            .FirstOrDefault();
        if (deviceClass is null)
            return null;

        var typeNames = new List<string>();
        string? minimumVersion = null;
        foreach (var assignment in cls.DescendantNodes().OfType<AssignmentExpressionSyntax>())
        {
            var target = RightmostName(assignment.Left);
            if (target == "TypeNames")
                typeNames.AddRange(TypeNameValues(cls, assignment.Right));
            else if (target == "MinimumEssentialsFrameworkVersion")
                minimumVersion = ResolveString(assignment.Right);
        }
        // TypeNames.Add("x")
        foreach (var call in cls.DescendantNodes().OfType<InvocationExpressionSyntax>())
        {
            if (call.Expression is MemberAccessExpressionSyntax { Name.Identifier.ValueText: "Add" } access &&
                RightmostName(access.Expression) == "TypeNames")
                typeNames.AddRange(StringLiterals(call.ArgumentList));
        }

        var description = DescriptionAttribute(cls)
            ?? Declarations(deviceClass).Select(DescriptionAttribute).FirstOrDefault(d => d is not null);
        var (configClass, configSource) = FindConfigClass(cls);
        typeNames = typeNames.Distinct(StringComparer.Ordinal).ToList();

        return new FactoryInfo(
            name,
            deviceClass,
            typeNames,
            description,
            configClass,
            configSource,
            minimumVersion,
            BranchDeviceClasses(cls, deviceClass, typeNames));
    }

    /// <summary>BuildDevice and the plugin methods it calls, directly or as Owner.Method()</summary>
    private List<MethodDeclarationSyntax> BuildDeviceMethods(ClassDeclarationSyntax factory)
    {
        var methods = factory.Members.OfType<MethodDeclarationSyntax>()
            .Where(m => m.Identifier.ValueText == "BuildDevice")
            .ToList();
        foreach (var call in methods.ToList().SelectMany(m => m.DescendantNodes().OfType<InvocationExpressionSyntax>()))
        {
            var (owner, method) = call.Expression switch
            {
                MemberAccessExpressionSyntax access => (RightmostName(access.Expression), access.Name.Identifier.ValueText),
                IdentifierNameSyntax id => (factory.Identifier.ValueText, id.Identifier.ValueText),
                _ => (null, null),
            };
            if (owner is null)
                continue;
            methods.AddRange(Declarations(owner)
                .SelectMany(c => c.Members.OfType<MethodDeclarationSyntax>())
                .Where(m => m.Identifier.ValueText == method && !methods.Contains(m)));
        }
        return methods;
    }

    /// <summary>
    /// A factory registered for several models often builds a different class per typeName:
    /// <c>if (typeName.StartsWith("dmtx201c")) return new DmTx201CController(...)</c>, or a switch on
    /// it. For each typeName, the first branch (in source order) whose string literals match it and
    /// that creates a plugin class deriving from the factory's device class.
    /// </summary>
    private Dictionary<string, string> BranchDeviceClasses(
        ClassDeclarationSyntax factory, string deviceClass, List<string> typeNames)
    {
        var branches = new List<(List<string> literals, bool prefix, bool contains, SyntaxNode body, string? returns)>();
        var methods = BuildDeviceMethods(factory);
        foreach (var method in methods)
        {
            var returns = RightmostName(method.ReturnType);
            foreach (var node in method.DescendantNodes())
            {
                switch (node)
                {
                    case IfStatementSyntax ifs:
                        var condition = ifs.Condition.ToString();
                        branches.Add((StringLiterals(ifs.Condition).ToList(),
                            condition.Contains(".StartsWith(", StringComparison.Ordinal),
                            condition.Contains(".Contains(", StringComparison.Ordinal),
                            ifs.Statement, returns));
                        break;
                    case SwitchSectionSyntax section:
                        branches.Add((section.Labels.SelectMany(StringLiterals).ToList(), false, false, section, returns));
                        break;
                    case SwitchExpressionArmSyntax arm:
                        branches.Add((StringLiterals(arm.Pattern).ToList(), false, false, arm.Expression, returns));
                        break;
                }
            }
        }
        // A lookup table in the helper's class: { "dmrmc4kz100c", (k, n, i) => new DmRmc4kZ100CController(...) }
        foreach (var cls in methods.Select(m => m.Parent).OfType<ClassDeclarationSyntax>().Distinct())
        {
            foreach (var element in cls.DescendantNodes().OfType<InitializerExpressionSyntax>()
                         .Where(i => i.IsKind(SyntaxKind.ComplexElementInitializerExpression) && i.Expressions.Count == 2))
            {
                if (element.Expressions[0] is LiteralExpressionSyntax key && key.IsKind(SyntaxKind.StringLiteralExpression))
                    branches.Add(([key.Token.ValueText], false, false, element.Expressions[1], null));
            }
        }

        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var typeName in typeNames)
        {
            var lower = typeName.ToLowerInvariant();
            var built = branches
                .Where(b => b.literals.Any(l =>
                {
                    var literal = l.ToLowerInvariant();
                    return lower == literal || (b.prefix && lower.StartsWith(literal, StringComparison.Ordinal))
                        || (b.contains && lower.Contains(literal, StringComparison.Ordinal));
                }))
                .Select(b => b.body.DescendantNodesAndSelf().OfType<ObjectCreationExpressionSyntax>()
                    .Select(c => RightmostName(c.Type))
                    .FirstOrDefault(c => c != deviceClass &&
                        (DerivesFrom(c, deviceClass) || (b.returns is not null && DerivesFrom(c, b.returns)))))
                .FirstOrDefault(c => c is not null);
            if (built is not null)
                result[typeName] = built;
        }
        return result;
    }

    /// <summary>Whether a plugin class has <paramref name="ancestor"/> somewhere in its base list chain</summary>
    private bool DerivesFrom(string className, string ancestor)
    {
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Queue<string>([className]);
        while (pending.TryDequeue(out var name))
        {
            if (!visited.Add(name))
                continue;
            foreach (var cls in Declarations(name))
            {
                foreach (var baseType in cls.BaseList?.Types ?? default)
                {
                    var baseName = RightmostName(baseType.Type);
                    if (baseName == ancestor)
                        return true;
                    pending.Enqueue(baseName);
                }
            }
        }
        return false;
    }

    /// <summary>
    /// dc.Properties.ToObject&lt;T&gt;() or JsonConvert.DeserializeObject&lt;T&gt;() in BuildDevice, or in a
    /// plugin method BuildDevice calls (PropsConfig.FromDeviceConfig(dc) and the like).
    /// </summary>
    private (string?, string?) FindConfigClass(ClassDeclarationSyntax factory)
    {
        var buildDevice = factory.Members.OfType<MethodDeclarationSyntax>()
            .Where(m => m.Identifier.ValueText == "BuildDevice")
            .ToList();

        foreach (var method in buildDevice)
        {
            var direct = DeserializedType(method);
            if (direct is not null)
                return (direct, "deserialize-call");
        }

        foreach (var method in buildDevice)
        {
            foreach (var call in method.DescendantNodes().OfType<InvocationExpressionSyntax>())
            {
                if (call.Expression is not MemberAccessExpressionSyntax access)
                    continue;
                var owner = RightmostName(access.Expression);
                var helper = Declarations(owner)
                    .SelectMany(c => c.Members.OfType<MethodDeclarationSyntax>())
                    .Where(m => m.Identifier.ValueText == access.Name.Identifier.ValueText)
                    .Select(DeserializedType)
                    .FirstOrDefault(t => t is not null);
                if (helper is not null)
                    return (helper, "helper-call");
            }
        }
        return (null, null);
    }

    /// <summary>
    /// A device whose constructor takes the raw DeviceConfig and deserializes its properties itself:
    /// a plugin class in ToObject&lt;T&gt;()/DeserializeObject&lt;T&gt;() in one of its constructors.
    /// </summary>
    public string? ConfigFromDeviceConstructor(string deviceClass) =>
        Declarations(deviceClass)
            .SelectMany(c => c.Members.OfType<ConstructorDeclarationSyntax>())
            .SelectMany(c => c.DescendantNodes().OfType<GenericNameSyntax>())
            .Where(g => g.Identifier.ValueText is "ToObject" or "DeserializeObject")
            .Select(g => RightmostName(g.TypeArgumentList.Arguments[0]))
            .FirstOrDefault(t => Declarations(t).Count > 0);

    private static string? DeserializedType(SyntaxNode node) =>
        node.DescendantNodes().OfType<GenericNameSyntax>()
            .Where(g => g.Identifier.ValueText is "ToObject" or "DeserializeObject")
            .Select(g => RightmostName(g.TypeArgumentList.Arguments[0]))
            .FirstOrDefault();

    /// <summary>
    /// new RoutingInputPort(key, eRoutingSignalType.X, eRoutingPortConnectionType.Y, ...) in the device
    /// class and the plugin classes it derives from. A key that isn't a literal or a string constant
    /// is reported as unresolved for the agent.
    /// </summary>
    public RoutingPortFacts ReadRoutingPorts(string deviceClass)
    {
        var ports = new RoutingPortFacts();
        var visited = new HashSet<string>(StringComparer.Ordinal);
        var pending = new Queue<string>([deviceClass]);

        while (pending.TryDequeue(out var className))
        {
            if (!visited.Add(className))
                continue;
            foreach (var cls in Declarations(className))
            {
                foreach (var baseType in cls.BaseList?.Types ?? default)
                    pending.Enqueue(RightmostName(baseType.Type));

                foreach (var creation in cls.DescendantNodes().OfType<ObjectCreationExpressionSyntax>())
                {
                    // Subclasses (RoutingInputPortWithVideoStatuses) take the same leading arguments
                    var typeName = RightmostName(creation.Type);
                    var list = typeName.StartsWith("RoutingInputPort", StringComparison.Ordinal) ? ports.Inputs
                        : typeName.StartsWith("RoutingOutputPort", StringComparison.Ordinal) ? ports.Outputs
                        : null;
                    if (list is null)
                        continue;

                    var port = ReadPort(creation);
                    if (port is null)
                        ports.Unresolved.Add(Location(creation));
                    else if (list.All(p => p.Name != port.Name))
                        list.Add(port);
                }
            }
        }
        return ports;
    }

    private RoutingPort? ReadPort(ObjectCreationExpressionSyntax creation)
    {
        var args = creation.ArgumentList?.Arguments;
        if (args is null || args.Value.Count < 3)
            return null;

        var key = ResolveString(args.Value[0].Expression);
        var signals = EnumMembers(args.Value[1].Expression, "eRoutingSignalType");
        var connections = EnumMembers(args.Value[2].Expression, "eRoutingPortConnectionType");
        if (key is null || signals.Count == 0)
            return null;

        return new RoutingPort(
            key,
            key,
            Mappings.SignalType(signals),
            Mappings.PortConnectionType(connections.FirstOrDefault()));
    }

    private string? ResolveString(ExpressionSyntax expression)
    {
        switch (expression)
        {
            case LiteralExpressionSyntax lit when lit.IsKind(SyntaxKind.StringLiteralExpression):
                return lit.Token.ValueText;
            case IdentifierNameSyntax or MemberAccessExpressionSyntax:
                // A const or static readonly string field, anywhere in the repo, then a const in a
                // referenced assembly (Essentials' RoutingPortNames)
                var field = RightmostName(expression);
                var owner = expression is MemberAccessExpressionSyntax access ? RightmostName(access.Expression) : null;
                return _classes.Values.SelectMany(l => l)
                    .Where(c => owner is null || c.Identifier.ValueText == owner)
                    .SelectMany(c => c.Members.OfType<FieldDeclarationSyntax>())
                    .SelectMany(f => f.Declaration.Variables)
                    .Where(v => v.Identifier.ValueText == field)
                    .Select(v => v.Initializer?.Value)
                    .OfType<LiteralExpressionSyntax>()
                    .Where(l => l.IsKind(SyntaxKind.StringLiteralExpression))
                    .Select(l => l.Token.ValueText)
                    .FirstOrDefault()
                    ?? ExternalConstant?.Invoke(owner, field);
            default:
                return null;
        }
    }

    private static List<string> EnumMembers(ExpressionSyntax expression, string enumName) =>
        expression.DescendantNodesAndSelf().OfType<MemberAccessExpressionSyntax>()
            .Where(m => RightmostName(m.Expression) == enumName)
            .Select(m => m.Name.Identifier.ValueText)
            .ToList();

    private void ReadDefaultsAndSummaries(string className, ClassDeclarationSyntax cls)
    {
        var summary = Summary(cls);
        if (summary is not null)
            Summaries.TryAdd(className, summary);

        foreach (var property in cls.Members.OfType<PropertyDeclarationSyntax>())
        {
            var key = $"{className}.{property.Identifier.ValueText}";
            var propertySummary = Summary(property);
            if (propertySummary is not null)
                Summaries.TryAdd(key, propertySummary);
            if (property.Initializer is not null && ToDefault(property.Initializer.Value) is { } value)
                Defaults.TryAdd(key, value);
        }

        foreach (var field in cls.Members.OfType<FieldDeclarationSyntax>()
                     .Where(f => f.Modifiers.Any(SyntaxKind.PublicKeyword) && !f.Modifiers.Any(SyntaxKind.ConstKeyword)))
        {
            var fieldSummary = Summary(field);
            foreach (var variable in field.Declaration.Variables)
            {
                var key = $"{className}.{variable.Identifier.ValueText}";
                if (fieldSummary is not null)
                    Summaries.TryAdd(key, fieldSummary);
                if (variable.Initializer is not null && ToDefault(variable.Initializer.Value) is { } value)
                    Defaults.TryAdd(key, value);
            }
        }

        // Prop = literal; in a parameterless constructor
        foreach (var ctor in cls.Members.OfType<ConstructorDeclarationSyntax>()
                     .Where(c => c.ParameterList.Parameters.Count == 0 && c.Body is not null))
        {
            foreach (var statement in ctor.Body!.Statements.OfType<ExpressionStatementSyntax>())
            {
                if (statement.Expression is AssignmentExpressionSyntax assignment &&
                    ToDefault(assignment.Right) is { } value)
                    Defaults.TryAdd($"{className}.{RightmostName(assignment.Left)}", value);
            }
        }
    }

    private static DefaultValue? ToDefault(ExpressionSyntax expression)
    {
        switch (expression)
        {
            case LiteralExpressionSyntax lit:
                return lit.Kind() switch
                {
                    SyntaxKind.StringLiteralExpression => new(JsonValue.Create(lit.Token.ValueText), null),
                    SyntaxKind.TrueLiteralExpression => new(JsonValue.Create(true), null),
                    SyntaxKind.FalseLiteralExpression => new(JsonValue.Create(false), null),
                    SyntaxKind.NumericLiteralExpression => new(JsonNode.Parse(
                        Convert.ToString(lit.Token.Value, System.Globalization.CultureInfo.InvariantCulture)!), null),
                    _ => null,
                };
            case PrefixUnaryExpressionSyntax { OperatorToken.ValueText: "-", Operand: LiteralExpressionSyntax num }
                when num.IsKind(SyntaxKind.NumericLiteralExpression):
                return new(JsonNode.Parse("-" + Convert.ToString(num.Token.Value, System.Globalization.CultureInfo.InvariantCulture)), null);
            case MemberAccessExpressionSyntax { Name.Identifier.ValueText: "Empty" } access
                when RightmostName(access.Expression) is "string" or "String":
                return new(JsonValue.Create(""), null);
            case MemberAccessExpressionSyntax access when access.Expression is IdentifierNameSyntax:
                // Most likely an enum member; the schema builder checks against the property's type
                return new(null, access.Name.Identifier.ValueText);
            case BaseObjectCreationExpressionSyntax { Initializer: null } creation when IsCollection(creation):
            case CollectionExpressionSyntax { Elements.Count: 0 }:
                return new(new JsonArray(), null);
            default:
                return null;
        }
    }

    private static bool IsCollection(BaseObjectCreationExpressionSyntax creation) =>
        creation is ObjectCreationExpressionSyntax { Type: var type } &&
        RightmostName(type) is "List" or "IList" or "Collection" or "ObservableCollection" or "HashSet";

    private static string? Summary(SyntaxNode node)
    {
        var doc = node.GetLeadingTrivia()
            .Select(t => t.GetStructure())
            .OfType<DocumentationCommentTriviaSyntax>()
            .FirstOrDefault();
        var summary = doc?.Content.OfType<XmlElementSyntax>()
            .FirstOrDefault(e => e.StartTag.Name.LocalName.ValueText == "summary");
        if (summary is null)
            return null;
        var text = string.Concat(summary.Content.Select(c => c switch
        {
            XmlTextSyntax t => string.Concat(t.TextTokens.Select(tok => tok.ValueText)),
            XmlEmptyElementSyntax e => e.Attributes.OfType<XmlCrefAttributeSyntax>().FirstOrDefault()?.Cref.ToString() ?? "",
            XmlElementSyntax e => e.Content.ToString(),
            _ => "",
        }));
        text = Regex.Replace(text, @"\s+", " ").Trim();
        return text.Length > 0 ? text : null;
    }

    private static string? DescriptionAttribute(ClassDeclarationSyntax cls) =>
        cls.AttributeLists.SelectMany(l => l.Attributes)
            .Where(a => RightmostName(a.Name) is "Description" or "DescriptionAttribute")
            .Select(a => a.ArgumentList?.Arguments.FirstOrDefault()?.Expression)
            .OfType<LiteralExpressionSyntax>()
            .Select(l => l.Token.ValueText)
            .FirstOrDefault();

    /// <summary>The literals on the right of TypeNames =, or in the field it copies (TypeNames = _typeNames.ToList())</summary>
    private static IEnumerable<string> TypeNameValues(ClassDeclarationSyntax cls, ExpressionSyntax value)
    {
        var literals = StringLiterals(value).ToList();
        if (literals.Count > 0)
            return literals;
        var referenced = value.DescendantNodesAndSelf().OfType<IdentifierNameSyntax>()
            .Select(i => i.Identifier.ValueText)
            .ToHashSet(StringComparer.Ordinal);
        var initializers = cls.Members.OfType<FieldDeclarationSyntax>()
            .SelectMany(f => f.Declaration.Variables)
            .Where(v => referenced.Contains(v.Identifier.ValueText) && v.Initializer is not null)
            .SelectMany(v => StringLiterals(v.Initializer!.Value));
        // _typeNames ??= new List<string> { ... } in the constructor
        var assignments = cls.DescendantNodes().OfType<AssignmentExpressionSyntax>()
            .Where(a => referenced.Contains(RightmostName(a.Left)))
            .SelectMany(a => StringLiterals(a.Right));
        return initializers.Concat(assignments);
    }

    private static IEnumerable<string> StringLiterals(SyntaxNode node) =>
        node.DescendantNodes().OfType<LiteralExpressionSyntax>()
            .Where(l => l.IsKind(SyntaxKind.StringLiteralExpression))
            .Select(l => l.Token.ValueText)
            .Where(v => v.Length > 0);

    private static string Location(SyntaxNode node)
    {
        var span = node.GetLocation().GetLineSpan();
        var code = Regex.Replace(node.ToString(), @"\s+", " ");
        return $"{span.Path}:{span.StartLinePosition.Line + 1}: {(code.Length > 160 ? code[..160] + "…" : code)}";
    }

    public static string RightmostName(SyntaxNode node) => node switch
    {
        QualifiedNameSyntax q => RightmostName(q.Right),
        AliasQualifiedNameSyntax a => RightmostName(a.Name),
        MemberAccessExpressionSyntax m => m.Name.Identifier.ValueText,
        GenericNameSyntax g => g.Identifier.ValueText,
        IdentifierNameSyntax i => i.Identifier.ValueText,
        PredefinedTypeSyntax p => p.Keyword.ValueText,
        NullableTypeSyntax n => RightmostName(n.ElementType),
        _ => node.ToString(),
    };
}
