using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Kniv;

/// Boodschappen in de volgorde waarin je door een Nederlandse supermarkt loopt; dezelfde regels als Gangpad.swift.
/// De woordenlijst staat in GangpadWoorden.cs (gemaakt door scripts/gangpad_poort.py).
static partial class Gangpad
{
    public static int Overig => Namen.Length - 1;

    static string Plat(string s)
    {
        var d = s.ToLowerInvariant().Normalize(NormalizationForm.FormD);
        return new string(d.Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark).ToArray()).Normalize(NormalizationForm.FormC);
    }

    static readonly string[] Uitgangen = { "tjes", "etjes", "jes", "tje", "je", "en", "s", "'s" };

    /// Het woord zelf en zonder verkleinwoord of meervoud: appeltjes → appel, citroenen → citroen.
    static IEnumerable<string> Vormen(string w) =>
        new[] { w }.Concat(Uitgangen.Where(u => w.EndsWith(u, StringComparison.Ordinal) && w.Length - u.Length >= 3).Select(u => w[..^u.Length]));

    // lui: de volgorde van statische velden over twee partial-bestanden ligt niet vast
    static string[][]? _plat;
    static string[][] PlatteWoorden => _plat ??= Woorden.Select(r => r.Select(Plat).ToArray()).ToArray();

    public static int Van(string item)
    {
        var klein = Plat(item);
        var tokens = Regex.Split(klein, @"[^\p{L}'\-]+").Where(t => t != "").ToList();
        if (tokens.Any(t => t.StartsWith("diepvries", StringComparison.Ordinal))) return Array.IndexOf(Namen, "Diepvries");
        var alle = tokens.SelectMany(Vormen).ToHashSet();
        int beste = Overig, lengte = 0;
        for (var pad = 0; pad < PlatteWoorden.Length; pad++)
            foreach (var w in PlatteWoorden[pad])
            {
                var raak = w.Contains(' ')
                    ? klein.Contains(w)
                    : alle.Contains(w) || alle.Any(v => v.EndsWith(w, StringComparison.Ordinal) && v.Length - w.Length >= (w.Length >= 4 ? 1 : 3));
                if (raak && w.Length > lengte) { beste = pad; lengte = w.Length; }
            }
        return beste;
    }

    /// Plat in looproute-volgorde; binnen een gangpad blijft de volgorde zoals hij was.
    public static List<T> Volgorde<T>(IEnumerable<T> items, Func<T, string> tekst) =>
        items.Select((it, i) => (it, i, pad: Van(tekst(it)))).OrderBy(x => x.pad).ThenBy(x => x.i).Select(x => x.it).ToList();
}
