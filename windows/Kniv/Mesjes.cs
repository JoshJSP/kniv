using System.Net.Http.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using XPath = Microsoft.UI.Xaml.Shapes.Path;

namespace Kniv;

// ---------------------------------------------------------------- Timers

/// Tikt door op de achtergrond (ook als Kniv in het systeemvak zit) en stuurt de meldingen.
static class Klok
{
    public static event Action? Tik;
    public static bool PomoLoopt, PomoPauze;
    public static DateTime PomoEind;
    public static readonly TimeSpan Focus = TimeSpan.FromMinutes(25), Pauze = TimeSpan.FromMinutes(5);  // eerst, want PomoRest leest Focus
    public static TimeSpan PomoRest = Focus;

    public static void Start()
    {
        var t = App.Ui.CreateTimer();
        t.Interval = TimeSpan.FromMilliseconds(500);
        t.Tick += (_, _) => Stap();
        t.Start();
    }

    public static TimeSpan PomoOver => PomoLoopt ? PomoEind - DateTime.Now : PomoRest;

    public static void PomoStartStop()
    {
        if (PomoLoopt) { PomoRest = PomoEind - DateTime.Now; PomoLoopt = false; }
        else { PomoEind = DateTime.Now + PomoRest; PomoLoopt = true; }
        Tik?.Invoke();
    }

    public static void PomoReset()
    {
        PomoLoopt = false;
        PomoPauze = false;
        PomoRest = Focus;
        Tik?.Invoke();
    }

    static void Stap()
    {
        var nu = DateTime.Now;
        if (PomoLoopt && nu >= PomoEind)
        {
            if (!PomoPauze)
            {   // focus klaar: pauze start vanzelf
                Meldingen.Toon("Tijd voor pauze", "25 minuten gefocust. Neem vijf minuten.");
                PomoPauze = true;
                PomoEind = nu + Pauze;
            }
            else
            {   // pauze klaar: wacht op jou
                Meldingen.Toon("Pauze voorbij", "Klaar voor nog een ronde van 25 minuten?");
                PomoPauze = false;
                PomoLoopt = false;
                PomoRest = Focus;
            }
        }
        var gemeld = false;
        foreach (var t in Opslag.Data.Timers.Where(t => !t.Gemeld && nu >= t.Eind))
        {
            t.Gemeld = gemeld = true;
            Meldingen.Toon(t.IsCountdown ? "Het is zover" : "Timer klaar", t.Naam);
        }
        if (gemeld) Opslag.Bewaar();
        Tik?.Invoke();
    }

    public static string Duur(TimeSpan d)
    {
        if (d < TimeSpan.Zero) d = TimeSpan.Zero;
        if (d.TotalDays >= 1) return $"{(int)d.TotalDays} {((int)d.TotalDays == 1 ? "dag" : "dagen")}, {d.Hours} uur";
        return d.TotalHours >= 1 ? d.ToString(@"h\:mm\:ss") : d.ToString(@"mm\:ss");
    }
}

public sealed class TimersPagina : UserControl
{
    readonly TextBlock _pomoTijd = new() { FontSize = 72, FontWeight = Microsoft.UI.Text.FontWeights.SemiLight, HorizontalAlignment = HorizontalAlignment.Center };
    readonly TextBlock _pomoFase = Ui.Tekst("", "BodyStrongTextBlockStyle");
    readonly ProgressBar _pomoBalk = new() { Maximum = 1, Width = 320 };
    readonly Button _pomoKnop;
    readonly StackPanel _timers = new() { Spacing = 6 }, _countdowns = new() { Spacing = 6 };
    readonly Dictionary<Guid, TextBlock> _resten = new();

