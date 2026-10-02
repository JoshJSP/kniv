using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.UI.Dispatching;

namespace Kniv;

// Inloggen met Google en notities synchroniseren via Supabase, volgens supabase/SYNC.md.
// Gewone HTTP (GoTrue + PostgREST) en een kale Realtime-websocket: geen extra pakketten, alles op de UI-thread.

public class Sessie
{
    public string AccessToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public long VerlooptOp { get; set; }        // unix-seconden
    public Guid Id { get; set; }
    public string Email { get; set; } = "";
    public string Naam { get; set; } = "";
}

/// Eén rij uit public.records zoals PostgREST hem geeft.
public class Rij
{
    [JsonPropertyName("id")] public Guid Id { get; set; }
    [JsonPropertyName("eigenaar")] public Guid Eigenaar { get; set; }
    [JsonPropertyName("groep")] public Guid? Groep { get; set; }
    [JsonPropertyName("soort")] public string Soort { get; set; } = "";
    [JsonPropertyName("data")] public JsonElement Data { get; set; }
    [JsonPropertyName("gewijzigd")] public DateTimeOffset Gewijzigd { get; set; }
    [JsonPropertyName("gewijzigd_door")] public Guid? GewijzigdDoor { get; set; }
    /// Door de server gezet bij elke wijziging; de ophaalcursor (niet de klok van een apparaat).
    [JsonPropertyName("ontvangen")] public DateTimeOffset? Ontvangen { get; set; }
    [JsonPropertyName("verwijderd")] public bool Verwijderd { get; set; }
}

public static class Sync
{
    public const string Url = "https://ykptlgckqppgxirtndch.supabase.co";
    public const string Sleutel = "sb_publishable_5oWWatyeuq3o-w3Qw_R_jA_qo5Tjv_l";   // publishable: mag in de app
    const int Poort = 53682;
    static readonly string Terug = $"http://localhost:{Poort}/auth";
    static string SessieBestand => Path.Combine(Opslag.Map, "sessie.bin");
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    public static Sessie? Wie { get; private set; }
    public static string Status { get; private set; } = "";
    public static DateTime? Laatst { get; private set; }
    public static event Action? Veranderd;

    static DispatcherQueueTimer? _elke15, _straks;
    static bool _bezig, _nogmaals;
    static CancellationTokenSource? _realtime, _inlog;
    static TcpListener? _luister;
    static readonly Dictionary<Guid, string> Namen = new();

    public static void Start()
    {
        try
        {
            if (File.Exists(SessieBestand))
                Wie = JsonSerializer.Deserialize<Sessie>(ProtectedData.Unprotect(File.ReadAllBytes(SessieBestand), null, DataProtectionScope.CurrentUser));
        }
        catch (Exception e) { App.Log(e); Wie = null; }

        var t = _elke15 = App.Ui.CreateTimer();       // vasthouden, anders ruimt de GC hem op
        t.Interval = TimeSpan.FromSeconds(15);
        t.Tick += (_, _) => _ = Nu();
        t.Start();
        var s = _straks = App.Ui.CreateTimer();       // kort na een lokale wijziging meteen versturen
        s.Interval = TimeSpan.FromSeconds(1.5);
        s.IsRepeating = false;
        s.Tick += (_, _) => _ = Nu();
        Opslag.Gewijzigd += () => { if (Wie != null && !_bezig) { s.Stop(); s.Start(); } };

        if (Wie != null) { StartRealtime(); _ = Nu(); }
    }

    static void Zet(string s) { Status = s; Veranderd?.Invoke(); }

    // ---------------------------------------------------------------- inloggen (PKCE via loopback)

