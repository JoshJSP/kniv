using System.Globalization;
using System.Text.RegularExpressions;

namespace Kniv;

// Vrij getypte commando's, precies zoals op de iPhone (Kniv/Logica/TimerParser.swift, Rekenen.swift › Omzetter, Herinnering.swift).

static class Rx
{
    /// Zoals Herinnering.eersteMatch: alle groepen, "" voor een groep die niet meedeed.
    public static string[]? Eerste(string patroon, string tekst)
    {
        var m = Regex.Match(tekst, patroon);
        return m.Success ? m.Groups.Cast<Group>().Select(g => g.Success ? g.Value : "").ToArray() : null;
    }
}

/// Ziet een timer in een notitie: "over 20 min oven uit" → ("Oven uit", 1200 s).
public static class TimerParser
{
    static readonly HashSet<string> Vulwoorden = new() { "over", "timer", "na", "in", "voor", "zet", "een" };
    const string Patroon = @"\b(\d{1,3})\s*(minuten|minuut|min|m|uur|u|seconden|sec|s)\b";

    public static (string naam, int seconden)? Vind(string tekst)
    {
        if (Rx.Eerste(Patroon, tekst.ToLowerInvariant()) is not { } m || !int.TryParse(m[1], out var n) || n <= 0) return null;
        var factor = m[2].StartsWith('u') ? 3600 : m[2].StartsWith('s') ? 1 : 60;
        var seconden = n * factor;
        if (seconden > 24 * 3600) return null;
        var zonderDuur = Regex.Replace(tekst, Patroon, " ", RegexOptions.IgnoreCase);
        var naam = string.Join(" ", zonderDuur.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Where(w => !Vulwoorden.Contains(w.ToLowerInvariant())));
        return (naam == "" ? "Timer" : char.ToUpper(naam[0]) + naam[1..], seconden);
    }
}

/// Vindt een moment in een notitie: "morgen oma bellen", "maandag om 14:30", "deadline 9 okt".
public static class Herinnering
{
    static readonly Dictionary<string, DayOfWeek> Dagen = new()
    {
        ["zondag"] = DayOfWeek.Sunday, ["maandag"] = DayOfWeek.Monday, ["dinsdag"] = DayOfWeek.Tuesday, ["woensdag"] = DayOfWeek.Wednesday,
        ["donderdag"] = DayOfWeek.Thursday, ["vrijdag"] = DayOfWeek.Friday, ["zaterdag"] = DayOfWeek.Saturday,
        ["sunday"] = DayOfWeek.Sunday, ["monday"] = DayOfWeek.Monday, ["tuesday"] = DayOfWeek.Tuesday, ["wednesday"] = DayOfWeek.Wednesday,
        ["thursday"] = DayOfWeek.Thursday, ["friday"] = DayOfWeek.Friday, ["saturday"] = DayOfWeek.Saturday,
    };
    static readonly Dictionary<string, int> Maanden = new()
    {
        ["jan"] = 1, ["feb"] = 2, ["mrt"] = 3, ["maa"] = 3, ["mar"] = 3, ["apr"] = 4, ["mei"] = 5, ["may"] = 5, ["jun"] = 6,
        ["jul"] = 7, ["aug"] = 8, ["sep"] = 9, ["okt"] = 10, ["oct"] = 10, ["nov"] = 11, ["dec"] = 12,
    };