    public TimersPagina()
    {
        _pomoKnop = Ui.Knop("Start", Klok.PomoStartStop, accent: true);
        _pomoFase.HorizontalAlignment = HorizontalAlignment.Center;
        var pomoKnoppen = Ui.Rij(8, _pomoKnop, Ui.Knop("Opnieuw", Klok.PomoReset));
        pomoKnoppen.HorizontalAlignment = HorizontalAlignment.Center;

        var naam = new TextBox { Header = "Naam", PlaceholderText = "Bijv. pasta", Width = 220 };
        var minuten = Ui.Getal("Minuten", 10, 1, 24 * 60);
        var start = Ui.Knop("Start timer", () =>
        {
            Opslag.Data.Timers.Add(new LosseTimer { Naam = naam.Text.Trim() is { Length: > 0 } t ? t : $"Timer van {Ui.Waarde(minuten):0} min", Eind = DateTime.Now.AddMinutes(Ui.Waarde(minuten)) });
            naam.Text = "";
            Opslag.Bewaar();
        }, accent: true);
        start.VerticalAlignment = VerticalAlignment.Bottom;

        var cdNaam = new TextBox { Header = "Waarnaar tel je af?", PlaceholderText = "Bijv. vakantie", Width = 220 };
        var datum = new CalendarDatePicker { Header = "Datum", Date = DateTimeOffset.Now.Date.AddDays(7), MinDate = DateTimeOffset.Now.Date };
        var tijd = new TimePicker { Header = "Tijd", ClockIdentifier = "24HourClock", Time = TimeSpan.FromHours(9) };
        var voegToe = Ui.Knop("Voeg toe", () =>
        {
            if (datum.Date is not { } d || cdNaam.Text.Trim() == "") return;
            Opslag.Data.Timers.Add(new LosseTimer { Naam = cdNaam.Text.Trim(), Eind = d.Date + tijd.Time, IsCountdown = true });
            cdNaam.Text = "";
            Opslag.Bewaar();
        }, accent: true);
        voegToe.VerticalAlignment = VerticalAlignment.Bottom;

        Content = Ui.Pagina("Timers",
            Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Pomodoro", "SubtitleTextBlockStyle"), _pomoFase, _pomoTijd, _pomoBalk, pomoKnoppen)),
            Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Losse timers", "SubtitleTextBlockStyle"), Ui.Rij(8, naam, minuten, start), _timers)),
            Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Aftellen naar een datum", "SubtitleTextBlockStyle"), Ui.Rij(8, cdNaam, datum, tijd, voegToe), _countdowns)),
            Ui.Tekst("Meldingen komen alleen als Kniv draait (ook in het systeemvak is goed).", "CaptionTextBlockStyle", zacht: true));

        Opslag.Gewijzigd += Lijsten;
        Klok.Tik += Werk;
        Lijsten();
        Werk();
    }

    void Lijsten()
    {
        _timers.Children.Clear();
        _countdowns.Children.Clear();
        _resten.Clear();
        foreach (var t in Opslag.Data.Timers.OrderBy(t => t.Eind))
        {
            var rest = new TextBlock { FontSize = 18, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 0, 44, 0) };
            _resten[t.Id] = rest;
            var rij = new Grid { MinHeight = 40 };
            var info = Ui.Stapel(0, new TextBlock { Text = t.Naam }, Ui.Tekst(t.Eind.ToString(t.IsCountdown ? "dddd d MMMM yyyy, HH:mm" : "'klaar om' HH:mm", Nl.Cultuur), "CaptionTextBlockStyle", zacht: true));
            info.VerticalAlignment = VerticalAlignment.Center;
            var weg = Ui.IcoonKnop("", "Weghalen", () => { Opslag.Data.Timers.Remove(t); Opslag.Bewaar(); });
            weg.HorizontalAlignment = HorizontalAlignment.Right;
            rij.Children.Add(info);
            rij.Children.Add(rest);
            rij.Children.Add(weg);
            (t.IsCountdown ? _countdowns : _timers).Children.Add(rij);
        }
        if (_timers.Children.Count == 0) _timers.Children.Add(Ui.Tekst("Geen timers.", zacht: true));
        if (_countdowns.Children.Count == 0) _countdowns.Children.Add(Ui.Tekst("Nog niks om naar af te tellen.", zacht: true));
    }

    void Werk()
    {
        var over = Klok.PomoOver;
        var totaal = Klok.PomoPauze ? Klok.Pauze : Klok.Focus;
        _pomoTijd.Text = Klok.Duur(over);
        _pomoFase.Text = Klok.PomoPauze ? "Pauze" : "Focus";
        _pomoBalk.Value = 1 - over / totaal;
        _pomoKnop.Content = Klok.PomoLoopt ? "Pauzeer" : over < totaal ? "Ga verder" : "Start";
        foreach (var t in Opslag.Data.Timers)
            if (_resten.TryGetValue(t.Id, out var tb))
                tb.Text = t.Gemeld ? (t.IsCountdown ? "Het is zover!" : "Klaar!") : Klok.Duur(t.Eind - DateTime.Now);
    }
}

