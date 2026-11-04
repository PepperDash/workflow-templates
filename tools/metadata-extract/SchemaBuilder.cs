using System.Reflection;
using System.Text.Json.Nodes;

namespace PepperDash.MetadataExtract;

/// <summary>
/// Builds a typeName's config schema from its config class, in the shape the config tool reads:
/// a draft-07 schema whose $defs.propertiesConfig describes the device's "properties" object,
/// with #root/... $ids that formMetadata schemaIds point at and a default that seeds new devices.
/// </summary>
public sealed class SchemaBuilder
{
    private const string JsonProperty = "Newtonsoft.Json.JsonPropertyAttribute";
    private const string JsonIgnore = "Newtonsoft.Json.JsonIgnoreAttribute";

    // The config tool edits these through controlMethods, not the properties form
    private static readonly HashSet<string> ControlPropertyTypes =
        ["EssentialsControlPropertiesConfig", "ControlPropertiesConfig"];

    private static readonly HashSet<string> IntegerTypes =
    [
        "System.Byte", "System.SByte", "System.Int16", "System.UInt16", "System.Int32", "System.UInt32",
        "System.Int64", "System.UInt64",
    ];
    private static readonly HashSet<string> NumberTypes = ["System.Single", "System.Double", "System.Decimal"];
    private static readonly HashSet<string> StringTypes =
        ["System.String", "System.Char", "System.DateTime", "System.DateTimeOffset", "System.TimeSpan", "System.Guid", "System.Uri"];
    private static readonly HashSet<string> ArrayTypes =
    [
        "System.Collections.Generic.List`1", "System.Collections.Generic.IList`1",
        "System.Collections.Generic.ICollection`1", "System.Collections.Generic.IEnumerable`1",
        "System.Collections.Generic.IReadOnlyList`1", "System.Collections.Generic.IReadOnlyCollection`1",
        "System.Collections.Generic.HashSet`1", "System.Collections.ObjectModel.Collection`1",
        "System.Collections.ObjectModel.ObservableCollection`1",
    ];
    private static readonly HashSet<string> DictionaryTypes =
    [
        "System.Collections.Generic.Dictionary`2", "System.Collections.Generic.IDictionary`2",
        "System.Collections.Generic.IReadOnlyDictionary`2", "System.Collections.Generic.SortedDictionary`2",
    ];

    private readonly SourceScanner _source;
    private readonly List<string> _warnings;

    public SchemaBuilder(SourceScanner source, List<string> warnings)
    {
        _source = source;
        _warnings = warnings;
    }

    public JsonObject Build(Type configClass, string typeName)
    {
        var propertiesConfig = ObjectSchema(configClass, "#root", new HashSet<string>());
        var defaults = propertiesConfig["default"]?.DeepClone() as JsonObject ?? new JsonObject();
        propertiesConfig.Remove("default");
        propertiesConfig.Remove("$id");
        propertiesConfig.Remove("title");

        var definition = new JsonObject
        {
            ["type"] = "object",
            ["additionalProperties"] = true,
            ["default"] = defaults,
        };
        foreach (var (key, value) in propertiesConfig.ToList())
        {
            if (key is "type")
                continue;
            propertiesConfig.Remove(key);
            definition[key] = value;
        }

        var schema = new JsonObject
        {
            ["$schema"] = "http://json-schema.org/draft-07/schema#",
            ["title"] = $"{typeName} properties config",
            ["type"] = "object",
            ["properties"] = new JsonObject
            {
                ["properties"] = new JsonObject { ["type"] = "object", ["$ref"] = "#/$defs/propertiesConfig" },
            },
            ["required"] = new JsonArray("properties"),
            ["$defs"] = new JsonObject { ["propertiesConfig"] = definition },
        };
        var description = _source.Summaries.GetValueOrDefault(configClass.Name);
        if (description is not null)
            schema["description"] = description;
        return schema;
    }

