using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics;
using WinRT.Interop;

namespace Kniv;

/// Kleine bouwstenen, zodat de schermen in gewone C# leesbaar blijven.
static class Ui
{
    public static Style Stijl(string sleutel) => (Style)Application.Current.Resources[sleutel];
    public static Brush Kwast(string sleutel) => (Brush)Application.Current.Resources[sleutel];

    public static TextBlock Tekst(string t, string? stijl = null, bool zacht = false)
    {
        var tb = new TextBlock { Text = t, TextWrapping = TextWrapping.Wrap };
        if (stijl != null) tb.Style = Stijl(stijl);
        if (zacht) tb.Foreground = Kwast("TextFillColorSecondaryBrush");
        return tb;
    }

    public static StackPanel Stapel(double ruimte, params UIElement[] kids)
    {
        var sp = new StackPanel { Spacing = ruimte };
        foreach (var k in kids) sp.Children.Add(k);
        return sp;
    }

    public static StackPanel Rij(double ruimte, params UIElement[] kids)
    {
        var sp = Stapel(ruimte, kids);
        sp.Orientation = Orientation.Horizontal;
        return sp;
    }

    public static Button Knop(string t, Action klik, bool accent = false)
    {
        var b = new Button { Content = t };
        if (accent) b.Style = Stijl("AccentButtonStyle");
        b.Click += (_, _) => klik();
        return b;
    }

    public static Button IcoonKnop(string glyph, string uitleg, Action klik)
    {
        var b = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 14 }, Padding = new Thickness(8), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), BorderThickness = new Thickness(0) };
        ToolTipService.SetToolTip(b, uitleg);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(b, uitleg);
        b.Click += (_, _) => klik();
        return b;
    }

    public static Border Kaart(UIElement inhoud, double padding = 16) => new()
    {
        Child = inhoud,
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(8),
        Background = Kwast("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = Kwast("CardStrokeColorDefaultBrush"),
        BorderThickness = new Thickness(1),
    };

    public static NumberBox Getal(string kop, double waarde, double min = double.MinValue, double max = double.MaxValue) => new()
    {
        Header = kop, Value = waarde, Minimum = min, Maximum = max, Width = 150, HorizontalAlignment = HorizontalAlignment.Left,
        SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, SmallChange = 1,
    };

    public static double Waarde(NumberBox n) => double.IsNaN(n.Value) ? 0 : n.Value;

    /// Standaard mesje-pagina: titel en daaronder gestapelde kaarten, scrollbaar.
    public static ScrollViewer Pagina(string titel, params UIElement[] inhoud)
    {
        var sp = Stapel(16, inhoud.Prepend(Tekst(titel, "TitleTextBlockStyle")).ToArray());
        sp.Padding = new Thickness(36, 20, 36, 36);
        sp.MaxWidth = 1000;
        sp.HorizontalAlignment = HorizontalAlignment.Left;
        return new ScrollViewer { Content = sp };
    }

    public static string Relatief(DateTime utc)
    {
        var d = DateTime.UtcNow - utc;
        if (d.TotalMinutes < 1) return "zojuist";
        if (d.TotalHours < 1) return $"{(int)d.TotalMinutes} min geleden";
        if (d.TotalDays < 1) return $"{(int)d.TotalHours} uur geleden";
        if (d.TotalDays < 2) return "gisteren";
        return utc.ToLocalTime().ToString("d MMM", Nl.Cultuur);
    }
}

public sealed class HoofdVenster : Window
{
    public bool EchtSluiten;
    readonly NavigationView _nav;
    readonly InfoBar _updateBalk = new() { Severity = InfoBarSeverity.Success, Title = "Nieuwe versie", IsClosable = true, Margin = new Thickness(16, 0, 16, 8) };
    readonly InfoBar _sneltoetsBalk = new() { Severity = InfoBarSeverity.Warning, Title = "Win+Shift+K werkt niet", IsClosable = true, Margin = new Thickness(16, 0, 16, 8),
        Message = "Een ander programma gebruikt deze sneltoets al. Open Kniv via het systeemvak." };
    readonly Dictionary<string, Func<UIElement>> _maak;
    readonly Dictionary<string, UIElement> _paginas = new();