    /// Lokale tijd; heeftTijd = er stond ook een kloktijd in.
    public static (DateTime dag, bool heeftTijd)? Vind(string tekst, DateTime? nuOpt = null)
    {
        var nu = nuOpt ?? DateTime.Now;
        var klein = tekst.ToLowerInvariant();
        var woorden = Regex.Split(klein, @"\P{L}+").ToHashSet();
        var vandaag = nu.Date;

        DateTime? dag = null;
        if (woorden.Contains("overmorgen")) dag = vandaag.AddDays(2);
        else if (woorden.Contains("morgen") || woorden.Contains("tomorrow")) dag = vandaag.AddDays(1);
        else if (woorden.Overlaps(new[] { "vandaag", "vanavond", "today", "tonight" })) dag = vandaag;
        else if (Dagen.FirstOrDefault(d => woorden.Contains(d.Key)) is { Key: not null } wd)
        {
            var verschil = ((int)wd.Value - (int)vandaag.DayOfWeek + 7) % 7;
            dag = vandaag.AddDays(verschil == 0 ? 7 : verschil);
        }
        else if (Rx.Eerste(@"\b(\d{1,2})\s*(jan|feb|mrt|maa|mar|apr|mei|may|jun|jul|aug|sep|okt|oct|nov|dec)", klein) is { } m
                 && int.TryParse(m[1], out var d) && d >= 1 && d <= DateTime.DaysInMonth(nu.Year, Maanden[m[2]]))
        {
            var kandidaat = new DateTime(nu.Year, Maanden[m[2]], d);
            dag = kandidaat < vandaag ? kandidaat.AddYears(1) : kandidaat;
        }

        (int uur, int minuut)? tijd = null;
        if (Rx.Eerste(@"\b(\d{1,2})[:.](\d{2})\b", klein) is { } t1 && int.Parse(t1[1]) < 24 && int.Parse(t1[2]) < 60) tijd = (int.Parse(t1[1]), int.Parse(t1[2]));
        else if (Rx.Eerste(@"\bom (\d{1,2})\b", klein) is { } t2 && int.Parse(t2[1]) < 24) tijd = (int.Parse(t2[1]), 0);
        else if (woorden.Overlaps(new[] { "vanavond", "tonight" })) tijd = (19, 0);

        // Alleen een tijd ("om 14:00 bellen") betekent vandaag, of morgen als dat al voorbij is.
        if (dag == null && tijd is { } tt)
        {
            var om = vandaag.AddHours(tt.uur).AddMinutes(tt.minuut);
            return (om > nu ? om : om.AddDays(1), true);
        }
        if (dag is not { } gevonden) return null;
        return tijd is { } t ? (gevonden.AddHours(t.uur).AddMinutes(t.minuut), true) : (gevonden, false);
    }
}

/// Omzetten: "3 cups bloem", "45 usd", "30% korting op 89", "10 km in mijl".
public static class Omzetter
{
    public static CultureInfo Cultuur = Nl.Cultuur;

    // Factoren zoals Foundation (Measurement) ze gebruikt; basis per dimensie: meter, kg, liter, kelvin, m/s, bit.
    record Soort(string[] Namen, string Dimensie, double Factor, string Doel, string Label, double Plus = 0);