// ---------------------------------------------------------------- Splitten & omzetten

public static class Rekenen
{
    public static (double perPersoon, double totaal) Delen(double bedrag, int personen, double fooiProcent)
    {
        var totaal = bedrag * (1 + fooiProcent / 100);
        return (totaal / Math.Max(1, personen), totaal);
    }

    // Fooi, precies zoals enum Fooi in Kniv/Logica/Rekenen.swift.
    static readonly double[] FooiSchaal = { 0, 2, 5, 8, 10, 15 };   // procent bij 0...5 sterren

    /// null = alles n.v.t. Gewichten: eten 1,5, drinken 1, service 2; lineair tussen de sterren.
    public static double? FooiProcent(int? eten, int? drinken, int? service)
    {
        var delen = new[] { (eten, 1.5), (drinken, 1.0), (service, 2.0) }
            .Where(d => d.Item1 != null).Select(d => (s: (double)Math.Clamp(d.Item1!.Value, 0, 5), g: d.Item2)).ToList();
        if (delen.Count == 0) return null;
        var sterren = delen.Sum(d => d.s * d.g) / delen.Sum(d => d.g);
        var laag = (int)Math.Floor(sterren);
        if (laag >= 5) return FooiSchaal[5];
        return FooiSchaal[laag] + (FooiSchaal[laag + 1] - FooiSchaal[laag]) * (sterren - laag);
    }

    /// Totaal afgerond op hele euro's (vanaf 50 op vijftallen), nooit onder de prijs.
    public static (double fooi, double totaal) FooiAdvies(double prijs, double procent)
    {
        var ruw = prijs * (1 + procent / 100);
        if (procent <= 0) return (0, prijs);
        var stap = ruw >= 50 ? 5.0 : 1.0;
        var totaal = Math.Max(Math.Round(ruw / stap, MidpointRounding.AwayFromZero) * stap, prijs);
        return (totaal - prijs, totaal);
    }

    /// Factor naar de basiseenheid per soort (meter, gram, milliliter). Temperatuur rekent apart.
    public static readonly Dictionary<string, Dictionary<string, double>> Eenheden = new()
    {
        ["Lengte"] = new() { ["mm"] = 0.001, ["cm"] = 0.01, ["m"] = 1, ["km"] = 1000, ["inch"] = 0.0254, ["voet"] = 0.3048, ["yard"] = 0.9144, ["mijl"] = 1609.344 },
        ["Gewicht"] = new() { ["mg"] = 0.001, ["g"] = 1, ["ons"] = 100, ["pond"] = 500, ["kg"] = 1000, ["oz"] = 28.349523125, ["lb"] = 453.59237 },
        ["Inhoud & koken"] = new() { ["ml"] = 1, ["cl"] = 10, ["dl"] = 100, ["l"] = 1000, ["theelepel"] = 5, ["eetlepel"] = 15, ["cup"] = 236.5882365, ["fl oz"] = 29.5735295625, ["pint (VS)"] = 473.176473, ["gallon (VS)"] = 3785.411784 },
        ["Temperatuur"] = new() { ["°C"] = 0, ["°F"] = 0, ["K"] = 0 },
    };

    public static double Omzetten(string soort, double v, string van, string naar)
    {
        if (soort != "Temperatuur") return v * Eenheden[soort][van] / Eenheden[soort][naar];
        var c = van switch { "°F" => (v - 32) * 5 / 9, "K" => v - 273.15, _ => v };
        return naar switch { "°F" => c * 9 / 5 + 32, "K" => c + 273.15, _ => c };
    }
}

public sealed class SplittenPagina : UserControl
{
    public SplittenPagina()
    {
        Content = Ui.Pagina("Splitten", Delen(), Fooi(), Procenten(), Eenheden(), Valuta());
    }

