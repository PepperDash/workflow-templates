using SchemaGen;

// SchemaGen --assembly <plugin.dll> --types "A;B;Ns.C" --out <dir> [--summary <path>]

var opts = ParseArgs(args);
string? summaryPath = opts.GetValueOrDefault("summary") ?? Environment.GetEnvironmentVariable("GITHUB_STEP_SUMMARY");

void Log(string line)
{
    Console.WriteLine(line);
    if (!string.IsNullOrEmpty(summaryPath))
    {
        try { File.AppendAllText(summaryPath, line + "\n"); } catch { /* best effort */ }
    }
}

Log("## Generate config schema");

var result = Runner.Run(
    opts.GetValueOrDefault("assembly") ?? "",
    new[] { opts.GetValueOrDefault("types") ?? "" },
    opts.GetValueOrDefault("out") ?? "schemas",
    Log);

return result.ExitCode;

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
