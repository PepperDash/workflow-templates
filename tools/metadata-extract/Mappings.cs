using System.Text;

namespace PepperDash.MetadataExtract;

public static class Naming
{
    /// <summary>Newtonsoft's CamelCasePropertyNamesContractResolver rule: HDBaseT -> hdBaseT, DVI -> dvi</summary>
    public static string CamelCase(string s)
    {
        if (string.IsNullOrEmpty(s) || !char.IsUpper(s[0]))
            return s;
        var chars = s.ToCharArray();
        for (var i = 0; i < chars.Length; i++)
        {
            if (i == 1 && !char.IsUpper(chars[i]))
                break;
            var hasNext = i + 1 < chars.Length;
            if (i > 0 && hasNext && !char.IsUpper(chars[i + 1]))
            {
                if (char.IsSeparator(chars[i + 1]))
                    chars[i] = char.ToLowerInvariant(chars[i]);
                break;
            }
            chars[i] = char.ToLowerInvariant(chars[i]);
        }
        return new string(chars);
    }

    /// <summary>pollIntervalMs -> Poll Interval Ms; the agent may polish it</summary>
    public static string Title(string name)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < name.Length; i++)
        {
            var c = name[i];
            var boundary = i > 0 && char.IsUpper(c) &&
                (char.IsLower(name[i - 1]) || (i + 1 < name.Length && char.IsLower(name[i + 1])));
            if (boundary || (i > 0 && char.IsDigit(c) && !char.IsDigit(name[i - 1])))
                sb.Append(' ');
            sb.Append(i == 0 ? char.ToUpperInvariant(c) : c);
        }
        return sb.ToString();
    }
}

/// <summary>The mapping rules in docs/pepperdash-metadata.md</summary>
public static class Mappings
{
    private static readonly HashSet<string> PortConnectionTypes =
        ["None", "DisplayPort", "Dvi", "Hdmi", "Rgb", "Vga", "LineAudio", "DigitalAudio", "Sdi"];

    public static string SignalType(IReadOnlyCollection<string> flags)
    {
        var audio = flags.Any(f => f is "Audio" or "SecondaryAudio" or "AudioVideo");
        var video = flags.Any(f => f is "Video" or "AudioVideo");
        if (audio && video) return "audioVideo";
        if (video) return "video";
        if (audio) return "audio";
        if (flags.Any(f => f.StartsWith("Usb", StringComparison.Ordinal))) return "usb";
        return "audioVideo";
    }

    public static string PortConnectionType(string? member) =>
        member is not null && PortConnectionTypes.Contains(member) ? member : "None";
}