    public HoofdVenster()
    {
        Title = "Kniv";
        ExtendsContentIntoTitleBar = true;
        SystemBackdrop = new MicaBackdrop();
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "kniv.ico"));
        AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;
        var schaal = Win32.GetDpiForWindow(WindowNative.GetWindowHandle(this)) / 96.0;
        AppWindow.Resize(new SizeInt32((int)(1120 * schaal), (int)(780 * schaal)));
        AppWindow.Closing += (s, e) => { if (!EchtSluiten) { e.Cancel = true; s.Hide(); } };  // sluiten = naar het systeemvak

        var titelBalk = new Grid { Height = 48, Padding = new Thickness(16, 0, 0, 0) };
        titelBalk.Children.Add(Ui.Rij(12,
            new Image { Source = new BitmapImage(new Uri(Path.Combine(AppContext.BaseDirectory, "kniv.png"))), Width = 18, Height = 18, VerticalAlignment = VerticalAlignment.Center },
            new TextBlock { Text = "Kniv", Style = Ui.Stijl("CaptionTextBlockStyle"), VerticalAlignment = VerticalAlignment.Center }));
        SetTitleBar(titelBalk);

        _maak = new()
        {
            ["Vandaag"] = () => new VandaagPagina(),
            ["Vastleggen"] = () => new VastleggenPagina(),
            ["Beheer"] = () => new BeheerPagina(),
            ["Timers"] = () => new TimersPagina(),
            ["Splitten"] = () => new SplittenPagina(),
            ["Kiezen"] = () => new KiezenPagina(),
            ["Instellingen"] = () => new InstellingenPagina(),
        };
        _nav = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsSettingsVisible = true,
            OpenPaneLength = 220,
        };
        foreach (var (naam, glyph) in new[] { ("Vastleggen", ""), ("Timers", ""), ("Splitten", ""), ("Kiezen", "") })
            _nav.MenuItems.Add(new NavigationViewItem { Content = naam, Tag = naam, Icon = new FontIcon { Glyph = glyph } });
        _nav.MenuItems.Insert(0, new NavigationViewItem { Content = "Vandaag", Tag = "Vandaag", Icon = new FontIcon { Glyph = "" } });
        if (Beheer.Beschikbaar)
            _nav.FooterMenuItems.Add(new NavigationViewItem { Content = "Beheer", Tag = "Beheer", Icon = new FontIcon { Glyph = "" } });
        _nav.SelectionChanged += (_, e) => Ga(e.IsSettingsSelected ? "Instellingen" : (string)((NavigationViewItem)e.SelectedItem).Tag);
        _nav.Loaded += (_, _) =>
        {
            if (_nav.SettingsItem is NavigationViewItem s) s.Content = "Instellingen";
            _nav.SelectedItem = _nav.MenuItems[0];
        };

        var herstart = Ui.Knop("Herstart en installeer", Updates.Herstart, accent: true);
        _updateBalk.ActionButton = herstart;
        Updates.Veranderd += () => App.Ui.TryEnqueue(ToonUpdate);

        var wortel = new Grid();
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        wortel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var balken = Ui.Stapel(0, _updateBalk, _sneltoetsBalk);
        Grid.SetRow(balken, 1);
        Grid.SetRow(_nav, 2);
        wortel.Children.Add(titelBalk);
        wortel.Children.Add(balken);
        wortel.Children.Add(_nav);
        Content = wortel;
    }

    void Ga(string naam)
    {
        if (!_paginas.TryGetValue(naam, out var p)) _paginas[naam] = p = _maak[naam]();
        _nav.Content = p;
    }

    public void ToonSneltoetsStatus() => _sneltoetsBalk.IsOpen = !App.SneltoetsWerkt;

    void ToonUpdate()
    {
        _updateBalk.IsOpen = Updates.Klaar != null;
        _updateBalk.Message = $"Kniv {Updates.Klaar?.Version} staat klaar.";
    }
}

