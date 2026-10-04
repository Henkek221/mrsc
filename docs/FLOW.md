# MRSC – Flow-Graph

Ziel: **Jede Sache hat genau einen Ort.** Man sieht zuerst nur das Nötige, der Rest öffnet sich erst, wenn man hinein tippt (Progressive Disclosure).

Drei Ebenen:

1. **Hören:** Home, Library, Search. Hier steht nur Musik, keine Werkzeuge.
2. **Jetzt läuft:** Now Playing. Alles zum aktuellen Song.
3. **Einrichten:** Settings ist die einzige Zentrale. Alles, was die App konfiguriert, liegt dort.

---

## Ist-Zustand (vereinfacht)

```mermaid
flowchart LR
  subgraph Tabs
    Home
    Library
    Search
  end
  Home -- "👤" --> Settings
  Library -- "⚙︎" --> Settings
  Library -- "…" --> ImpA["Import-Menü A<br/>(5 Einträge)"]
  Library -- "+" --> ImpB["Import-Menü B<br/>(3-5 Einträge)"]
  Search -- "+ (classic)" --> ImpC["Import-Popover C<br/>(7-9 Einträge)"]
  Library --> Songs & Playlists & Artists & Albums & Favorites & Recent & Radio & Downloads
  Library --> Studio --> EQ & AudioLab & TrackMix & QueuePresets
  Studio --> XF1["Crossfade 1–12 s"]
  Library --> Files --> Organize & Tags & ImpD["Import-Liste D<br/>(6 Einträge)"]
  Files -- "⚙︎" --> Settings
  Files --> Sources
  Library --> Sources
  Settings --> Sources
  Settings --> AudioLab
  Settings --> XF2["Crossfade 1–12 s"]
  Settings --> Offline1["Offline Mode"]
  Sources --> Offline2["Offline Mode"]
  AudioLab --> TrackMix --> XF3["Crossfade 1–20 s"]
  NowPlaying --> EQSheet["EQ-Sheet"] 
  NowPlaying --> Queue --> XF4["Crossfade-Icon"]
```

Probleme:

- **Import:** 4 verschiedene Import-Menüs, die jeweils andere Optionen anbieten.
- **Doppelte Wege:** Sources ist 3× erreichbar, Audio Lab 4×, Crossfade 4× (mit drei verschiedenen Bereichen).
- **Settings-Zugang:** 3 verschiedene Icons öffnen Settings.
- **Library:** In der Library stehen Werkzeuge (Studio, Files, Sources) zwischen der Musik.
- **Leere Bibliothek:** Alle 11 Zeilen erscheinen mit „0“. Songs und Albums verweisen auf einen „Files tab“, der gar nicht existiert.

---

## Soll-Zustand

```mermaid
flowchart LR
  subgraph Hören
    Home
    Library
    Search
  end
  Library --> Songs & Playlists & Artists & Albums & Favorites & Recent & Radio
  Library -. "nur mit Server" .-> Downloads
  Library -- "+" --> Add
  Home -- "leer" --> Add
  Search -- "+ (classic)" --> Add

  subgraph Add["Add Music (ein Sheet, Schritt für Schritt)"]
    direction TB
    A0{"Woher?"} --> A1["Dateien auf dem iPhone"]
    A0 --> A2["Musik-Ordner<br/>(bleibt synchron)"]
    A0 --> A3["Musik-Server"] --> A3a["Jellyfin / Subsonic → Login"]
    A0 --> A4["Song-Liste einfügen"]
    A0 --> A5["Mehr…<br/>Playlist-/Artist-Ordner,<br/>MRSC-Ordner scannen, Demo"]
  end

  Home -- "⚙︎" --> Settings
  Library -- "⚙︎" --> Settings
  subgraph Settings["Settings (einzige Zentrale)"]
    direction TB
    S1["Sources<br/>Server · Module · Qualität · Offline"]
    S2["Sound<br/>EQ · Audio Lab · Track Mix/Crossfade ·<br/>Wiedergabe · Queue Presets · Sleep"]
    S3["Library & Files<br/>Organize · Tags · Scan · Speicher · Löschen"]
    S4["Customize"]
    S5["Lyrics · Integration · Scrobbling · About"]
  end
  S1 --> Add

  NowPlaying["Now Playing"] -- "EQ" --> EQSheet["EQ-Sheet"]
  NowPlaying --> Queue
```

Regeln:

- **Crossfade** gibt es nur noch in Track Mix. Queue und Now Playing zeigen lediglich den Status.
- **Offline Mode** steht nur in Sources und erscheint erst, wenn eine Streaming-Quelle existiert.
- **„Delete All Music“** gibt es nur unter Library & Files.
- **Leere Bibliothek:** Es erscheint nur die Karte „Add Music“, ohne leere Zeilen.
- **Menüs:** höchstens 6 direkte Einträge, alles Weitere kommt in ein Untermenü.

---

## Phasen

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Settings als einzige Zentrale · ein Add-Music-Flow · Library nur mit Musik · doppelte Einstellungen entfernen · Router-Bugs (Suche bleibt offen, Back-Stack geht verloren) | ✅ fertig, im Simulator getestet |
| 2 | Now Playing & Menüs auf ≤ 6 Einträge · Crossfade/Queue-Status · EQ-Knopf → Sound für diesen Song | offen |
| 3 | Feedback & Sicherheit: Namensabfrage bei „Save Queue as Playlist“, nach dem Song-List-Import zur Playlist springen, Bestätigung vor dem Löschen, Organize-Sackgasse, Cover Designer standardmäßig auf „This Song“ | offen |
| 4 | Erster Start: kurzer Einstieg „Woher kommt deine Musik?“ | ✅ fertig (`Onboarding.swift`), im Simulator getestet |

### Onboarding (Phase 4)

```mermaid
flowchart LR
  L["App-Start<br/>Bibliothek leer, kein Server"] --> H["Hello<br/>Platte fährt ein, dreht sich,<br/>lässt sich anfassen und anschubsen"]
  H -- "Get Started" --> S["Where’s your music?<br/>Platte fährt hoch, 4 Hüllen erscheinen versetzt"]
  H -- "Try the demo" --> Demo["Demo laden"]
  S -- "Hülle auf die Platte ziehen oder tippen" --> C["Hülle fliegt in die Platte,<br/>Label übernimmt Farbe und Icon, Platte dreht hoch"]
  C --> I["Dateiauswahl / Ordner / Add Music → Server / Song-Liste"]
  S -- "Later" --> App
```

- **Bewegung:** Springs statt starrer Kurven. Die Platte hat Schwung und reibt sich langsam auf ihr Tempo im Leerlauf herunter; man kann sie jederzeit wieder greifen.
- **Text:** Headlines erscheinen Buchstabe für Buchstabe aus der Unschärfe (`BlurReveal`, ein TextRenderer).
- **Haptik:** Beim Drehen tickt es an den Rillen, dazu ein Impuls bei „Get Started“, ein leichter Tap, wenn die Hülle über der Platte schwebt, und „Success“ beim Ablegen.
- **„Bewegung reduzieren“:** Keine Einflug- oder Drehanimation mehr, nur Einblendungen.
- **Erneut ansehen:** Settings → About → „Show Welcome Again“. Zum Testen startet die App mit dem Launch-Argument `-forceOnboarding YES` immer im Onboarding.
