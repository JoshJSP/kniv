using System.Globalization;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Kniv;

/// Mijn woorden: wat je in Talen op de iPhone bewaarde, per taal, met kaartjes om te oefenen.
/// Alleen lezen; weghalen doe je op de iPhone.
public sealed class WoordenPagina : UserControl
{
    readonly StackPanel _inhoud = new() { Spacing = 16 };
    readonly TextBlock _status = Ui.Tekst("", zacht: true);

    public WoordenPagina()
    {
        Content = Ui.Pagina("Mijn woorden", _status, _inhoud);
        Vul();
        _ = Ververs();
    }

    async Task Ververs()
    {
        _status.Text = "Ophalen…";
        var rijen = await Sync.HaalSoort("woord");
        if (rijen != null)
        {
            Opslag.Data.Woorden = rijen.Select(Lees).Where(w => w.Tekst != "").ToList();
            Opslag.Bewaar();
        }
        DispatcherQueue.TryEnqueue(() =>
        {
            _status.Text = rijen == null
                ? (Opslag.Data.Woorden.Count > 0 ? "Offline: dit is de laatste stand." : "Log in bij Instellingen om je woorden uit Talen te zien.")
                : "Bewaard op je iPhone, bij een leesstukje in Talen.";
            Vul();
        });
    }

    static Woord Lees(Rij r)
    {
        string S(string naam) => r.Data.ValueKind == JsonValueKind.Object && r.Data.TryGetProperty(naam, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
        return new Woord { Taal = S("taal"), Tekst = S("woord"), Betekenis = S("betekenis"), Zin = S("zin") };
    }

    public static string TaalNaam(string code)
    {
        try { var c = CultureInfo.GetCultureInfo(code); return Nl.Cultuur.TextInfo.ToTitleCase(c.DisplayName); }
        catch (CultureNotFoundException) { return code.ToUpperInvariant(); }
    }

    void Vul()
    {
        _inhoud.Children.Clear();
        foreach (var groep in Opslag.Data.Woorden.GroupBy(w => w.Taal).OrderByDescending(g => g.Count()))
        {
            var lijst = new StackPanel { Spacing = 10 };
            foreach (var w in groep)
            {
                var regel = new StackPanel { Spacing = 1 };
                regel.Children.Add(new TextBlock { Text = w.Betekenis == "" ? w.Tekst : $"{w.Tekst}  —  {w.Betekenis}", TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
                if (w.Zin != "") regel.Children.Add(Ui.Tekst(w.Zin, zacht: true));
                lijst.Children.Add(regel);
            }
            var lijstGroep = groep.ToList();
            var kop = Ui.Rij(12, Ui.Tekst($"{TaalNaam(groep.Key)}  {lijstGroep.Count}", "SubtitleTextBlockStyle"),
                             Ui.Knop("Oefen", () => Oefen(groep.Key, lijstGroep), accent: true));
            _inhoud.Children.Add(Kaart(Ui.Stapel(12, kop, lijst)));
        }
    }

    static Border Kaart(UIElement inhoud) => new()
    {
        Child = inhoud,
        Padding = new Thickness(18),
        CornerRadius = new CornerRadius(12),
        Background = Ui.Kwast("CardBackgroundFillColorDefaultBrush"),
    };

    /// Kaartjes: woord, draaien naar betekenis, dan "nog eens" (komt na 4 andere terug) of "wist ik" (uit dit rondje).
    void Oefen(string taal, List<Woord> woorden)
    {
        var rij = woorden.OrderBy(_ => Random.Shared.Next()).ToList();
        var groot = Ui.Tekst("", "TitleLargeTextBlockStyle");
        groot.TextWrapping = TextWrapping.Wrap;
        var klein = Ui.Tekst("", zacht: true);
        klein.TextWrapping = TextWrapping.Wrap;
        var over = Ui.Tekst("", zacht: true);
        var omgedraaid = false;
        var knoppen = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var draai = Ui.Knop("Draai", () => { }, accent: true);

        void Toon()
        {
            knoppen.Children.Clear();
            if (rij.Count == 0)
            {
                groot.Text = "Rondje klaar";
                klein.Text = "Je kende ze allemaal een keer.";
                over.Text = "";
                knoppen.Children.Add(Ui.Knop("Nog een rondje", () => Oefen(taal, woorden), accent: true));
                knoppen.Children.Add(Ui.Knop("Terug", Vul));
                return;
            }
            var w = rij[0];
            over.Text = $"Nog {rij.Count}";
            groot.Text = omgedraaid ? (w.Betekenis == "" ? "—" : w.Betekenis) : w.Tekst;
            klein.Text = omgedraaid ? w.Zin : "";
            if (!omgedraaid) { knoppen.Children.Add(draai); return; }
            knoppen.Children.Add(Ui.Knop("Nog eens", () => { var k = rij[0]; rij.RemoveAt(0); rij.Insert(Math.Min(4, rij.Count), k); omgedraaid = false; Toon(); }));
            knoppen.Children.Add(Ui.Knop("Wist ik", () => { rij.RemoveAt(0); omgedraaid = false; Toon(); }, accent: true));
        }

        draai.Click += (_, _) => { omgedraaid = true; Toon(); };
        _inhoud.Children.Clear();
        _inhoud.Children.Add(Ui.Rij(12, Ui.Tekst(TaalNaam(taal), "SubtitleTextBlockStyle"), over, Ui.Knop("Stoppen", Vul)));
        _inhoud.Children.Add(Kaart(Ui.Stapel(14, groot, klein, knoppen)));
        Toon();
    }
}
