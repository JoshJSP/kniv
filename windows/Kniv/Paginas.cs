using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Kniv;

// ---------------------------------------------------------------- Vandaag

/// Eerste pagina: wat er nu speelt. Alleen blokken die iets te melden hebben.
public sealed class VandaagPagina : UserControl
{
    readonly StackPanel _inhoud = new() { Spacing = 16 };
    readonly TextBlock _datum = Ui.Tekst("", zacht: true);
    readonly Dictionary<Guid, TextBlock> _resten = new();
    TextBlock? _pomo;
    bool _pomoGetoond;

    public VandaagPagina()
    {
        Content = Ui.Pagina("Vandaag", _datum, _inhoud);
        Opslag.Gewijzigd += Vul;
        Klok.Tik += Tik;
        Vul();
        _ = LaadWeer();
    }

    async Task LaadWeer()
    {
        await Weer.VerversAsync();
        DispatcherQueue.TryEnqueue(Vul);
    }

    void Vul()
    {
        _datum.Text = DateTime.Now.ToString("dddd d MMMM", Nl.Cultuur);
        _inhoud.Children.Clear();
        _resten.Clear();
        _pomo = null;
        _pomoGetoond = Klok.PomoLoopt;
        var nu = DateTime.Now;

        // Timers die lopen, en aftellers die vandaag aflopen.
        var timers = Opslag.Data.Timers.Where(t => !t.Gemeld && (!t.IsCountdown || t.Eind.Date == nu.Date)).OrderBy(t => t.Eind).ToList();
        if (timers.Count > 0 || Klok.PomoLoopt)
        {
            var lijst = new StackPanel { Spacing = 4 };
            if (Klok.PomoLoopt) lijst.Children.Add(Regel(Klok.PomoPauze ? "Pauze" : "Focus", _pomo = new TextBlock()));
            foreach (var t in timers) lijst.Children.Add(Regel(t.Naam, _resten[t.Id] = new TextBlock()));
            _inhoud.Children.Add(Blok("Loopt nu", lijst));
        }

        // Openstaande boodschappen.
        var boodschappen = Opslag.Data.Notities.Where(n => n.Bakje == "Boodschappen").OrderByDescending(n => n.Gewijzigd).ToList();
        var items = boodschappen.SelectMany(n => n.Items.Count > 0 ? n.Items.Select(i => i.Tekst) : new[] { n.Titel }).ToList();
        if (items.Count > 0)
        {
            var lijst = new StackPanel { Spacing = 2 };
            foreach (var i in items) lijst.Children.Add(new TextBlock { Text = "·  " + i, TextWrapping = TextWrapping.Wrap });
            _inhoud.Children.Add(Blok($"Boodschappen  {items.Count}", lijst));
        }

        // Notities met een moment dat vandaag valt ("morgen oma bellen", gisteren getypt).
        var vandaag = Opslag.Data.Notities
            .Select(n => (n, m: Herinnering.Vind(n.VolledigeTekst, n.Gemaakt.ToLocalTime())))
            .Where(x => x.m?.dag.Date == nu.Date)
            .OrderBy(x => x.m!.Value.heeftTijd ? x.m.Value.dag : nu.Date.AddDays(1))
            .ToList();
        if (vandaag.Count > 0)
        {
            var lijst = new StackPanel { Spacing = 4 };
            foreach (var (n, m) in vandaag)
                lijst.Children.Add(Regel(n.Titel, new TextBlock { Text = m!.Value.heeftTijd ? m.Value.dag.ToString("HH:mm") : n.Bakje ?? "" }));
            _inhoud.Children.Add(Blok("Voor vandaag", lijst));
        }

        // Weer: regen op komst of koud.
        if (Weer.Advies is { } weer)
            _inhoud.Children.Add(Blok("Weer", new TextBlock { Text = weer, TextWrapping = TextWrapping.Wrap }));

        // Wat mee moet.
        var mee = Meenemen.Lijst(Opslag.Data.Notities);
        if (mee.Count > 0)
        {
            var lijst = new StackPanel { Spacing = 2 };
            foreach (var m in mee.Take(8)) lijst.Children.Add(new TextBlock { Text = "·  " + m, TextWrapping = TextWrapping.Wrap });
            _inhoud.Children.Add(Blok("Niet vergeten", lijst));
        }

        if (_inhoud.Children.Count == 0)
            _inhoud.Children.Add(Ui.Stapel(6, Ui.Tekst("Niks dat vandaag wacht.", "SubtitleTextBlockStyle"),
                Ui.Tekst("Timers, boodschappen en notities met een datum van vandaag verschijnen hier vanzelf.", zacht: true)));
        Tik();
    }

    void Tik()
    {
        if (Klok.PomoLoopt != _pomoGetoond) { Vul(); return; }
        if (_pomo != null) _pomo.Text = Klok.Duur(Klok.PomoOver);
        foreach (var t in Opslag.Data.Timers)
            if (_resten.TryGetValue(t.Id, out var tb)) tb.Text = t.IsCountdown ? t.Eind.ToString("HH:mm") : Klok.Duur(t.Eind - DateTime.Now);
    }

    static Grid Regel(string links, TextBlock rechts)
    {
        var g = new Grid { MinHeight = 28 };
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        g.Children.Add(new TextBlock { Text = links, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
        rechts.VerticalAlignment = VerticalAlignment.Center;
        rechts.Foreground = Ui.Kwast("TextFillColorSecondaryBrush");
        Grid.SetColumn(rechts, 1);
        g.Children.Add(rechts);
        return g;
    }

    static Border Blok(string titel, UIElement inhoud)
    {
        var k = Ui.Kaart(Ui.Stapel(10, Ui.Tekst(titel, "BodyStrongTextBlockStyle"), inhoud));
        k.MaxWidth = 560;
        k.HorizontalAlignment = HorizontalAlignment.Left;
        k.MinWidth = 420;
        return k;
    }
}

// ---------------------------------------------------------------- Beheer (alleen Josh)

public sealed class BeheerPagina : UserControl
{
    readonly TextBlock _gebruikers = Groot(), _actief = Groot(), _soort = Groot();
    readonly TextBlock _status = Ui.Tekst("", "CaptionTextBlockStyle", zacht: true);

    public BeheerPagina()
    {
        UIElement Tegel(string label, TextBlock waarde)
        {
            var k = Ui.Kaart(Ui.Stapel(4, Ui.Tekst(label, zacht: true), waarde), 20);
            k.Width = 220;
            return k;
        }
        Content = Ui.Pagina("Beheer",
            Ui.Tekst("Alleen op deze pc zichtbaar (beheer.env). Aantallen, geen inhoud.", zacht: true),
            Ui.Rij(12, Tegel("Gebruikers", _gebruikers), Tegel("Actief vandaag", _actief), Tegel("Populairste soort", _soort)),
            Ui.Rij(12, Ui.Knop("Vernieuwen", () => _ = Laad()), _status));
        _status.VerticalAlignment = VerticalAlignment.Center;
        _ = Laad();
    }

    static TextBlock Groot() => new() { Text = "–", FontSize = 36, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };

    async Task Laad()
    {
        _status.Text = "Ophalen…";
        try
        {
            var c = await Beheer.Haal();
            _gebruikers.Text = c.Gebruikers.ToString();
            _actief.Text = c.ActiefVandaag.ToString();
            _soort.Text = c.PopulairsteSoort ?? "–";
            _status.Text = $"Bijgewerkt om {DateTime.Now:HH:mm}";
        }
        catch (Exception e)
        {
            App.Log(e);
            _status.Text = "Ophalen lukte niet. Klopt beheer.env?";
        }
    }
}