// ---------------------------------------------------------------- Vastleggen

/// Invoer die in het hoofdscherm én het snelvenster hetzelfde werkt:
/// Enter bewaart, Shift+Enter is een nieuwe regel, plakken van een afbeelding/bestand en slepen maken een foto-notitie.
static class Invoer
{
    /// commando: krijgt de tekst bij Enter; true = afgehandeld (timer, rekensom). Ctrl+Enter bewaart altijd als notitie.
    public static void Koppel(TextBox tb, UIElement sleepVlak, Action<Notitie?> bewaard, Func<string, bool>? commando = null)
    {
        tb.AcceptsReturn = true;
        tb.TextWrapping = TextWrapping.Wrap;
        tb.PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Windows.System.VirtualKey.Enter) return;
            bool Ingedrukt(Windows.System.VirtualKey k) => Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(k)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
            if (Ingedrukt(Windows.System.VirtualKey.Shift)) return;
            e.Handled = true;
            if (!Ingedrukt(Windows.System.VirtualKey.Control) && commando?.Invoke(tb.Text) == true) return;
            var n = Opslag.Nieuw(tb.Text);
            if (n != null) tb.Text = "";
            bewaard(n);
        };
        tb.Paste += async (_, e) =>
        {
            var inhoud = Windows.ApplicationModel.DataTransfer.Clipboard.GetContent();
            if (inhoud.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems))
            {
                e.Handled = true;
                await Bestanden(await inhoud.GetStorageItemsAsync(), tb, bewaard);
            }
            else if (inhoud.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Bitmap))
            {
                e.Handled = true;
                try
                {
                    var naam = await BewaarAfbeelding(await inhoud.GetBitmapAsync());
                    bewaard(Opslag.Nieuw(tb.Text, naam));
                    tb.Text = "";
                }
                catch (Exception) { bewaard(null); }
            }
        };
        sleepVlak.AllowDrop = true;
        sleepVlak.AddHandler(UIElement.DragOverEvent, new DragEventHandler((_, e) =>
        {
            if (!e.DataView.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems)) return;
            e.AcceptedOperation = Windows.ApplicationModel.DataTransfer.DataPackageOperation.Copy;
            e.DragUIOverride.Caption = "Bewaar in Kniv";
        }), true);
        sleepVlak.AddHandler(UIElement.DropEvent, new DragEventHandler(async (_, e) =>
        {
            if (!e.DataView.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.StorageItems)) return;
            await Bestanden(await e.DataView.GetStorageItemsAsync(), tb, bewaard);
        }), true);
    }

    static async Task Bestanden(IReadOnlyList<Windows.Storage.IStorageItem> items, TextBox tb, Action<Notitie?> bewaard)
    {
        foreach (var f in items.OfType<Windows.Storage.StorageFile>())
        {
            try
            {
                var naam = await Task.Run(() => Opslag.KopieerBestand(f.Path));
                bewaard(Opslag.Nieuw(tb.Text, naam));
                tb.Text = "";
            }
            catch (Exception) { bewaard(null); }
        }
    }

    static async Task<string> BewaarAfbeelding(Windows.Storage.Streams.RandomAccessStreamReference bron)
    {
        using var stroom = await bron.OpenReadAsync();
        var dec = await Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(stroom);
        using var bmp = await dec.GetSoftwareBitmapAsync(Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8, Windows.Graphics.Imaging.BitmapAlphaMode.Premultiplied);
        var naam = Guid.NewGuid().ToString("N") + "_screenshot.png";
        using var fs = File.Create(Opslag.FotoPad(naam));
        var enc = await Windows.Graphics.Imaging.BitmapEncoder.CreateAsync(Windows.Graphics.Imaging.BitmapEncoder.PngEncoderId, fs.AsRandomAccessStream());
        enc.SetSoftwareBitmap(bmp);
        await enc.FlushAsync();
        return naam;
    }

    public static Uri? EersteLink(string tekst)
    {
        var m = Regex.Match(tekst, @"https?://\S+");
        return m.Success && Uri.TryCreate(m.Value, UriKind.Absolute, out var u) ? u : null;
    }

    public static async void LaadMiniatuur(Image img, string naam, int breedte)
    {
        try
        {
            var bi = new BitmapImage { DecodePixelWidth = breedte };
            using var s = File.OpenRead(Opslag.FotoPad(naam));
            await bi.SetSourceAsync(s.AsRandomAccessStream());
            img.Source = bi;
        }
        catch (Exception) { }
    }
}

