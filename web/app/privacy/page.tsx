import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Privacy · Kniv",
  description: "Privacybeleid van Kniv / Kniv privacy policy",
};

const MAIL = "josh.kramer2004@gmail.com";

export default function Privacy() {
  return (
    <main className="wrap stapel tekstpagina">
      <header className="hero">
        <a href="/">
          <img src="/icon-256.png" alt="Kniv" width={72} height={72} style={{ width: 72, height: 72, borderRadius: 16 }} />
        </a>
        <h1>Privacy</h1>
        <nav className="taal">
          <a href="#nl">Nederlands</a>
          <a href="#en">English</a>
        </nav>
      </header>

      <article className="glas" id="nl" lang="nl">
        <h2 style={{ marginTop: 0 }}>Privacybeleid</h2>
        <p className="zacht klein">Laatst bijgewerkt: 14 oktober 2026</p>
        <p>
          Kniv is een app van Josh Kramer. Dit beleid legt uit welke gegevens Kniv gebruikt en waarom. Kort gezegd: zo
          weinig mogelijk, en nooit om te verkopen.
        </p>

        <h2>Inloggen met Google</h2>
        <p>
          Je logt in met je Google-account. Kniv krijgt dan je <b>naam</b>, <b>e-mailadres</b> en <b>profielfoto</b>.
          Die gebruiken we om je account te herkennen en om je naam en profielbolletje te tonen aan mensen met wie je
          iets deelt.
        </p>

        <h2>Wat we opslaan</h2>
        <ul>
          <li>
            De <b>tekst</b> van notities en lijstjes die je synchroniseert met je andere apparaten of deelt met anderen
            (inclusief tekst die uit een foto is gehaald).
          </li>
          <li>Welke groepen je deelt en wie daarin zit.</li>
          <li>Bij Talen: welke talen je leert, je leesstukjes en de woorden die je bewaart.</li>
          <li>Hoe vaak je de slimme functies (AI) gebruikt, zodat er een daglimiet kan gelden.</li>
        </ul>
        <p>
          <b>Foto's blijven op je telefoon.</b> Spraakopnames ook, behalve in het geval hieronder. Dingen die je op
          &quot;privé&quot; zet, verlaten je telefoon nooit.
        </p>

        <h2>Slimme functies</h2>
        <p>
          Het meeste doet je iPhone zelf. Lukt dat niet, dan gaat alleen dat ene stukje via Kniv naar <b>Groq</b>, een
          AI-dienst uit de VS:
        </p>
        <ul>
          <li>Verstond je iPhone een spraakopname niet goed, dan gaat die opname naar Groq om hem uit te schrijven.</li>
          <li>
            Bij Talen gaat de tekst van je vraag naar Groq (een stukje maken, een woord opzoeken, een zin nakijken, een
            gesprekje) als je iPhone die taal niet zelf kan.
          </li>
        </ul>
        <p>Groq krijgt daarbij geen naam of e-mailadres. Kniv bewaart de opname niet op de server.</p>

        <h2>Waar het staat</h2>
        <p>
          De gegevens staan bij Supabase, in een datacenter in de <b>EU (Frankfurt, Duitsland)</b>. Alles is beveiligd
          zodat je alleen je eigen gegevens ziet en die van groepen waar je lid van bent. Een deellink laat de inhoud
          van die ene groep zien aan wie de link heeft, tot de link verloopt.
        </p>

        <h2>Wat we niet doen</h2>
        <ul>
          <li>Geen verkoop van gegevens.</li>
          <li>Geen tracking, geen analytics van derden.</li>
          <li>Geen advertenties.</li>
        </ul>

        <h2>Verwijderen</h2>
        <p>
          In de app ga je naar <b>Instellingen → Account verwijderen</b>. Dan worden je account en al je gegevens
          gewist. Lijstjes die je met anderen deelt, gaan over op het lid dat er het langst in zit. Uitgaven die je in
          het potje van iemand anders zette, blijven in dat potje staan, zodat de stand voor de anderen blijft kloppen.
        </p>

        <h2>Contact</h2>
        <p>
          Vragen of een verzoek over je gegevens? Mail naar <a href={`mailto:${MAIL}`}>{MAIL}</a>.
        </p>
      </article>

      <article className="glas" id="en" lang="en">
        <h2 style={{ marginTop: 0 }}>Privacy policy</h2>
        <p className="zacht klein">Last updated: 14 October 2026</p>
        <p>
          Kniv is an app made by Josh Kramer. This policy explains which data Kniv uses and why. In short: as little as
          possible, and never to sell.
        </p>

        <h2>Sign in with Google</h2>
        <p>
          You sign in with your Google account. Kniv then receives your <b>name</b>, <b>email address</b> and{" "}
          <b>profile picture</b>. We use these to recognise your account and to show your name and avatar to people you
          share things with.
        </p>

        <h2>What we store</h2>
        <ul>
          <li>
            The <b>text</b> of notes and lists you sync between your devices or share with others (including text
            extracted from a photo).
          </li>
          <li>Which groups you share and who is in them.</li>
          <li>In Languages: which languages you learn, your reading pieces and the words you save.</li>
          <li>How often you use the smart (AI) features, so a daily limit can apply.</li>
        </ul>
        <p>
          <b>Photos stay on your phone.</b> So do voice recordings, except in the case below. Anything you mark as
          &quot;private&quot; never leaves your phone.
        </p>

        <h2>Smart features</h2>
        <p>
          Most of it runs on your iPhone. When that doesn&apos;t work, only that one piece goes through Kniv to{" "}
          <b>Groq</b>, an AI service based in the US:
        </p>
        <ul>
          <li>If your iPhone didn&apos;t understand a voice recording well, that recording goes to Groq to be written out.</li>
          <li>
            In Languages, the text of your request goes to Groq (making a reading piece, looking up a word, checking a
            sentence, a chat) when your iPhone can&apos;t handle that language itself.
          </li>
        </ul>
        <p>Groq doesn&apos;t get your name or email address. Kniv doesn&apos;t keep the recording on the server.</p>

        <h2>Where it is stored</h2>
        <p>
          Data is stored with Supabase in a data centre in the <b>EU (Frankfurt, Germany)</b>. Access is restricted so
          you only see your own data and that of groups you belong to. A share link shows the contents of that one
          group to anyone who has the link, until the link expires.
        </p>

        <h2>What we don&apos;t do</h2>
        <ul>
          <li>No selling of data.</li>
          <li>No tracking, no third-party analytics.</li>
          <li>No advertising.</li>
        </ul>

        <h2>Deleting your data</h2>
        <p>
          In the app, go to <b>Settings → Delete account</b>. This erases your account and all your data. Lists you
          share with others are handed over to the longest-standing member. Expenses you added to someone else&apos;s pot
          stay in that pot, so the totals stay right for the others.
        </p>

        <h2>Contact</h2>
        <p>
          Questions or a request about your data? Email <a href={`mailto:${MAIL}`}>{MAIL}</a>.
        </p>
      </article>

      <footer className="voet">
        <a href="/">Kniv</a>
      </footer>
    </main>
  );
}