    private JsonObject TypeSchema(Type type, string id, HashSet<string> stack)
    {
        if (type.IsGenericType && type.GetGenericTypeDefinition().FullName == "System.Nullable`1")
            type = type.GetGenericArguments()[0];

        var full = type.IsGenericType ? type.GetGenericTypeDefinition().FullName : type.FullName;

        if (full == "System.Boolean")
            return new JsonObject { ["type"] = "boolean" };
        if (full is not null && IntegerTypes.Contains(full))
            return new JsonObject { ["type"] = "integer" };
        if (full is not null && NumberTypes.Contains(full))
            return new JsonObject { ["type"] = "number" };
        if (full is not null && StringTypes.Contains(full))
            return new JsonObject { ["type"] = "string" };
        if (type.IsEnum)
        {
            // Newtonsoft reads enum names without a StringEnumConverter, and configs use names
            var names = new JsonArray();
            foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Static))
                names.Add(field.Name);
            return new JsonObject { ["type"] = "string", ["enum"] = names };
        }
        if (type.IsArray)
            return ArraySchema(type.GetElementType()!, id, stack);
        if (full is not null && ArrayTypes.Contains(full))
            return ArraySchema(type.GetGenericArguments()[0], id, stack);
        if (full is not null && DictionaryTypes.Contains(full))
        {
            return new JsonObject
            {
                ["type"] = "object",
                ["additionalProperties"] = TypeSchema(type.GetGenericArguments()[1], $"{id}/additionalProperties", stack),
            };
        }
        if (full is "System.Object" || type.Namespace?.StartsWith("Newtonsoft.Json.Linq", StringComparison.Ordinal) == true)
            return new JsonObject();
        if (type.IsClass || (type.IsValueType && !type.IsPrimitive))
            return ObjectSchema(type, id, stack);

        _warnings.Add($"{id}: no schema rule for {type.FullName}; left unconstrained");
        return new JsonObject();
    }

    private JsonObject ArraySchema(Type element, string id, HashSet<string> stack)
    {
        var items = TypeSchema(element, $"{id}/items", stack);
        items["$id"] = $"{id}/items";
        return new JsonObject { ["type"] = "array", ["items"] = items };
    }

    private JsonObject ObjectSchema(Type type, string id, HashSet<string> stack)
    {
        var key = type.FullName ?? type.Name;
        if (!stack.Add(key))
            return new JsonObject { ["type"] = "object" };

        var properties = new JsonObject();
        var required = new JsonArray();
        var defaults = new JsonObject();

        foreach (var (property, memberType) in SerializedMembers(type))
        {
            var attributes = Attributes(property);
            if (attributes.Any(a => a.AttributeType.FullName == JsonIgnore))
                continue;

            var jsonProperty = attributes.FirstOrDefault(a => a.AttributeType.FullName == JsonProperty);
            var name = Safe(() => JsonName(jsonProperty)) ?? Naming.CamelCase(property.Name);
            var propertyType = memberType;

            if (ControlPropertyTypes.Contains(propertyType.Name))
            {
                defaults[name] = new JsonObject { ["method"] = "" };
                continue;
            }

            var propertyId = $"{id}/{name}";
            JsonObject schema;
            try
            {
                schema = TypeSchema(propertyType, propertyId, stack);
            }
            catch (FileNotFoundException e)
            {
                // One unresolvable type (a Compact Framework Crestron type) costs this member, not the schema
                _warnings.Add($"{type.Name}.{property.Name}: left out of the schema, missing reference: {e.Message}");
                continue;
            }
            var ordered = new JsonObject
            {
                ["$id"] = propertyId,
                ["title"] = Naming.Title(name),
            };
            var declaring = property.DeclaringType?.Name ?? type.Name;
            var description = _source.Summaries.GetValueOrDefault($"{declaring}.{property.Name}");
            if (description is not null)
                ordered["description"] = description;
            foreach (var (k, v) in schema.ToList())
            {
                schema.Remove(k);
                ordered[k] = v;
            }

            var value = DefaultFor(type, property, propertyType, ordered);
            if (value is not null)
            {
                ordered["default"] = value.DeepClone();
                defaults[name] = value;
            }
            properties[name] = ordered;

            if (Safe(() => IsRequired(jsonProperty)))
                required.Add(name);
        }

        stack.Remove(key);
        var result = new JsonObject
        {
            ["$id"] = id,
            ["title"] = Naming.Title(type.Name),
            ["type"] = "object",
            ["properties"] = properties,
        };
        if (required.Count > 0)
            result["required"] = required;
        if (defaults.Count > 0)
            result["default"] = defaults;
        return result;
    }

    /// <summary>
    /// A literal default from source, or the default an object property's own schema carries. A
    /// derived config's constructor runs after its base's initializers, so the source is searched
    /// from <paramref name="owner"/> up to the member's declaring class.
    /// </summary>
    private JsonNode? DefaultFor(Type owner, MemberInfo member, Type type, JsonObject schema)
    {
        var found = ClassChain(owner, member.DeclaringType)
            .Select(c => _source.Defaults.GetValueOrDefault($"{c}.{member.Name}"))
            .FirstOrDefault(d => d is not null);
        if (ReferenceEquals(found, DefaultValue.Unknown))
            return null;
        if (found is not null)
        {
            if (schema["enum"] is JsonArray names)
            {
                // Configs use member names; a numeric initializer (Mode = 0) is the member with that value
                var enumName = found.EnumMember ?? EnumName(type, found.Value);
                return enumName is not null && names.Any(n => n?.GetValue<string>() == enumName)
                    ? JsonValue.Create(enumName) : null;
            }
            // The scanner's node is shared by every schema that uses this class; hand out copies
            if (found.Value is not null)
                return found.Value.DeepClone();
        }
        return schema["default"] is JsonObject nested && type.IsClass ? nested.DeepClone() : null;
    }

    /// <summary>Class names from <paramref name="type"/> up to and including <paramref name="declaring"/></summary>
    private static IEnumerable<string> ClassChain(Type type, Type? declaring)
    {
        for (Type? t = type; t is not null; t = Safe(() => t.BaseType))
        {
            yield return t.Name;
            if (declaring is null || t == declaring)
                yield break;
        }
    }

    private static string? EnumName(Type type, JsonNode? value)
    {
        if (type.IsGenericType && type.GetGenericTypeDefinition().FullName == "System.Nullable`1")
            type = type.GetGenericArguments()[0];
        if (!type.IsEnum || value is not JsonValue number || !number.TryGetValue<decimal>(out var n))
            return null;
        foreach (var field in type.GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            try
            {
                if (Convert.ToDecimal(field.GetRawConstantValue(), System.Globalization.CultureInfo.InvariantCulture) == n)
                    return field.Name;
            }
            catch (InvalidOperationException)
            {
            }
        }
        return null;
    }

    /// <summary>
    /// What Newtonsoft reads by default: writable public properties, get-only collections it
    /// populates in place, and public fields that aren't readonly (ScheduledEventConfig uses fields).
    /// </summary>
    private IEnumerable<(MemberInfo Member, Type Type)> SerializedMembers(Type type)
    {
        PropertyInfo[] properties;
        FieldInfo[] fields;
        try
        {
            properties = type.GetProperties(BindingFlags.Public | BindingFlags.Instance);
            fields = type.GetFields(BindingFlags.Public | BindingFlags.Instance);
        }
        catch (FileNotFoundException e)
        {
            _warnings.Add($"{type.Name}: properties incomplete, missing reference: {e.Message}");
            return [];
        }
        var members = new List<(MemberInfo, Type)>();
        void Add(MemberInfo member, Func<Type> memberType, Func<Type, bool> serialized)
        {
            try
            {
                var resolved = memberType();
                if (serialized(resolved))
                    members.Add((member, resolved));
            }
            catch (FileNotFoundException e)
            {
                _warnings.Add($"{type.Name}.{member.Name}: left out of the schema, missing reference: {e.Message}");
            }
        }
        // Newtonsoft also sets a non-public setter when the property is marked [JsonProperty]
        foreach (var p in properties.Where(p => p.GetIndexParameters().Length == 0))
            Add(p, () => p.PropertyType, t => p.SetMethod?.IsPublic == true || IsCollection(t) ||
                (p.SetMethod is not null && Attributes(p).Any(a => a.AttributeType.FullName == JsonProperty)));
        foreach (var f in fields.Where(f => !f.IsInitOnly))
            Add(f, () => f.FieldType, _ => true);
        return members;
    }

    private static bool IsCollection(Type type) =>
        type.IsGenericType && type.GetGenericTypeDefinition().FullName is { } full &&
        (ArrayTypes.Contains(full) || DictionaryTypes.Contains(full));

    private IList<CustomAttributeData> Attributes(MemberInfo property)
    {
        try
        {
            return property.GetCustomAttributesData();
        }
        catch (FileNotFoundException)
        {
            return [];
        }
    }

    /// <summary>
    /// Reading an attribute's arguments resolves their types, which throws when one comes from an
    /// assembly that isn't available; treat that argument as absent
    /// </summary>
    private static T? Safe<T>(Func<T> read)
    {
        try
        {
            return read();
        }
        catch (FileNotFoundException)
        {
            return default;
        }
        catch (TypeLoadException)
        {
            return default;
        }
    }

    private static string? JsonName(CustomAttributeData? attribute)
    {
        if (attribute is null)
            return null;
        if (attribute.ConstructorArguments.FirstOrDefault().Value is string name)
            return name;
        return attribute.NamedArguments
            .Where(a => a.MemberName == "PropertyName")
            .Select(a => a.TypedValue.Value as string)
            .FirstOrDefault();
    }

    /// <summary>Required.Always (2) and Required.AllowNull (1) mean the property must be present</summary>
    private static bool IsRequired(CustomAttributeData? attribute) =>
        attribute?.NamedArguments.Any(a => a.MemberName == "Required" && a.TypedValue.Value is int v && v is 1 or 2) == true;
}