public sealed class VastleggenPagina : UserControl
{
    static readonly HashSet<Guid> Doorgestreept = new();
    readonly TextBox _invoer = new() { PlaceholderText = "Wat wil je kwijt?", MinHeight = 64, MaxHeight = 220, FontSize = 16 };
    readonly TextBox _zoek = new() { PlaceholderText = "Zoek in alles", Width = 280 };
    readonly TextBlock _melding = Ui.Tekst("", "CaptionTextBlockStyle", zacht: true);
    readonly StackPanel _lijst = new() { Spacing = 22 };

    public VastleggenPagina()
    {
        var bewaar = Ui.Knop("Bewaar", () => Bewaard(Opslag.Nieuw(_invoer.Text)), accent: true);
        bewaar.VerticalAlignment = VerticalAlignment.Bottom;
        var invoerRij = new Grid { ColumnSpacing = 8 };
        invoerRij.ColumnDefinitions.Add(new ColumnDefinition());
        invoerRij.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(bewaar, 1);
        invoerRij.Children.Add(_invoer);
        invoerRij.Children.Add(bewaar);
        _melding.Text = "Enter bewaart · Shift+Enter voor een nieuwe regel · \"- \" maakt een afvinklijstje · plak een screenshot of sleep een bestand hierheen · Win+Shift+K opent Kniv overal";

        var kop = new Grid();
        kop.Children.Add(Ui.Tekst("Vastleggen", "TitleTextBlockStyle"));
        _zoek.HorizontalAlignment = HorizontalAlignment.Right;
        _zoek.TextChanged += (_, _) => Ververs();
        kop.Children.Add(_zoek);

        var sp = Ui.Stapel(16, kop, Ui.Kaart(Ui.Stapel(8, invoerRij, _melding)), _lijst);
        sp.Padding = new Thickness(36, 20, 36, 36);
        var scroll = new ScrollViewer { Content = sp };
        Content = scroll;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_invoer, "Nieuwe notitie");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_zoek, "Zoeken");
        Invoer.Koppel(_invoer, scroll, Bewaard);
        Opslag.Gewijzigd += Ververs;
        Ververs();
    }

    void Bewaard(Notitie? n)
    {
        if (n == null) return;
        _invoer.Text = "";
        _melding.Text = n.Bakje != null ? $"Bewaard in {n.Bakje}." : "Bewaard. Kniv twijfelt even, kies hieronder het bakje.";
    }

    void Ververs()
    {
        _lijst.Children.Clear();
        var zoek = _zoek.Text.Trim();
        bool Past(Notitie n) => zoek == "" || n.ZoekTekst.Contains(zoek, StringComparison.CurrentCultureIgnoreCase);

        var open = Opslag.Data.Notities.Where(n => n.Bakje == null && Past(n)).ToList();
        if (open.Count > 0)
        {
            var twijfel = Ui.Stapel(8, Ui.Tekst("Even checken", "SubtitleTextBlockStyle"));
            foreach (var n in open) twijfel.Children.Add(Ui.Kaart(Ui.Stapel(10, Ui.Tekst(n.Titel), KiesKnoppen(n)), 14));
            _lijst.Children.Add(twijfel);
        }

        foreach (var b in Opslag.SlimmeVolgorde())
        {
            var notities = Opslag.Data.Notities.Where(n => n.Bakje == b.Naam && Past(n)).OrderByDescending(n => n.Gewijzigd).ToList();
            if (notities.Count == 0) continue;
            var rij = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            foreach (var n in notities) rij.Children.Add(Kaartje(n));
            _lijst.Children.Add(Ui.Stapel(8,
                Ui.Rij(8, Ui.Tekst(b.Naam, "SubtitleTextBlockStyle"), new TextBlock { Text = notities.Count.ToString(), Foreground = Ui.Kwast("TextFillColorSecondaryBrush"), VerticalAlignment = VerticalAlignment.Center }),
                new ScrollViewer
                {
                    Content = rij, HorizontalScrollMode = ScrollMode.Enabled, HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                    VerticalScrollMode = ScrollMode.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, Padding = new Thickness(0, 0, 0, 12),
                }));
        }

        if (Opslag.Data.Notities.Count == 0)
            _lijst.Children.Add(Ui.Stapel(6, Ui.Tekst("Nog niks vastgelegd", "SubtitleTextBlockStyle"),
                Ui.Tekst("Typ iets, plak een screenshot of sleep een bestand hierheen. Kniv sorteert het voor je.", zacht: true)));
        else if (zoek != "" && _lijst.Children.Count == 0)
            _lijst.Children.Add(Ui.Tekst($"Niks gevonden voor \"{zoek}\".", zacht: true));
    }

    public static StackPanel KiesKnoppen(Notitie n, Action? daarna = null)
    {
        var rij = Ui.Rij(8);
        foreach (var optie in n.Twijfel)
            rij.Children.Add(Ui.Knop(optie, () => { Opslag.Kies(n, optie, leer: true); daarna?.Invoke(); }));
        var ander = new MenuFlyout();
        foreach (var b in Opslag.Data.Bakjes)
        {
            var item = new MenuFlyoutItem { Text = b.Naam };
            item.Click += (_, _) => { Opslag.Kies(n, b.Naam, leer: true); daarna?.Invoke(); };
            ander.Items.Add(item);
        }
        rij.Children.Add(new DropDownButton { Content = "Ander", Flyout = ander });
        return rij;
    }

    UIElement Kaartje(Notitie n)
    {
        var sp = new StackPanel { Spacing = 6 };
        if (n.Foto != null)
        {
            if (Opslag.IsAfbeelding(n.Foto))
            {
                var img = new Image { Height = 130, Stretch = Stretch.UniformToFill, HorizontalAlignment = HorizontalAlignment.Stretch };
                Invoer.LaadMiniatuur(img, n.Foto, 480);
                var rand = new Border { Child = img, CornerRadius = new CornerRadius(6), Height = 130 };
                rand.Tapped += (_, _) => Open(Opslag.FotoPad(n.Foto));
                sp.Children.Add(rand);
            }
            else
            {
                var knop = new HyperlinkButton { Content = Ui.Rij(8, new FontIcon { Glyph = "", FontSize = 16 }, new TextBlock { Text = Opslag.OrigineleNaam(n.Foto), TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 190 }), Padding = new Thickness(0) };
                knop.Click += (_, _) => Open(Opslag.FotoPad(n.Foto));
                sp.Children.Add(knop);
            }
        }
        if (n.Tekst != "")
            sp.Children.Add(new TextBlock { Text = n.Tekst, TextWrapping = TextWrapping.Wrap, MaxLines = 6, TextTrimming = TextTrimming.CharacterEllipsis, IsTextSelectionEnabled = true });
        if (Invoer.EersteLink(n.Tekst) is { } link)
            sp.Children.Add(new HyperlinkButton { Content = link.Host, NavigateUri = link, Padding = new Thickness(0) });
        foreach (var item in n.Items)
        {
            var tb = new TextBlock { Text = item.Tekst, TextWrapping = TextWrapping.Wrap };
            var vink = new CheckBox { Content = tb, IsChecked = Doorgestreept.Contains(item.Id), MinWidth = 0 };
            Streep(tb, vink.IsChecked == true);
            vink.Checked += (_, _) => Vink(n, item, tb, true);
            vink.Unchecked += (_, _) => Vink(n, item, tb, false);
            sp.Children.Add(vink);
        }

        var voet = new Grid();
        voet.Children.Add(new TextBlock { Text = Ui.Relatief(n.Gemaakt), Style = Ui.Stijl("CaptionTextBlockStyle"), Foreground = Ui.Kwast("TextFillColorTertiaryBrush"), VerticalAlignment = VerticalAlignment.Center });
        var meer = Ui.IcoonKnop("", "Meer", () => { });
        meer.HorizontalAlignment = HorizontalAlignment.Right;
        meer.Flyout = Menu(n);
        voet.Children.Add(meer);
        sp.Children.Add(voet);

        var kaart = Ui.Kaart(sp, 12);
        kaart.Width = 250;
        kaart.VerticalAlignment = VerticalAlignment.Top;
        kaart.ContextFlyout = Menu(n);
        return kaart;
    }

    MenuFlyout Menu(Notitie n)
    {
        var m = new MenuFlyout();
        var bewerk = new MenuFlyoutItem { Text = "Bewerken", Icon = new FontIcon { Glyph = "" } };
        bewerk.Click += async (_, _) => await Bewerk(n);
        m.Items.Add(bewerk);
        var naar = new MenuFlyoutSubItem { Text = "Naar bakje", Icon = new FontIcon { Glyph = "" } };
        foreach (var b in Opslag.Data.Bakjes)
        {
            var i = new MenuFlyoutItem { Text = b.Naam };
            i.Click += (_, _) => Opslag.Kies(n, b.Naam, leer: true);
            naar.Items.Add(i);
        }
        m.Items.Add(naar);
        var kopie = new MenuFlyoutItem { Text = "Kopiëren", Icon = new FontIcon { Glyph = "" } };
        kopie.Click += (_, _) =>
        {
            var dp = new Windows.ApplicationModel.DataTransfer.DataPackage();
            dp.SetText(n.VolledigeTekst);
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(dp);
        };
        m.Items.Add(kopie);
        m.Items.Add(new MenuFlyoutSeparator());
        var weg = new MenuFlyoutItem { Text = "Verwijderen", Icon = new FontIcon { Glyph = "" } };
        weg.Click += (_, _) => Opslag.Verwijder(n);
        m.Items.Add(weg);
        return m;
    }

    async Task Bewerk(Notitie n)
    {
        var tekst = new TextBox { Text = n.VolledigeTekst, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 140, MaxHeight = 360, Header = "Notitie (\"- \" aan het begin van een regel maakt een afvinkpunt)" };
        var bakje = new ComboBox { Header = "Bakje", ItemsSource = Opslag.Data.Bakjes.Select(b => b.Naam).ToList(), SelectedItem = n.Bakje, MinWidth = 200 };
        var dlg = new ContentDialog
        {
            XamlRoot = XamlRoot, Title = "Notitie bewerken", Content = Ui.Stapel(12, tekst, bakje),
            PrimaryButtonText = "Bewaar", CloseButtonText = "Annuleer", DefaultButton = ContentDialogButton.Primary,
        };
        if (await dlg.ShowAsync() != ContentDialogResult.Primary) return;
        var (rest, items) = NotitieParser.Ontleed(tekst.Text);
        n.Tekst = rest;
        n.Items = items.Select(t => n.Items.FirstOrDefault(i => i.Tekst == t) ?? new LijstItem { Tekst = t }).ToList();
        n.Gewijzigd = DateTime.UtcNow;
        if (bakje.SelectedItem is string b && b != n.Bakje) Opslag.Kies(n, b, leer: true);
        else Opslag.Bewaar();
    }

    static void Streep(TextBlock tb, bool aan)
    {
        tb.TextDecorations = aan ? Windows.UI.Text.TextDecorations.Strikethrough : Windows.UI.Text.TextDecorations.None;
        tb.Opacity = aan ? 0.5 : 1;
    }

    /// Doorstrepen, twee tellen wachten, weg. Nog een klik in die twee tellen maakt het ongedaan.
    static async void Vink(Notitie n, LijstItem item, TextBlock tb, bool aan)
    {
        Streep(tb, aan);
        if (!aan) { Doorgestreept.Remove(item.Id); return; }
        if (!Doorgestreept.Add(item.Id)) return;
        await Task.Delay(2000);
        if (!Doorgestreept.Remove(item.Id)) return;
        n.Items.Remove(item);
        n.Gewijzigd = DateTime.UtcNow;
        if (n.Items.Count == 0 && n.Tekst == "" && n.Foto == null) Opslag.Verwijder(n);
        else Opslag.Bewaar();
    }

    static void Open(string pad)
    {
        try { Process.Start(new ProcessStartInfo(pad) { UseShellExecute = true }); } catch (Exception) { }
    }
}

