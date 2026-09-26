import Kopieer from "./Kopieer";

const BRON = "https://raw.githubusercontent.com/JoshJSP/kniv-releases/main/apps.json";
const WINDOWS = "https://github.com/JoshJSP/kniv-releases/releases/download/win/Kniv-Setup.exe";

const MESJES = [
  ["Vastleggen", "Notities, lijstjes, foto's en spraak"],
  ["Timers", "Focus, countdowns en losse timers"],
  ["Splitten", "Rekening delen en omrekenen"],
  ["Kiezen", "Rad, dobbelsteen, munt en stemmen"],
  ["Scanner", "QR-codes en documenten"],
  ["Meten", "Waterpas, liniaal en geluid"],
];

export default function Installeren() {
  return (
    <main className="wrap stapel">
      <header className="hero">
        <img src="/icon.png" alt="" width={104} height={104} />
        <h1>Kniv</h1>
        <p>Een zakmes vol kleine handige dingen.</p>
      </header>

      <section className="glas">
        <h2>Zes mesjes</h2>
        <p className="zacht">
          Alles wat je even snel nodig hebt, in één app. Werkt offline en synct met je laptop en vrienden.
        </p>
        <div className="mesjes">
          {MESJES.map(([naam, uitleg]) => (
            <div className="mesje" key={naam}>
              <b>{naam}</b>
              <span>{uitleg}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="glas" id="iphone">
        <h2>iPhone</h2>
        <p className="zacht">Kniv staat niet in de App Store; je installeert hem gratis via SideStore.</p>
        <ol className="stappen">
          <li>
            <div>
              Open deze pagina <b>op je iPhone</b> en tik op de knop hieronder.
            </div>
          </li>
          <li>
            <div>SideStore opent en vraagt of je de bron wilt toevoegen. Tik op <b>Toevoegen</b>.</div>
          </li>
          <li>
            <div>
              Ga naar <b>Bladeren</b>, kies <b>Kniv</b> en tik op <b>Installeer</b>.
            </div>
          </li>
        </ol>
        <a className="knop" href={`sidestore://source?url=${BRON}`}>
          Toevoegen aan SideStore
        </a>
        <p className="zacht klein" style={{ marginTop: 16 }}>
          Werkt de knop niet? Kopieer de bron en plak hem in SideStore bij <b>Bronnen → +</b>.
        </p>
        <Kopieer tekst={BRON} />
        <details style={{ marginTop: 16 }}>
          <summary style={{ cursor: "pointer", fontWeight: 600 }}>Nog geen SideStore?</summary>
          <p className="klein" style={{ marginTop: 10 }}>
            SideStore installeert apps met je eigen (gratis) Apple-ID, zonder App Store. Je zet het één keer op met
            een computer; daarna ververst het zichzelf op je iPhone. Volg de uitleg op{" "}
            <a href="https://sidestore.io" target="_blank" rel="noopener">
              sidestore.io
            </a>{" "}
            en kom daarna terug naar deze pagina.
          </p>
        </details>
      </section>

      <section className="glas" id="windows">
        <h2>Windows</h2>
        <p className="zacht">Kniv voor je laptop, met alle mesjes en een sneltoets (Win + Shift + K).</p>
        <a className="knop" href={WINDOWS}>
          Download voor Windows
        </a>
        <p className="klein" style={{ marginTop: 16 }}>
          Windows kent Kniv nog niet en laat misschien een blauw scherm zien (SmartScreen). Klik dan op{" "}
          <b>Meer info</b> en daarna op <b>Toch uitvoeren</b>.
        </p>
      </section>

      <footer className="voet">
        <a href="/privacy">Privacy</a>
      </footer>
    </main>
  );
}