    static readonly Soort[] Soorten =
    {
        new(new[] { "mijl", "mile", "miles", "mi" }, "lengte", 1609.34, "km", "mijl"),
        new(new[] { "km", "kilometer" }, "lengte", 1000, "mijl", "km"),
        new(new[] { "m", "meter" }, "lengte", 1, "ft", "m"),
        new(new[] { "cm" }, "lengte", 0.01, "inch", "cm"),
        new(new[] { "ft", "feet", "foot", "voet" }, "lengte", 0.3048, "m", "ft"),
        new(new[] { "inch", "inches", "\"" }, "lengte", 0.0254, "cm", "inch"),
        new(new[] { "yard", "yards", "yd" }, "lengte", 0.9144, "m", "yd"),
        new(new[] { "lb", "lbs", "pond", "pound", "pounds" }, "massa", 0.453592, "kg", "lb"),
        new(new[] { "oz", "ounce", "ounces" }, "massa", 0.0283495, "g", "oz"),
        new(new[] { "stone", "st" }, "massa", 6.35029, "kg", "stone"),
        new(new[] { "kg", "kilo" }, "massa", 1, "lb", "kg"),
        new(new[] { "g", "gram" }, "massa", 0.001, "oz", "g"),
        new(new[] { "cup", "cups", "kop", "kopjes" }, "volume", 0.24, "ml", "cups"),
        new(new[] { "tbsp", "el", "eetlepel", "eetlepels" }, "volume", 0.0147868, "ml", "el"),
        new(new[] { "tsp", "tl", "theelepel", "theelepels" }, "volume", 0.00492892, "ml", "tl"),
        new(new[] { "gallon", "gallons", "gal" }, "volume", 3.78541, "l", "gallon"),
        new(new[] { "l", "liter" }, "volume", 1, "gallon", "l"),
        new(new[] { "ml" }, "volume", 0.001, "cups", "ml"),
        new(new[] { "f", "°f", "fahrenheit" }, "temperatuur", 0.55555555555556, "c", "°F", 255.37222222222427),
        new(new[] { "c", "°c", "celsius" }, "temperatuur", 1, "f", "°C", 273.15),
        new(new[] { "mph" }, "snelheid", 0.44704, "km/h", "mph"),
        new(new[] { "km/h", "kmh", "km/u" }, "snelheid", 0.277778, "mph", "km/h"),
        new(new[] { "gb" }, "opslag", 8e9, "mb", "GB"),
        new(new[] { "mb" }, "opslag", 8e6, "gb", "MB"),
        new(new[] { "tb" }, "opslag", 8e12, "gb", "TB"),
        new(new[] { "mbps", "mbit", "mbit/s" }, "opslag", 1e6, "mb", "Mbps"),
    };

    /// Gram per US-cup, zodat "3 cups bloem" ook in gram kan.
    static readonly Dictionary<string, double> Dichtheid = new()
    {
        ["bloem"] = 125, ["flour"] = 125, ["suiker"] = 200, ["sugar"] = 200, ["boter"] = 227, ["butter"] = 227,
        ["rijst"] = 185, ["rice"] = 185, ["havermout"] = 90, ["oats"] = 90, ["cacao"] = 100, ["melk"] = 240, ["milk"] = 240,
    };

    static readonly Dictionary<string, string> Symbolen = new() { ["$"] = "USD", ["£"] = "GBP", ["¥"] = "JPY", ["₺"] = "TRY", ["kr"] = "SEK", ["zł"] = "PLN", ["chf"] = "CHF" };

    public static string? Reken(string invoer, Dictionary<string, double>? koersen = null)
    {
        var klein = invoer.ToLowerInvariant().Trim();
        return Procent(klein) ?? Valuta(klein, koersen ?? new()) ?? Eenheid(klein);
    }

    static double? Getal(string s) => double.TryParse(s.Replace(',', '.'), NumberStyles.Float, CultureInfo.InvariantCulture, out var v) ? v : null;

    public static string Mooi(double v)
    {
        var dec = Math.Abs(v) < 10 ? 2 : Math.Abs(v) < 100 ? 1 : 0;
        return Math.Round(v, dec, MidpointRounding.ToEven).ToString("#,0.##", Cultuur);
    }

    public static string Euro(double v, string code = "EUR") =>
        code == "EUR" ? v.ToString("C2", Cultuur) : $"{code} {v.ToString("#,0.00", Cultuur)}";

    const string Num = @"(-?\d+(?:[.,]\d+)?)";

    static string? Procent(string t)
    {
        if (Rx.Eerste(Num + @"\s*%\s*(korting|off)?\s*(?:op|van|of|on)\s*€?\s*" + Num, t) is not { } m || Getal(m[1]) is not { } p || Getal(m[3]) is not { } b) return null;
        var deel = b * p / 100;
        return m[2] == "" ? $"{Mooi(p)}% van {Mooi(b)} = {Mooi(deel)}" : $"Je betaalt {Euro(b - deel)} en bespaart {Euro(deel)}";
    }

