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
        // "14:30", of "om 14.30"; een los "2.50" is een prijs, geen tijd. "om 3" is 's middags, tenzij het ochtend is.
        var ochtend = woorden.Overlaps(new[] { "ochtend", "morgens", "vroeg", "am" });
        int Middag(int u) => u is >= 1 and <= 7 && !ochtend ? u + 12 : u;
        if ((Rx.Eerste(@"\b(\d{1,2}):(\d{2})\b", klein) ?? Rx.Eerste(@"\bom (\d{1,2})\.(\d{2})\b", klein)) is { } t1 && int.Parse(t1[1]) < 24 && int.Parse(t1[2]) < 60) tijd = (int.Parse(t1[1]), int.Parse(t1[2]));
        else if (Rx.Eerste(@"\bom (\d{1,2})\b", klein) is { } t2 && int.Parse(t2[1]) < 24) tijd = (Middag(int.Parse(t2[1])), 0);
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

    public static string? Reken(string invoer, Dictionary<string, double>? koersen = null, DateTime? nuOpt = null)
    {
        var klein = invoer.ToLowerInvariant().Trim();
        return Tijd(klein, nuOpt ?? DateTime.Now) ?? Goedkoper(klein) ?? Procent(klein) ?? Valuta(klein, koersen ?? new()) ?? Eenheid(klein);
    }

    // Rekenen met tijd, zoals Kniv/Logica/Rekenen.swift: "14:35 + 2u50", "9:15 tot 17:30", "dagen tot 25 dec", "15:00 in tokyo".
    static string? Tijd(string t, DateTime nu)
    {
        if (Rx.Eerste(@"^(?:dagen tot|hoe lang tot|days until|how long until)\s+(.+)$", t) is { } d && Herinnering.Vind(d[1], nu) is { } doel)
        {
            var dagen = (int)(doel.dag.Date - nu.Date).TotalDays;
            return dagen == 0 ? "Dat is vandaag!" : dagen >= 14 ? $"Nog {dagen} dagen ({dagen / 7} weken en {dagen % 7} dagen)" : $"Nog {dagen} dagen";
        }
        if (Rx.Eerste(@"^(?:hoe laat is het in|hoe laat in|tijd in|time in|what time in)\s+(.+?)\s*\??$", t) is { } h && Zone(h[1]) is { } z)
        {
            var daar = TimeZoneInfo.ConvertTime(nu, TimeZoneInfo.Local, z.tz);
            var verschil = (daar - nu).TotalHours;
            return $"In {z.naam} is het nu {daar:H:mm}" + (Math.Abs(verschil) < 0.01 ? "" : $" ({(verschil > 0 ? "+" : "")}{Mooi(verschil)} uur)");
        }
        const string klok = @"(\d{1,2}):(\d{2})";
        if (Rx.Eerste("^" + klok + @"\s+(?:in|naar|to)\s+(.+)$", t) is { } iz && Minuten(iz[1], iz[2]) is { } m0 && Zone(iz[3]) is { } z2)
        {
            var daar = TimeZoneInfo.ConvertTime(nu.Date.AddMinutes(m0), TimeZoneInfo.Local, z2.tz);
            return $"{iz[1]}:{iz[2]} hier = {daar:H:mm} in {z2.naam}";
        }
        if (Rx.Eerste("^" + klok + @"\s*(?:tot|-|–|to|until)\s*" + klok + "$", t) is { } r && Minuten(r[1], r[2]) is { } a && Minuten(r[3], r[4]) is { } b)
        {
            var duur = (b - a + 1440) % 1440;
            return $"{r[1]}:{r[2]} tot {r[3]}:{r[4]} = {DuurTekst(duur)} ({Mooi(duur / 60.0)} uur)";
        }
        if (Rx.Eerste("^" + klok + @"\s*([+-])\s*(.+)$", t) is { } p && Minuten(p[1], p[2]) is { } start && Duur(p[4]) is { } lengte)
        {
            var som = start + (p[3] == "+" ? lengte : -lengte);
            var dag = (int)Math.Floor(som / 1440.0);
            var rest = som - dag * 1440;
            var extra = dag > 0 ? " (volgende dag)" : dag < 0 ? " (dag ervoor)" : "";
            return $"{p[1]}:{p[2]} {p[3]} {DuurTekst(lengte)} = {rest / 60}:{rest % 60:00}{extra}";
        }
        return null;
    }

    static int? Minuten(string u, string m) => int.Parse(u) is var uu && int.Parse(m) is var mm && uu < 24 && mm < 60 ? uu * 60 + mm : null;

    public static int? Duur(string s)
    {
        var t = s.Trim();
        if (Rx.Eerste(@"^(\d+):(\d{2})$", t) is { } a) return int.Parse(a[1]) * 60 + int.Parse(a[2]);
        if (Rx.Eerste(@"^(\d+(?:[.,]\d+)?)\s*(?:u|uur|h|hours?)\s*(?:(\d+)\s*(?:m|min|minuten|minutes)?)?$", t) is { } b && Getal(b[1]) is { } u)
            return (int)Math.Round(u * 60) + (b[2] == "" ? 0 : int.Parse(b[2]));
        if (Rx.Eerste(@"^(\d+)\s*(?:m|min|minuten|minutes)$", t) is { } c) return int.Parse(c[1]);
        return null;
    }

    static string DuurTekst(int min) => min < 60 ? $"{min} min" : min % 60 == 0 ? $"{min / 60} u" : $"{min / 60} u {min % 60} min";

    static readonly Dictionary<string, string> Steden = new()
    {
        ["new york"] = "America/New_York", ["ny"] = "America/New_York", ["boston"] = "America/New_York", ["miami"] = "America/New_York",
        ["toronto"] = "America/Toronto", ["chicago"] = "America/Chicago", ["los angeles"] = "America/Los_Angeles", ["la"] = "America/Los_Angeles",
        ["san francisco"] = "America/Los_Angeles", ["vancouver"] = "America/Vancouver", ["mexico"] = "America/Mexico_City",
        ["curaçao"] = "America/Curacao", ["curacao"] = "America/Curacao", ["aruba"] = "America/Aruba", ["suriname"] = "America/Paramaribo",
        ["paramaribo"] = "America/Paramaribo", ["rio"] = "America/Sao_Paulo", ["sao paulo"] = "America/Sao_Paulo", ["hawaii"] = "Pacific/Honolulu",
        ["londen"] = "Europe/London", ["london"] = "Europe/London", ["lissabon"] = "Europe/Lisbon", ["lisbon"] = "Europe/Lisbon",
        ["istanbul"] = "Europe/Istanbul", ["turkije"] = "Europe/Istanbul", ["moskou"] = "Europe/Moscow", ["athene"] = "Europe/Athens",
        ["marokko"] = "Africa/Casablanca", ["marrakech"] = "Africa/Casablanca", ["kaapstad"] = "Africa/Johannesburg", ["cape town"] = "Africa/Johannesburg",
        ["dubai"] = "Asia/Dubai", ["india"] = "Asia/Kolkata", ["delhi"] = "Asia/Kolkata", ["mumbai"] = "Asia/Kolkata",
        ["bangkok"] = "Asia/Bangkok", ["thailand"] = "Asia/Bangkok", ["bali"] = "Asia/Makassar", ["jakarta"] = "Asia/Jakarta",
        ["singapore"] = "Asia/Singapore", ["hong kong"] = "Asia/Hong_Kong", ["beijing"] = "Asia/Shanghai", ["peking"] = "Asia/Shanghai",
        ["shanghai"] = "Asia/Shanghai", ["seoul"] = "Asia/Seoul", ["korea"] = "Asia/Seoul", ["tokyo"] = "Asia/Tokyo", ["japan"] = "Asia/Tokyo",
        ["sydney"] = "Australia/Sydney", ["melbourne"] = "Australia/Melbourne", ["perth"] = "Australia/Perth", ["auckland"] = "Pacific/Auckland",
        ["nieuw-zeeland"] = "Pacific/Auckland", ["amsterdam"] = "Europe/Amsterdam", ["nederland"] = "Europe/Amsterdam",
    };

    static (string naam, TimeZoneInfo tz)? Zone(string naam)
    {
        var sleutel = naam.Trim().Trim('?', '!', '.', ',');
        if (!Steden.TryGetValue(sleutel, out var id)) return null;
        try
        {
            var tz = TimeZoneInfo.FindSystemTimeZoneById(id);
            return (sleutel.Length <= 2 ? sleutel.ToUpperInvariant() : CultureInfo.InvariantCulture.TextInfo.ToTitleCase(sleutel), tz);
        }
        catch (Exception) { return null; }     // Windows zonder ICU kent de IANA-namen niet
    }

    // Wat is goedkoper: "2,49 voor 500g of 3,99 voor 1kg"
    static string? Goedkoper(string t)
    {
        const string deel = @"€?\s*(\d+(?:[.,]\d+)?)\s*(?:voor|for|per|/)\s*(\d+(?:[.,]\d+)?)?\s*(g|gr|gram|kg|kilo|ml|cl|l|liter|stuks?|st)";
        if (Rx.Eerste("^" + deel + @"\s*(?:of|or|vs\.?|tegen)\s*" + deel + "$", t) is not { } m
            || PerEenheid(m[1], m[2], m[3]) is not { } a || PerEenheid(m[4], m[5], m[6]) is not { } b || a.soort != b.soort || a.prijs <= 0 || b.prijs <= 0) return null;
        var label = a.soort == "st" ? "per stuk" : a.soort == "kg" ? "per kilo" : "per liter";
        if (Math.Abs(a.prijs - b.prijs) < 0.005) return $"Even duur: {Euro(a.prijs)} {label}";
        var (goed, duur, welke) = a.prijs < b.prijs ? (a.prijs, b.prijs, "De eerste") : (b.prijs, a.prijs, "De tweede");
        return $"{welke} is {(int)Math.Round((1 - goed / duur) * 100)}% goedkoper: {Euro(goed)} tegen {Euro(duur)} {label}";
    }

    static (double prijs, string soort)? PerEenheid(string prijs, string hoeveel, string eenheid)
    {
        if (Getal(prijs) is not { } p) return null;
        var n = hoeveel == "" ? 1 : Getal(hoeveel) ?? 0;
        if (n <= 0) return null;
        return eenheid switch
        {
            "g" or "gr" or "gram" => (p / (n / 1000), "kg"),
            "kg" or "kilo" => (p / n, "kg"),
            "ml" => (p / (n / 1000), "l"),
            "cl" => (p / (n / 100), "l"),
            "l" or "liter" => (p / n, "l"),
            _ => (p / n, "st"),
        };
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

    public static string? Reken(string t) => EenRegel(t) ? Omzetter.Reken(t, Opslag.Data.Koersen) ?? Rekenmachine.Tekst(t) : null;

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

/// Sommen in het snelvenster: "12*3+4", "(19,99 + 5) / 3", "2^10". Zelfde regels als de iPhone (Kniv/Logica/Rekenmachine.swift).
public static class Rekenmachine
{
    public static double? Uitkomst(string invoer)
    {
        var som = invoer.Replace(",", ".").Replace("x", "*").Replace("×", "*").Replace("÷", "/").Replace(" ", "");
        if (som == "" || som.Any(c => !"0123456789.+-*/^()".Contains(c)) || !som.Any(char.IsDigit)) return null;
        // Een min telt alleen met spaties eromheen, anders wordt 06-12345678 een som.
        if (!som.Any(c => "+*/^".Contains(c)) && !invoer.Contains(" - ")) return null;
        var p = new Parser(som);
        var v = p.Optelling();
        return v is { } w && p.I == som.Length && double.IsFinite(w) ? w : null;
    }

    public static string? Tekst(string invoer) =>
        Uitkomst(invoer) is { } v ? $"{invoer.Trim()} = {v.ToString("0.##", CultureInfo.GetCultureInfo("nl-NL"))}" : null;

    sealed class Parser(string t)
    {
        public int I;

        public double? Optelling()
        {
            var l = Vermenigvuldiging();
            while (l != null && I < t.Length && (t[I] == '+' || t[I] == '-'))
            {
                var op = t[I++];
                var r = Vermenigvuldiging();
                if (r == null) return null;
                l = op == '+' ? l + r : l - r;
            }
            return l;
        }

        double? Vermenigvuldiging()
        {
            var l = Macht();
            while (l != null && I < t.Length && (t[I] == '*' || t[I] == '/'))
            {
                var op = t[I++];
                var r = Macht();
                if (r == null || (op == '/' && r == 0)) return null;
                l = op == '*' ? l * r : l / r;
            }
            return l;
        }

        double? Macht()
        {
            var g = Teken();
            if (g != null && I < t.Length && t[I] == '^') { I++; var e = Macht(); return e == null ? null : Math.Pow(g.Value, e.Value); }
            return g;
        }

        double? Teken()
        {
            if (I < t.Length && t[I] == '-') { I++; return -Teken(); }
            if (I < t.Length && t[I] == '(')
            {
                I++;
                var v = Optelling();
                if (v == null || I >= t.Length || t[I] != ')') return null;
                I++;
                return v;
            }
            var start = I;
            while (I < t.Length && (char.IsDigit(t[I]) || t[I] == '.')) I++;
            return I > start && double.TryParse(t[start..I], NumberStyles.Float, CultureInfo.InvariantCulture, out var n) ? n : null;
        }
    }
}

/// Weeradvies zoals op de iPhone (Kniv/Logica/Advies.swift): regen op komst, of koud genoeg voor een jas.
public static class Weer
{
    static string? _advies;
    static DateTime _tijd = DateTime.MinValue;

    public static string? Advies => DateTime.Now - _tijd < TimeSpan.FromHours(1) ? _advies : null;

    public static string? Bepaal(IEnumerable<(int uur, int kans, double mm, double temp)> uren)
    {
        var lijst = uren.ToList();
        var regen = lijst.FirstOrDefault(u => u.kans >= 50 && u.mm >= 0.2);
        if (regen != default) return $"Regen rond {regen.uur:00}:00, paraplu mee";
        if (lijst.Count > 0 && lijst.Min(u => u.temp) is var k && k < 8) return $"Fris vandaag ({Math.Round(k)}°), jas aan";
        return null;
    }

    /// Haalt het weer op voor waar de laptop is (Windows-locatie). Lukt dat niet, dan geen advies.
    public static async Task VerversAsync()
    {
        if (DateTime.Now - _tijd < TimeSpan.FromMinutes(30)) return;
        try
        {
            var plek = await new Windows.Devices.Geolocation.Geolocator().GetGeopositionAsync(TimeSpan.FromHours(1), TimeSpan.FromSeconds(6));
            var p = plek.Coordinate.Point.Position;
            using var http = new HttpClient();
            var json = await http.GetStringAsync(FormattableString.Invariant(
                $"https://api.open-meteo.com/v1/forecast?latitude={p.Latitude:0.###}&longitude={p.Longitude:0.###}&hourly=precipitation_probability,precipitation,temperature_2m&forecast_hours=12&timezone=auto"));
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            var h = doc.RootElement.GetProperty("hourly");
            var tijden = h.GetProperty("time").EnumerateArray().Select(t => t.GetString() ?? "").ToList();
            var kans = h.GetProperty("precipitation_probability").EnumerateArray().Select(v => v.ValueKind == System.Text.Json.JsonValueKind.Number ? v.GetInt32() : 0).ToList();
            var mm = h.GetProperty("precipitation").EnumerateArray().Select(v => v.ValueKind == System.Text.Json.JsonValueKind.Number ? v.GetDouble() : 0).ToList();
            var temp = h.GetProperty("temperature_2m").EnumerateArray().Select(v => v.ValueKind == System.Text.Json.JsonValueKind.Number ? v.GetDouble() : 15).ToList();
            _advies = Bepaal(tijden.Select((t, i) => (int.TryParse(t.Length >= 13 ? t.Substring(11, 2) : "0", out var u) ? u : 0, kans[i], mm[i], temp[i])));
            _tijd = DateTime.Now;
        }
        catch { /* geen locatie of geen internet: dan maar geen weer */ }
    }
}

/// Regels of lijstjes met "mee", "meenemen" of "niet vergeten" (zoals op de iPhone).
public static class Meenemen
{
    static readonly Regex Patroon = new(@"(?i)\b(mee|meenemen|meebrengen|niet vergeten|vergeet niet)\b");

    public static List<string> Lijst(IEnumerable<Notitie> notities) =>
        notities.SelectMany(n => n.Items.Count > 0 && Patroon.IsMatch(n.Tekst ?? "")
            ? n.Items.Select(i => i.Tekst)
            : (n.Tekst ?? "").Split('\n').Where(r => Patroon.IsMatch(r))).Where(r => !string.IsNullOrWhiteSpace(r)).ToList();
}