    static string Base64Url(byte[] b) => Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public static async Task Inloggen()
    {
        _inlog?.Cancel();   // nieuwe klik: de vorige poging afbreken, zodat de poort vrijkomt
        _luister?.Stop();
        using var stop = _inlog = new CancellationTokenSource(TimeSpan.FromMinutes(5));
        TcpListener luister;
        try { luister = _luister = new TcpListener(IPAddress.Loopback, Poort); luister.Start(); }
        catch (SocketException) { _inlog = null; Zet($"Poort {Poort} is bezet. Sluit het andere inlogvenster en probeer opnieuw."); return; }
        try
        {
            var verifier = Base64Url(RandomNumberGenerator.GetBytes(48));
            var challenge = Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
            var url = $"{Url}/auth/v1/authorize?provider=google&redirect_to={Uri.EscapeDataString(Terug)}&code_challenge={challenge}&code_challenge_method=s256";
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            Zet("Log in via je browser…");

            string? code = null, fout = null;
            while (code == null && fout == null)
            {
                using var client = await luister.AcceptTcpClientAsync(stop.Token);
                // Een lege of blijven hangende verbinding (browser-preconnect) mag de login niet afbreken.
                using var kort = CancellationTokenSource.CreateLinkedTokenSource(stop.Token);
                kort.CancelAfter(TimeSpan.FromSeconds(10));
                try
                {
                    var stroom = client.GetStream();
                    var lezer = new StreamReader(stroom, Encoding.ASCII);
                    var regel = await lezer.ReadLineAsync(kort.Token) ?? "";            // GET /auth?code=… HTTP/1.1
                    while (!string.IsNullOrEmpty(await lezer.ReadLineAsync(kort.Token))) { }
                    var pad = regel.Split(' ').ElementAtOrDefault(1) ?? "";
                    if (!pad.StartsWith("/auth")) { await Antwoord(stroom, "404 Not Found", ""); continue; }   // favicon e.d.
                    var q = System.Web.HttpUtility.ParseQueryString(new Uri("http://localhost" + pad).Query);
                    code = q["code"];
                    fout = code == null ? q["error_description"] ?? q["error"] ?? "Er kwam geen inlogcode terug." : null;
                    await Antwoord(stroom, "200 OK", fout == null
                        ? "<h2>Je bent ingelogd bij Kniv.</h2><p>Je kunt dit tabblad sluiten.</p>"
                        : $"<h2>Inloggen lukte niet</h2><p>{WebUtility.HtmlEncode(fout)}</p>");
                }
                catch (Exception e) when (!stop.IsCancellationRequested) { App.Log("Inlogverbinding: " + e.Message); }
            }
            if (fout != null) { Zet("Inloggen lukte niet: " + fout); return; }

            var r = await Http.SendAsync(Verzoek(HttpMethod.Post, "/auth/v1/token?grant_type=pkce", null, new { auth_code = code, code_verifier = verifier }));
            if (!r.IsSuccessStatusCode) { Zet("Inloggen lukte niet (" + (int)r.StatusCode + ")."); App.Log(await r.Content.ReadAsStringAsync()); return; }
            BewaarSessie(await r.Content.ReadFromJsonAsync<JsonElement>());
            Zet("Ingelogd. Synchroniseren…");
            StartRealtime();
            await Nu();
        }
        catch (Exception) when (_inlog != stop) { }   // afgebroken door een nieuwe klik
        catch (OperationCanceledException) { Zet("Inloggen duurde te lang. Probeer het nog eens."); }
        catch (Exception e) { App.Log(e); Zet("Inloggen lukte niet. Geen internet?"); }
        finally
        {
            luister.Stop();
            if (_inlog == stop) { _inlog = null; _luister = null; }
        }
    }

    static async Task Antwoord(NetworkStream s, string status, string body)
    {
        var html = $"<!doctype html><meta charset=utf-8><title>Kniv</title><body style=\"font-family:Segoe UI,sans-serif;text-align:center;padding-top:15vh\">{body}</body>";
        var bytes = Encoding.UTF8.GetBytes(html);
        var kop = Encoding.ASCII.GetBytes($"HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {bytes.Length}\r\nConnection: close\r\n\r\n");
        await s.WriteAsync(kop);
        await s.WriteAsync(bytes);
        await s.FlushAsync();
    }

