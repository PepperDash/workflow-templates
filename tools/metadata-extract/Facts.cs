using System.Text.Json.Nodes;

namespace PepperDash.MetadataExtract;

/// <summary>
/// What the extractor could establish about one repo. The metadata script turns this into
/// pepperdash-metadata.json; anything null or listed under unresolved is left for the agent.
/// </summary>
public sealed class Facts
{
    public string Tool { get; init; } = $"metadata-extract@{typeof(Facts).Assembly.GetName().Version?.ToString(3)}";
    public string? MinimumEssentialsVersion { get; set; }
    /// <summary>The PepperDashEssentials version the build restored; null without --assembly or a restore</summary>
    public string? EssentialsDependencyVersion { get; set; }
    public SortedDictionary<string, TypeNameFacts> TypeNames { get; } = new(StringComparer.Ordinal);
    /// <summary>Every public interface defined in the inspected assemblies and their references</summary>
    public SortedSet<string> DefinedInterfaces { get; } = new(StringComparer.Ordinal);
    public List<string> Warnings { get; } = new();
}

public sealed class TypeNameFacts
{
    public required string Factory { get; init; }
    public required string DeviceClass { get; init; }
    /// <summary>factory (its generic argument) or build-device-branch (the class BuildDevice builds for this typeName)</summary>
    public required string DeviceClassSource { get; init; }
    public string? ConfigClass { get; set; }
    /// <summary>How the config class was found: deserialize-call, helper-call, constructor-parameter or device-constructor</summary>
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

/// <summary>Name is the key exactly as the code passes it: config tie lines reference it verbatim</summary>
public sealed record RoutingPort(
    string Name,
    string Label,
    string SignalType,
    string PortConnectionType);
