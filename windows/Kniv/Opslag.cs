using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Kniv;

// Alles heeft een Guid en een Gewijzigd-tijd (UTC): genoeg om later met Supabase te syncen (laatste wint).

public class Notitie
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public DateTime Gemaakt { get; set; } = DateTime.UtcNow;
    public DateTime Gewijzigd { get; set; } = DateTime.UtcNow;
    public string Tekst { get; set; } = "";
    public string? Foto { get; set; }          // bestandsnaam in de map "fotos" (afbeelding of ander bestand)
    public string? Bakje { get; set; }         // null = nog niet gesorteerd
    public List<string> Twijfel { get; set; } = new();
    public List<LijstItem> Items { get; set; } = new();
    public string? FotoTekst { get; set; }     // tekst uit een telefoonfoto (de foto zelf synct niet)
    public Guid? Eigenaar { get; set; }        // Supabase: wie hem maakte (null = nog nooit gesynct)
    public Guid? Groep { get; set; }           // Supabase: gedeelde groep, null = alleen eigen apparaten

    [JsonIgnore] public string ZoekTekst => string.Join("\n", new[] { Tekst, Foto ?? "" }.Concat(Items.Select(i => i.Tekst)));
    [JsonIgnore] public string Titel =>
        Tekst.Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()
        ?? Items.FirstOrDefault()?.Tekst
        ?? (Foto == null ? "Leeg" : Opslag.IsAfbeelding(Foto) ? "Foto" : Opslag.OrigineleNaam(Foto));
    [JsonIgnore] public string VolledigeTekst => string.Join("\n", new[] { Tekst }.Concat(Items.Select(i => "- " + i.Tekst)).Where(s => s != ""));
}

public class LijstItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Tekst { get; set; } = "";
    public Guid? Door { get; set; }            // wie het item toevoegde (profielbolletje op de telefoon)

    /// Zoekt bij een tekst een oud item met die tekst, elk oud item maar één keer (anders vinkt één klik twee items af).
    public static Func<string, LijstItem?> Koppel(IEnumerable<LijstItem> oud)
    {
        var over = oud.ToList();
        return tekst =>
        {
            var i = over.FindIndex(o => o.Tekst == tekst);
            if (i < 0) return null;
            var o = over[i];
            over.RemoveAt(i);
            return o;
        };
    }
}

public class Bakje
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Naam { get; set; } = "";
    public bool Vast { get; set; }
    public DateTime LaatstGebruikt { get; set; } = DateTime.MinValue;
}

public class LosseTimer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Naam { get; set; } = "";
    public DateTime Eind { get; set; }         // lokale tijd
    public bool IsCountdown { get; set; }      // countdown naar een datum i.p.v. een losse timer
    public bool Gemeld { get; set; }
}

public class KnivData
{
    public List<Bakje> Bakjes { get; set; } = new();
    public List<Notitie> Notities { get; set; } = new();
    public Dictionary<string, string> Geleerd { get; set; } = new();
    public List<LosseTimer> Timers { get; set; } = new();
    public Dictionary<string, double> Koersen { get; set; } = new();
    public string KoersDatum { get; set; } = "";
    // Sync (zie Sync.cs): laatst verstuurde/ontvangen gewijzigd-tijd per notitie, nog te verwijderen ids, en tot waar opgehaald.
    public Dictionary<Guid, DateTime> Gesynct { get; set; } = new();
    public Dictionary<Guid, DateTime> Weg { get; set; } = new();
    public DateTime? OpgehaaldTot { get; set; }
    public Guid? SyncVan { get; set; }         // van welke gebruiker de sync-gegevens hierboven zijn (blijft staan na een verlopen sessie)
}

public static class Opslag
{
    // KNIV_MAP: andere map, om te testen zonder de echte gegevens te raken.
    public static readonly string Map = Environment.GetEnvironmentVariable("KNIV_MAP") is { Length: > 0 } m ? m
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Kniv");
    public static readonly string FotoMap = Path.Combine(Map, "fotos");
    static readonly string Bestand = Path.Combine(Map, "kniv.json");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static KnivData Data { get; private set; } = new();
    public static event Action? Gewijzigd;
    static bool _geladen;   // false: kniv.json kon niet gelezen worden, dus niet overschrijven