    static TextBlock Uitkomst() => new() { FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap };

    static UIElement Delen()
    {
        var bedrag = Ui.Getal("Bedrag (€)", 0, 0);
        var personen = Ui.Getal("Personen", 2, 1, 100);
        var fooi = new RadioButtons { Header = "Fooi", MaxColumns = 4, SelectedIndex = 0 };
        foreach (var f in new[] { "Geen", "5%", "10%", "15%" }) fooi.Items.Add(f);
        var uit = Uitkomst();
        var sub = Ui.Tekst("", zacht: true);
        void Reken()
        {
            var (pp, totaal) = Rekenen.Delen(Ui.Waarde(bedrag), (int)Ui.Waarde(personen), new[] { 0, 5, 10, 15 }[Math.Max(0, fooi.SelectedIndex)]);
            uit.Text = $"{Nl.Euro(pp)} per persoon";
            sub.Text = $"Totaal {Nl.Euro(totaal)}";
        }
        bedrag.ValueChanged += (_, _) => Reken();
        personen.ValueChanged += (_, _) => Reken();
        fooi.SelectionChanged += (_, _) => Reken();
        Reken();
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Rekening delen", "SubtitleTextBlockStyle"), Ui.Rij(12, bedrag, personen, fooi), uit, sub));
    }

