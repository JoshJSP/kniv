using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using Velopack;
using Velopack.Sources;
using WinRT.Interop;

namespace Kniv;

public static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        VelopackApp.Build().Run();
        if (args.Length > 0 && args[0] == "--selftest") return Zelftest.Draai(args.ElementAtOrDefault(1));
        if (args.Length > 0 && args[0] == "--updatetest") return Updates.Test(args.ElementAtOrDefault(1) ?? "updatetest.txt");

        WinRT.ComWrappersSupport.InitializeComWrappers();
        // Eén Kniv tegelijk: een tweede start (Startmenu, melding) opent gewoon het bestaande venster.
        var sleutel = AppInstance.FindOrRegisterForKey("Kniv-hoofd");
        if (!sleutel.IsCurrent)
        {
            var a = AppInstance.GetCurrent().GetActivatedEventArgs();
            Task.Run(() => sleutel.RedirectActivationToAsync(a).AsTask()).Wait();
            return 0;
        }
        sleutel.Activated += (_, _) => App.Huidig?.Toon();
        Application.Start(p =>
        {
            SynchronizationContext.SetSynchronizationContext(new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new App();
        });
        return 0;
    }
}

public partial class App : Application
{
    public static App? Huidig;
    public static DispatcherQueue Ui = null!;
    public static bool SneltoetsWerkt;
    public HoofdVenster Hoofd = null!;
    SnelVenster? _snel;

    public App()
    {
        InitializeComponent();
        Huidig = this;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Ui = DispatcherQueue.GetForCurrentThread();
        Opslag.Laad();
        Meldingen.Start();
        Hoofd = new HoofdVenster();
        Hoofd.Activate();
        Win32.Sneltoets = ToonSnel;
        Win32.Snelvenster = ToonSnel;
        Win32.Openen = Toon;
        Win32.Afsluiten = Afsluiten;
        SneltoetsWerkt = Win32.Start(WindowNative.GetWindowHandle(Hoofd));
        Hoofd.ToonSneltoetsStatus();
        Klok.Start();
        Updates.Start();
    }

    public void Toon() => Ui.TryEnqueue(() =>
    {
        Hoofd.AppWindow.Show();
        Hoofd.Activate();
        Win32.NaarVoren(WindowNative.GetWindowHandle(Hoofd));
    });

    public void ToonSnel()
    {
        _snel ??= new SnelVenster();
        _snel.Toon();
    }

    public void Afsluiten()
    {
        Win32.Stop();
        Meldingen.Stop();
        Updates.BijAfsluiten();
        Hoofd.EchtSluiten = true;
        _snel?.Close();
        Hoofd.Close();
        Exit();
    }
}

static class Meldingen
{
    public static void Start()
    {
        try
        {
            AppNotificationManager.Default.NotificationInvoked += (_, _) => App.Huidig?.Toon();
            AppNotificationManager.Default.Register("Kniv", new Uri(Path.Combine(AppContext.BaseDirectory, "kniv.png")));
        }
        catch (Exception) { /* zonder meldingen werkt de rest gewoon */ }
    }

    public static void Toon(string titel, string tekst)
    {
        try { AppNotificationManager.Default.Show(new AppNotificationBuilder().AddText(titel).AddText(tekst).BuildNotification()); }
        catch (Exception) { }
    }

    public static void Stop()
    {
        try { AppNotificationManager.Default.Unregister(); } catch (Exception) { }
    }
}

/// Velopack. De feed staat vast op de release "win" in kniv-releases, zodat de iOS-releases daar nooit meetellen.
static class Updates
{
    public const string Feed = "https://github.com/JoshJSP/kniv-releases/releases/download/win/";
    static readonly UpdateManager Mgr = new(new SimpleWebSource(Feed));
    public static VelopackAsset? Klaar;
    public static string Status = "";
    public static event Action? Veranderd;

    public static string Versie => Mgr.CurrentVersion?.ToString()
        ?? typeof(Updates).Assembly.GetName().Version?.ToString(3) ?? "?";

    public static void Start()
    {
        _ = Zoek();
        var t = App.Ui.CreateTimer();   // Kniv staat vaak dagen in het systeemvak
        t.Interval = TimeSpan.FromHours(6);
        t.Tick += (_, _) => _ = Zoek();
        t.Start();
    }

    public static async Task Zoek()
    {
        if (Klaar != null) return;
        if (!Mgr.IsInstalled) { Zet("Updates werken alleen in de geïnstalleerde versie."); return; }
        try
        {
            Zet("Zoeken naar updates…");
            var info = await Mgr.CheckForUpdatesAsync();
            if (info == null) { Zet("Je hebt de nieuwste versie."); return; }
            var v = info.TargetFullRelease.Version;
            Zet($"Versie {v} downloaden…");
            await Mgr.DownloadUpdatesAsync(info);
            Klaar = info.TargetFullRelease;
            Zet($"Versie {v} staat klaar.");
        }
        catch (Exception) { Zet("Kon niet op updates controleren. Geen internet?"); }
    }