    public static void Laad()
    {
        Directory.CreateDirectory(FotoMap);
        try { Data = Lees(Bestand) ?? Reserve(); _geladen = true; }
        catch (JsonException)
        {
            // Kapot bestand niet overschrijven: bewaar het ernaast en val terug op de vorige versie.
            try { File.Copy(Bestand, Bestand + $".kapot-{DateTime.Now:yyyyMMdd-HHmmss}", true); _geladen = true; }
            catch (Exception e) { App.Log(e); }
            Data = Reserve();
        }
        catch (Exception e)
        {
            // Op slot (virusscanner, OneDrive) of onleesbaar: niets overschrijven zolang dat zo is.
            App.Log(e);
            Data = Reserve();
        }
        if (Data.Bakjes.Count == 0)
            Data.Bakjes = Sorteerder.StandaardBakjes.Select(n => new Bakje { Naam = n, Vast = true }).ToList();
    }

    /// null = bestaat niet. JsonException = kapot; een IO-fout wordt een paar keer opnieuw geprobeerd.
    static KnivData? Lees(string pad)
    {
        for (var poging = 1; ; poging++)
            try { return File.Exists(pad) ? JsonSerializer.Deserialize<KnivData>(File.ReadAllText(pad), Json) ?? new() : null; }
            catch (Exception e) when (e is not JsonException && poging < 5) { Thread.Sleep(200); }
    }

    static KnivData Reserve()
    {
        try { return Lees(Bestand + ".bak") ?? new(); }
        catch (Exception e) { App.Log(e); return new(); }
    }

    /// Schrijft via een tijdelijk bestand (echt op schijf) en houdt de vorige versie als .bak, zodat een crash nooit de data kost.
    public static void Bewaar()
    {
        if (!_geladen) { App.Log("Niet bewaard: kniv.json kon bij het starten niet gelezen worden."); return; }
        var tmp = Bestand + ".tmp";
        using (var f = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(f, Data, Json);
            f.Flush(true);
        }
        if (File.Exists(Bestand)) File.Replace(tmp, Bestand, Bestand + ".bak");
        else File.Move(tmp, Bestand);
        Gewijzigd?.Invoke();
    }

