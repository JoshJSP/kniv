using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using WinRT.Interop;

namespace Kniv;

/// Win+Shift+K: klein venster midden in beeld. Eén balk, daaronder recente notities. Enter bewaart, Esc sluit.
public sealed class SnelVenster : Window
{
    readonly TextBox _invoer = new() { PlaceholderText = "Wat wil je kwijt?", FontSize = 20, MaxHeight = 160, BorderThickness = new Thickness(0), Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent) };
    readonly StackPanel _recent = new() { Spacing = 2 };
    readonly StackPanel _vraag = new() { Spacing = 8, Visibility = Visibility.Collapsed };
    readonly TextBlock _status = Ui.Tekst("Enter bewaart · Shift+Enter nieuwe regel · plak een screenshot of sleep een bestand · Esc sluit", "CaptionTextBlockStyle", zacht: true);
    readonly IntPtr _hwnd;

    public SnelVenster()
    {
        Title = "Kniv snelvenster";
        ExtendsContentIntoTitleBar = true;
        SystemBackdrop = new DesktopAcrylicBackdrop();
        _hwnd = WindowNative.GetWindowHandle(this);
        var p = OverlappedPresenter.Create();
        p.IsResizable = false;
        p.IsMaximizable = false;
        p.IsMinimizable = false;
        p.IsAlwaysOnTop = true;
        p.SetBorderAndTitleBar(true, false);
        AppWindow.SetPresenter(p);
        AppWindow.IsShownInSwitchers = false;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "kniv.ico"));
        AppWindow.Closing += (s, e) => { e.Cancel = true; s.Hide(); };
        Activated += (_, e) => { if (e.WindowActivationState == WindowActivationState.Deactivated) AppWindow.Hide(); };

        var logo = new FontIcon { Glyph = "", FontSize = 20, Foreground = Ui.Kwast("AccentTextFillColorPrimaryBrush"), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 8, 0, 0) };
        var balk = new Grid { ColumnSpacing = 8 };
        balk.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        balk.ColumnDefinitions.Add(new ColumnDefinition());
        Grid.SetColumn(_invoer, 1);
        balk.Children.Add(logo);
        balk.Children.Add(_invoer);

        var wortel = new Grid { Padding = new Thickness(20, 16, 20, 14), RowSpacing = 10 };
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        wortel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        wortel.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var lijn = new Border { Height = 1, Background = Ui.Kwast("DividerStrokeColorDefaultBrush") };
        var recentBlok = Ui.Stapel(4, Ui.Tekst("Recent", "CaptionTextBlockStyle", zacht: true), _recent);
        Grid.SetRow(lijn, 1);
        Grid.SetRow(_vraag, 2);
        Grid.SetRow(recentBlok, 3);
        Grid.SetRow(_status, 4);
        foreach (var e in new UIElement[] { balk, lijn, _vraag, recentBlok, _status }) wortel.Children.Add(e);
        wortel.PreviewKeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Escape) { e.Handled = true; AppWindow.Hide(); } };
        Content = wortel;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(_invoer, "Nieuwe notitie");
        Invoer.Koppel(_invoer, wortel, Bewaard);
    }

    public void Toon()
    {
        _vraag.Visibility = Visibility.Collapsed;
        _status.Text = "Enter bewaart · Shift+Enter nieuwe regel · plak een screenshot of sleep een bestand · Esc sluit";
        VulRecent();
        var schaal = Win32.GetDpiForWindow(_hwnd) / 96.0;
        var scherm = DisplayArea.GetFromWindowId(App.Huidig!.Hoofd.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int b = (int)(660 * schaal), h = (int)(420 * schaal);
        AppWindow.MoveAndResize(new RectInt32(scherm.X + (scherm.Width - b) / 2, scherm.Y + (int)(scherm.Height * 0.22), b, h));
        AppWindow.Show();
        Activate();
        Win32.NaarVoren(_hwnd);
        _invoer.Focus(FocusState.Programmatic);
    }

    void Bewaard(Notitie? n)
    {
        if (n == null) { _status.Text = "Dat lukte niet. Probeer het nog eens."; return; }
        VulRecent();
        if (n.Bakje != null) { Klaar($"Bewaard in {n.Bakje}."); return; }
        // Twijfel: meteen vragen, met één klik.
        _vraag.Children.Clear();
        _vraag.Children.Add(Ui.Tekst($"Waar hoort \"{n.Titel}\" bij?"));
        _vraag.Children.Add(VastleggenPagina.KiesKnoppen(n, () => Klaar($"Bewaard in {n.Bakje}.")));
        _vraag.Visibility = Visibility.Visible;
    }

    async void Klaar(string tekst)
    {
        _vraag.Visibility = Visibility.Collapsed;
        _status.Text = tekst;
        VulRecent();
        await Task.Delay(700);
        if (_invoer.Text == "") AppWindow.Hide();
    }

    void VulRecent()
    {
        _recent.Children.Clear();
        foreach (var n in Opslag.Data.Notities.OrderByDescending(n => n.Gewijzigd).Take(6))
        {
            var rij = new Grid { Padding = new Thickness(8, 6, 8, 6), CornerRadius = new CornerRadius(4) };
            rij.Children.Add(new TextBlock { Text = n.Titel, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 0, 120, 0) });
            rij.Children.Add(new TextBlock { Text = n.Bakje ?? "Even checken", HorizontalAlignment = HorizontalAlignment.Right, Foreground = Ui.Kwast("TextFillColorSecondaryBrush"), Style = Ui.Stijl("CaptionTextBlockStyle"), VerticalAlignment = VerticalAlignment.Center });
            rij.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            rij.PointerEntered += (_, _) => rij.Background = Ui.Kwast("SubtleFillColorSecondaryBrush");
            rij.PointerExited += (_, _) => rij.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            rij.Tapped += (_, _) => { AppWindow.Hide(); App.Huidig?.Toon(); };
            _recent.Children.Add(rij);
        }
        if (_recent.Children.Count == 0) _recent.Children.Add(Ui.Tekst("Nog niks. Typ iets en druk op Enter.", zacht: true));
    }
}