    static UIElement Fooi()
    {
        var prijs = Ui.Getal("Prijs zonder fooi (€)", 0, 0);
        var uit = Uitkomst();
        var sub = Ui.Tekst("", zacht: true);
        var rijen = new StackPanel { Spacing = 4 };
        var sterren = new List<(RatingControl r, CheckBox nvt)>();
        void Reken()
        {
            int? S((RatingControl r, CheckBox nvt) x) => x.nvt.IsChecked == true ? null : (int)Math.Max(0, x.r.Value);
            var pct = Rekenen.FooiProcent(S(sterren[0]), S(sterren[1]), S(sterren[2]));
            if (pct == null) { uit.Text = "Geen fooi"; sub.Text = "Alles staat op n.v.t."; return; }
            var (fooi, totaal) = Rekenen.FooiAdvies(Ui.Waarde(prijs), pct.Value);
            uit.Text = $"Betaal {Nl.Euro(totaal)}";
            sub.Text = $"Fooi {Nl.Euro(fooi)} · advies {Nl.Getal(pct.Value, 1)}%";
        }
        foreach (var naam in new[] { "Eten", "Drinken", "Service" })
        {
            var r = new RatingControl { Value = 4, IsClearEnabled = true, MaxRating = 5, VerticalAlignment = VerticalAlignment.Center };
            var nvt = new CheckBox { Content = "n.v.t.", MinWidth = 0, VerticalAlignment = VerticalAlignment.Center };
            r.ValueChanged += (_, _) => Reken();
            nvt.Checked += (_, _) => { r.IsEnabled = false; Reken(); };
            nvt.Unchecked += (_, _) => { r.IsEnabled = true; Reken(); };
            sterren.Add((r, nvt));
            var label = new TextBlock { Text = naam, Width = 90, VerticalAlignment = VerticalAlignment.Center };
            rijen.Children.Add(Ui.Rij(16, label, r, nvt));
        }
        prijs.ValueChanged += (_, _) => Reken();
        Reken();
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Fooi", "SubtitleTextBlockStyle"),
            Ui.Tekst("Geef sterren (nul sterren = klik nog eens op de gekozen ster). Kniv rondt het totaal af op een mooi bedrag.", zacht: true),
            prijs, rijen, uit, sub));
    }

    static UIElement Procenten()
    {
        var prijs = Ui.Getal("Prijs (€)", 100, 0);
        var korting = Ui.Getal("Korting (%)", 25, 0, 100);
        var uit = Uitkomst();
        var sub = Ui.Tekst("", zacht: true);
        var deel = Ui.Getal("Deel", 15, 0);
        var geheel = Ui.Getal("Van", 60, 0);
        var procent = Ui.Tekst("");
        void Reken()
        {
            var p = Ui.Waarde(prijs);
            var k = p * Ui.Waarde(korting) / 100;
            uit.Text = $"Je betaalt {Nl.Euro(p - k)}";
            sub.Text = $"Je bespaart {Nl.Euro(k)}";
            var g = Ui.Waarde(geheel);
            procent.Text = g == 0 ? "" : $"{Nl.Getal(Ui.Waarde(deel))} is {Nl.Getal(Ui.Waarde(deel) / g * 100, 1)}% van {Nl.Getal(g)}";
        }
        foreach (var n in new[] { prijs, korting, deel, geheel }) n.ValueChanged += (_, _) => Reken();
        Reken();
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Korting & procenten", "SubtitleTextBlockStyle"), Ui.Rij(12, prijs, korting), uit, sub,
            Ui.Rij(12, deel, geheel), procent));
    }

    static UIElement Eenheden()
    {
        var soort = new ComboBox { Header = "Soort", ItemsSource = Rekenen.Eenheden.Keys.ToList(), SelectedIndex = 0, Width = 170 };
        var waarde = Ui.Getal("Waarde", 1);
        var van = new ComboBox { Header = "Van", Width = 140 };
        var naar = new ComboBox { Header = "Naar", Width = 140 };
        var uit = Uitkomst();
        var wissel = Ui.IcoonKnop("", "Omdraaien", () => (van.SelectedIndex, naar.SelectedIndex) = (naar.SelectedIndex, van.SelectedIndex));
        wissel.VerticalAlignment = VerticalAlignment.Bottom;
        void Reken()
        {
            if (soort.SelectedItem is not string s || van.SelectedItem is not string a || naar.SelectedItem is not string b) { uit.Text = ""; return; }
            uit.Text = $"{Nl.Getal(Ui.Waarde(waarde), 4)} {a} = {Nl.Getal(Rekenen.Omzetten(s, Ui.Waarde(waarde), a, b), 4)} {b}";
        }
        void Soort()
        {
            var lijst = Rekenen.Eenheden[(string)soort.SelectedItem].Keys.ToList();
            van.ItemsSource = lijst;
            naar.ItemsSource = lijst;
            van.SelectedIndex = soort.SelectedIndex == 3 ? 0 : 1;
            naar.SelectedIndex = soort.SelectedIndex == 3 ? 1 : lijst.Count - 1;
            Reken();
        }
        soort.SelectionChanged += (_, _) => Soort();
        van.SelectionChanged += (_, _) => Reken();
        naar.SelectionChanged += (_, _) => Reken();
        waarde.ValueChanged += (_, _) => Reken();
        Soort();
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Eenheden omzetten", "SubtitleTextBlockStyle"), Ui.Rij(8, soort, waarde, van, wissel, naar), uit));
    }

    static UIElement Valuta()
    {
        var bedrag = Ui.Getal("Bedrag", 10, 0);
        var van = new ComboBox { Header = "Van", Width = 110 };
        var naar = new ComboBox { Header = "Naar", Width = 110 };
        var uit = Uitkomst();
        var bron = Ui.Tekst("", "CaptionTextBlockStyle", zacht: true);
        var wissel = Ui.IcoonKnop("", "Omdraaien", () => (van.SelectedIndex, naar.SelectedIndex) = (naar.SelectedIndex, van.SelectedIndex));
        wissel.VerticalAlignment = VerticalAlignment.Bottom;
        void Reken()
        {
            var k = Opslag.Data.Koersen;
            if (van.SelectedItem is not string a || naar.SelectedItem is not string b || !k.ContainsKey(a) || !k.ContainsKey(b)) { uit.Text = ""; return; }
            var x = Ui.Waarde(bedrag) / k[a] * k[b];
            uit.Text = $"{Ui.Waarde(bedrag).ToString("#,0.##", Nl.Cultuur)} {a} = {x.ToString("#,0.00", Nl.Cultuur)} {b}";
        }
        void Vul()
        {
            var codes = Opslag.Data.Koersen.Keys.OrderBy(c => c).ToList();
            var (a, b) = (van.SelectedItem as string ?? "EUR", naar.SelectedItem as string ?? "USD");
            van.ItemsSource = codes;
            naar.ItemsSource = codes;
            van.SelectedItem = codes.Contains(a) ? a : codes.FirstOrDefault();
            naar.SelectedItem = codes.Contains(b) ? b : codes.FirstOrDefault();
            bron.Text = codes.Count == 0 ? "Nog geen koersen: er is internet nodig voor de eerste keer." : $"Koersen van {Opslag.Data.KoersDatum} (Europese Centrale Bank, via Frankfurter).";
            Reken();
        }
        van.SelectionChanged += (_, _) => Reken();
        naar.SelectionChanged += (_, _) => Reken();
        bedrag.ValueChanged += (_, _) => Reken();
        Vul();
        _ = HaalKoersen(Vul);
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Valuta", "SubtitleTextBlockStyle"), Ui.Rij(8, bedrag, van, wissel, naar), uit, bron));
    }

    record Frankfurter(string date, Dictionary<string, double> rates);

    static async Task HaalKoersen(Action klaar)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var f = await http.GetFromJsonAsync<Frankfurter>("https://api.frankfurter.app/latest?from=EUR");
            if (f?.rates == null) return;
            Opslag.Data.Koersen = new(f.rates) { ["EUR"] = 1 };
            Opslag.Data.KoersDatum = DateTime.TryParse(f.date, out var d) ? d.ToString("d MMMM yyyy", Nl.Cultuur) : f.date;
            Opslag.Bewaar();
            klaar();
        }
        catch (Exception) { /* offline: de bewaarde koersen blijven staan */ }
    }
}