    public static readonly string[] AfbeeldingExt = { ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp" };
    public static bool IsAfbeelding(string naam) => AfbeeldingExt.Contains(Path.GetExtension(naam).ToLowerInvariant());
    public static string FotoPad(string naam) => Path.Combine(FotoMap, naam);
    /// Opgeslagen als "guid_origineel.ext"; dit geeft "origineel.ext" terug.
    public static string OrigineleNaam(string naam) => naam.Length > 33 && naam[32] == '_' ? naam[33..] : naam;

    public static string KopieerBestand(string bron)
    {
        var naam = Guid.NewGuid().ToString("N") + "_" + Path.GetFileName(bron);
        File.Copy(bron, FotoPad(naam));
        return naam;
    }

    // ---- vastleggen ----

    public static Notitie? Nieuw(string tekst, string? foto = null)
    {
        var schoon = tekst.Trim();
        if (schoon == "" && foto == null) return null;
        var (rest, items) = NotitieParser.Ontleed(schoon);
        var n = new Notitie { Tekst = rest, Foto = foto, Items = items.Select(i => new LijstItem { Tekst = i }).ToList() };
        var opties = Sorteerder.Sorteer(n.ZoekTekst, Data.Bakjes.Select(b => b.Naam).ToList(), Data.Geleerd);
        Data.Notities.Insert(0, n);
        if (opties.Count == 1) Kies(n, opties[0], leer: false);
        else { n.Twijfel = opties; Bewaar(); }
        return n;
    }

    public static void Kies(Notitie n, string bakje, bool leer)
    {
        n.Bakje = bakje;
        n.Twijfel = new();
        n.Gewijzigd = DateTime.UtcNow;
        var b = Data.Bakjes.FirstOrDefault(x => x.Naam == bakje);
        if (b != null) b.LaatstGebruikt = DateTime.UtcNow;
        if (leer) Sorteerder.Leer(n.ZoekTekst, bakje, Data.Geleerd);
        Bewaar();
    }

    public static void Verwijder(Notitie n)
    {
        if (n.Foto != null) try { File.Delete(FotoPad(n.Foto)); } catch (IOException) { }
        Data.Notities.Remove(n);
        // Ooit verstuurd (of onderweg): andere apparaten moeten hem ook weghalen.
        if (Data.Gesynct.ContainsKey(n.Id) || n.Eigenaar != null) Data.Weg[n.Id] = DateTime.UtcNow;
        Bewaar();
    }

    /// School bovenaan op schooltijd, Boodschappen rond etenstijd, en wat je net gebruikte schuift mee omhoog.
    public static List<Bakje> SlimmeVolgorde(DateTime? tijd = null)
    {
        var nu = tijd ?? DateTime.Now;
        var uur = nu.Hour;
        var weekend = nu.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday;
        double Score(Bakje b)
        {
            var s = Math.Max(0, 1.5 - (DateTime.UtcNow - b.LaatstGebruikt).TotalDays);
            if (b.Naam == "School" && !weekend && uur is >= 8 and < 17) s += 2;
            else if (b.Naam == "Boodschappen" && (uur is >= 16 and < 20 || (weekend && uur is >= 10 and < 18))) s += 2;
            else if (b.Naam == "To-do" && uur is >= 7 and < 10) s += 1.5;
            return s;
        }
        return Data.Bakjes.Select((b, i) => (b, i)).OrderByDescending(x => Score(x.b)).ThenBy(x => x.i).Select(x => x.b).ToList();
    }
}

/// Herkent afvinklijstjes: regels die met "- ", "• ", "* " of "[ ] " beginnen.
public static class NotitieParser
{
    static readonly string[] Voorvoegsels = { "- ", "• ", "* ", "[ ] ", "[] " };

    public static (string rest, List<string> items) Ontleed(string tekst)
    {
        var rest = new List<string>();
        var items = new List<string>();
        foreach (var regel in tekst.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            var kaal = regel.Trim();
            if (Voorvoegsels.Contains(kaal + " ")) continue;  // leeg streepje: overslaan
            var p = Voorvoegsels.FirstOrDefault(kaal.StartsWith);
            var item = p == null ? "" : kaal[p.Length..].Trim();
            if (item != "") items.Add(item); else rest.Add(regel);
        }
        return (string.Join("\n", rest).Trim(), items);
    }
}

/// Kiest het bakje. Eén antwoord = zeker, twee = Kniv twijfelt en vraagt het.
/// Volgorde (zoals op de iPhone, zonder taalmodel): bakjesnaam letterlijk genoemd → geleerd van jouw keuzes → trefwoorden.
public static class Sorteerder
{
    public static readonly string[] StandaardBakjes = { "School", "Boodschappen", "Ideeën", "To-do", "Persoonlijk" };

    static readonly Dictionary<string, string[]> Trefwoorden = new()
    {
        ["School"] = new[] { "school", "les", "lessen", "college", "tentamen", "toets", "opdracht", "deadline", "buas", "huiswerk",
            "project", "presentatie", "leren", "studie", "docent", "rooster", "hoofdstuk", "blok", "inleveren", "assignment" },
        ["Boodschappen"] = new[] { "melk", "brood", "eieren", "kaas", "boter", "boodschappen", "supermarkt", "jumbo", "ah", "albert heijn",
            "lidl", "aldi", "pasta", "rijst", "groente", "fruit", "appels", "bananen", "vlees", "kip", "wc-papier",
            "shampoo", "koffie", "thee", "yoghurt", "chips", "drinken", "halen" },
        ["To-do"] = new[] { "bellen", "mailen", "regelen", "moet", "vergeten", "afspraak", "betalen", "opruimen", "maken", "fixen",
            "sturen", "aanvragen", "opzeggen", "wassen", "was", "todo", "to-do", "straks" },
        ["Persoonlijk"] = new[] { "oma", "opa", "mama", "papa", "moeder", "vader", "zus", "broer", "verjaardag", "vriendin", "vriend",
            "cadeau", "voel", "dagboek", "gezondheid", "dokter", "tandarts", "sporten" },
        ["Ideeën"] = new[] { "idee", "ideeën", "app", "misschien", "concept", "bedenken", "plan", "zou", "wat als", "inspiratie",
            "ontwerp", "verhaal", "game" },
    };

