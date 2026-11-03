using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace PepperDash.MetadataExtract;

/// <summary>
/// What the extractor could establish about one repo. The metadata script turns this into
/// pepperdash-metadata.json; anything null or listed under unresolved is left for the agent.
/// </summary>
public sealed class Facts
{
    public string Tool { get; init; } = $"metadata-extract@{typeof(Facts).Assembly.GetName().Version?.ToString(3)}";
    public string? MinimumEssentialsVersion { get; set; }
    public SortedDictionary<string, TypeNameFacts> TypeNames { get; } = new(StringComparer.Ordinal);
    /// <summary>Every public interface defined in the inspected assemblies and their references</summary>
    public SortedSet<string> DefinedInterfaces { get; } = new(StringComparer.Ordinal);
    public List<string> Warnings { get; } = new();
}

public sealed class TypeNameFacts
{
    public required string Factory { get; init; }
    public required string DeviceClass { get; init; }
    public string? ConfigClass { get; set; }
    /// <summary>How the config class was found: deserialize-call, helper-call or constructor-parameter</summary>
    public string? ConfigClassSource { get; set; }
    public string? Description { get; set; }
    /// <summary>Null when no assembly was given</summary>
    public List<string>? Interfaces { get; set; }
    /// <summary>Null when no assembly was given or no config class was found</summary>
    public JsonObject? Schema { get; set; }
    public RoutingPortFacts RoutingPorts { get; } = new();
}

public sealed class RoutingPortFacts
{
    public List<RoutingPort> Inputs { get; } = new();
    public List<RoutingPort> Outputs { get; } = new();
    /// <summary>Port constructions the source scan couldn't read, as file:line and the code</summary>
    public List<string> Unresolved { get; } = new();
}

public sealed record RoutingPort(
    string Name,
    string Label,
    string SignalType,
    string PortConnectionType,
    /// <summary>The key exactly as the code passes it; Name is its camelCase form</summary>
    [property: JsonPropertyName("key")] string Key);