    static void Zet(string s) { Status = s; Veranderd?.Invoke(); }

    public static void Herstart() { if (Klaar != null) Mgr.ApplyUpdatesAndRestart(Klaar); }

    public static void BijAfsluiten()
    {
        try { if (Klaar != null) Mgr.WaitExitThenApplyUpdates(Klaar, true, false); } catch (Exception) { }
    }

    /// Voor CI en handmatig testen: lees de feed zonder venster en schrijf het resultaat weg.
    public static int Test(string uit)
    {
        try
        {
            string r;
            if (Mgr.IsInstalled)
            {
                var info = Mgr.CheckForUpdatesAsync().GetAwaiter().GetResult();
                r = $"OK geinstalleerd versie={Mgr.CurrentVersion} nieuwer={info?.TargetFullRelease.Version.ToString() ?? "geen"}";
            }
            else
            {
                using var http = new HttpClient();
                var feed = VelopackAssetFeed.FromJson(http.GetStringAsync(Feed + "releases.win.json").GetAwaiter().GetResult());
                r = "OK niet-geinstalleerd feed=" + string.Join(",", feed.Assets.Select(a => a.Version.ToString()));
            }
            File.WriteAllText(uit, r);
            return 0;
        }
        catch (Exception e)
        {
            File.WriteAllText(uit, "FOUT " + e);
            return 1;
        }
    }
}

static class Zelftest
{
    public static int Draai(string? uit)
    {
        var fouten = new List<string>();
        void Is(bool ok, string wat) { if (!ok) fouten.Add(wat); }
        var bakjes = Sorteerder.StandaardBakjes.ToList();
        var geleerd = new Dictionary<string, string>();
        string S(string t) => string.Join("|", Sorteerder.Sorteer(t, bakjes, geleerd));

        Is(S("melk en brood halen") == "Boodschappen", "boodschappen");
        Is(S("oma bellen") == "Persoonlijk|To-do", "twijfel oma bellen: " + S("oma bellen"));
        Is(S("iets voor school") == "School", "bakjesnaam");
        Is(S("xyz") == "Ideeën|To-do", "niks herkend");
        Sorteerder.Leer("kunstgeschiedenis tentamen", "Persoonlijk", geleerd);
        Is(S("kunstgeschiedenis") == "Persoonlijk", "geleerd");

        var (rest, items) = NotitieParser.Ontleed("Weekend\n- melk\n- \n• kaas");
        Is(rest == "Weekend" && items.SequenceEqual(new[] { "melk", "kaas" }), "lijstje");

        var (pp, totaal) = Rekenen.Delen(100, 4, 10);
        Is(Math.Abs(pp - 27.5) < 1e-9 && Math.Abs(totaal - 110) < 1e-9, "delen");
        Is(Math.Abs(Rekenen.Omzetten("Lengte", 1, "mijl", "km") - 1.609344) < 1e-9, "mijl");
        Is(Math.Abs(Rekenen.Omzetten("Temperatuur", 100, "°C", "°F") - 212) < 1e-9, "graden");
        Is(Math.Abs(Rekenen.Omzetten("Temperatuur", 0, "K", "°C") + 273.15) < 1e-9, "kelvin");

        Is(Rekenen.FooiProcent(null, null, null) == null, "fooi niks");
        Is(Rekenen.FooiProcent(5, null, 5) == 15, "fooi max");
        Is(Math.Abs(Rekenen.FooiProcent(3, 3, 3)!.Value - 8) < 1e-9, "fooi 3 sterren");
        Is(Math.Abs(Rekenen.FooiProcent(4, 2, 3)!.Value - (8 + 2 * (14 / 4.5 - 3))) < 1e-9, "fooi gewogen: " + Rekenen.FooiProcent(4, 2, 3));
        Is(Rekenen.FooiAdvies(40, 8) == (3, 43), "fooi afronden euro");
        Is(Rekenen.FooiAdvies(60, 10) == (5, 65), "fooi afronden vijf");
        Is(Rekenen.FooiAdvies(20, 0) == (0, 20), "geen fooi");
        Is(Rekenen.FooiAdvies(50.2, 1) == (0, 50.2), "nooit onder de prijs");

        var tekst = fouten.Count == 0 ? "OK" : "FOUT " + string.Join("; ", fouten);
        if (uit != null) File.WriteAllText(uit, tekst);
        return fouten.Count == 0 ? 0 : 1;
    }
}