    /// Antwoord van /auth/v1/token → Sessie, versleuteld (DPAPI, alleen deze Windows-gebruiker) op schijf.
    static void BewaarSessie(JsonElement j)
    {
        var user = j.GetProperty("user");
        var meta = user.TryGetProperty("user_metadata", out var m) ? m : default;
        string? Tekst(JsonElement e, string naam) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(naam, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        var verloopt = j.TryGetProperty("expires_at", out var ea) ? ea.GetInt64() : DateTimeOffset.UtcNow.ToUnixTimeSeconds() + j.GetProperty("expires_in").GetInt64();
        Wie = new Sessie
        {
            AccessToken = j.GetProperty("access_token").GetString()!,
            RefreshToken = j.GetProperty("refresh_token").GetString()!,
            VerlooptOp = verloopt,
            Id = Guid.Parse(user.GetProperty("id").GetString()!),
            Email = Tekst(user, "email") ?? "",
            Naam = Tekst(meta, "full_name") ?? Tekst(meta, "name") ?? "",
        };
        Directory.CreateDirectory(Opslag.Map);
        var tmp = SessieBestand + ".tmp";
        File.WriteAllBytes(tmp, ProtectedData.Protect(JsonSerializer.SerializeToUtf8Bytes(Wie), null, DataProtectionScope.CurrentUser));
        File.Move(tmp, SessieBestand, true);
        // Na een verlopen sessie bleef alles staan: een ander account begint schoon, dezelfde gebruiker verstuurt de rest alsnog.
        var d = Opslag.Data;
        if (d.SyncVan != Wie.Id)
        {
            if (d.SyncVan != null) Opruimen();
            d.SyncVan = Wie.Id;
            Opslag.Bewaar();
        }
        Veranderd?.Invoke();
    }

    public static async Task Uitloggen()
    {
        while (_bezig) await Task.Delay(100);
        await Nu();   // eerst nog versturen wat er ligt
        var token = Wie?.AccessToken;
        Afmelden();
        Opruimen();
        Opslag.Bewaar();
        Zet("Uitgelogd.");
        if (token != null)
            try { await Http.SendAsync(Verzoek(HttpMethod.Post, "/auth/v1/logout", token)); } catch (Exception) { }
    }

    static void Afmelden()
    {
        Wie = null;
        _realtime?.Cancel();
        try { File.Delete(SessieBestand); } catch (IOException) { }
        Laatst = null;
    }

    /// Gedeelde lijsten zijn van de groep, niet van deze pc; eigen notities blijven gewoon lokaal staan.
    static void Opruimen()
    {
        var d = Opslag.Data;
        d.Notities.RemoveAll(n => n.Groep != null);
        foreach (var n in d.Notities) n.Eigenaar = null;
        d.Gesynct.Clear();
        d.Weg.Clear();
        d.OpgehaaldTot = null;
        d.SyncVan = null;
    }

    /// Geldig toegangstoken; ververst hem een minuut voor hij verloopt.
    static async Task<string?> Token()
    {
        if (Wie == null) return null;
        if (DateTimeOffset.FromUnixTimeSeconds(Wie.VerlooptOp) > DateTimeOffset.UtcNow.AddMinutes(1)) return Wie.AccessToken;
        var r = await Http.SendAsync(Verzoek(HttpMethod.Post, "/auth/v1/token?grant_type=refresh_token", null, new { refresh_token = Wie.RefreshToken }));
        if (r.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized)
        {
            App.Log("Verversen geweigerd: " + await r.Content.ReadAsStringAsync());
            Afmelden();   // Weg en onverstuurde wijzigingen blijven staan tot dezelfde gebruiker weer inlogt
            Zet("Je sessie is verlopen. Log opnieuw in.");
            return null;
        }
        r.EnsureSuccessStatusCode();
        BewaarSessie(await r.Content.ReadFromJsonAsync<JsonElement>());
        StartRealtime();   // opnieuw aanmelden met het nieuwe token
        return Wie!.AccessToken;
    }

    static HttpRequestMessage Verzoek(HttpMethod methode, string pad, string? token, object? body = null, string? prefer = null)
    {
        var v = new HttpRequestMessage(methode, Url + pad);
        v.Headers.Add("apikey", Sleutel);
        if (token != null) v.Headers.Authorization = new("Bearer", token);
        if (prefer != null) v.Headers.Add("Prefer", prefer);
        if (body != null) v.Content = JsonContent.Create(body);
        return v;
    }

    // ---------------------------------------------------------------- synchroniseren

    public static string Iso(DateTime utc) => utc.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture);