// ---------------------------------------------------------------- Instellingen

public sealed class InstellingenPagina : UserControl
{
    readonly StackPanel _bakjes = new() { Spacing = 4 };
    readonly TextBlock _updateStatus = Ui.Tekst("", zacht: true);
    readonly Button _herstart = Ui.Knop("Herstart en installeer", Updates.Herstart, accent: true);
    readonly TextBlock _wie = Ui.Tekst(""), _syncStatus = Ui.Tekst("", "CaptionTextBlockStyle", zacht: true);
    readonly Button _inloggen = Ui.Knop("Inloggen met Google", () => _ = Sync.Inloggen(), accent: true);
    readonly Button _uitloggen = Ui.Knop("Uitloggen", () => _ = Sync.Uitloggen());

    void ToonAccount()
    {
        var w = Sync.Wie;
        _wie.Text = w == null
            ? "Log in om je notities te synchroniseren met je iPhone en gedeelde lijsten te zien."
            : w.Naam != "" ? $"{w.Naam} · {w.Email}" : w.Email;
        _syncStatus.Text = Sync.Status != "" ? Sync.Status
            : w == null ? "Privé blijft altijd op je telefoon; alleen tekst gaat mee, geen foto's."
            : Sync.Laatst is { } t ? $"Gesynchroniseerd om {t:HH:mm:ss}" : "Synchroniseren…";
        _inloggen.Visibility = w == null ? Visibility.Visible : Visibility.Collapsed;
        _uitloggen.Visibility = w == null ? Visibility.Collapsed : Visibility.Visible;
    }