    static string? Valuta(string t, Dictionary<string, double> koersen)
    {
        var codes = koersen.Keys.Select(k => k.ToLowerInvariant()).ToHashSet();
        double? bedrag = null;
        string? code = null;
        if (Rx.Eerste(Num + @"\s*([a-z]{3})\b", t) is { } m1 && (codes.Contains(m1[2]) || m1[2] == "eur"))
        { bedrag = Getal(m1[1]); code = m1[2].ToUpperInvariant(); }
        else if (Rx.Eerste(@"(\$|£|¥|₺|€)\s*" + Num, t) is { } m2)
        { bedrag = Getal(m2[2]); code = m2[1] == "€" ? "EUR" : Symbolen.GetValueOrDefault(m2[1]); }
        else if (Rx.Eerste(Num + @"\s*(\$|£|¥|₺|€|kr|zł)", t) is { } m3)
        { bedrag = Getal(m3[1]); code = m3[2] == "€" ? "EUR" : Symbolen.GetValueOrDefault(m3[2]); }
        if (bedrag is not { } x || code == null) return null;
        if (code == "EUR")
        {
            if (Rx.Eerste(@"(?:in|naar|to)\s+([a-z]{3})\b", t) is not { } m || !koersen.TryGetValue(m[1].ToUpperInvariant(), out var r)) return null;
            return $"{Euro(x)} ≈ {Euro(x * r, m[1].ToUpperInvariant())}";
        }
        if (!koersen.TryGetValue(code, out var k) || k <= 0) return null;
        return $"{Euro(x, code)} ≈ {Euro(x / k)}";
    }

    static Soort? Zoek(string naam) => Soorten.FirstOrDefault(s => s.Namen.Contains(naam));

    static string? Eenheid(string t)
    {
        if (Rx.Eerste(Num + @"\s*(°?[a-z]+(?:/[a-z]+)?|"")", t) is not { } m || Getal(m[1]) is not { } waarde || Zoek(m[2]) is not { } van) return null;
        var gevraagd = Rx.Eerste(@"(?:in|naar|to)\s+(°?[a-z]+(?:/[a-z]+)?)\s*$", t) is { } g ? Zoek(g[1]) : null;
        if ((gevraagd ?? Zoek(van.Doel)) is not { } naar || naar.Dimensie != van.Dimensie) return null;
        var basis = waarde * van.Factor + van.Plus;
        var uitkomst = (basis - naar.Plus) / naar.Factor;
        var tekst = $"{Mooi(waarde)} {van.Label} = {Mooi(uitkomst)} {naar.Label}";
        if (van.Dimensie == "volume" && Dichtheid.FirstOrDefault(d => t.Contains(d.Key)) is { Key: not null } stof)
            tekst += $" ≈ {Mooi(basis / 0.24 * stof.Value)} g {stof.Key}";
        return tekst;
    }
}

/// Win+Shift+K herkent commando's zonder slash. Alleen op één regel; een moment ("morgen om 3 uur") blijft een notitie.
public static class SnelCommando
{
    static bool EenRegel(string t) => t.Trim() != "" && !t.Trim().Contains('\n') && !t.Trim().Contains('\r');

    public static string? Reken(string t) => EenRegel(t) ? Omzetter.Reken(t, Opslag.Data.Koersen) : null;

    public static (string naam, int seconden)? Timer(string t) =>
        EenRegel(t) && Herinnering.Vind(t) == null ? TimerParser.Vind(t.Trim()) : null;

    /// Het stukje dat je wilt plakken: "10 km = 6,21 mijl" → "6,21 mijl".
    public static string Kern(string uitkomst)
    {
        var i = uitkomst.IndexOfAny(new[] { '=', '≈' });
        if (i < 0) return uitkomst;
        var rest = uitkomst[(i + 1)..].Trim();
        var j = rest.IndexOf(" ≈ ", StringComparison.Ordinal);
        return j < 0 ? rest : rest[..j];
    }

    public static string Klok(int seconden) =>
        seconden >= 3600 ? $"{seconden / 3600}:{seconden / 60 % 60:00}:{seconden % 60:00}" : $"{seconden / 60:00}:{seconden % 60:00}";
}