    /// Afgerond op milliseconden, zodat de tijd na een rondje via de server precies gelijk blijft.
    public static DateTime Ms(DateTime utc) => new(utc.Ticks - utc.Ticks % TimeSpan.TicksPerMillisecond, DateTimeKind.Utc);

    public static async Task Nu()
    {
        if (Wie == null) return;
        if (_bezig) { _nogmaals = true; return; }
        _bezig = true;
        try
        {
            do { _nogmaals = false; await Ronde(); } while (_nogmaals && Wie != null);
            if (Wie != null) { Laatst = DateTime.Now; Zet(""); }
        }
        catch (Exception e)
        {
            App.Log(e);
            Zet("Synchroniseren lukt nu niet. Kniv probeert het zo weer.");
        }
        finally { _bezig = false; }
    }

    /// Alle (niet verwijderde) records van één soort van jezelf; null als je niet ingelogd of offline bent.
    /// Voor Mijn woorden: alleen lezen, los van de notitie-sync en zijn ophaalcursor.
    public static async Task<List<Rij>?> HaalSoort(string soort)
    {
        if (await Token() is not { } token) return null;
        try
        {
            var r = await Http.SendAsync(Verzoek(HttpMethod.Get,
                $"/rest/v1/records?select=*&soort=eq.{Uri.EscapeDataString(soort)}&verwijderd=eq.false&order=gewijzigd.desc&limit=2000", token));
            return r.IsSuccessStatusCode ? await r.Content.ReadFromJsonAsync<List<Rij>>() : null;
        }
        catch (HttpRequestException) { return null; }
        catch (TaskCanceledException) { return null; }
    }