    public InstellingenPagina()
    {
        var nieuw = new TextBox { PlaceholderText = "Nieuw bakje", Width = 240 };
        void VoegToe()
        {
            var naam = nieuw.Text.Trim();
            if (naam == "" || Opslag.Data.Bakjes.Any(b => b.Naam.Equals(naam, StringComparison.CurrentCultureIgnoreCase))) return;
            Opslag.Data.Bakjes.Add(new Bakje { Naam = naam });
            nieuw.Text = "";
            Opslag.Bewaar();
        }
        nieuw.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) VoegToe(); };

        var zoekUpdate = Ui.Knop("Zoek naar updates", () => _ = Updates.Zoek());
        Updates.Veranderd += () => App.Ui.TryEnqueue(ToonUpdate);
        ToonUpdate();

        Sync.Veranderd += () => App.Ui.TryEnqueue(ToonAccount);
        ToonAccount();

        Content = Ui.Pagina("Instellingen",
            Ui.Kaart(Ui.Stapel(8,
                Ui.Tekst("Account", "SubtitleTextBlockStyle"),
                _wie, _syncStatus,
                Ui.Rij(8, _inloggen, _uitloggen))),
            Ui.Kaart(Ui.Stapel(10,
                Ui.Tekst("Mijn bakjes", "SubtitleTextBlockStyle"),
                Ui.Tekst("Eigen bakjes herkent Kniv zodra je hun naam gebruikt, en hij leert van jouw keuzes.", zacht: true),
                _bakjes,
                Ui.Rij(8, nieuw, Ui.Knop("Voeg toe", VoegToe)))),
            Ui.Kaart(Ui.Stapel(6,
                Ui.Tekst("Sneltoets", "SubtitleTextBlockStyle"),
                Ui.Tekst("Win+Shift+K opent overal een klein Kniv-venster. Sluiten met het kruisje zet Kniv in het systeemvak; afsluiten doe je via het icoon daar.", zacht: true))),
            Ui.Kaart(Ui.Stapel(8,
                Ui.Tekst("Gegevens", "SubtitleTextBlockStyle"),
                Ui.Tekst("Alles staat op deze pc in " + Opslag.Map + ". Ingelogd gaan notities (zonder foto's) ook naar je Kniv-account.", zacht: true),
                Ui.Knop("Map openen", () => Process.Start(new ProcessStartInfo(Opslag.Map) { UseShellExecute = true })))),
            Ui.Kaart(Ui.Stapel(8,
                Ui.Tekst("Over Kniv", "SubtitleTextBlockStyle"),
                Ui.Tekst($"Versie {Updates.Versie}"),
                _updateStatus,
                Ui.Rij(8, zoekUpdate, _herstart))));

        Opslag.Gewijzigd += VulBakjes;
        VulBakjes();
    }

    void ToonUpdate()
    {
        _updateStatus.Text = Updates.Status;
        _herstart.Visibility = Updates.Klaar != null ? Visibility.Visible : Visibility.Collapsed;
    }

    void VulBakjes()
    {
        _bakjes.Children.Clear();
        foreach (var b in Opslag.Data.Bakjes.ToList())
        {
            var aantal = Opslag.Data.Notities.Count(n => n.Bakje == b.Naam);
            var rij = new Grid { ColumnSpacing = 8, MinHeight = 40 };
            rij.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
            rij.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            rij.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            if (b.Vast)
                rij.Children.Add(new TextBlock { Text = b.Naam, VerticalAlignment = VerticalAlignment.Center });
            else
            {
                var naam = new TextBox { Text = b.Naam, VerticalAlignment = VerticalAlignment.Center };
                naam.LostFocus += (_, _) => Hernoem(b, naam.Text.Trim());
                rij.Children.Add(naam);
            }
            var tel = Ui.Tekst(aantal == 1 ? "1 notitie" : $"{aantal} notities", zacht: true);
            tel.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(tel, 1);
            rij.Children.Add(tel);
            if (!b.Vast)
            {
                var weg = Ui.IcoonKnop("", "Bakje verwijderen", () => Verwijder(b));
                Grid.SetColumn(weg, 2);
                rij.Children.Add(weg);
            }
            _bakjes.Children.Add(rij);
        }
    }

    static void Hernoem(Bakje b, string naam)
    {
        if (naam == "" || naam == b.Naam || Opslag.Data.Bakjes.Any(x => x.Naam.Equals(naam, StringComparison.CurrentCultureIgnoreCase))) return;
        foreach (var n in Opslag.Data.Notities.Where(n => n.Bakje == b.Naam)) { n.Bakje = naam; n.Gewijzigd = DateTime.UtcNow; }
        foreach (var k in Opslag.Data.Geleerd.Where(g => g.Value == b.Naam).Select(g => g.Key).ToList()) Opslag.Data.Geleerd[k] = naam;
        b.Naam = naam;
        Opslag.Bewaar();
    }

    /// Notities uit een verwijderd bakje komen terug bij "Even checken".
    static void Verwijder(Bakje b)
    {
        Opslag.Data.Bakjes.Remove(b);
        var namen = Opslag.Data.Bakjes.Select(x => x.Naam).ToList();
        foreach (var n in Opslag.Data.Notities.Where(n => n.Bakje == b.Naam))
        {
            n.Bakje = null;
            n.Twijfel = Sorteerder.Sorteer(n.ZoekTekst, namen, new());
            if (n.Twijfel.Count < 2) n.Twijfel = namen.Take(2).ToList();
            n.Gewijzigd = DateTime.UtcNow;
        }
        foreach (var k in Opslag.Data.Geleerd.Where(g => g.Value == b.Naam).Select(g => g.Key).ToList()) Opslag.Data.Geleerd.Remove(k);
        Opslag.Bewaar();
    }
}