// ---------------------------------------------------------------- Kiezen

public sealed class KiezenPagina : UserControl
{
    public KiezenPagina()
    {
        Content = Ui.Pagina("Kiezen", Rad(), Dobbelstenen(), Munt(), Teams());
    }

    static string[] Regels(string t) => t.Split(new[] { '\n', '\r', ',' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    // Rad: strak monochroom, winnaar in zakmesrood.
    static UIElement Rad()
    {
        const double R = 150;
        var opties = new TextBox { Header = "Opties (één per regel)", Text = "Pizza\nSushi\nPasta\nFriet\nWraps", AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Width = 220, Height = 220 };
        var wiel = new Canvas { Width = 2 * R, Height = 2 * R };
        var draai = new RotateTransform { CenterX = R, CenterY = R };
        wiel.RenderTransform = draai;
        var wijzer = new Polygon { Points = { new Point(R - 12, -4), new Point(R + 12, -4), new Point(R, 22) }, Fill = Ui.Kwast("TextFillColorPrimaryBrush") };
        var houder = new Grid { Width = 2 * R, Height = 2 * R };
        houder.Children.Add(wiel);
        var wijzerLaag = new Canvas();
        wijzerLaag.Children.Add(wijzer);
        houder.Children.Add(wijzerLaag);
        var uit = Uitkomst();
        var segmenten = new List<Shape>();
        var bezig = false;

        void Teken(int winnaar = -1)
        {
            wiel.Children.Clear();
            segmenten.Clear();
            var namen = Regels(opties.Text);
            if (namen.Length == 0) return;
            var donker = wiel.ActualTheme == ElementTheme.Dark;
            var tinten = donker ? new[] { "#2E2E2E", "#3C3C3C", "#4A4A4A" } : new[] { "#EDEDED", "#DCDCDC", "#CBCBCB" };
            var hoek = 360.0 / namen.Length;
            for (int i = 0; i < namen.Length; i++)
            {
                // laatste segment nooit dezelfde tint als het eerste
                var tint = tinten[namen.Length % 3 == 1 && i == namen.Length - 1 ? 1 : i % 3];
                var kleur = i == winnaar ? Ui.Kwast("AccentFillColorDefaultBrush") : new SolidColorBrush(Kleur(tint));
                Shape vorm = namen.Length == 1 ? new Ellipse { Width = 2 * R, Height = 2 * R } : Segment(R, i * hoek, (i + 1) * hoek);
                vorm.Fill = kleur;
                vorm.Stroke = Ui.Kwast("CardStrokeColorDefaultBrush");
                wiel.Children.Add(vorm);
                segmenten.Add(vorm);
                var midden = (i + 0.5) * hoek;
                var label = new TextBlock
                {
                    Text = namen[i], Width = R * 0.62, TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis,
                    Foreground = i == winnaar ? new SolidColorBrush(Microsoft.UI.Colors.White) : Ui.Kwast("TextFillColorPrimaryBrush"),
                    FontWeight = i == winnaar ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
                    RenderTransform = new RotateTransform { Angle = midden - 90, CenterX = 0, CenterY = 10 },
                };
                // tekst langs de straal, beginnend op 30% van het midden
                var rad = midden * Math.PI / 180;
                Canvas.SetLeft(label, R + R * 0.3 * Math.Sin(rad));
                Canvas.SetTop(label, R - R * 0.3 * Math.Cos(rad) - 10);
                wiel.Children.Add(label);
            }
        }

        void Draai()
        {
            var namen = Regels(opties.Text);
            if (bezig || namen.Length == 0) return;
            bezig = true;
            uit.Text = "";
            Teken();
            var hoek = 360.0 / namen.Length;
            var winnaar = Random.Shared.Next(namen.Length);
            var doel = (360 - (winnaar + 0.5 + (Random.Shared.NextDouble() - 0.5) * 0.7) * hoek + 360) % 360;
            var nu = draai.Angle % 360;
            var eind = draai.Angle + 360 * 5 + ((doel - nu + 360) % 360);
            var anim = new DoubleAnimation { From = draai.Angle, To = eind, Duration = TimeSpan.FromSeconds(3.5), EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
            Storyboard.SetTarget(anim, draai);
            Storyboard.SetTargetProperty(anim, "Angle");
            var sb = new Storyboard();
            sb.Children.Add(anim);
            sb.Completed += (_, _) =>
            {
                draai.Angle = eind;
                Teken(winnaar);
                uit.Text = $"Het wordt: {namen[winnaar]}";
                bezig = false;
            };
            sb.Begin();
        }

        opties.TextChanged += (_, _) => { if (!bezig) Teken(); };
        wiel.Loaded += (_, _) => Teken();
        wiel.ActualThemeChanged += (_, _) => Teken();
        var knop = Ui.Knop("Draai", Draai, accent: true);
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Rad van fortuin", "SubtitleTextBlockStyle"),
            Ui.Rij(32, Ui.Stapel(12, opties, knop), houder), uit));
    }

    static Windows.UI.Color Kleur(string hex) => Microsoft.UI.ColorHelper.FromArgb(255,
        Convert.ToByte(hex[1..3], 16), Convert.ToByte(hex[3..5], 16), Convert.ToByte(hex[5..7], 16));

    static XPath Segment(double r, double van, double tot)
    {
        Point Op(double graden) { var a = graden * Math.PI / 180; return new Point(r + r * Math.Sin(a), r - r * Math.Cos(a)); }
        var fig = new PathFigure { StartPoint = new Point(r, r), IsClosed = true };
        fig.Segments.Add(new LineSegment { Point = Op(van) });
        fig.Segments.Add(new ArcSegment { Point = Op(tot), Size = new Size(r, r), SweepDirection = SweepDirection.Clockwise, IsLargeArc = tot - van > 180 });
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        return new XPath { Data = geo };
    }

    static TextBlock Uitkomst() => new() { FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };

    static UIElement Dobbelstenen()
    {
        var aantal = Ui.Getal("Aantal stenen", 2, 1, 6);
        var stenen = Ui.Rij(12);
        var totaal = Ui.Tekst("", zacht: true);
        var bezig = false;
        void Toon(int[] ogen)
        {
            stenen.Children.Clear();
            foreach (var o in ogen) stenen.Children.Add(Steen(o));
            totaal.Text = ogen.Length > 1 ? $"Totaal {ogen.Sum()}" : "";
        }
        async void Gooi()
        {
            if (bezig) return;
            bezig = true;
            var n = (int)Math.Clamp(Ui.Waarde(aantal), 1, 6);
            for (int i = 0; i < 8; i++) { Toon(Enumerable.Range(0, n).Select(_ => Random.Shared.Next(1, 7)).ToArray()); await Task.Delay(45 + i * 12); }
            bezig = false;
        }
        Toon(new[] { 6, 6 });
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Dobbelsteen", "SubtitleTextBlockStyle"),
            Ui.Rij(12, aantal, BodemKnop(Ui.Knop("Gooi", Gooi, accent: true))), stenen, totaal));
    }

    static Button BodemKnop(Button b) { b.VerticalAlignment = VerticalAlignment.Bottom; return b; }

    static Border Steen(int ogen)
    {
        var raster = new Grid { Width = 54, Height = 54 };
        for (int i = 0; i < 3; i++) { raster.RowDefinitions.Add(new RowDefinition()); raster.ColumnDefinitions.Add(new ColumnDefinition()); }
        var plekken = ogen switch
        {
            1 => new[] { 4 }, 2 => new[] { 0, 8 }, 3 => new[] { 0, 4, 8 }, 4 => new[] { 0, 2, 6, 8 },
            5 => new[] { 0, 2, 4, 6, 8 }, _ => new[] { 0, 2, 3, 5, 6, 8 },
        };
        foreach (var p in plekken)
        {
            var oog = new Ellipse { Width = 11, Height = 11, Fill = Ui.Kwast("TextFillColorPrimaryBrush") };
            Grid.SetRow(oog, p / 3);
            Grid.SetColumn(oog, p % 3);
            raster.Children.Add(oog);
        }
        var b = Ui.Kaart(raster, 10);
        b.CornerRadius = new CornerRadius(14);
        return b;
    }

    static UIElement Munt()
    {
        var vlak = new TextBlock { Text = "?", FontSize = 30, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) };
        var schaal = new ScaleTransform { CenterX = 55, CenterY = 55 };
        var munt = new Border { Width = 110, Height = 110, CornerRadius = new CornerRadius(55), Background = Ui.Kwast("AccentFillColorDefaultBrush"), Child = vlak, RenderTransform = schaal };
        var bezig = false;
        async void Gooi()
        {
            if (bezig) return;
            bezig = true;
            var kop = Random.Shared.Next(2) == 0;
            for (int i = 0; i < 10; i++)
            {
                for (double s = 1; s >= 0; s -= 0.34) { schaal.ScaleX = s; await Task.Delay(12); }
                vlak.Text = i == 9 ? (kop ? "Kop" : "Munt") : (i % 2 == 0 ? "Kop" : "Munt");
                for (double s = 0; s <= 1; s += 0.34) { schaal.ScaleX = s; await Task.Delay(12); }
            }
            schaal.ScaleX = 1;
            bezig = false;
        }
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Munt", "SubtitleTextBlockStyle"), Ui.Rij(24, munt, BodemKnop(Ui.Knop("Gooi munt", Gooi, accent: true)))));
    }

    static UIElement Teams()
    {
        var namen = new TextBox { Header = "Namen (één per regel of met komma's)", Text = "Josh\nSam\nNoah\nLisa\nEmma\nDaan", AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, Width = 260, Height = 170 };
        var aantal = Ui.Getal("Teams", 2, 2, 20);
        var uit = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        void Verdeel()
        {
            var lijst = Regels(namen.Text).ToArray();
            Random.Shared.Shuffle(lijst);
            var n = (int)Math.Clamp(Ui.Waarde(aantal), 2, Math.Max(2, lijst.Length));
            uit.Children.Clear();
            for (int t = 0; t < n; t++)
            {
                var leden = lijst.Where((_, i) => i % n == t).ToList();
                uit.Children.Add(Ui.Kaart(Ui.Stapel(4, new[] { (UIElement)Ui.Tekst($"Team {t + 1}", "BodyStrongTextBlockStyle") }.Concat(leden.Select(l => (UIElement)Ui.Tekst(l))).ToArray()), 12));
            }
        }
        return Ui.Kaart(Ui.Stapel(12, Ui.Tekst("Teams", "SubtitleTextBlockStyle"),
            Ui.Rij(12, namen, Ui.Stapel(12, aantal, Ui.Knop("Verdeel", Verdeel, accent: true))),
            new ScrollViewer { Content = uit, HorizontalScrollMode = ScrollMode.Enabled, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto, VerticalScrollMode = ScrollMode.Disabled }));
    }
}