    static async Task Ronde()
    {
        if (await Token() is not { } token) return;
        var d = Opslag.Data;
        var veranderd = false;

        // 1. Ophalen op servertijd ('ontvangen'), zodat ook offline gemaakte wijzigingen van andere apparaten binnenkomen.
        var eersteKeer = d.OpgehaaldTot == null;
        // Een minuut marge: een transactie die eerder begon kan later zichtbaar worden. Verwerk is idempotent.
        var filter = eersteKeer ? "" : "&ontvangen=gte." + Uri.EscapeDataString(Iso(d.OpgehaaldTot!.Value.AddMinutes(-1)));
        var r = await Http.SendAsync(Verzoek(HttpMethod.Get, $"/rest/v1/records?select=*&soort=eq.notitie{filter}&order=ontvangen.asc&limit=1000", token));
        r.EnsureSuccessStatusCode();
        var rijen = await r.Content.ReadFromJsonAsync<List<Rij>>() ?? new();
        var anderen = new List<(Guid door, string titel)>();
        foreach (var rij in rijen)
        {
            veranderd |= Verwerk(rij, eersteKeer ? null : anderen);
            var t = (rij.Ontvangen ?? rij.Gewijzigd).UtcDateTime;
            if (d.OpgehaaldTot == null || t > d.OpgehaaldTot) d.OpgehaaldTot = t;
        }
        if (rijen.Count == 1000) _nogmaals = true;

        // 2. Versturen wat hier veranderd is (laatste wijziging wint, upsert op id).
        var vuil = d.Notities.Where(n => !d.Gesynct.TryGetValue(n.Id, out var t) || n.Gewijzigd > t).ToList();
        if (vuil.Count > 0)
        {
            // Vóór het versturen vastleggen wat er weggaat: wie tijdens de upload verder typt, blijft vuil.
            var pakket = vuil.Select(n =>
            {
                n.Gewijzigd = Ms(n.Gewijzigd);
                n.Eigenaar ??= Wie!.Id;   // aangeboden: verwijderen maakt vanaf nu een Weg-regel
                return (n.Id, tijd: n.Gewijzigd, rij: NaarRij(n));
            }).ToList();
            const string upsert = "resolution=merge-duplicates,return=minimal";
            var p = await Http.SendAsync(Verzoek(HttpMethod.Post, "/rest/v1/records", token, pakket.Select(x => x.rij).ToList(), upsert));
            if (p.IsSuccessStatusCode) foreach (var x in pakket) d.Gesynct[x.Id] = x.tijd;
            else
            {   // één kapotte rij mag de rest niet tegenhouden
                App.Log("Upsert: " + await p.Content.ReadAsStringAsync());
                foreach (var x in pakket)
                {
                    var een = await Http.SendAsync(Verzoek(HttpMethod.Post, "/rest/v1/records", token, new[] { x.rij }, upsert));
                    if (een.IsSuccessStatusCode) d.Gesynct[x.Id] = x.tijd;
                    else App.Log($"Upsert {x.Id}: {await een.Content.ReadAsStringAsync()}");
                }
            }
            veranderd = true;
        }

        // 3. Zacht verwijderen.
        foreach (var (id, tijd) in d.Weg.ToList())
        {
            var w = await Http.SendAsync(Verzoek(new HttpMethod("PATCH"), $"/rest/v1/records?id=eq.{id}", token,
                new { verwijderd = true, gewijzigd = Iso(tijd), gewijzigd_door = Wie!.Id }, "return=representation"));
            if (!w.IsSuccessStatusCode) { App.Log($"Verwijderen {id}: {await w.Content.ReadAsStringAsync()}"); continue; }
            d.Weg.Remove(id);
            d.Gesynct.Remove(id);
            // De trigger negeert een verwijdering die ouder is dan de laatste wijziging (en geeft toch 2xx): die wijziging wint.
            foreach (var rij in await w.Content.ReadFromJsonAsync<List<Rij>>() ?? new())
                if (!rij.Verwijderd) Verwerk(rij, null);
            veranderd = true;
        }

        if (veranderd) Opslag.Bewaar();
        _straks?.Stop();   // onze eigen Bewaar hoeft geen nieuwe ronde

        foreach (var (door, titel) in anderen.Take(3))
            Meldingen.Toon("Gedeelde lijst aangepast", $"{await Naam(door, token)} heeft \"{titel}\" aangepast.");
    }

    static object NaarRij(Notitie n) => new
    {
        id = n.Id,
        eigenaar = n.Eigenaar ?? Wie!.Id,
        groep = n.Groep,
        soort = "notitie",
        data = new
        {
            tekst = n.Tekst,
            fotoTekst = n.FotoTekst ?? "",
            bakje = n.Bakje,
            gemaakt = Iso(n.Gemaakt),
            items = n.Items.Select((i, k) => new { tekst = i.Tekst, volgorde = k, door = i.Door }).ToList(),
        },
        gewijzigd = Iso(n.Gewijzigd),
        gewijzigd_door = Wie!.Id,
        verwijderd = false,
    };