    static readonly HashSet<string> Stopwoorden = new() { "voor", "naar", "maar", "even", "nog", "niet", "met", "van", "een", "het", "de",
        "dat", "die", "wat", "als", "ook", "moet", "morgen", "vandaag", "the", "and", "with" };

    public static List<string> Sorteer(string tekst, List<string> bakjes, Dictionary<string, string> geleerd)
    {
        var namen = bakjes.Count == 0 ? StandaardBakjes.ToList() : bakjes;
        var klein = tekst.ToLowerInvariant();
        var genoemd = namen.FirstOrDefault(n => klein.Contains(n.ToLowerInvariant()));
        if (genoemd != null) return new() { genoemd };
        var uitGeleerd = UitGeleerd(klein, namen, geleerd);
        if (uitGeleerd != null) return new() { uitGeleerd };
        return OpTrefwoorden(klein, namen);
    }

    public static HashSet<string> Tokens(string klein)
    {
        var set = new HashSet<string>();
        var huidig = new System.Text.StringBuilder();
        foreach (var c in klein + " ")
        {
            if (char.IsLetterOrDigit(c) || c == '-') huidig.Append(c);
            else if (huidig.Length > 0) { set.Add(huidig.ToString()); huidig.Clear(); }
        }
        return set;
    }

    static List<string> OpTrefwoorden(string klein, List<string> namen)
    {
        var woorden = Tokens(klein);
        var scores = new Dictionary<string, int>();
        foreach (var (bakje, lijst) in Trefwoorden)
        {
            if (!namen.Contains(bakje)) continue;
            foreach (var w in lijst)
                if (w.Contains(' ') ? klein.Contains(w) : woorden.Contains(w))
                    scores[bakje] = scores.GetValueOrDefault(bakje) + 1;
        }
        var top = scores.OrderByDescending(s => s.Value).ThenBy(s => s.Key, StringComparer.Ordinal).ToList();
        if (top.Count > 0)
            return top.Count > 1 && top[1].Value == top[0].Value ? new() { top[0].Key, top[1].Key } : new() { top[0].Key };
        var twijfel = new[] { "Ideeën", "To-do" }.Where(namen.Contains).ToList();
        return twijfel.Count == 2 ? twijfel : namen.Take(2).ToList();
    }

    public static void Leer(string tekst, string bakje, Dictionary<string, string> geleerd)
    {
        foreach (var t in Tokens(tekst.ToLowerInvariant()))
            if (t.Length >= 4 && !Stopwoorden.Contains(t)) geleerd[t] = bakje;
    }

    static string? UitGeleerd(string klein, List<string> namen, Dictionary<string, string> geleerd)
    {
        var scores = new Dictionary<string, int>();
        foreach (var t in Tokens(klein))
            if (geleerd.TryGetValue(t, out var b) && namen.Contains(b)) scores[b] = scores.GetValueOrDefault(b) + 1;
        var top = scores.OrderByDescending(s => s.Value).ToList();
        if (top.Count == 0) return null;
        return top.Count > 1 && top[1].Value == top[0].Value ? null : top[0].Key;
    }
}

public static class Nl
{
    public static readonly CultureInfo Cultuur = new("nl-NL");
    public static string Euro(double x) => x.ToString("C2", Cultuur);
    public static string Getal(double x, int dec = 2) => Math.Round(x, dec).ToString("#,0.##########", Cultuur);
}
