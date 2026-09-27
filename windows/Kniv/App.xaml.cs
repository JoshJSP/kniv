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
        var testMap = Environment.GetEnvironmentVariable("KNIV_MAP");
        var sleutel = AppInstance.FindOrRegisterForKey(string.IsNullOrEmpty(testMap) ? "Kniv-hoofd" : "Kniv-test");
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
    DispatcherQueueTimer? _sneltoetsTimer;

    public App()
    {
        InitializeComponent();
        Huidig = this;
        UnhandledException += (_, e) => { Log(e.Exception); e.Handled = true; };
        TaskScheduler.UnobservedTaskException += (_, e) => { Log(e.Exception); e.SetObserved(); };
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log(e.ExceptionObject);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Ui = DispatcherQueue.GetForCurrentThread();
        Opslag.Laad();
        Meldingen.Start();
        Sync.Start();
        _ = SplittenPagina.HaalKoersen();   // voor "45 usd" in het snelvenster
        Hoofd = new HoofdVenster();
        Hoofd.Activate();
        Win32.Sneltoets = ToonSnel;
        Win32.Snelvenster = ToonSnel;
        Win32.Openen = Toon;
        Win32.Afsluiten = Afsluiten;
        Win32.Start(WindowNative.GetWindowHandle(Hoofd));
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("KNIV_MAP"))) SneltoetsWerkt = true;   // testexemplaar: de sneltoets blijft van de echte Kniv
        else if (!(SneltoetsWerkt = Win32.RegistreerSneltoets()))
        {
            var t = _sneltoetsTimer = Ui.CreateTimer();   // elke minuut opnieuw: misschien komt hij vrij
            t.Interval = TimeSpan.FromMinutes(1);
            t.Tick += (_, _) => { if (!Win32.RegistreerSneltoets()) return; t.Stop(); SneltoetsWerkt = true; Hoofd.ToonSneltoetsStatus(); };
            t.Start();
        }
        Hoofd.ToonSneltoetsStatus();
        Klok.Start();
        Updates.Start();
    }

    /// Fouten niet laten crashen maar opschrijven in fouten.log in de Kniv-map.
    public static void Log(object fout)
    {
        try
        {
            Directory.CreateDirectory(Opslag.Map);
            File.AppendAllText(Path.Combine(Opslag.Map, "fouten.log"), $"{DateTime.Now:s} {fout}{Environment.NewLine}{Environment.NewLine}");
        }
        catch (Exception) { }
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
        catch (Exception e) { App.Log(e); /* zonder meldingen werkt de rest gewoon */ }
    }

    public static void Toon(string titel, string tekst)
    {
        try { AppNotificationManager.Default.Show(new AppNotificationBuilder().AddText(titel).AddText(tekst).BuildNotification()); }
        catch (Exception e) { App.Log(e); }
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

    static DispatcherQueueTimer? _timer;

    public static void Start()
    {
        _ = Zoek();
        var t = _timer = App.Ui.CreateTimer();   // Kniv staat vaak dagen in het systeemvak
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

    public static void Herstart()
    {
        if (Klaar == null) return;
        Win32.Stop();   // anders blijft er een dood icoon in het systeemvak staan
        Mgr.ApplyUpdatesAndRestart(Klaar);
    }

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
        Is(Rekenen.FooiAdvies(40, 8) == (3.5, 43.5), "fooi afronden halve euro omhoog");
        Is(Rekenen.FooiAdvies(3, 8) == (0.5, 3.5), "kleine fooi wordt geen nul");
        Is(Rekenen.FooiAdvies(20, 0) == (0, 20), "geen fooi");
        Is(Rekenen.FooiAdvies(10, 0) == (0, 10), "geen fooi = prijs");

        // Snelvenster-commando's, dezelfde gevallen als Tests/main.swift
        string R(string t, Dictionary<string, double>? k = null) => Omzetter.Reken(t, k) ?? "nil";
        var usd = new Dictionary<string, double> { ["USD"] = 1.1 };
        Is(R("3 cups bloem").Contains("720 ml") && R("3 cups bloem").Contains("375 g bloem"), "cups bloem: " + R("3 cups bloem"));
        Is(R("10 mijl").Contains("16,1 km"), "mijl: " + R("10 mijl"));
        Is(R("100 f").Contains("37,8 °C"), "fahrenheit: " + R("100 f"));
        Is(R("10 km in mijl").Contains("6,21 mijl"), "km in mijl: " + R("10 km in mijl"));
        Is(R("30% korting op 89").Contains("62,30"), "korting: " + R("30% korting op 89"));
        Is(R("45 usd", usd).Contains("40,91"), "valuta: " + R("45 usd", usd));
        Is(R("$12.99", usd).Contains("11,81"), "dollarteken: " + R("$12.99", usd));
        Is(R("20 min pasta") == "nil" && R("gewoon tekst") == "nil", "geen omzetting");
        Is(R("14:35 + 2u50") == "14:35 + 2 u 50 min = 17:25", "tijd optellen: " + R("14:35 + 2u50"));
        Is(R("23:30 + 45 min") == "23:30 + 45 min = 0:15 (volgende dag)", "tijd middernacht: " + R("23:30 + 45 min"));
        Is(R("22:00 - 6:30").StartsWith("22:00 tot 6:30 = 8 u 30 min"), "nachtdienst: " + R("22:00 - 6:30"));
        Is(Omzetter.Reken("dagen tot 9 okt", null, new DateTime(2026, 9, 26, 10, 0, 0)) == "Nog 13 dagen", "dagen tot");
        Is(R("15:00 in tokyo").EndsWith("in Tokyo") && R("15:00 in atlantis") == "nil", "tijdzone: " + R("15:00 in tokyo"));
        Is(R("2,49 voor 500g of 3,99 voor 1kg").StartsWith("De tweede is 20% goedkoper"), "goedkoper kilo: " + R("2,49 voor 500g of 3,99 voor 1kg"));
        Is(R("1,50 voor 330ml of 2,19 voor 1,5l").StartsWith("De tweede is 68% goedkoper") && R("2,49 voor 500g of 3,99 voor 1l") == "nil", "goedkoper liter");
        Is(SnelCommando.Kern("10 km = 6,21 mijl") == "6,21 mijl" && SnelCommando.Kern("3 cups = 720 ml ≈ 375 g bloem") == "720 ml", "kern");

        Is(TimerParser.Vind("over 20 min oven uit") == ("Oven uit", 1200), "timer uit notitie: " + TimerParser.Vind("over 20 min oven uit"));
        Is(TimerParser.Vind("20 min pasta") == ("Pasta", 1200), "20 min pasta");
        Is(TimerParser.Vind("over 10 minuten thee") == ("Thee", 600), "10 minuten thee");
        Is(TimerParser.Vind("pasta 9 minuten")?.seconden == 540, "pasta 9 minuten");
        Is(TimerParser.Vind("1 uur")?.naam == "Timer", "naamloze timer");
        Is(TimerParser.Vind("tandarts om 14:30") == null, "kloktijd is geen timer");
        Is(Weer.Bepaal(new[] { (14, 10, 0.0, 15.0), (15, 70, 1.2, 14.0) }) == "Regen rond 15:00, paraplu mee", "weer regen");
        Is(Weer.Bepaal(new[] { (8, 0, 0.0, 4.0) }) == "Fris vandaag (4°), jas aan" && Weer.Bepaal(new[] { (12, 0, 0.0, 18.0) }) == null, "weer koud/droog");
        Is(Rekenmachine.Uitkomst("12*3+4") == 40 && Rekenmachine.Uitkomst("2^10") == 1024 && Rekenmachine.Uitkomst("-3*-2") == 6, "rekenen");
        Is(Rekenmachine.Uitkomst("06-12345678") == null && Rekenmachine.Uitkomst("10 - 3") == 7 && Rekenmachine.Uitkomst("1/0") == null, "rekenen grensgevallen");
        Is(SnelCommando.Kern(Rekenmachine.Tekst("12*3+4")!) == "40", "rekenen in snelvenster");
        Is(SnelCommando.Klok(125) == "02:05" && SnelCommando.Klok(3725) == "1:02:05", "klok");
        Is(SnelCommando.Timer("morgen om 3 uur tandarts") == null, "moment blijft notitie");
        Is(SnelCommando.Timer("10 km in mijl") == null && SnelCommando.Timer("45 usd") == null, "omzetten is geen timer");

        var zaterdag = new DateTime(2026, 9, 26, 10, 0, 0);
        Is(Herinnering.Vind("morgen oma bellen", zaterdag)?.dag == new DateTime(2026, 9, 27), "morgen");
        Is(Herinnering.Vind("zaterdag feest", zaterdag)?.dag == new DateTime(2026, 10, 3), "zelfde weekdag = volgende week");
        Is(Herinnering.Vind("maandag om 14:30", zaterdag)?.dag == new DateTime(2026, 9, 28, 14, 30, 0), "maandag 14:30");
        Is(Herinnering.Vind("feestje 3 mei", zaterdag)?.dag.Year == 2027, "voorbije datum = volgend jaar");
        Is(Herinnering.Vind("om 9 bellen", zaterdag)?.dag.Day == 27, "tijd al voorbij = morgen");
        Is(Herinnering.Vind("om 3 bellen", zaterdag)?.dag == new DateTime(2026, 9, 26, 15, 0, 0), "om 3 = middag");
        Is(Herinnering.Vind("morgen om 7 vroeg", zaterdag)?.dag == new DateTime(2026, 9, 27, 7, 0, 0), "om 7 vroeg = ochtend");
        Is(Herinnering.Vind("om 14.30 tandarts", zaterdag)?.dag == new DateTime(2026, 9, 26, 14, 30, 0), "om 14.30");
        Is(Herinnering.Vind("brood 2.50", zaterdag) == null, "prijs is geen tijd");
        Is(Herinnering.Vind("gewoon tekst", zaterdag) == null && Herinnering.Vind("morgenochtend", zaterdag) == null, "geen moment");

        // Sync: een rij van de server wordt een notitie, een oudere rij wint niet, verwijderd haalt hem weg.
        var id = Guid.NewGuid();
        var json = "{\"id\":\"" + id + "\",\"eigenaar\":\"" + Guid.NewGuid() + "\",\"groep\":null,\"soort\":\"notitie\",\"gewijzigd\":\"2026-09-27T10:00:00.123+00:00\",\"gewijzigd_door\":null,\"verwijderd\":false,"
            + "\"data\":{\"tekst\":\"Weekend\",\"fotoTekst\":\"\",\"bakje\":\"Boodschappen\",\"gemaakt\":\"2026-09-27T09:00:00.000Z\",\"items\":[{\"tekst\":\"kaas\",\"volgorde\":1,\"door\":null},{\"tekst\":\"melk\",\"volgorde\":0,\"door\":null}]}}";
        var rij = System.Text.Json.JsonSerializer.Deserialize<Rij>(json)!;
        Is(Sync.Verwerk(rij, null), "sync nieuw");
        var sn = Opslag.Data.Notities.FirstOrDefault(n => n.Id == id);
        Is(sn != null && sn.Bakje == "Boodschappen" && string.Join(",", sn.Items.Select(i => i.Tekst)) == "melk,kaas"
            && sn.Gewijzigd == new DateTime(2026, 9, 27, 10, 0, 0, 123, DateTimeKind.Utc), "sync velden");
        rij.Gewijzigd = rij.Gewijzigd.AddSeconds(-1);
        Is(!Sync.Verwerk(rij, null), "sync ouder wint niet");
        rij.Gewijzigd = rij.Gewijzigd.AddSeconds(5);
        rij.Verwijderd = true;
        Is(Sync.Verwerk(rij, null) && !Opslag.Data.Notities.Any(n => n.Id == id), "sync zacht verwijderd");
        Is(Sync.Iso(new DateTime(2026, 9, 27, 10, 0, 0, 5, DateTimeKind.Utc)) == "2026-09-27T10:00:00.005Z", "iso");

        var tekst = fouten.Count == 0 ? "OK" : "FOUT " + string.Join("; ", fouten);
        if (uit != null) File.WriteAllText(uit, tekst);
        return fouten.Count == 0 ? 0 : 1;
    }
}