    /// Eén rij van de server toepassen. True = er veranderde lokaal iets. anderen = null: niet melden (eerste keer ophalen).
    public static bool Verwerk(Rij r, List<(Guid, string)>? anderen)
    {
        var d = Opslag.Data;
        if (r.Soort != "notitie") return false;
        var tijd = r.Gewijzigd.UtcDateTime;
        if (d.Weg.TryGetValue(r.Id, out var weg))
        {
            if (tijd <= weg) return false;   // hier verwijderd, en dat is nieuwer
            d.Weg.Remove(r.Id);              // elders daarna nog gewijzigd: die wijziging wint
        }
        var n = d.Notities.FirstOrDefault(x => x.Id == r.Id);
        if (n != null && tijd <= n.Gewijzigd) return false;       // hier is hij nieuwer (of gelijk)
        var vanAnder = anderen != null && r.Groep != null && r.GewijzigdDoor is { } door && door != Wie?.Id;

        if (r.Verwijderd)
        {
            if (n == null) return false;
            d.Notities.Remove(n);
            d.Gesynct.Remove(n.Id);
            if (vanAnder) anderen!.Add((r.GewijzigdDoor!.Value, n.Titel));
            return true;
        }

        var j = r.Data;
        string? S(string naam) => j.ValueKind == JsonValueKind.Object && j.TryGetProperty(naam, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        if (n == null) { n = new Notitie { Id = r.Id }; d.Notities.Insert(0, n); }
        n.Tekst = S("tekst") ?? "";
        n.FotoTekst = S("fotoTekst") is { Length: > 0 } ft ? ft : null;
        n.Bakje = S("bakje");
        n.Gemaakt = DateTimeOffset.TryParse(S("gemaakt"), out var g) ? g.UtcDateTime : tijd;
        n.Gewijzigd = tijd;
        n.Eigenaar = r.Eigenaar;
        n.Groep = r.Groep;
        var pak = LijstItem.Koppel(n.Items);
        n.Items = j.ValueKind == JsonValueKind.Object && j.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray()
                .Select(i => (tekst: i.TryGetProperty("tekst", out var t) ? t.GetString() ?? "" : "",
                              volgorde: i.TryGetProperty("volgorde", out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : 0,
                              door: i.TryGetProperty("door", out var dd) && dd.ValueKind == JsonValueKind.String && Guid.TryParse(dd.GetString(), out var gd) ? gd : (Guid?)null))
                .OrderBy(i => i.volgorde)
                .Select(i => new LijstItem { Id = pak(i.tekst)?.Id ?? Guid.NewGuid(), Tekst = i.tekst, Door = i.door })
                .ToList()
            : new();
        if (n.Bakje == null)
        {
            var namen = d.Bakjes.Select(b => b.Naam).ToList();
            n.Twijfel = Sorteerder.Sorteer(n.ZoekTekst, namen, d.Geleerd);
            if (n.Twijfel.Count < 2) n.Twijfel = namen.Take(2).ToList();
        }
        else
        {
            n.Twijfel = new();
            if (!d.Bakjes.Any(b => b.Naam == n.Bakje)) d.Bakjes.Add(new Bakje { Naam = n.Bakje });   // eigen bakje van de telefoon
        }
        d.Gesynct[n.Id] = tijd;
        if (vanAnder) anderen!.Add((r.GewijzigdDoor!.Value, n.Titel));
        return true;
    }

    static async Task<string> Naam(Guid id, string token)
    {
        if (Namen.TryGetValue(id, out var naam)) return naam;
        try
        {
            var r = await Http.SendAsync(Verzoek(HttpMethod.Get, $"/rest/v1/profielen?select=naam&id=eq.{id}", token));
            var lijst = await r.Content.ReadFromJsonAsync<List<JsonElement>>();
            naam = lijst?.FirstOrDefault().ValueKind == JsonValueKind.Object ? lijst[0].GetProperty("naam").GetString() ?? "" : "";
        }
        catch (Exception) { naam = ""; }
        return Namen[id] = naam == "" ? "Iemand" : naam;
    }

    // ---------------------------------------------------------------- realtime: een seintje, daarna gewoon ophalen

    static void StartRealtime()
    {
        _realtime?.Cancel();
        var stop = _realtime = new CancellationTokenSource();
        _ = Task.Run(() => RealtimeLus(stop.Token));
    }

    static async Task RealtimeLus(CancellationToken stop)
    {
        while (!stop.IsCancellationRequested && Wie is { } wie)
        {
            try
            {
                using var ws = new ClientWebSocket();
                await ws.ConnectAsync(new Uri($"{Url.Replace("https://", "wss://")}/realtime/v1/websocket?apikey={Sleutel}&vsn=1.0.0"), stop);
                async Task Stuur(object o) => await ws.SendAsync(JsonSerializer.SerializeToUtf8Bytes(o), WebSocketMessageType.Text, true, stop);
                await Stuur(new
                {
                    topic = "realtime:kniv-records", @event = "phx_join", @ref = "1", join_ref = "1",
                    payload = new { config = new { postgres_changes = new[] { new { @event = "*", schema = "public", table = "records" } } }, access_token = wie.AccessToken },
                });
                using var hart = CancellationTokenSource.CreateLinkedTokenSource(stop);   // stopt de hartslag als deze verbinding eindigt
                var ht = hart.Token;
                _ = Task.Run(async () =>
                {
                    try
                    {
                        for (var i = 2; ws.State == WebSocketState.Open && !ht.IsCancellationRequested; i++)
                        {
                            await Task.Delay(TimeSpan.FromSeconds(25), ht);
                            await Stuur(new { topic = "phoenix", @event = "heartbeat", payload = new { }, @ref = i.ToString() });
                        }
                    }
                    catch (Exception) { }   // gestopt of verbinding weg: de ontvangstlus merkt het zelf
                });

                var buf = new byte[16 * 1024];
                try
                {
                    while (ws.State == WebSocketState.Open)
                    {
                        using var bericht = new MemoryStream();
                        WebSocketReceiveResult ontvangen;
                        do
                        {
                            ontvangen = await ws.ReceiveAsync(buf, stop);
                            bericht.Write(buf, 0, ontvangen.Count);
                        } while (!ontvangen.EndOfMessage && ontvangen.MessageType != WebSocketMessageType.Close);
                        if (ontvangen.MessageType == WebSocketMessageType.Close) break;
                        var tekst = Encoding.UTF8.GetString(bericht.ToArray());
                        if (tekst.Contains("\"postgres_changes\"")) App.Ui.TryEnqueue(() => _ = Nu());
                        else if (tekst.Contains("\"phx_error\"") || tekst.Contains("\"status\":\"error\"")) { App.Log("Realtime: " + tekst); break; }
                    }
                }
                finally { hart.Cancel(); }
            }
            catch (OperationCanceledException) { return; }
            catch (Exception e) { App.Log("Realtime: " + e.Message); }
            try { await Task.Delay(TimeSpan.FromSeconds(30), stop); } catch (OperationCanceledException) { return; }
        }
    }
}

/// Beheerpaneel voor Josh: alleen als %LOCALAPPDATA%\Kniv\beheer.env bestaat. De secret key staat alleen daar.
public static class Beheer
{
    static string Bestand => Path.Combine(Opslag.Map, "beheer.env");
    public static bool Beschikbaar => File.Exists(Bestand);

    public record Cijfers(long Gebruikers, long ActiefVandaag, string? PopulairsteSoort);

    public static async Task<Cijfers> Haal()
    {
        var env = File.ReadAllLines(Bestand).Select(l => l.Split('=', 2)).Where(p => p.Length == 2)
            .ToDictionary(p => p[0].Trim(), p => p[1].Trim().Trim('"'));
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        var v = new HttpRequestMessage(HttpMethod.Get, env["SUPABASE_URL"].TrimEnd('/') + "/rest/v1/beheer_cijfers?select=*");
        v.Headers.Add("apikey", env["SUPABASE_SECRET"]);
        var r = await http.SendAsync(v);
        r.EnsureSuccessStatusCode();
        var rij = (await r.Content.ReadFromJsonAsync<List<JsonElement>>())![0];
        return new(rij.GetProperty("gebruikers").GetInt64(), rij.GetProperty("actief_vandaag").GetInt64(),
            rij.GetProperty("populairste_soort").ValueKind == JsonValueKind.String ? rij.GetProperty("populairste_soort").GetString() : null);
    }
}
