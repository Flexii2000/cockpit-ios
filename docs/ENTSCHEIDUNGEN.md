# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

## 2026-10-09 — Healthy: Logbook als Seite im Dashboard, Speichern von Hand
Felix hat entschieden (Plan vom 09.10.): Logbook nach dem Whoop-Prinzip, die
Daten beim Weight Tracker, eine Karte im Dashboard und eine eigene Seite, kein
sechster Tab; Ja/Nein, optional mit Einheit und Menge; ein gespeicherter Tag
heißt „nicht Angetipptes = nein", ein nie gespeicherter fehlt; Erinnerung um
09:00 nur bei offenem Vortag. In der App:
- **Tag von gestern bis vor 14 Tagen, Vorgabe gestern**, mit ‹ ›. Heute nicht:
  eingetragen wird ein Tag, wenn er vorbei ist, und seine Wirkung misst die
  Recovery am Morgen danach. **Verworfen:** auch heute anbieten (der Dienst
  nähme es) - ein halber Tag sähe gespeichert aus.
- **„Speichern" von Hand**, und erst dann ist der Tag ausgefüllt. Geschickt
  wird nur, was an ist; den Rest setzt der Dienst auf 0. **Verworfen:** jeden
  Tipp sofort speichern (ein einziger Tipp machte aus allen anderen ein
  „nein"); ausdrücklich Nullen schicken (gleiches Ergebnis, aber eine gerade
  gelöschte Verhaltensweise im Postausgang wäre wieder mitgeschickt worden).
- **Eine angetippte Verhaltensweise mit Einheit braucht eine Menge**; bis dahin
  ist „Speichern" aus. **Verworfen:** 1 vorbelegen - eine erfundene Menge sähe
  hinterher aus wie eine eingetragene.
- **Ein Tag im Postausgang zählt als gespeichert** (Uhr statt Haken, keine
  Erinnerung für ihn): `LogbookMemory` merkt sich Tag und Werte, bis der
  Postausgang leer ist. **Verworfen:** nur den Stand des Dienstes zählen -
  dann käme morgens „gestern offen", obwohl der Tag offline gespeichert ist.
- **Effekte: Farbe nur, wo nach Holm ein Stern steht** (grün besser, orange
  schlechter); Zeilen ohne Effekt (`TOO_FEW`, `NOT_SEPARABLE`) eingeklappt unter
  „Zu wenig Daten (n)" mit dem Stand („3/5 ja · 5/5 nein", „9/14 Tage",
  „fällt aufs Wochenende"). Die Quelle als kleines Symbol (Logbook, coHabit,
  Healthy). **Verworfen:** jede Zahl nach Vorzeichen färben - ein Effekt ohne
  Stern ist noch kein Befund.
- **Karte im Dashboard:** „gestern offen" (bzw. „gestern gespeichert"), die
  ersten drei auswertbaren Effekte in der Reihenfolge des Dienstes und „› alle
  Effekte". **Verworfen:** nur signifikante zeigen - anfangs stünde dort wegen
  Holm lange nichts.
- **Erinnerung**: Kennung `logbook-<Tag, an dem sie kommt>`, 14 Tage voraus; die
  Erlaubnis fragt die App beim Anlegen der ersten Verhaltensweise. Ein Tipp
  öffnet Dashboard und Logbook. **Verworfen:** nach der Erlaubnis beim Start
  fragen (ohne Zusammenhang).
- **Verhalten-Blatt**: Antippen benennt um, nach rechts wischen archiviert
  (bzw. holt zurück), nach links wischen löscht nach Rückfrage - dasselbe im
  Kontextmenü. Nur online. **Verworfen:** ein Bearbeiten-Modus mit eigener
  Seite je Verhaltensweise (für Name und Archiv zu viel Weg).

## 2026-10-09 — Healthy: Dashboard als erster Tab, Recovery als Seite darin
Felix hat entschieden (Plan vom 09.10.): neuer Tab **Dashboard ganz links, die
App macht dort auf**; Recovery (und das Logbook) sind Seiten im Dashboard,
kein eigener Tab; das Layout der Karten ist freigegeben. In der App:
- **Jede Karte fällt für sich aus.** Ein 404 heißt „kennt dieser Dienst noch
  nicht" - die Karte fehlt ohne Meldung, damit die App vor dem Ausrollen des
  Weight Trackers genauso aussieht wie danach ohne Daten. Ein Banner nur bei
  fehlendem Zugang; bei anderen Fehlern bleibt der letzte Stand. **Verworfen:**
  eine Fehlermeldung je Karte (vor dem Ausrollen stünden drei da) und Flags
  „kann Recovery" beim Dienst.
- **Der Ring ohne Zielkerbe** (`GaugeView.showsTarget`) und ohne Unterzeile
  beim Score - daneben oder darüber steht ohnehin „Recovery". Beim Kalibrieren
  „9/14" / „Nächte", ohne Score ein Strich mit dem Grund („Keine Nacht",
  „Keine HRV", „Zu kurz"). **Verworfen:** ein eigener Kreisring statt
  `GaugeView` - der Tacho ist die Form, die man aus dem Essen-Tab kennt.
- **Die Energie-Karte bleibt eine Zeile** und wird lieber etwas kleiner
  (`minimumScaleFactor`), als nach einem „·" umzubrechen. **Verworfen:** drei
  Spalten mit Beschriftung über der Zahl (nicht das freigegebene Layout) und
  ein Umbruch an den Trennern (ein Punkt am Zeilenende sah verloren aus).
- **Eine Mitteilung ohne Art führt in den Essen-Tab** (`HealthyRoute`): die
  APNs-Meldung des Kalorienzählers hat keine, und vorher landete sie nur
  deshalb richtig, weil die App ohnehin dort aufmachte. Die lokale „Vorschlag
  ist fertig" bekommt die Art `quick-capture`. **Verworfen:** dem Dienst eine
  Art beibringen (älteren App-Fassungen wäre sie egal, neueren fehlte sie bis
  zum Ausrollen).
- **Kalorien-Kachel → `healthy://food`, Essen mit heute.** Dafür hat Healthy
  jetzt eine eigene `Info.plist` aus `project.yml` (wie Fokus und coHabit).
  **Verworfen:** die Kachel ohne Link lassen - sie öffnete dann das Dashboard.
- **Die Health-Erlaubnis fragt das Dashboard**, der Gewicht-Tab gleicht nur
  noch ab, wenn es fällig ist. **Verworfen:** weiter im Gewicht-Tab fragen -
  die App macht dort nicht mehr auf, und die neuen Arten (Schlaf, Herz) gehören
  zur Recovery im Dashboard.
- **Eine Offline-Leiste für das Dashboard**, über beide Dienste
  (`OfflineBanner(backends:)`). **Verworfen:** zwei Leisten - die zählten die
  wartenden Änderungen doppelt.
- **Vorführmodus `COCKPIT_DASHBOARD_DEMO=1`** mit erfundenen Werten für
  Dashboard, Recovery und Energie, nur im Speicher. Der Simulator bekommt keine
  Health-Daten, und ohne Nächte gibt es keine Recovery. **Verworfen:** gegen
  einen lokalen Weight Tracker mit eingespielten Nächten (geht zusätzlich, ist
  aber für jede Aufnahme ein Dienst samt Daten).

## 2026-10-09 — Healthy: Energiebilanz im Essen- und im Gewicht-Tab
Felix hat entschieden (Plan vom 09.10.): Verbrauch = Ruhe- + Aktivenergie,
**am Gewicht kalibriert**, Defizit heute als Prognose fürs Tagesende, die
Formate wie im Vertrag §5 auf allen Oberflächen gleich. In der App:
- **Energiezeilen im Tacho-Block unter „von … kcal"**, nicht für Folgetage.
  Neben dem großen Tacho ist die Spalte schmal; passt „Verbrauch ≈ 2.840 kcal ·
  Uhr 3.087 · −8 %" nicht, bricht die Zeile **vor „Uhr"** um (`ViewThatFits`).
  **Verworfen:** die Zeilen über die ganze Breite unter den Tacho - dann
  stünden sie nicht mehr bei „Verzehrt … von …", wo man nach der Bilanz sucht;
  ein freier Umbruch irgendwo in der Zeile.
- **Kurve „Verbrauch ⌀" im Essen-Verlauf vorgewählt, im Gewicht-Diagramm nur
  angeboten**, Indigo `#4338CA`/`#6E7BFF`, gestrichelt (`[4, 4]`), solange ihr
  Fenster nicht ganz vorbei ist - gepunktet sind schon die unvollständigen
  kcal- und Gewichtsmittel. Der Schalter erscheint nur, wenn es einen Verbrauch
  gibt. **Verworfen:** auch im Gewicht-Diagramm vorwählen (dort geht es um
  Kilogramm, und eine fünfte Kurve macht die Zielkurve unleserlich); den
  Schalter immer zeigen (ohne Uhr ein Schalter ohne Kurve).
- **Die Schalter im Essen-Verlauf brechen um** (`FlowLayout` wie im
  Gewicht-Tab), statt seitlich zu scrollen, und die Zeile „Gelb: kcal im
  7-Tage-Mittel …" entfällt - die Schalter sind die Legende. **Verworfen:** die
  Scroll-Leiste behalten - mit fünf Schaltern läge „Gewicht täglich" sicher
  hinter dem Rand.
- **Kacheln** „Defizit ⌀ 7 T", „Verbrauch ⌀ 7 T", „Kalibrierung" hinten in der
  Registry (`WeightWidget`), Werte und Notizen wie im Vertrag; sie sehen über
  `TileInput` neben der Gewichts- auch die Energie-Summary. Ohne Energie zeigen
  sie „–". **Verworfen:** eigene Karte statt Kacheln (die Auswahl je Person
  gäbe es dann nicht).
- **Zahlen ausdrücklich `de_DE`** mit „−" (U+2212), nicht nach der
  Gerätesprache (`GermanNumber`). **Verworfen:** `Double.whole` - auf einem
  englisch eingestellten iPhone stünde „2,610" für zweitausend.
- **Ziehen im Essen-Tab holt nur die Energie aus Health**, nicht Nächte und
  Gewicht. **Verworfen:** den ganzen Abgleich - das Defizit hängt nur am
  Verbrauch, und Ziehen soll schnell sein.

## 2026-10-09 — Healthy liest Energie, Schlaf und Herzwerte aus Health
Teil von Felix' Freigabe „Energiebilanz, Recovery, Dashboard, Logbook" (Plan
und Vertrag `../weight-app/docs/HEALTHY-CONTRACT.md`). Gerechnet wird im
Weight Tracker; die App bildet nur Tage und Nächte, nach den Regeln des
Vertrags, damit iOS und Android dieselbe Nacht schicken.
- **Gelesen:** Gewicht, Schritte, aktive und Ruheenergie, Schlaf, HRV (SDNN,
  ab iOS 27 zusätzlich RMSSD - beide gehen hin, der Dienst wählt),
  Herzfrequenz, Atemfrequenz. **Verworfen:** Hauttemperatur, Sauerstoff und
  Apples Tages-Ruhepuls - sie gehen in das gewählte Modell nicht ein, und jede
  Art mehr ist eine Zeile mehr im Health-Dialog.
- **Die Quelle einer Nacht wird je Aufwachtag gewählt.** Je Quelle wird die
  Hauptschlafphase für den Tag D nach §2.2 gesucht; hat die Uhr eine, zählt nur
  sie, sonst die Quelle, deren Phase die meisten Schlafminuten hat - nie zwei
  zusammen. Der Vertrag sagt „gibt es Segmente der Apple Watch, zählen nur
  diese", aber nicht, worauf sich das bezieht. **Verworfen:** (a) eine Quelle
  für das ganze 14-Nächte-Fenster - eine Nacht mit der Uhr am Ladekabel fiele
  weg, obwohl das iPhone sie hat; (b) „irgendein Segment der Uhr in der Nähe"
  - ein Nickerchen mit Uhr am Vortag verdrängte die Nacht des iPhones. Android
  sollte dieselbe Lesart nehmen.
- **Unplausibles fehlt lieber, als dass es geschickt wird** (HRV außerhalb
  1–400 ms, Puls 20–220, Atem 3–60, Nächte über 24 h). Eine einzige solche Zahl
  lässt beim Dienst die ganze Anfrage mit 400 scheitern. **Verworfen:**
  schicken und den Fehler hinnehmen - dann fehlten alle 14 Nächte.
- **Abgleich höchstens alle zehn Minuten**, Ziehen erzwingt ihn; der
  Gewicht-Tab gleicht nicht mehr bei jedem Erscheinen ab. **Verworfen:** wie
  bisher bei jedem Erscheinen - seit Nächte und Energie dazukommen, wären das
  bei jedem Tabwechsel zwei Uploads.
- **Ein unverändertes Nächte-Fenster geht nicht noch einmal raus** (Hash des
  JSON), beim Weckruf und beim normalen Abgleich; wer zieht, schickt immer.
  **Verworfen:** jedes Mal schicken - die Uhr schreibt Schlaf in Raten, und
  jeder Weckruf hätte 14 Nächte ersetzt, die sich nicht geändert haben.
- **Die Historie kommt einmalig, in Blöcken, nur im Vordergrund und ohne dass
  jemand darauf wartet** (Nächte 365 in 60er-Blöcken, Energie zehn Jahre in
  365er-Blöcken, Cursor nach jedem Block). **Verworfen:** in einem Zug beim
  ersten Start (eine Minute Ladekreisel beim Ziehen) oder im Hintergrund (dort
  hat die App Sekunden, und ein abgebrochener Block käme doppelt).
- **Gesperrtes iPhone: keine Nacht.** HealthKit meldet dann
  `errorDatabaseInaccessible`; jede Abfrage bricht den Nacht-Upload ab
  (`HealthReader.Failure.locked`), `errorNoData` dagegen heißt „leer".

## 2026-10-05 — coHabit: Typfarben wählt jede Person selbst, aus zehn Farben
Torben fand nach der Farbe nach Typ (Eintrag darunter) alles braun: fast alles
sind Streaks, und Pfirsich ist im Dunkeln braun. Entschieden hat Felix:
- **Jede Person wählt die Farbe je Typ** (Streak, Abstinenz, Ziel, Challenge
  und „Automatisch" für alles mit `autoSource`), gespeichert beim Dienst
  (`/me/type-colors`), damit sie auf jedem Gerät, im Web und auf den Kacheln
  gilt. Vorgaben wie bisher. **Verworfen:** feste Typfarben für alle (etwa nur
  eine andere Farbe statt Pfirsich); eine Wahl nur je Gerät - Kacheln, Web und
  ein zweites Gerät wüssten nichts davon.
- **Zehn Farben**: die sechs plus Lavendel, Himmelblau, Salbei, Koralle; mehrere
  Typen dürfen dieselbe haben. **Verworfen:** bei den sechs bleiben.
- **Seite „Farben"** im Profil unter „Benachrichtigungen": fünf Karten in der
  gewählten Farbe, darunter die zehn als Kreise in zwei Reihen zu fünf, ein Tipp
  speichert sofort; keine Erklärtexte, kein Zurücksetzen-Knopf. **Verworfen:**
  eine Farbwahl beim Anlegen je Co-Habit (wie vor dem Nachmittag) - gleiche
  Typen sähen wieder verschieden aus.

In der App: die Kreise zeigen den **Akzent**, nicht die Fläche - Pfirsich und
Koralle sind als helle Fläche kaum zu unterscheiden, die dunklen Flächen
untereinander auch nicht. Der Name auf der Karte steht wie auf „Heute" in
`onSurface` (kräftig auf hell, Tinte auf dunkel); der Vertrag sagt „in der
kräftigen Farbe", die wäre auf der dunklen Fläche aber kaum zu lesen.
**Verworfen:** die kräftige Stufe auch dunkel. Gespeichert wird **nur der
getippte Platz** und sofort angezeigt; lehnt der Dienst ab oder fehlt das Netz,
springt die Wahl zurück und seine Meldung kommt als Toast. **Verworfen:** den
Postausgang - eine Farbe ist keine Änderung, die später genauso gelten muss, und
ein stilles Warten wäre hier verwirrender als ein Zurückspringen.

## 2026-10-05 — coHabit, klassische Liste: Abhakbares vor Lassen
Reihenfolge jetzt Aufbauen → Ziele und Challenges → Lassen → automatisch, in
jeder Gruppe nach Anlegedatum (`classicOrder`). **Warum:** Felix; ein neues
tägliches Habit rutschte unter ältere Lassen-Habits, obwohl man es abhakt und
bei Lassen nur einen Rückfall einträgt. **Verworfen:** (a) nur Aufbauen vor
Lassen, Ziele und Challenges weiter dahinter; (b) heute Offene ganz oben – die
Liste würde sich beim Abhaken umsortieren.

## 2026-10-05 — Feature Requests als Push in Fokus: über das To-Do, Tipp öffnet die Karte
Felix wollte von Fokus benachrichtigt werden, wenn ein Feature Request angelegt
wird. Entschieden hat er:
- **Nur Wünsche von anderen**, seine eigenen melden nichts. **Verworfen:** jede
  Anfrage, auch die eigenen.
- **Der Tipp öffnet die Karte** (Safari), nicht nur den To-Do-Tab. **Verworfen:**
  To-Do-Tab wie bei Erinnerungen — ohne App-Update, aber ein Tipp mehr.
- **Text** „Feature Request · <App>“ / „<Person>: <Titel>“. **Verworfen:** Person
  im Titel; neutraler Titel „Neuer Feature Request“.

Technisch schickt das **To-Do** den Push, nicht der Kalorienzähler: nur das
To-Do kennt die Push-Kennungen von Fokus (`/api/devices`), und die Meldung hängt
so am Anlegen der Unteraufgabe — kommt die erst mit dem Nachlauf, kommt die
Meldung mit, und eine übernommene (schon vorhandene) Aufgabe meldet sich nicht
doppelt. **Verworfen:** ein eigener `/api/notify`-Endpunkt, den der
Kalorienzähler nach dem Anlegen ruft — dann bräuchte jeder Wiederholungsweg
seine eigene Regel, wann gemeldet wird.

## 2026-10-05 — coHabit „Heute": nach Typ wie die klassische Liste, Farbe nach Typ
Felix findet die klassische Liste leichter zu verfolgen als die moderne -
wegen der Reihenfolge nach Typ und der Balken. Entschieden hat er:
- **Reihenfolge wie in der klassischen Liste**, in Liste **und** Dashboard:
  manuelle Streaks, Ziele und Challenges, Abstinenz, automatische (jede mit
  `autoSource`); darin nach Anlegedatum (`createdAt`), ohne Datum nach Name.
  Das Dashboard behält seine Karten (Streaks groß, Ziele/Challenges klein
  paarweise, Abstinenz und automatische groß), nur in dieser Folge.
  **Verworfen:** die bisherige Folge des Dienstes (offen zuerst) - ein
  abgehaktes Co-Habit sprang nach unten.
- **Keine Abschnitte**: eine Liste nach Typ ohne Überschriften; Erledigtes bleibt
  stehen und zeigt den Haken statt des Pfeils. **Verworfen:** „Offen heute" und
  „Läuft".
- **Kennzahl ohne Abkürzung**: Zahl groß, Einheit klein in ganzen Worten
  daneben („17" „Tage"), passt das nicht, darunter (`HeadlineFigure`) - auch im
  Kopf der Detailseite und im Archiv. `headline.short` („3 Wo.") zeigt die App
  nicht mehr. Im Kopf über dem Chat steht die Einheit immer darunter, sonst
  würde der Name gekürzt.
- **Balken** wie beim Ziel für Ziele, Challenges (eigener Stand gegen den
  Zielwert bzw. den Führenden - der Dienst rechnet ihn), Schritte je Woche und
  Fokus-Zeit; keiner für Track food, das kcal-Ziel im Wochenmittel und die
  Evaluation (kein Ziel zum Auffüllen) und für unbekannte Quellen. Manuelle
  Streaks behalten die Punkte der Woche.
- **Farbe nach Typ in der ganzen App** (Heute, Detail, Chat, Timeline,
  Statistik, Profil, Einladungen, Kacheln): Streak Pfirsich, Abstinenz Minze,
  Ziel Flieder, Challenge Butter, automatisch (jeder Typ) Aqua - einmal in
  `CohabitRef.typeColor`. Die gespeicherte Farbe heißt in der App `storedColor`,
  damit keine Ansicht sie aus Versehen nimmt. Anlegen zeigt keine Farbwahl mehr
  und schickt die Typfarbe (so sehen Web und Android dasselbe); Bearbeiten zeigt
  keine und lässt die gespeicherte, wie sie ist. **Verworfen:** eine Farbe je
  Co-Habit - gleiche Typen sahen auf „Heute" verschieden aus. *(Am Abend
  desselben Tages: die Farbe je Typ wählt jede Person selbst, siehe oben.)*

## 2026-10-05 — coHabit: GIFs, Emoji-Reaktionen, Bild in Benachrichtigungen
Felix' Wahl (Vertrag §2.7a): GIFs aus KLIPY (Tenor ist abgeschaltet), eigene
GIFs, beliebige Emojis als Reaktion (eine je Person), Bilder in den
Benachrichtigungen. Was der Vertrag dem iOS-Agenten überließ:
- **GIFs werden über ImageIO animiert** (`CGAnimateImageDataWithBlock`, Bild für
  Bild dekodiert, `AnimatedImageView`) - im Chat das `webpUrl` (ImageIO spielt
  animiertes WebP ab, kleiner als GIF), ohne es das `gifUrl`, bis dahin
  `stillUrl`; dieselbe Ansicht für eigene GIFs und die Kacheln im GIF-Blatt.
  Außerhalb des Fensters hält die Animation an, mit „Bewegung reduzieren" steht
  das erste Bild. **Verworfen:** `mp4Url` als stumme `AVPlayerLooper`-Schleife -
  kleiner und hardwaredekodiert, aber je sichtbarer Nachricht ein AVPlayer samt
  Layer (iOS begrenzt gleichzeitige Dekoder), eine Audio-Sitzung, die ohne
  `.ambient` Musik anderer Apps anhält, und ein zweiter Weg für die eigenen GIFs,
  die es nur als GIF gibt. `UIImage.animatedImage` - legt alle Bilder auf einmal
  in den Speicher.
- **KLIPY-Medien nur im Speicher und im HTTP-Cache** (`KlipyMedia`: `NSCache`
  bis 48 MB, eigene `URLCache` mit 200 MB, weil die geteilte zu klein für GIFs
  ist). KLIPY verbietet Kopien in eigenen Dateien; der HTTP-Cache ist erlaubt.
- **„+" öffnet die Emoji-Tastatur** (`EmojiInputField`: ein `UITextField`, das
  `textInputMode` „emoji" verlangt) - mit der Emoji-Suche des Systems und jedem
  Emoji, das iOS kennt. Das erste Emoji der Eingabe zählt, alles andere wird
  verworfen. Ist die Emoji-Tastatur nicht eingerichtet, kommt die normale (dort
  über den Globus). **Verworfen:** ein eigenes Raster - bräuchte einen
  Emoji-Katalog samt Namen für eine Suche und hinkte jeder iOS-Fassung hinterher.
- **Die Leiste ist ein Blatt**, kein Kontextmenü: Schnellauswahl und „+" oben,
  Löschen/Melden/Blockieren (Timeline: Antworten) darunter; Aktionen laufen erst
  nach dem Schließen, damit Melde- und Blockier-Dialog hochkommen. **Verworfen:**
  `.contextMenu` - nimmt keine eigene Leiste auf; eine Palette
  (`ControlGroup`) im Menü scrollt bei sieben Einträgen seitlich, und die
  Hervorhebung des eigenen Emojis ginge nicht. Ist das eigene Emoji keins der
  sechs, steht es als achtes in der Leiste (hervorgehoben, antippen nimmt es
  zurück) - acht Felder passen auch auf ein schmales iPhone.
- **Reaktionen sofort sichtbar**, dann der Stand des Dienstes; bei Ablehnung
  zurück. Im Postausgang zählt je Ziel nur die jüngste: ein zweites Emoji
  ersetzt das wartende, Zurücknehmen und wieder Setzen hebt sich auf - aber
  Setzen und Zurücknehmen gehen **beide** raus, weil das Setzen ein früheres
  eigenes Emoji ersetzt hat, das sonst wiederkäme. **Verworfen:** die bisherige
  Regel „Gegenbewegung hebt sich auf" für alle Paare.
- **Eigene GIFs wie Fotos:** aus der Galerie oder per „Einfügen" (ein
  `PasteButton` im Feld, nur wenn ein GIF in der Zwischenablage liegt - der
  Blick auf den Typ löst keinen Hinweis von iOS aus) hängen sie am Feld und
  gehen mit „Senden" samt Text raus, wie Fotos in App und Web. Erkannt wird ein
  GIF am Dateianfang, hoch geht es unverändert. **Verworfen:** sofort beim
  Auswählen senden - dann verhielten sich Fotos und GIFs aus derselben Galerie
  verschieden.
- **Die Erweiterung `coHabitNotifications` übersetzt nur sechs Dateien**
  (`NotificationImage`, `ImageFormat`, `CohabitToken`, `Keychain`, `Backend`,
  sich selbst), lädt mit einer eigenen `URLSession` und lässt beim Foto keine
  Weiterleitung zu (der Token ginge mit), beim GIF nur zwischen
  `static*.klipy.com`. **Verworfen:** `CohabitAPI` - zöge Postausgang,
  Offline-Stand und `CohabitSync` (MainActor) mit, für eine Erweiterung mit
  wenig Speicher und 30 Sekunden.
- **Ein KLIPY-Stub im Repo** (`tools/klipy-stub.py`) statt eines Schlüssels:
  der gehört in kein Repo, und ohne ihn antwortet KLIPY nicht. Die Medien-URLs
  darin sind die öffentlichen aus KLIPYs Doku, damit der Dienst sie beim Senden
  annimmt.

## 2026-10-04 — Evaluation: Zusammenhänge mit Signifikanz, 14 Tage
Felix wollte Zusammenhänge zwischen den Antworten mit Signifikanzniveaus.
Entschieden hat er:
- **Spearman ρ und Pearson r nebeneinander** je Frage-Paar. **Verworfen:**
  nur eins von beiden.
- **p-Werte mit effektivem n nach Bartlett**: n · (1 − a·b)/(1 + a·b) mit den
  Autokorrelationen beider Reihen um einen Tag (bei ρ auf den Rängen), nie mehr
  als n; dann t-Test mit n_eff − 2 Freiheitsgraden, zweiseitig. Tageswerte
  hängen von Tag zu Tag zusammen, ein klassischer Test machte die p-Werte zu
  klein - zwei unabhängige, langsam schwankende Reihen sähen „signifikant"
  korreliert aus. **Verworfen:** (a) klassisch mit n − 2; (b) Korrelation der
  Veränderungen zum Vortag - nimmt Trends heraus, beantwortet aber eine andere
  Frage.
- **Holm-Korrektur**, je Maß über alle Tests (gleicher Tag und versetzt): bei
  drei Fragen neun. Sterne nach dem korrigierten p (* < 0,05, ** < 0,01,
  *** < 0,001). ρ und r sind zwei Blicke auf dieselben Hypothesen, deshalb je
  Maß eine Familie. **Verworfen:** keine Korrektur; roh und korrigiert
  nebeneinander.
- **Zusätzlich um einen Tag versetzt** (heute A → morgen B, beide Richtungen).
- **Über den oben gewählten Zeitraum**, ab 5 Paaren ein Koeffizient, ab
  n_eff 4 ein p-Wert. Die unvollständige Betafunktion für den t-Test rechnet die
  App selbst (Kettenbruch wie in den Numerical Recipes), geprüft gegen scipy.
- **Fragen mit Kurznamen** in den Zeilen (Felix, zweiter Anlauf am selben
  Tag): je Frage ein optionaler Kurzname von etwa zwei Worten, im Fragen-Blatt
  unter der Frage einzutragen und genauso privat. Ohne ihn steht die Frage,
  auf eine Zeile gekürzt. **Verworfen:** Farbpunkte (erster Anlauf) - man
  musste erst in der Legende nachsehen; ganze Sätze - neun Zeilen wären kaum
  zu lesen. VoiceOver liest weiter die ganzen Fragen.
- **14 Tage** als fünfter Zeitraum vorn (Felix). Fünf gleich breite Segmente
  schnitten „180 Tage" ab - deshalb wie im Gewicht-Tab `ContentWidthSegments`.

## 2026-10-04 — Evaluation: nur auf dem iPhone, Fragen in der App, Face ID mit Frist
Felix wollte in Healthy (nur iOS) einen Tab, in dem er ein paar persönliche
Fragen täglich mit 1–10 beantwortet und den Verlauf sieht. Seine Vorgaben: Face
ID, die nach fünf Minuten abläuft (gezählt ab dem Wechsel), Fragen nicht im
Repo, Daten privat. Entschieden hat er (04.10.):
- **Speicher nur auf dem iPhone** - eine Datei mit Datenschutz „vollständig",
  im iPhone-Backup, an keinen Server. **Verworfen:** (a) iCloud-Privatdatenbank
  - geräteübergreifend, aber mehr Einrichtung; (b) eine Datei im Kalorienzähler
  - dort könnte der Server-Agent sie lesen. Preis: wer die App löscht, verliert
  die Antworten.
- **Fragen in der App festlegen.** **Verworfen:** eine von Git ignorierte
  Datei, die mitgebaut wird - Ändern hieße neu bauen.
- **Skala 1–10**, zehn Knöpfe; derselbe Knopf noch einmal nimmt zurück.
- **Verlauf als Linien und Heatmap:** je Frage das Mittel der letzten sieben
  Tage als Linie, Antworten blass als Punkte; darunter je Frage ein Raster
  (Wochen als Spalten, Montag oben). Das Mittel schaut **zurück** statt
  zentriert wie beim Gewicht: „wie war die letzte Woche" ist die Frage, und
  zentriert reichte es am heutigen Rand in Tage, die noch kommen.
- **Gerechnet wird in der App** - Ausnahme von „die Dienste rechnen", weil es
  keinen Dienst gibt. Nur das Mittel und das Raster, in `EvaluationChartData`.
- **Erinnerung um 21:30** als lokale Mitteilung je Tag, 30 Tage im Voraus, neu
  verteilt bei jeder Antwort und jedem Wechsel in den Vordergrund; an einem
  beantworteten Abend keine. Text ohne Frage („Evaluation · Noch offen").
  **Verworfen:** eine täglich wiederholte Mitteilung - von der lässt sich ein
  einzelner Abend nicht abbestellen.
- **Nachtragen nur heute und gestern.**
- **Frist der Sperre ab dem ersten Wechsel weg vom Tab** (in einen anderen Tab
  oder aus der App), gemessen mit `ContinuousClock`. Zurück in die App fragt
  sie von selbst nur, wenn die Frist eben abgelaufen ist - der Face-ID-Dialog
  macht die App kurz inaktiv, und wer ihn abbricht, käme sonst sofort wieder
  hinein. Beim Wechsel in den Tab fragt sie immer. **Verworfen:** `Date()` -
  springt mit, wenn jemand die Uhr verstellt; `systemUptime` - steht still,
  während das iPhone schläft.
- **Entfernen einer Frage blendet ihren Verlauf nur aus**, die Antworten
  bleiben in der Datei. Umbenennen behält ihn.

## 2026-10-03 — 180 Tage: eigener Endpunkt, Segmente so breit wie ihre Beschriftung
Felix wollte eine 180-Tage-Ansicht in allen Frontends, im Gewichtsverlauf wie im
Kalorien-Verlauf.
- **Eigener Endpunkt `/api/weight/last180`** (Weight Tracker), Form wie
  `last90`. **Verworfen:** im Client aus `/year` zuschneiden wie bei „3 Jahre" -
  die Weboberfläche und das Gewichts-Overlay des Kalorienzählers im Browser
  brauchen ihn ohnehin (CORS gilt je Pfad), und dann ist ein zweiter Weg in
  den Apps nur eine zweite Wahrheit.
- **Overlay im Kalorien-Verlauf lädt `last180` erst ab mehr als 90 Tagen**,
  darunter weiter `last90`. So bleiben 14/30/90 Tage heil, auch wenn die App
  vor dem Dienst ausgerollt wird. **Verworfen:** immer `last180` - ein Dienst
  ohne den Pfad nähme dann jedem Zeitraum die Gewichtskurve.
- **Zeitraum-Umschalter im Gewicht-Tab als `UISegmentedControl` mit
  `apportionsSegmentWidthsByContent`** (`ContentWidthSegments`). Mit sechs
  gleich breiten Segmenten wurde „180 Tage" auf dem iPhone 17e zu „180 Ta…",
  während „Alles" Platz übrig hatte; nach Beschriftung verteilt passt alles.
  **Verworfen:** (a) die globale Appearance - verzöge auch „Zeitraum | Linie"
  im Highlights-Blatt und den Kalorien-Verlauf; (b) kürzere Beschriftungen
  („½ Jahr", „6 M") - eine Textfrage für Felix, nicht nötig, solange es passt.

## 2026-10-03 — coHabit, mehrere Beweisfotos: „+"-Kachel öffnet die Kamera, Karussell mit eigenen Punkten
Bis zu vier Fotos je Eintrag (Vertrag §2.3a; Felix: höchstens 4, wischbares
Karussell in voller Breite, Punkte nur bei mehr als einem, Fotos beim Bearbeiten
ergänzen und entfernen).
- **Blatt:** ohne Foto die Kamera-Vorschau wie bisher; danach das gewählte Foto
  groß, darunter die Vorschaubilder (umbrechend) mit „×" und eine „+"-Kachel.
  „+" schaltet die große Fläche wieder auf die Kamera (Auslöser, Galerie mit
  Mehrfachauswahl bis vier voll, Kamerawechsel); ein Tipp auf ein Vorschaubild
  zeigt es wieder groß. Die Kamera läuft nur, solange ihre Vorschau zu sehen
  ist. Beim Bearbeiten dieselbe Reihe, nur ohne das große Bild
  (`ProofPhotoPicker`, `showsSelection`). **Verworfen:** „+" als Menü
  „Kamera | Galerie" - ein Schritt mehr, und die Galerie steckt ohnehin neben
  dem Auslöser.
- **Karussell** als `TabView` im Seitenstil mit eigenen Punkten darunter
  (`PhotoCarousel`, `PageDots`) - die System-Punkte lägen weiß auf dem Foto und
  verschwänden auf hellen Bildern. Ein Foto sieht aus wie bisher.
- **Postausgang:** jedes Foto eine eigene Datei, der Reihe nach hoch, jede
  hochgeladene Kennung sofort in der Anfrage - so lädt ein Abbruch nach dem
  zweiten von drei Fotos beim nächsten Mal nur das dritte. Mit Netz bricht ein
  Eintrag mitten im Hochladen ab, wandert nur der Rest in den Postausgang.
  **Verworfen:** alle Fotos neu hochladen (dieselbe Kennung je Foto ginge auch,
  aber jede Wiederholung kostete den ganzen Upload).
- **Bearbeiten lädt direkt hoch**, ohne Postausgang - wie jedes Bearbeiten nur
  mit Netz („Kein Netz."). Unveränderte Fotos schickt die App als `null`.

## 2026-10-03 — coHabit, Laufpunkte: eigenes Lauf-Blatt, Läufe dürfen in den Postausgang
Eine Challenge mit Wertung „Laufpunkte" (`RUN_POINTS`, Vertrag §2.6a) fragt je
Eintrag Dauer und Distanz; Punkte und Pace rechnet nur der Dienst.
- **Ein eigenes Blatt** (`RunEntrySheet`) für alle Wege - Karte, Detailseite,
  Chat, klassische Liste, Deep Link der Kachel: Dauer, Distanz, bei Pflicht das
  Beweisfoto (dieselbe Kamera-Vorschau wie im Beweisfoto-Blatt, dafür als
  `ProofPhotoPicker` herausgelöst), Caption, „Anderer Tag"; der Knopf heißt
  `checkInLabel`. `runEntry` geht in `CheckInController.step` vor der
  Foto-Pflicht. **Verworfen:** Dauer und Distanz in Beweisfoto- und Wert-Blatt
  einbauen - der Lauf wäre über zwei Blätter verteilt, je nachdem ob ein Foto
  Pflicht ist.
- **Ohne Netz wartet ein Lauf im Postausgang** wie jeder Eintrag (er trägt sein
  Datum). Ob die Pace reicht, weiß erst der Dienst; lehnt er beim Nachsenden ab,
  fliegt der Lauf wie jede Ablehnung raus, und die Leiste nennt ihn:
  „Lauf 4,1 km in 35 Min. nicht angenommen: Ø-Pace …" - die Eingaben sind dann
  weg, so weiß man, was neu einzutragen ist. Mit Netz bleibt die Meldung im
  Blatt und die Eingaben stehen. **Verworfen:** (a) Läufe nur mit Netz - ein
  Lauf wird draußen eingetragen, oft mit schlechtem Netz, und ginge dann ganz
  verloren; (b) die Pace in der App vorab prüfen - das wäre die Regel ein
  zweites Mal (CLAUDE.md: gerechnet wird im Dienst); (c) den abgelehnten Lauf
  im Postausgang liegen lassen - er würde bei jedem Start erneut abgelehnt.
- **Die Punkte nach dem Speichern als Meldung oben** (`Toast` mit zweiter
  Zeile: „+20 P" groß, „Basis 10 · Distanz 5 · Dauer 5" klein), auch nach dem
  Bearbeiten eines Laufs - so zeigt die App schon jede Bestätigung, und die
  Meldung liegt im eigenen Fenster über jedem Blatt. **Verworfen:** ein eigener
  Dialog zum Wegtippen (ein Tipp mehr nach jedem Lauf).
- **Die Wertung bleibt Text** (`ChallengeScoring` nur als Konstanten), kein
  `LenientEnum`: ein unbekannter Wert fiele dort auf eine bekannte Wertung
  zurück, und das Bearbeiten-Formular schickte sie beim Sichern so zurück.

## 2026-10-02 — Gewicht-Tab: Serien-Chips brechen um, `FlowLayout` nach `Core/`
Die Serien-Chips unter dem Gewichtsdiagramm scrollten seitlich; schon der
fünfte lag hinter dem Rand, der neue Chip „Zeiträume" dahinter. Jetzt brechen
sie um, mit dem `FlowLayout` aus coHabit, das dafür nach `Core/` zieht.
**Warum:** Felix will keine seitlich scrollenden Chip-Leisten (was am Rand
abgeschnitten ist, findet niemand). `Core/` übersetzen genau die fünf Apps und
keine Erweiterung - und gebraucht wird es von zwei Apps, von keiner Kachel.
**Verworfen:** (a) `Shared/` - ginge auch, würde aber in jede Erweiterung
mitübersetzt, die es nie benutzt; (b) eine zweite Fassung in `Healthy/` -
dieselbe Umbruchrechnung zweimal, und der Rundungsfehler, den die coHabit-
Fassung schon behoben hat, käme in der Kopie wieder.

## 2026-10-02 — Zeiträume ausblenden: ein Schalter für alle, je Gerät gemerkt
Unter dem Gewichtsdiagramm steht als letzter Chip „Zeiträume"; aus blendet
alle Bänder und Linien aus, in jedem Zeitraum zugleich (anders als die
Serien, die „Alles" getrennt merkt - ein Urlaub stört im Jahr wie in 30
Tagen). Gemerkt in den `UserDefaults` des Geräts, ohne Wert an. Dasselbe in
Weboberfläche und Android-App. **Warum:** Felix („ein Schalter für alle",
„pro Gerät"). **Verworfen:** (a) ein Schalter je Eintrag in der Liste
(Urlaub aus, krank an) - ließe sich später neben dem einen Chip ergänzen,
ohne ihn zu ändern; (b) beim Dienst in `highlights.json` speichern, damit Web,
iPhone und Android gleich stehen - braucht einen Umbau und Deploy des Weight
Trackers für einen Anzeigewunsch.

## 2026-10-01 — Klassische Liste: sieben Punkte auch bei Zielen und Challenges
Nach „Eintragen" änderte sich die Zeile einer Challenge in der klassischen Liste
nicht sichtbar. Jetzt stehen dort wie bei „Track food" die sieben Punkte: Tage
mit eigenem Eintrag, ältester zuerst, heute rechts (`recent`, Dienst ab
`fe93938`). Die App zeigt die Reihe, sobald `recent` nicht leer ist - ein
älterer Dienst schickt bei Zielen und Challenges `[]`, dann bleibt die Zeile
wie bisher. **Warum:** Felix („Punkte drunter wie bei Track food"). **Verworfen:**
ein Haken für „heute eingetragen" neben dem Knopf (mein Vorschlag) - die Punkte
zeigen dasselbe und dazu die Woche, im Stil, den die Liste schon hat.

## 2026-10-01 — Wald-Kategorien: ein Knopf über „Baum pflanzen", ein Blatt für alles
Felix will im Wald jedem Baum eine Kategorie geben (Dienst ab `10536d7`). Über
„Baum pflanzen" steht ein grauer Knopf mit der gewählten Kategorie („Ohne
Kategorie" bei keiner); er öffnet ein Blatt mit „Ohne Kategorie", den
Kategorien und darunter einem Feld „Neue Kategorie". Antippen wählt und
schließt, eine neu angelegte ist sofort gewählt (und das Blatt geht zu);
Umbenennen und Löschen per Langdruck oder Wischen (kein Vollwischen, damit
nichts aus Versehen verschwindet). Vorbelegt ist die zuletzt benutzte - je
Gerät, mit Namen gemerkt, damit der Knopf schon vor dem Laden stimmt; ein
Testbaum zählt dabei nicht. Die laufende Session zeigt die Kategorie unter dem
Countdown, die Tageszeile darunter die Kategorien mit ihren Minuten
(„Bachelorarbeit 1:30 · Uni 0:45", Bäume ohne als „Ohne Kategorie"); ohne jede
Kategorie sieht die Zeile aus wie vorher. Der Wald bleibt, wie er war.
**Warum:** Felix; ein Knopf im Stil des Pflanzen-Knopfs passt in die Karte, und
ein Blatt hat Platz für Anlegen, Umbenennen und Löschen, ohne dass eine eigene
Verwaltungsseite nötig wird. **Verworfen:** (a) ein Menü statt des Blatts
(schneller beim Wählen, aber Anlegen und Umbenennen bräuchten dann je einen
Dialog und Löschen ein Untermenü); (b) Kategorien als Chips direkt in der
Karte (bei mehr als drei sprengen sie die Karte über dem Rad); (c) jeden Baum
einzeln in der Liste (die Liste zeigt seit jeher Tage; die Minuten je
Kategorie sind das, was Felix wissen will); (d) eine Rückfrage vor dem Löschen
(gelöscht wird nur aus der Auswahl, Bäume und Habits behalten den Namen).

## 2026-10-01 — Wald-Kategorien ohne Netz: nur wählen, nicht anlegen
Ein Baum geht mit `categoryId` raus, auch aus dem Postausgang. Kategorien
anlegen, umbenennen und löschen geht dagegen nur mit Netz (sonst „Kein
Netz."); ohne Netz steht die zuletzt geladene Liste zur Wahl. **Warum:** eine
offline angelegte Kategorie, die beim Nachsenden scheitert (Name inzwischen
vergeben → 409), hätte jeden Baum mit ihr mitgenommen - der Dienst lehnt eine
unbekannte Kategorie ab, und ein abgelehnter Baum ist verloren. Neue
Kategorien legt man selten an, Bäume pflanzt man oft. **Verworfen:** Anlegen
mit eigener Kennung in den Postausgang (der Dienst würde es annehmen, aber
der Fehlerfall träfe ausgerechnet die Bäume). Ebenso entschieden: Das
Tagesziel des Waldes nimmt nur ein Fokus-Habit über alle Bäume und je Tag
(`FocusGoal`) - „1 h Bachelorarbeit" oder „10 h pro Woche" gegen die Summe
aller Bäume von heute zu stellen wäre ein falscher Balken; gibt es nur
solche, zeigt der Wald die Summe ohne Ziel.

## 2026-10-01 — Fokus-Habits: Zeitraum, Minuten, Kategorie im Formular
Anlegen und Bearbeiten eines automatischen Fokus-Habits zeigen unter der
Quelle drei Dinge: „Täglich | Pro Woche" (Segmente wie bei „Zählt"), die
Minuten als Stepper („4:00 h am Tag" in Viertelstunden bis 16 h wie bisher,
„10:00 h pro Woche" in Stunden bis 168 h) und „Kategorie" als Chips („Alle
Bäume" + die Kategorien aus `GET /focus/categories`). Der Titel bleibt frei.
Beim Wechsel des Zeitraums bleiben die Minuten, soweit sie passen, wie im
Web-Formular. Die App schickt `focusCategoryId` und `focusPeriod` immer, den
Namen nie (den trägt der Dienst ein). Eine im Wald gelöschte Kategorie, die ein
Habit noch hat, bleibt als Chip stehen. Im alten Editor der klassischen Liste
dasselbe in dessen Stil (Segmente, Zahlenfeld, Picker), vorbelegt aus
`focus`; die Zeile nennt die Kategorie im Untertitel („3 Tage ·
Bachelorarbeit"). **Warum:** Felix; dieselben drei Felder wie im Web, im Stil
des jeweiligen Formulars. **Verworfen:** (a) beim Wechsel auf „Pro Woche" die
Minuten mal sieben nehmen (aus 4 h am Tag würden 28 h pro Woche - weit weg von
dem, was man pro Woche üblicherweise einstellt, und viele Taps zurück); (b) ein
Picker statt Chips im neuen Formular (das Formular wählt überall per Chip);
(c) die Kategorie im Namen der Zeile statt im Untertitel (der Name ist frei
und oft schon die Kategorie).

## 2026-10-01 — Kalorienziel im Wochenmittel: nur ein Chip, in der alten Liste mit „Ø"
Neue automatische Quelle `FOOD_TARGET_WEEKLY` (Dienst ab `f0f69c6`): im
Formular der Chip „Kalorienziel im Wochenmittel" ohne weitere Felder,
Rhythmus einmal pro Woche. In der klassischen Liste kommt sie als Art FOOD in
Wochen; die Zeile schreibt den Wochenschnitt mit „Ø" davor („Ø 2.191/2.300
kcal"), der Editor nennt die Art beim Namen und erklärt die Wochenregel statt
der von „Track food". **Warum:** ohne „Ø" sähe der Schnitt der Woche aus wie
der Stand von heute, und die alte Erklärung („80 % des kcal-Ziels …") wäre
falsch. **Verworfen:** eine eigene Zeilenart in der klassischen Liste (der
Dienst liefert FOOD/WEEKS mit allem, was die Zeile braucht); die Quelle im
alten Editor zum Anlegen anbieten (nicht verlangt, das Formular kennt nur die
fünf alten Arten). Unbekannte Quellen bleiben Text und stehen mit ihrem Namen
als Chip da.

## 2026-10-01 — kcal aus Healthy: ein Schalter statt der Apple-Health-Abfrage
Felix wollte „kcal aus Healthy" als Wert in Co-Habits. Die Werte holt der
Dienst selbst aus dem Kalorienzähler (`source: HEALTHY`); die App bietet beim
Anlegen und Bearbeiten die Health-Metrik „kcal aus Healthy" (`KCAL`, Einheit
`KCAL`) und kennt „kcal" überall, wo Einheiten beschriftet werden. Auf der
Detailseite steht statt „Health-Sync aus/aktiv" mit „Verbinden" eine Karte mit
Titel `health.label`, `shareText`, „zuletzt …" und einem Schalter für die
Einwilligung (`PUT …/settings/me`); ohne Quelle `FOOD` ist er gesperrt, darunter
„Kein Healthy-Zugang". Für Apple Health bleibt alles, wie es war.
`CohabitHealthSync` abonniert KCAL ausdrücklich nicht und fragt dafür keine
HealthKit-Erlaubnis an - auch nicht über das Blatt „Benachrichtigungen" oder
die Profilseite „Health-Verbindung", die beide sonst beim Einschalten Apple
Health abfragten. **Warum:** Felix; die Daten liegen beim Kalorienzähler nebenan,
kein Handy muss etwas schicken. Eine Health-Abfrage dafür hätte nach einer
Erlaubnis gefragt, die nichts bewirkt. **Verworfen:** (a) die alte Karte mit
„Verbinden" behalten (öffnete den Apple-Health-Dialog für Daten, die gar nicht
vom Gerät kommen); (b) die Karte bei KCAL ganz weglassen (dann gäbe es auf der
Detailseite keinen Weg zur Einwilligung, nur noch im Benachrichtigungs-Blatt);
(c) „kcal aus Healthy" nur Personen mit Healthy-Zugang zum Anlegen anbieten
(wer anlegt, ist nicht unbedingt der, der kcal beisteuert).

## 2026-10-01 — Klassische Liste: Ziele und Challenges in der alten Zeile
Felix will in der klassischen Liste alles sehen, was die neue zeigt - seine
Challenges fehlten ihm. Sie stehen jetzt dort im alten Stil: statt der Flamme
ein Pokal (Challenge) bzw. eine Zielflagge (Ziel) mit der Kennzahl der neuen
Liste darunter („#1", „30%"), Untertitel aus `listLine`, bei Zielen der alte
Balken, keine sieben Punkte (seit dem Nachmittag doch, siehe oben); rechts „Eintragen" im Stil des alten
„Rückfall"-Knopfs, ohne Eintragen ein Haken für „heute eingetragen". Der Knopf
öffnet über `CheckInController` genau das, was der Eintragen-Knopf der neuen
Liste öffnet (Wert-Blatt, +1, Beweisfoto) - die Liste hat keine eigene Logik.
Der Name führt immer zur Detailseite, Langdruck-Nachtragen gibt es nicht,
Wischen wie bei den anderen. Reihenfolge: Aufbauen/Lassen, dann Ziele und
Challenges, dann die automatischen (`classicOrder`; seit 05.10. Lassen erst
nach Zielen und Challenges, siehe dort). Der Editor legt weiter nur
die fünf alten Arten an. **Warum:** Felix; die alte Zeile hat genau drei
Plätze (Kennzahl links, Text in der Mitte, Knopf rechts), in die die
Zusammenfassung passt. Auf dem Knopf steht „Eintragen" und nicht
`checkInLabel`: „+1 Wer kocht öfter? eintragen" sprengt den kleinen Knopf;
der volle Text ist das VoiceOver-Label. **Verworfen:** (a) Ziele und
Challenges weglassen (der bisherige Stand - genau das fehlte Felix); (b) sie als
Karten der neuen Liste einbetten (bräche das alte Aussehen); (c) ein eigener
Abschnitt „Ziele & Challenges" (die alte Liste hat keine Abschnitte); (d) ein
eigenes Eintragen-Blatt in der Liste (zweite Logik neben `CheckInController`).
Dabei aufgefallen: Die Knöpfe in den Zeilen („Doch nicht", jetzt „Eintragen")
erbten das Violett von coHabit, weil der zurückgesetzte Tint nur die
Leistenknöpfe erreicht - die Liste setzt jetzt ausdrücklich Systemblau wie in
Fokus.

## 2026-10-01 — Timeline-Filter: ein Knopf und eine Abhak-Liste statt Chips
Felix fand die seitlich scrollenden Habit-Chips oben in der Timeline
unübersichtlich; die letzten verschwanden am Rand. Jetzt steht dort ein Knopf
mit dem aktuellen Filter und ▾ („Alle Habits", bei genau einem sichtbaren
dessen Name, sonst „n von m Habits"; gefiltert in Tinte wie früher der gewählte
Chip). Er öffnet ein Blatt (halb/ganz) mit „Alle" als Umschalter und jedem
aktiven Co-Habit mit Farbpunkt, Name und Haken; Mehrfachauswahl, jede Änderung
wirkt sofort. Gemerkt wird je Gerät die Menge der **ausgeblendeten** Kennungen
(`timeline.hidden`), geladen mit `GET /timeline?exclude=`. Kennungen, die es
unter den aktiven nicht mehr gibt, zählen nicht und werden nicht ausgeblendet.
Ist alles aus, steht „0 von m Habits" und darunter „Keine Habits ausgewählt".
**Warum:** Felix' Entscheidung. Ausblenden statt auswählen, damit ein neues
Co-Habit von selbst erscheint; nur aktive zählen, weil im Blatt nur sie stehen -
was dort nicht abzuwählen ist (archiviert), darf nicht unsichtbar weggefiltert
bleiben. **Verworfen:** (a) die Chips behalten (unübersichtlich, die letzten
verschwinden am Rand, nur eins auf einmal); (b) eine aufklappbare Liste oben in
der Timeline (schiebt die Einträge weg und steht beim Scrollen im Weg, ein
Blatt ist der Ort für eine Auswahl); (c) die gewählten Kennungen merken (ein
neues Co-Habit bliebe unsichtbar, bis man es von Hand anhakt).

## 2026-10-01 — Timeline-Filter: als gesehen gilt das neueste Ereignis überhaupt
Wer in die Timeline schaut, setzt „neue Beweisfotos" auf „Heute" zurück
(`POST /timeline/seen`). Ungefiltert meldet die App wie bisher das oberste
Ereignis der Liste; ist etwas ausgeblendet, fragt sie das neueste Ereignis ohne
Filter nach (`limit=1`) und meldet dieses. **Warum:** Der Filter ist jetzt
gemerkt, und der Dienst zählt die Fotos ohne ihn zu kennen. **Verworfen:** (a)
nur ungefiltert melden, wie bei den Chips (mit einem dauerhaft ausgeblendeten
Habit stünde „n neue Beweisfotos" für immer da); (b) das oberste sichtbare
Ereignis melden (neuere Fotos ausgeblendeter Habits hingen fest, bis etwas
Sichtbares neuer ist). Die Folge: Fotos ausgeblendeter Habits gelten mit dem
nächsten Blick in die Timeline als gesehen, auch wenn sie dort nicht stehen.

## 2026-09-30 — coHabit: ein Link ohne Anmeldung meldet sofort an
Öffnet ein Link mit Token (App-, Setup-, Healthy-Link) die App, während niemand
angemeldet ist, meldet sie damit sofort an - dieselbe Anmeldung wie „Link
einfügen", bei einem 401 steht „Link ungültig" auf dem Start. Ein
Einladungslink öffnet die Registrierung. Nur Links, die erst mit Sitzung etwas
bedeuten, warten in `pendingLink`. **Warum:** Der Knopf „In der App öffnen" der
Weboberfläche ist genau dafür da; ein Link, der nur bereitliegt, bis jemand
etwas einfügt, sieht aus wie ein kaputter Knopf (auf Felix' iPhone passiert).
Geprüft wird der Token ohnehin, bevor er gespeichert wird (`GET /me`).
**Verworfen:** (a) den Link ins Feld „Link einfügen" legen und auf „Weiter"
warten (ein Tipp mehr, der nichts prüft, was die Anmeldung nicht schon prüft);
(b) wie bisher in `pendingLink` warten lassen (dort sah niemand hin).

## 2026-09-30 — Klassische Liste: Schalter im Profil, „Heute" zeigt dann die alte Liste
Felix mochte die Habit-Liste der Fokus-App lieber als das neue Design. coHabit
hat im Profil den Schalter „Klassische Liste" (je Gerät,
`@AppStorage("today.classic")`); ist er an, zeigt der Tab „Heute" die alte
Liste statt Dashboard und Liste. Timeline, Statistik und Profil bleiben.
Aussehen und Bedienung sind der Stand `529c651` (System-Liste, Flamme, Punkte,
Langdruck, Editor, Wischen, Titel „Habits", „+" oben rechts) - ohne den
Zugang-Knopf, den es in coHabit nicht gibt, und mit zurückgesetztem statt
violettem Tint (ein ausdrückliches `.tint(.blue)` färbte unter iOS 26 auch das
„+" blau; in der Fokus-App war es schwarz).
**Warum:** Felix' Entscheidung; je Gerät wie die Wahl Dashboard/Liste, weil es
eine Frage der Ansicht ist, nicht der Daten. **Verworfen:** (a) ein drittes
Segment neben „Dashboard | Liste" im Kopf von „Heute" (die alte Liste hat
diesen Kopf nicht - mit Umschalter darin sähe sie nicht mehr aus wie früher);
(b) ein eigener Tab (die Leiste ist mit „+" voll, und zwei Startseiten
nebeneinander wären doppelt); (c) der Habits-Tab zurück in Fokus (zwei Apps für
dieselben Habits, geteilte kämen dort nicht an).

## 2026-09-30 — Klassische Liste: Streaks und Abstinenz, auch geteilte
Die Liste zeigt alle aktiven Streaks und Abstinenzen der Person, auch die, die
sie mit anderen teilt; Ziele und Challenges nicht - die liefert der Dienst gar
nicht erst (`GET /classic/habits`). **Warum:** Felix. Nur diese beiden Typen
passen in die alte Zeile (Flamme, Haken bzw. Rückfall), und für den eigenen
Haken ist es gleich, ob noch jemand mitmacht. **Verworfen:** (a) nur, was man
allein hat (dann fehlte „Laufen" mit Lena und Max, obwohl man dort jeden Tag
abhakt); (b) alle vier Typen (Beiträge und Ranglisten haben in der Zeile keinen
Platz).

## 2026-09-30 — Klassische Liste: wo das alte Design nichts hat, übernimmt coHabit
Drei Fälle, die es in der Fokus-App nicht gab:
- **Foto-Pflicht:** der Haken öffnet das Beweisfoto-Blatt von coHabit für
  dieses Co-Habit - dasselbe wie der Kamera-Knopf auf dem Dashboard, gefüllt
  aus der Zusammenfassung von `GET /cohabits/{id}` (Farbe, wer das Foto sieht).
  Nachtragen per Langdruck gibt es dort nicht. **Verworfen:** den Haken
  schicken und die 400 des Dienstes zeigen (eine Sackgasse); den Haken
  ausblenden (dann ließe sich das Habit in der Liste nicht abhaken).
- **Nicht Admin:** Tipp auf den Namen öffnet die Detailseite in coHabit.
  **Verworfen:** der alte Editor schreibgeschützt (zeigt nichts, was man tun
  kann); ein Tipp, der nichts tut.
- **Geteilt:** Wischen fragt erst „„Name" verlassen?" (destruktiv
  „Verlassen"), dann `DELETE` - der Dienst verlässt, statt zu löschen. Der
  Knopf trägt dafür keine destruktive Rolle, die ließe die Zeile schon vor der
  Antwort verschwinden; die Rückfrage hängt an der Zeile, weil sie unter iOS 26
  ein Popover ist (ohne „Abbrechen", daneben tippen) und sonst auf eine fremde
  Zeile zeigte. **Verworfen:** sofort verlassen, wie früher sofort
  gelöscht wurde (man verlässt dabei Chat und Mitglieder - das verdient eine
  Rückfrage); Wischen bei geteilten sperren (dann gäbe es aus der Liste keinen
  Weg hinaus).

## 2026-09-30 — Klassische Liste: Haken ohne Netz im Postausgang von coHabit
Haken und Rücknahmen gehen ohne Netz in `CohabitOutbox` (Aufträge
`classicMark` mit der Kennung aus dem ersten Versuch und `classicUnmark`); ein
409 beim Nachsenden eines Hakens heißt „steht schon". Die Aufträge und
`ClassicMarkRequest` liegen deshalb in `CohabitShared/`, obwohl die Kachel die
Liste gar nicht zeigt. **Warum:** Die Kachel liest und schreibt dieselbe Datei
(ihr Abhak-Knopf legt ohne Netz dort ab). Kennte sie einen Auftrag nicht,
schlüge das Dekodieren fehl, und sie schriebe die Datei mit nur ihrem eigenen
Eintrag neu - die Haken der Liste wären weg. **Verworfen:** (a) ein eigener
Postausgang nur für die Liste (zwei Warteschlangen, zwei Nachsende-Läufe, zwei
Stände in der Leiste); (b) ohne Netz nur eine Fehlermeldung (der alte Tab
konnte ohne Netz abhaken).

## 2026-09-30 — coHabit: fünfte App im Repo, eigener Client mit Bearer
coHabit ist ein weiteres Target (`coHabit` + `coHabitWidget`) in diesem Repo,
mit eigenem Ordner `CohabitShared/` für das, was App und Kachel teilen. Es
spricht die API nicht über `APIClient`, sondern über `CohabitAPI`: der Token
der Person geht als `Authorization: Bearer` mit, Cookies bleiben aus.
**Warum:** Der Vertrag (../habits/docs/COHABIT-CONTRACT.md §1.3) legt das Ziel
hier fest, und Tools, Harness, `Shared/` und `Core/` gibt es schon. Der
vorhandene Client ist auf die Cookie-Dienste zugeschnitten: alles außer 2xx
heißt dort „Zugang prüfen", 403 wird zu `notAuthorised`, Fehlertext ist
Klartext. coHabit antwortet sauber (401 = nicht angemeldet, 403/409/429 mit
`{"message"}`), und diese Meldungen sollen auf den Bildschirm. Den
`OfflineCache` benutzt coHabit mit, den Rest nicht. **Verworfen:** (a)
`APIClient` um Bearer und JSON-Meldungen erweitern (hätte das Verhalten von
Healthy, Vault und Fokus mitverändert); (b) ein eigenes Repo (Tools, Harness,
Keychain-Hülle doppelt).

## 2026-09-30 — coHabit: eigener Postausgang in der App-Gruppe
Einträge, Nachrichten und Reaktionen warten ohne Netz in `CohabitOutbox`,
einer Liste typisierter Aufträge in `group.com.fherrmann.cohabit` - ein Haken
mit Foto heißt dort „erst das Foto hochladen (mit Idempotenz-Schlüssel), dann
den Eintrag mit dessen Kennung schicken". **Warum:** Der `Outbox` der anderen
Apps spielt rohe Anfragen ohne Kopfzeilen nach (Cookies aus dem gemeinsamen
Speicher) und kennt kein Multipart; coHabit braucht Bearer beim Nachsenden
und eine Reihenfolge Foto → Eintrag. In der App-Gruppe liegt er, weil auch
der Abhak-Knopf der Kachel ohne Netz dort ablegt. Doppelt entsteht nichts:
Einträge und Nachrichten tragen ihre Kennung von der App, das Foto seinen
Schlüssel - bei jedem Versuch derselbe (Test `OutboxTests`). Nachgerechnet
wird nichts: der Knopf zeigt eine Uhr, bis der Dienst geantwortet hat.
**Verworfen:** (a) den geteilten `Outbox` erweitern (andere Apps mitbetroffen,
Multipart dort fremd); (b) Fotos ohne Netz gar nicht erlauben (Beweisfoto im
Funkloch ist genau der Fall).

## 2026-09-30 — coHabit: Token in eigener Keychain-Gruppe, nie `fh_private`
Der coHabit-Token liegt in `ZWFV263P59.com.fherrmann.cohabit`, die nur App und
Kachel tragen, nicht in der geteilten Gruppe der anderen Apps.
**Warum:** Keine andere App braucht ihn, und der Vertrag schließt aus, dass
coHabit den Master-Token bekommt (§1.2) - Felix meldet sich wie alle über
einen App-Link an. Die Kachel liest ihn bei gesperrtem Gerät
(`AfterFirstUnlockThisDeviceOnly`, wie die anderen Token). **Verworfen:** die
geteilte Gruppe (jede App sähe den Token; und ein vorhandenes `fh_private`
läge verführerisch daneben).

## 2026-09-30 — coHabit: eigene untere Leiste über einer versteckten TabView
Die Leiste aus den Entwürfen (weiße Kapsel, großes violettes „+" in der Mitte)
ist selbst gezeichnet und liegt über einer `TabView`, deren Systemleiste
versteckt ist; auf geschobenen Seiten verschwindet sie. **Warum:** So sieht es
aus wie entworfen, und die `TabView` hält trotzdem den Zustand jedes Bereichs
(Scrollstand, geladene Daten). „+" ist kein Bereich, es öffnet das Anlegen.
**Verworfen:** (a) die sichtbare Systemleiste (kein großes „+", anderer Stil);
(b) ein eigener Umschalter ohne `TabView` (jeder Wechsel baute den Bereich neu
und lud alles noch einmal).

## 2026-09-30 — coHabit zeigt „Du" statt des eigenen Namens
In Ranglisten, Wochenraster, Beiträgen, Podest und Avataren steht für die
angemeldete Person „Du" (Avatar in Tinte), wie in den Entwürfen; das Profil
zeigt den echten Namen. **Warum:** Man sucht sich in einer Liste schneller als
„Du" als unter dem eigenen Namen, und die Entwürfe zeigen es durchgängig so.
Die Texte des Dienstes („Lena & Max heute schon") bleiben unverändert.
**Verworfen:** überall den Anzeigenamen (so steht man in der eigenen Rangliste
als „Felix").

## 2026-09-30 — Beweisfoto-Blatt mit eigener Kamera-Vorschau
Das Blatt zeigt die Kamera selbst (`AVCaptureSession` mit Vorschau, Auslöser,
Kamerawechsel), die Galerie über `PhotosPicker`. **Warum:** So steht es im
Entwurf (S. 15): Vorschau im Blatt, Caption darunter, „Posten & abhaken" in
einem Zug. Ohne Kamera (Simulator) steht dort ein gestreifter Platzhalter, die
Galerie geht trotzdem. Hochgeladen wird aufrecht neu gezeichnet (≤ 2048 px,
JPEG 0,85), weil der Dienst EXIF nicht auswertet. **Verworfen:** der
`CameraPicker` aus Healthy (`UIImagePickerController`, Vollbild - ein
Umweg mehr pro Beweisfoto).

## 2026-09-30 — Health in coHabit: nur beim Öffnen, nur was sich änderte
Welche Co-Habits Health wollen (Metrik + Einwilligung), merkt sich die App
aus jedem geladenen Detail; abgeglichen wird beim Start und bei jedem
Vordergrund, höchstens alle zehn Minuten, je Tag ein Wert und nur, wenn er
sich seit dem letzten Senden geändert hat. **Warum:** „Heute" kennt die Metrik
nicht, und bei jedem Start alle Details zu holen kostete je Co-Habit eine
Anfrage. Hintergrund-Wecken wie beim Gewicht in Healthy lohnt nicht: iOS
deckelt Schritte auf stündlich, und die Zahl ist eine Stunde später wieder
überholt (dieselbe Abwägung wie bei den Schritten in Healthy). **Verworfen:**
(a) `HKObserverQuery` mit Hintergrundzustellung; (b) alle Details bei jedem
Start.

## 2026-09-30 — Wald-Tagesziel aus coHabit statt ohne Ziel
Der Wald zeigt bei „Heute" weiter „2:15/4:00 h". Das Ziel kommt jetzt aus dem
Co-Habit mit der Quelle FOCUS (`config.auto.focusMinutesGoal`), gefragt mit
dem Privat-Cookie, den Fokus ohnehin hat; die Kennung des Co-Habits merkt sich
Fokus. **Warum:** Mit dem Umzug antwortet `/habits/api/habits` mit 410 - ohne
Ersatz verlöre Felix das Tagesziel im Wald, und der Vertrag verspricht
„verlustfrei". Ein zweites, in Fokus einstellbares Ziel wäre eine zweite
Wahrheit neben dem Co-Habit. **Verworfen:** (a) Ziel weglassen; (b) Ziel in
Fokus einstellen; (c) die vollen coHabit-Modelle nach `Shared/` ziehen (drei
Felder genügen, `FocusGoal`).

## 2026-09-30 — „{frei} von 8 Plätzen frei" im Einladungsdialog
Der Chip nennt die freien Plätze und sagt das dazu. **Warum:** Der Vertrag
verlangt `{frei}` (§5.2.16), der Entwurf zeigt „2 von 8 Plätzen" mit zwei
Mitgliedern, also die belegten. „6 von 8 Plätzen" allein läse jeder als
belegt. **Verworfen:** die belegten zeigen (widerspräche dem Vertrag).

## 2026-09-30 — Anlegen: der Einladungslink legt das Co-Habit schon an
Wer in Schritt 3 auf „Teilen" tippt, bekommt das Co-Habit sofort angelegt -
der Link braucht ein bestehendes (`POST /cohabits/{id}/invite-link`). „Co-Habit
starten" schickt danach nur noch die Einladungen an die gewählten Freunde.
**Verworfen:** den Link erst nach „Starten" anbieten (Schritt 3 zeigt ihn
laut Entwurf oben).

## 2026-09-26 — To-Do-Links: nur beim Anlegen, in der App ein eigener Pfeil
Aufgaben haben ein optionales `link`, gesetzt nur mit `POST /api/todos`;
`PUT` lässt es stehen. In Fokus öffnet ein Pfeil neben dem Titel den Link in
Safari, im Web ein ↗. **Warum:** Die Links kommen von einem anderen Dienst
(Torbens Wünsche aus dem Kalorienzähler), nicht von Hand. Ein `PUT`, das den
Link übernimmt, hätte ihn bei jedem Speichern aus der Fokus-Version auf dem
Handy oder einem offenen Browser-Tab gelöscht — die kennen das Feld nicht.
Der Pfeil ist ein eigenes Tippziel, weil der Tipp auf den Text schon das
Blatt öffnet und Wischen schon Löschen heißt. Die App nimmt nur http(s) mit
Host und macht aus allem anderen nil, statt am Brett zu scheitern.
**Verworfen:** (a) `PUT` mit Link (bräche jeden alten Client); (b) die ganze
Zeile als Link (nähme dem Text das Blatt); (c) den Link nur im Blatt oder im
Kontextmenü (ein Umweg für genau das, wofür die Links da sind); (d) strikt
dekodieren (ein kaputter Link ließe den ganzen Tab leer).

## 2026-09-24 — Habits bearbeiten: Tipp auf den Namen, die Art bleibt fest
Ein Tipp auf Name oder Untertitel öffnet denselben Editor wie das Plus, mit
den Werten des Habits vorbelegt; änderbar sind Name, Ziel, Rhythmus und
Häufigkeit — die Art nicht. Die Beschriftung neben den Punkten („7 Tage",
„7 Wochen") ist weg. **Warum:** Felix wollte Zielwerte ändern können, ohne
das Habit samt Strähne neu anzulegen. Die Art lässt der Dienst nicht ändern,
und das ist richtig so: aus „Aufbauen" ein „Lassen" zu machen kehrte jeden
Haken in einen Rückfall um. „7 Wochen" las sich wie ein Ziel, dabei sagt es
nur, wie lang die Punktreihe ist — das sieht man ihr selbst an. **Verworfen:**
(a) Bearbeiten im Kontextmenü (langes Drücken öffnet schon die früheren
Tage, ein Menü davor war die Indirektion, die Felix gerade abgeschafft
hatte); (b) ein eigenes Blatt nur fürs Ziel (zweiter Editor für dieselben
Felder); (c) eine Beschriftung wie „letzte 7 Wochen" (erklärt, was die
Reihe zeigt — Erklärtexte gehören nicht in die Oberfläche; als
Accessibility-Label bleibt sie).

## 2026-09-22 — „Flow" nur als Anzeigename, technisch bleibt es Fokus
Die App heisst auf dem Homebildschirm „Flow", Bundle-ID, Target, Ordner,
Schema und URL-Schema bleiben `Fokus`. **Warum:** Eine neue Bundle-ID wäre
eine neue App — Family Controls, App-Gruppe, Push-Kennung, Keychain-Gruppe,
gespeicherte Session und Whitelist wären weg, und der Umbau des Repos wäre
ein Tag Arbeit ohne sichtbaren Nutzen. **Verworfen:** die Umbenennung bis in
die Kennungen. **Nachtrag 2026-09-23:** Der Anzeigename ist wieder „Fokus",
das Icon die Habits-Flamme — Felix mochte „Flow" mit der Welle nicht. Die
Begründung, warum die Kennungen bleiben, gilt unverändert.

## 2026-09-22 — Die Insel folgt der Sonne über Hamburg, nicht dem Dunkelmodus
Tag, Dämmerung und Nacht der Insel kommen aus dem gerechneten Sonnenstand
für einen festen Ort (Hamburg), nicht aus `colorScheme` und nicht aus dem
Standort des Geräts. **Warum:** Felix will die Insel bei Tageslicht sehen,
wenn draussen Tag ist — der Dunkelmodus sagt darüber nichts. Ein fester Ort
spart die Standortabfrage samt Dialog; eine Viertelstunde Abweichung an
einem anderen Ort sieht niemand. **Verworfen:** (a) Dunkelmodus als Nacht
(war so, „immer Nacht"); (b) Standortabfrage (Dialog, Berechtigung, für
Minuten Genauigkeit); (c) feste Uhrzeiten 7–20 Uhr (im Winter ist es um
17 Uhr dunkel, im Sommer um 21 Uhr hell).

## 2026-09-23 — Foto der Mahlzeit: Datei im Postfach, der Agent liest sie
Das Foto geht als Base64 im JSON zum Kalorienzähler, der es als Datei in
`data/inbox/` ablegt; die Claude-Code-Session des Agenten bekommt dafür ein
einziges zusätzliches Recht, `Read` auf genau diesen Ordner, und liest das
Bild selbst. **Warum:** Die Schnellerfassung läuft bewusst als Claude-Code-
Session mit Felix' Abo, nicht über die API mit Schlüssel; Bilder kann die
Session nur als Datei sehen. Das Recht ist auf den Ordner begrenzt, die Datei
heisst nach der Auftragsnummer und wird nach der Auswertung gelöscht — die
Leitplanke bleibt das Verzeichnis. **Verworfen:** (a) direkter API-Aufruf mit
Bild (Schlüssel und Kosten je Bild, zweiter Weg neben der Session);
(b) Multipart-Upload (ein zweiter Endpunkt für denselben Auftrag; Base64 im
JSON kostet ein Drittel mehr Bytes, spart aber alles andere).

## 2026-09-23 — Essen-Tab: Karten von Hand gezogen, kein Pager
Die Tageskarten werden mit einer eigenen `DragGesture` verschoben (Liste des
Tages plus Nachbarliste im `ZStack`, versetzt um den Zug), die Geste liegt
nur auf Tacho-Block, Überschriften und „Hinzufügen"-Zeilen. **Warum:** Der
`TabView(.page)`-Pager vom Vortag ist ein horizontales Scrollfeld und
schluckte jeden Wisch nach links — Eintragszeilen liessen sich nicht mehr
löschen (Felix, 23.09.). Die Eintragszeilen gehören ihrem eigenen Wisch;
Tacho-Block und Überschriften sind gross genug zum Blättern. **Verworfen:**
(a) der Pager mit Löschen im Bearbeiten-Blatt (ein Standard-Wisch weniger);
(b) UIPageViewController (unklar, ob dessen Scrollfeld den Zeilen-Wisch
durchlässt, und ein UIKit-Umweg für eine Geste).

## 2026-09-22 — Essen-Tab: drei Karten im Pager statt einer Wisch-Geste
Der Tag im Essen-Tab ist eine von drei Karten in einem `TabView(.page)`;
Nachbarn liegen vorgeladen daneben. **Warum:** Felix will beim Wischen
sehen, wie die Karten verschoben werden, nicht ein Umblenden am Ende der
Geste. Ein Pager macht das nativ, samt Richtungserkennung gegen das
senkrechte Scrollen und Abbremsen. **Verworfen:** (a) die bisherige
`DragGesture` mit Übergang am Ende (kein Mitziehen, „Blink"); (b) eine eigene
Zieh-Animation über der Liste (zwei Listen übereinander versetzen, Richtung
selbst erkennen, Rand selbst abfedern — alles, was der Pager schon kann).
**Zurückgenommen am 23.09.**, siehe oben: der Pager frass den Lösch-Wisch.

## 2026-09-22 — Fokus-Modus per Automation und App Intent statt URL-Sprung
Die App bietet die Aktion „Fokus-Restminuten" an; eine Automation „Wenn
Fokus geschlossen wird" holt sie sich und befristet den Fokus-Modus. **Warum:**
Der Sprung in die Kurzbefehle-App beim Pflanzen störte. Eine App kann keinen
Kurzbefehl im Hintergrund starten, eine Automation aber läuft still — ihr
fehlte nur die Endzeit, und die kann ein App Intent liefern. **Verworfen:**
(a) nur der URL-Sprung (bleibt als Rückfall hinter dem Schalter); (b) die
Automation auf „App geöffnet" (läuft dann vor dem Pflanzen).

## 2026-09-21 — Schild auch aus der Erweiterung, Session in einer App-Gruppe
Die Erweiterung `FokusMonitor` legt den Schild beim Start ihres Intervalls
(neu), nicht nur die App beim Pflanzen; laufende Session und erlaubte Apps
liegen dafür in der App-Gruppe `group.com.fherrmann.fokus` (`FocusShared/`).
**Warum:** Ein Neustart des Handys nimmt den Schild weg — Felix hat es so an
der Sperre vorbei geschafft. Das DeviceActivity-Intervall überlebt den
Neustart, und iOS ruft `intervalDidStart` erneut; das ist auch Apples
Muster (Schild in `intervalDidStart`, weg in `intervalDidEnd`). Die
Erweiterung sieht die UserDefaults der App nicht, daher die Gruppe.
**Verworfen:** (a) nur die App beim nächsten Öffnen (bis dahin ist alles
frei — genau die Lücke); (b) Hintergrund-Auffrischung (`BGAppRefreshTask`,
Zeitpunkt nicht steuerbar); (c) die Whitelist in den Store-Namen kodieren
(Stores lassen sich nicht aufzählen).

## 2026-09-21 — Wald in 3D mit SceneKit, aus Grundkörpern statt Modellen
Der Wald ist eine Insel in SceneKit (`ForestScene`), die Bäume aus Kegeln,
Kugeln und Zylindern, je Session eine Pflanzstelle in einer
Sonnenblumen-Spirale. **Warum:** Felix will einen Wald, der „richtig
ausgeschmückt, mindestens 3D" ist. SceneKit läuft in SwiftUI (`SceneView`)
und im Simulator, kennt Schatten, Nebel und Aktionen (der wachsende Baum ist
eine `scale`-Aktion), und ein paar hundert Knoten aus Grundkörpern reichen für
den Low-Poly-Stil — keine USDZ-Dateien im Repo, nichts zu laden. Die Varianz
je Baum kommt aus einem stabilen Hash der Session-Id, damit der Wald bei jedem
Start gleich aussieht. **Verworfen:** (a) RealityKit/`RealityView` (mächtiger,
aber auf Modelle und Materialien ausgelegt; für Kegel und Kugeln nichts
gewonnen, und die Simulator-Unterstützung ist dünner); (b) ein 2D-Wald aus
SF-Symbolen (war der erste Wurf, „noch nicht so schön"); (c) fertige
3D-Modelle (Lizenzfragen, Dateien im Repo, eine Pipeline für einen Baum).

## 2026-09-21 — Kurzbefehl „Fokus an" bekommt Minuten, kein Datum
Die App übergibt dem Kurzbefehl die Restdauer in Minuten („30"), nicht mehr den
Endzeitpunkt als Text. **Warum:** Ein Datum als Text muss der Kurzbefehl erst
lesen — Format, Sprache, Zeitzone —, und beim Testbaum lag die Zeit ohne
Sekunden schon in der Vergangenheit, was „Fokus einschalten bis" als „bis
morgen" nahm. Eine Zahl kennt keinen dieser Fehler; der Kurzbefehl rechnet sie
mit „Datum anpassen" auf das aktuelle Datum. **Verworfen:** (a) ISO-8601-Text
(löst Format und Zeitzone, nicht das Aufrunden und nicht das Lesen); (b) „Fokus
aus" aus der Erweiterung (Erweiterungen können keine Kurzbefehle starten).

## 2026-09-21 — Open Food Facts direkt aus der App, nicht über den Kalorienzähler
Der Barcode-Scanner fragt `world.openfoodfacts.org/api/v2/product/<code>.json`
selbst ab (`OpenFoodFactsAPI`, nur `product_name`, `brands`, `quantity`,
`serving_size`, `nutriments`, User-Agent `Cockpit-iOS/0.2 (private,
non-commercial)`, keine Cookies, keine Kennung). **Warum:** Es ist eine
öffentliche, anonyme Leseanfrage ohne Geheimnis — es gibt nichts, was ein
Server dazwischen schützen oder berechnen müsste; der Kalorienzähler bekommt
wie bisher nur das fertige Gericht (`POST /entries` mit `dish`). Ein Umweg
über `../food` hieße einen neuen Endpunkt, ein Ausrollen und eine zweite
Stelle, die die Antwort liest, nur um sie durchzureichen. Das Parsen liegt
in einem eigenen Typ (`OpenFoodFactsParser`) und ist aus echten Antworten
ohne Netz getestet. **Verworfen:** (a) ein Proxy-Endpunkt im Kalorienzähler
(`GET /api/food/lookup/{code}`) — mehr Code an zwei Stellen für dieselbe
Antwort, und ohne den Dienst geht dann auch das Scannen nicht; (b) eine
Produkt-Datenbank im Dienst spiegeln — Open Food Facts ist zu groß und
ändert sich laufend. Wird eine zweite Quelle nötig (Nutritionix, fddb),
ist das der Punkt, an dem ein Dienst-Endpunkt sinnvoll wird.

## 2026-09-21 — Scanner mit VisionKit statt AVFoundation
Der Scanner ist `VisionKit.DataScannerViewController` in einem
`UIViewControllerRepresentable`, nicht eine eigene `AVCaptureSession` mit
`AVCaptureMetadataOutput`. **Warum:** VisionKit bringt Kamera-Vorschau,
Fokus, Hervorheben des erkannten Codes, Zoom per Fingergeste und die
Anleitung („Code ausrichten") fertig mit — mit AVFoundation wären das alles
eigene Layer und eigene Delegaten. Die Abfrage `isSupported`/`isAvailable`
sagt vorher, ob es geht (im Simulator: nein), und die Kamera-Erlaubnis
holt die App selbst über `AVCaptureDevice`, bevor der Scanner steht. Preis:
iOS 16+, kein Simulator — beides gilt hier ohnehin (Deployment iOS 18, und
der Ablauf hinter dem Scan ist über `COCKPIT_SCAN` ohne Kamera prüfbar).
**Verworfen:** (a) `AVCaptureSession` + `AVCaptureMetadataOutput` — läuft
auch im Simulator nicht, aber deutlich mehr Code für weniger; (b) eine
Fremdbibliothek (z. B. CodeScanner) — eine Abhängigkeit für das, was das
System selbst kann.

## 2026-09-20 — Wald: Sperre über das Screen-Time-API, Ende in einer eigenen Erweiterung
Eine Fokus-Session sperrt alle anderen Apps über `ManagedSettings` (Schild auf
alle Kategorien außer der Whitelist aus Apples `FamilyActivityPicker`); das
Ende ist bei `DeviceActivity` angemeldet, und die Erweiterung `FokusMonitor`
leert den Store, wenn das Intervall abläuft. **Warum:** Felix will, dass
„alle anderen Apps gesperrt" sind — das kann auf iOS nur das Screen-Time-API,
und nur eine DeviceActivity-Erweiterung läuft garantiert am Ende, auch wenn
die App längst beendet ist. Die App räumt zusätzlich selbst auf, sobald sie
wieder aktiv ist, weil Apples Rückruf „zeitnah" kommt, nicht auf die Sekunde.
**Verworfen:** (a) nur ein Timer in der App (räumt nichts weg, wenn die App
nicht läuft — die Sperre bliebe stehen); (b) Geführter Zugriff / Sperren der
App auf sich selbst (sperrt nichts anderes, und Abbrechen wäre ein Dreifachklick
entfernt); (c) eine Fremd-App wie Forest (die kann weder das Habit speisen noch
Felix' Whitelist und Kurzbefehle).

## 2026-09-20 — Wald: Sessions liegen beim Habits-Dienst, Tag = Tag des Beginns
Die durchgestandenen Sessions speichert der Habits-Dienst
(`/api/focus/sessions`, `data/focus.json`), und das neue Habit „Fokus-Zeit"
(FOCUS, Tagesziel 240 Minuten) rechnet aus demselben Bestand. **Warum:** Felix
will das Habit mit dem Wald „synchronisiert" — ein Bestand, eine Regel, gerechnet
im Dienst wie alle Sträh­nen. Eine Session gehört zum Tag ihres **Beginns**
(Europe/Berlin), nicht anteilig zu beiden Tagen: wer um 23:30 pflanzt, hat am
Abend fokussiert, und eine Aufteilung machte aus einem Baum zwei halbe.
**Verworfen:** (a) Sessions nur auf dem Gerät (das Habit könnte sie nicht sehen,
und ein neues Handy hätte einen leeren Wald); (b) ein eigener Dienst (ein
vierter Spring-Boot-Prozess für eine Liste von Zeitpunkten); (c) Aufteilen an
Mitternacht.

## 2026-09-20 — Wald: kein Abbrechen, Mitteilungen über Felix' Kurzbefehle
Eine laufende Session hat keinen Abbrechen-Knopf und keinen Weg über die App
hinaus; Mitteilungen schaltet nicht die App, sondern die Kurzbefehle „Fokus an"
und „Fokus aus", die sie per x-callback-URL aufruft (mit dem Endzeitpunkt als
Eingabe). **Warum:** Beides Felix' Entscheidung — „vorzeitig abbrechen soll
nicht möglich sein", Mitteilungen „per Kurzbefehl automatisch". Den
Fokus-Modus des Systems darf eine App nicht selbst schalten; ein Kurzbefehl
darf es. „Fokus aus" kann erst laufen, wenn die App nach dem Ende wieder im
Vordergrund ist (Kurzbefehle starten nicht aus dem Hintergrund) — deshalb geht
der Endzeitpunkt mit, damit „Fokus an" den Modus bis dahin befristen kann.
**Verworfen:** (a) Abbrechen mit Strafe (verfaulter Baum) — ausdrücklich nicht
gewollt; (b) Mitteilungen nur über den Schild (der sperrt Apps, keine Banner);
(c) Felix schaltet den Fokus-Modus von Hand (vergisst man, und die Session
ist dann keine).

## 2026-09-20 — kcal als 7-Tage-Mittel, zentriert, gerechnet im Kalorienzähler
Die kcal-Kurven in beiden Verlaufsdiagrammen (Gewicht-Tab, Essen-Tab; Web
genauso) zeigen standardmäßig das **gleitende 7-Tage-Mittel**, der Tageswert
ist ein zweiter, blasserer Umschalter und aus. **Warum:** Felix will ein
„sinnvolles Mittel" statt der springenden Tageswerte; Tage ohne Eintrag
dürfen nicht als null einrechnen. Das Fenster ist **zentriert** (3 davor, der
Tag, 3 danach) wie das 7-Tage-Mittel des Gewichts – im selben Diagramm decken
beide Kurven dieselben Tage ab, und der vorläufige Rand ist gepunktet wie beim
Gewicht. Gerechnet wird im Kalorienzähler (`/api/food/daily-average`), nicht
in den Clients: vier Oberflächen, ein Wert. Felix hat zentriert gewählt und
für das Web das Mittel standardmäßig an (vorher waren die kcal dort aus).
**Verworfen:** (a) rückblickendes Fenster (steht am Rand sofort fest, läuft
dem Gewichtsmittel aber drei Tage hinterher); (b) 14 Tage (träger);
(c) Rechnen im Client (zweimal Swift, zweimal JS, und die App hat nur den
sichtbaren Zeitraum, das Fenster des ersten Tages bräuchte mehr).

## 2026-09-17 — 7-Tage-Residuum: Tagesmesswert gegen Tages-Target, gerechnet im Dienst
Die Kachel mittelt `Messwert − Target` **je Tag** über die letzten sieben
Kalendertage bis zur letzten Messung. **Warum:** Felix will einen fairen
Vergleich auch für die letzten Tage. Das zentrierte 7-Tage-Mittel reicht am
aktuellen Rand in noch ungemessene Tage und hinkt deshalb nach; der Abstand
eines Tages zu seinem eigenen Target steht fest, sobald der Tag gemessen ist.
Gerechnet wird im Weight Tracker (`residual7`, `residual7Days` in der Summary), nicht
in der App — sonst rechneten Web und App dieselbe Regel zweimal, und in der
App hängt die geladene Reihe am Zeitraum-Umschalter. Fehlen Tage, steht es
unter dem Wert („5 von 7 Tagen“, neuer `note`-Text an Kacheln); gefärbt wie
„Differenz z. Target“, beim Halten mit der halben Korridorbreite als Toleranz.
**Name:** „7-Tage-Residuum" — der statistische Begriff für genau diese
Größe, Messwert minus Modell (die Zielkurve); hieß am ersten Tag
„7-Tage-Differenz". Felix wollte einen fachlichen Namen und schlug
„7-Tage-Delta" vor; verworfen, weil ein „Delta über 7 Tage" als Veränderung
seit letzter Woche gelesen wird, nicht als Abstand zur Kurve.
„Soll-Ist-Abweichung" und „Bias" standen ebenfalls zur Wahl.
**Verworfen:** (a) `avg7 − target` aus der bestehenden Summary — genau das
Nachhinken, das die Kachel vermeiden soll. (b) Im Client aus der Monatsreihe
rechnen — zwei Implementierungen, und die Reihe ist nicht immer die vom Monat.
(c) Das Fenster auf „heute“ statt auf den letzten Messtag setzen — nach zwei
Tagen ohne Waage stünde ein 5-Tage-Mittel da, obwohl sieben gemessene Tage
vorliegen.

## 2026-09-11 — Linien und Zeiträume in einer Liste, Farbe als Hex-String
Ein Typ `Highlight` mit `kind` (band | line) statt zwei Endpunkten und zwei
Listen. **Warum:** dieselbe Verwaltung für beides — wer eine Linie anlegen
kann, muss sie auch in derselben Liste wiederfinden und entfernen können; und
der Dienst sortiert einmal nach `start`, egal was es ist. Die Farbe kommt
als `#rrggbb` wie bei den Einkaufs-Kategorien, nicht als Name aus einer
festen Palette: die acht Vorgabekreise sind Bequemlichkeit, der Farbwähler
darf alles. Antwort von POST und DELETE ist die **ganze** Liste — die App
ersetzt ihre Kopie, statt einen Eintrag in eine sortierte Liste einzufädeln.
**Verworfen:** (a) ein `Vacation` mit `start == end` als Linie deuten — ein
eintägiges Band ist etwas anderes als eine Linie, und die Deutung stünde
in zwei Clients. (b) Nur Zeiträume verwaltbar, Linien nur in der Datei —
dann stünde in der Liste etwas, das man nicht loswird.

## 2026-09-05 — Einkaufsliste: eigener Dienst, eigener Token, vierte App
**Warum:** Joana soll die Liste bedienen und sonst nichts sehen.
Der Privat-Token öffnet alles — also ein eigener Dienst (`fherrmann.com/
shopping-list`) mit eigenen Token je Person (`SHOPPING_TOKENS`), außerhalb des
Privat-Gates. Die App setzt den Token als Cookie nur für diesen Pfad; Healthy
zeigt den Tab, sobald er da ist, und **Einkaufsliste** ist derselbe Tab als eigene
App (`Shopping/` in beiden Targets). Der Name „Einkaufsliste" ist meine Wahl —
kurz, deutsch, passt neben Healthy/Vault/Fokus; leicht zu ändern, solange die
App noch auf keinem zweiten Handy liegt.
**Gerichte liegen im Einkaufs-Dienst, nicht im Kalorienzähler.** Der Plan sah
Zutaten an den Gerichten des Kalorienzählers vor (mit Migration). Felix wollte
„Gerichte speichern, die man als Ganzes auf die Liste packt" — das ist eine
Zutatenliste, keine Nährwertfrage. So kann sie auch seine Freundin pflegen,
ohne Schreibrecht auf den Kalorienzähler.
**Ohne Netz sofort sichtbar.** Der Store ändert seinen Stand selbst, wenn ein
Aufruf im Postausgang liegt (siehe `ARCHITEKTUR.md`) — im Laden fehlt das Netz
am häufigsten.
**Verworfen:** TestFlight für das zweite Handy (später, siehe Plan); Bearer-
Header statt Cookie in der App (der Dienst nimmt beides, das Cookie spart
einen zweiten Auth-Pfad im `APIClient`); Abschnitte je Kategorie in der Liste
(Felix: eine Liste, nur sortiert, mit Icons).

## 2026-09-04 — „Alles“ ist zurück, mit dem 30-Tage-Mittel als Vorgabe
**Warum:** Felix will die ganze Historie wieder sehen — als ruhige Kurve.
Über acht Jahre ist das 7-Tage-Mittel fast so unruhig wie die Messwerte; das
30-Tage-Mittel zeigt den Verlauf. Darum hat „Alles“ ein eigenes Angebot an
Umschaltern (30-Tage- statt 7-Tage-Mittel, ohne kcal als Vorgabe) und eine
eigene, gemerkte Auswahl — ein Wechsel zwischen den Zeiträumen tauscht keine
Haken aus. „3 Jahre“ bleibt daneben bestehen (siehe 2026-09-02).
**Verworfen:** fünf Umschalter in einer Reihe (zu breit fürs iPhone) und
geglättete Interpolation (überschwingt in Lücken, siehe 2026-09-02).

## 2026-09-04 — Drei Apps aus einem Repo: Healthy, Vault, Fokus
**Warum:** fünf Tabs waren voll, drei Dienste kommen dazu (To-Do, Roadmap,
Einkaufsliste), und die drei Gruppen haben verschiedene Nutzungen: täglich
eintragen, geschützt nachlesen, planen. Die Logik liegt in den Backends, die
Querverbindungen laufen serverseitig - der Schnitt kostet Struktur, keine
Funktion (`PLAN-AUFTEILUNG.md`).
**Ein Repo, drei Targets**, nicht drei Repos: Zugang, Cookies, Cache,
Postausgang, Sperre, Tools und Harness würden sonst dreifach gepflegt.
**Verworfen:** `Core/` als Swift-Package. Ordner, die in mehrere Targets
eingebunden werden, tun dasselbe ohne Paketverwaltung - und `Shared/` lief
so schon seit dem Widget.
**Healthy behält die alte Bundle-ID:** HealthKit-Berechtigung, Push-Anmeldung
beim Kalorienzähler und die vorhandenen Kalorien-Kacheln bleiben damit
unangetastet. Vault und Fokus sind neue Apps mit allem, was das heißt.

## 2026-09-04 — Eine geteilte Keychain-Gruppe, die Token wandern einmal
**Warum:** die Token sollen einmal eingegeben werden, nicht dreimal. Alle
fünf Targets tragen `com.fherrmann.shared` in den Entitlements; Healthy holt
die vorhandenen Einträge beim ersten Start aus der alten Vorgabegruppe
hinüber. Die alte Gruppe wird **nicht** geleert - fällt die Wanderung aus,
liest Healthy weiter von dort, und Vault/Fokus sagen sichtbar „Kein Zugang".
**Nicht gewandert:** das Noten-Passwort. Es liegt hinter Face ID; Vault fragt
es einmal neu ab, statt dass Healthy beim Start eine Abfrage zeigt, deren
Ergebnis sie selbst nie braucht.

## 2026-09-04 — Vault sperrt die ganze App, nicht zwei Tabs
**Warum:** in Vault liegt hinter jedem Tab etwas Schützenswertes. Eine Sperre
um alles ist weniger Code und ein klareres Versprechen: beim Verlassen zu,
beim Zurückkommen gleich wieder fragen, Sichtschutz im App-Umschalter immer.
Der `LAContext` dieser einen Sperre holt auch das Noten-Passwort heraus.

## 2026-09-03 — Offline: letzter Stand plus Postausgang, aber kein Nachrechnen
**Warum:** Felix' Wunsch — ohne Netz wenigstens die aktuellen Werte sehen,
im besten Fall auch Haken und Messwerte eintragen, die später nachgehen.
**Wie:** `APIClient` legt jede erfolgreiche GET-Antwort als Datei ab und
liefert sie bei einem Transportfehler zurück (nur dann — bei 403 oder 500 hat
der Dienst geantwortet, und den alten Stand darüberzulegen hieße, ein Problem
zu verstecken). Ausgewählte Änderungen gehen mit `queueWhenOffline: true` in
den `Outbox` und werden beim nächsten Netz der Reihe nach nachgesendet; lehnt
der Dienst eine ab (4xx), fliegt sie raus und der Grund steht in der Leiste.
**Bewusst nicht:** lokal nachrechnen. Ein offline gesetzter Haken zeigt eine
Uhr, keine neue Sträh­ne; ein offline eingetragenes Gewicht ändert die Kacheln
erst nach dem Nachsenden. Sonst stünde die Rechenregel an zwei Stellen — genau
das, was „Kein Offline-Cache" vom 01.09. vermeiden wollte. Die Entscheidung
von damals bleibt im Kern: kein zweiter Datenstand, nur ein Zwischenspeicher.
**Verworfen:** Anmeldung, Habit anlegen, Ziele ändern im Postausgang — dort
braucht man die Antwort sofort (eine ID, eine Bestätigung), und ein Passwort
hat in einer Warteschlange nichts verloren.

## 2026-09-02 — Zugang wird ein Blatt, weil fünf Tabs voll sind
**Warum:** iOS zeigt höchstens fünf Tabs; der sechste wandert unter „Mehr",
und dort landete ausgerechnet der Tab, den man braucht, wenn alles andere
„Kein Zugang" sagt. Zugang ist selten nötig - ein Zahnrad reicht.
**Verworfen:** Habits unter „Mehr" (der neue Tab wäre der versteckte),
Finanzen und Noten zusammenlegen (zwei Sperren, zwei Dienste).
**Nebenwirkung:** `COCKPIT_TAB=setup` gibt es weiter, öffnet aber das Blatt.

## 2026-09-02 — Habits: kein Web-UI, die App rechnet nichts
**Warum:** Felix' Entscheidung (API + Tab). Ohne zweite Oberfläche gibt es
keine Anzeigeregeln, die an zwei Stellen stimmen müssten - genau das Problem,
das die Übersicht der doppelt gepflegten Regeln beschreibt. Deshalb liefert
der Dienst `HabitStatus` fertig gerechnet: Sträh­ne, „heute erledigt",
„gefährdet". Die App zeigt und schickt Haken, sonst nichts.
**Auch so entschieden:** „Track food" zählt automatisch - ab 80 % des
kcal-Ziels oder wenn Frühstück, Mittag und Abend je einen Eintrag haben
(Felix' Regel, ein Snack ersetzt keine Mahlzeit).

## 2026-09-02 — Die Noten melden sich selbst, nicht über den Kalorienzähler
**Warum:** Felix' Entscheidung. Der naheliegende Weg wäre gewesen, das
food-Backend zur Push-Zentrale zu machen — dort liegen Schlüssel und
Gerätekennungen schon. Dagegen sprach die Kopplung: der Notendienst wäre für
seine eigene Meldung auf einen fremden Dienst angewiesen, und ein Ausfall des
Kalorienzählers nähme ihm die Stimme.
**Preis, bewusst bezahlt:** eine zweite APNs-Umsetzung (Python statt Java),
eine zweite Geräteliste und eine **Kopie** des `.p8` als `/etc/apns-grades.p8`.
Die Kopie statt einer Gruppenmitgliedschaft: die Dienste laufen unter
verschiedenen Benutzern, und `flexii` in die Gruppe `food` zu stecken gäbe
Zugriff auf alles, was dieser Gruppe gehört.
**Nicht verhandelbar war der Wächter selbst:** der Notenchecker bemerkt neue
Noten längst, liegt aber unter `/opt/notenchecker` und ist tabu. Wir lesen
seine Datei und vergleichen selbst.

## 2026-09-02 — Face ID ersetzt das Passwort, statt es zu ersparen
**Warum:** die Weboberfläche hat zwei Schranken, Geräte-Token und Anmeldung.
Die App spielt beide nach — der Endpunkt hätte sich auch mit dem Token allein
öffnen lassen, aber dann läse jeder die Noten, der den Token hat.
Benutzername und Passwort gibt Felix einmal ein; das Passwort liegt danach
hinter `.userPresence` im Keychain.
**Der Kniff:** der `LAContext`, mit dem der Tab entsperrt wurde, ist bereits
ausgewiesen. Die Keychain gibt das Passwort damit **ohne zweite Abfrage**
heraus - eine Sperre, zwei Zwecke.
**Verworfen:** das Passwort ungeschützt neben die Token legen. Die sind
Geräte-Token, die das Widget bei gesperrtem Bildschirm braucht; ein Passwort
braucht das nie.

## 2026-09-02 — Annahmen liegen in der App, nicht in der Sitzung
**Warum:** im Web merkt sich der Server die angenommenen Noten in der Sitzung.
Für die App wäre das derselbe Zustand für zwei Oberflächen: ein Tippen auf dem
Handy schriebe den Browser-Tab um, der nebenbei offen ist. Die App schickt sie
deshalb bei jeder Anfrage mit und merkt sie sich selbst.
**Gerechnet wird trotzdem dort:** die Regel aus PO-I23 § 8 Abs. 2 steht in
`berechnung.py` und nirgends sonst. Ein Nachbau in Swift wäre eine zweite
Stelle, an der eine Prüfungsordnung richtig sein muss.

## 2026-09-02 — Der UI-Harness bekommt seine Token über TEST_RUNNER_
**Warum:** `xcodebuild` reicht **nur** so präfixierte Variablen an den
Testläufer weiter und streicht das Präfix dabei. Vorher standen sie ohne
Präfix im Skript — der Testläufer sah leere Token, und die Läufe waren
trotzdem grün, weil im Simulator noch Token vom letzten `run-simulator.sh` im
Keychain lagen. Ein Harness auf Resten sieht aus wie einer, der prüft.
**Nebenbei entstanden:** `COCKPIT_URL_<DIENST>` biegt im Debug-Build die
Adresse eines Dienstes um. Damit läuft der Noten-Tab gegen einen lokal
gestarteten Dienst - der einzige Weg, ihn mit echten Daten zu sehen, ohne ein
Passwort in den Schlüsselbund dieses Rechners zu legen.

## 2026-09-02 — Das Widget holt seine Daten selbst
**Warum:** eine Widget-Erweiterung ist ein eigener Prozess mit eigenem
Container; die Cookies der App sieht sie nicht. Sie liest das Token aus der
**Keychain-Zugriffsgruppe** — der Vorgabegruppe der App, in der es ohnehin
liegt — und ruft `/api/food/day` selbst auf. Die App stößt nach einer Änderung
nur ein Neuzeichnen an.
**Verworfen:** eine App Group, in die die App den letzten Stand schreibt. Das
wäre ein zweiter Datenstand (siehe „Kein Offline-Cache"), und das Widget zeigte
alte Zahlen weiter, wenn die App länger nicht lief. Es zeigt jetzt lieber den
letzten bekannten Stand **mit Datum**, statt ihn als heutigen auszugeben.
**Verworfen:** eine zusätzliche Keychain-Gruppe. Die Vorgabegruppe
(`$(AppIdentifierPrefix)com.fherrmann.cockpit`) reicht, solange beide Ziele
mit demselben Team signiert sind.

## 2026-09-02 — Die Finanz-Sperre prüft den Gerätebesitzer, nicht das Gesicht
**Warum:** `deviceOwnerAuthentication` fällt auf den Gerätecode zurück, wenn
Face ID fehlschlägt oder nicht eingerichtet ist. `…WithBiometrics` hätte den
Tab auf einem Gerät ohne Face ID unerreichbar gemacht — und im Simulator jeden
Test.
**Fallstrick, teuer gelernt:** `evaluatePolicy` schiebt den Systemdialog vor
die App, die damit `.inactive` wird. Wer beim Verlassen des Vordergrunds neu
sperrt, sperrt sich mitten in der eigenen Abfrage — der Dialog kommt sofort
wieder, endlos. Deshalb das `isAuthenticating`-Flag.

## 2026-09-02 — Die Schritte bekommen eine Leiste, keinen Tacho
**Warum:** der Tacho im Essen-Tab beantwortet „drüber oder drunter" und hat
dafür eine Zielkerbe. Schritte sind ein Mindestwert — es geht um „wie weit",
und dafür ist ein Balken die naheliegendere Form. Über dem Ziel bleibt er voll
statt aus dem Rahmen zu laufen; dass es mehr war, sagt die Zahl daneben.

## 2026-09-02 — Jede Kachel ist entfernbar, und die gespeicherte Liste ist vollständig
**Warum:** vier fest verdrahtete Kacheln waren eine Annahme darüber, was
jemand sehen will. „Komplett modular" heißt auch: alle weg ist ein gültiger
Zustand.
**Der Haken war die Umstellung.** Alte und neue Bedeutung sehen als JSON
gleich aus — eine Liste von Schlüsseln. Ohne Unterscheidung hätte das erste
Laden nach dem Deploy vier Kacheln stillschweigend gelöscht. Deshalb ein
`version`-Feld: fehlt es, gilt die alte Bedeutung, und der Server ergänzt.
Das schützt auch einen Browser-Tab, der die Umstellung noch nicht kennt.
**Die vier früheren Basis-Schlüssel stehen jetzt im Backend** — bewusst als
eingefrorener Schnappschuss für die Umstellung, nicht als zweite Registry:
welche Kacheln es gibt, weiß weiterhin nur die Oberfläche.

## 2026-09-02 — Gerade Linien, keine geglätteten Kurven
`.interpolationMethod(.linear)` in beiden Diagrammen.
**Warum:** Catmull-Rom überschwingt zwischen weit auseinanderliegenden Punkten
und zeichnet Werte, die nie gemessen wurden. Mit der importierten Historie —
teils Monate zwischen zwei Messungen — wäre das grob irreführend. Eine gerade
Verbindung behauptet nur, was zwischen zwei Messungen bekannt ist: nichts.
**Verworfen:** Glättung wie in der Weboberfläche (`tension: 0.2`), die dort
über dichte Tagesdaten läuft und deshalb weniger anrichtet.

## 2026-09-02 — „3 Jahre" statt „Alles", zugeschnitten im Client
**Warum:** ein rollendes Fenster ist über neun Jahre lesbarer als die gesamte
Historie, in der die letzten Monate zu einem Strich zusammenschrumpfen. Der
Zuschnitt passiert im Client, weil die Reihe klein ist und ein eigener
Endpunkt je Zeitraum Backend-Arbeit für eine reine Anzeigefrage wäre.
**Verworfen:** ein `/api/weight/three-years` (Deploy für eine Beschriftung).

## 2026-09-02 — Health-Werte füllen nur Lücken
`keepExisting` im Backend, gesetzt nur vom Abgleich.
**Warum:** es gibt genau einen Wert pro Tag, und der von Hand eingetragene ist
der verlässlichere. Ohne diese Regel hinge das Ergebnis daran, wer zuletzt
geschrieben hat — je nach Weckzeitpunkt von iOS mal so, mal so.
**Warum im Backend und nicht im Client:** dort ist die Prüfung atomar und gilt
für jeden, der schreibt; im Client wäre sie ein Wettlauf zwischen Lesen und
Schreiben. Im Browser und in der App bleibt Überschreiben ausdrücklich erlaubt
— die Schonung gilt nur für Importe.

## 2026-09-02 — Der erste Abgleich holt weiterhin alles
**Warum:** Felix' Entscheidung, nachdem der erste Lauf 265 Werte zurück bis
2018 eingespielt hat. Eine Neuinstallation spielt sie also wieder ein — was
folgenlos ist, seit vorhandene Tage geschont werden.
**Was dabei schiefging und die Entscheidung nötig machte:** ich hatte den
ersten Abgleich ohne Grenze gebaut. Dass damit acht Jahre Historie in den
Tracker laufen, hätte vorher zur Sprache gehört, nicht hinterher.

## 2026-09-02 — Die früheste Messung eines Tages gewinnt
**Warum:** Health kennt beliebig viele Messungen pro Tag, der Weight Tracker
genau eine. Morgens nüchtern ist der über Tage vergleichbare Wert; eine
Abendmessung liegt regelmäßig ein bis zwei Kilo darüber und würde die Kurve
verrauschen.
**Verworfen:** die letzte Messung (Abendwert), der Tagesdurchschnitt (mischt
zwei verschiedene Messbedingungen).

## 2026-09-02 — Push liegt im food-Backend, nicht in der App
**Warum:** die Schnellerfassung läuft dort ohnehin schon asynchron. Nur der
Server weiß, wann ein Auftrag fertig ist — und nur er läuft weiter, wenn das
Handy gesperrt ist.
**Ohne Bibliothek:** APNs ist ein HTTP/2-POST mit einem signierten Token im
Kopf, und beides kann das JDK. Eine Abhängigkeit für dreißig Zeilen wäre mehr
Pflege als Ersparnis. Der Fallstrick steckt in der Signatur (DER → JOSE), und
darauf zeigen drei Tests.
**Die App fragt trotzdem weiter selbst nach:** die Benachrichtigung ist ein
Zustellweg, keine Voraussetzung.

## 2026-09-01 — Die Schnellerfassung wartet nicht mehr im Blatt
Der Auftrag gehört dem Store, nicht der Ansicht. Abschicken schließt das Blatt
sofort; das Nachfragen läuft weiter, eine Zeile in der Tagesliste zeigt es an,
und ist der Vorschlag da, geht er von selbst auf.
**Warum:** eine Minute auf ein Blatt zu starren, das nichts tut, war der
schlechteste Teil des Ablaufs — und der Server arbeitet ohnehin schon
asynchron, nur die App stand daneben.
**Die Kennung wird gemerkt** (`UserDefaults`): wird die App weggeräumt,
rechnet der Server weiter, und ohne die Kennung wäre das Ergebnis danach
nicht mehr abholbar.
**Benachrichtigung nur, wenn die App nicht im Bild ist** — sonst sieht man das
Blatt ohnehin aufgehen, und die Meldung wäre Lärm.
**Grenze, bewusst in Kauf genommen:** liegt das Handy gesperrt, friert iOS die
App nach etwa 30 Sekunden ein; der Auftrag dauert bis zu 56. Die Meldung kommt
dann erst beim nächsten Öffnen. Für „Handy weglegen" bräuchte es echtes Push
und damit einen APNs-Dienst im food-Backend.

## 2026-09-01 — Der Zeitbereich eines Diagramms kommt vom gewählten Zeitraum
`FoodChartView` bekommt `from`/`to` von außen; die Achse steht per
`.chartXScale`, statt sich aus den Daten zu ergeben.
**Warum:** aus den Daten abgeleitet hingen daran gleich **drei** Fehler, die
wie drei verschiedene aussahen. Bei zwei erfassten Tagen war die Achse zwei
Tage breit — daher „1. Sep" doppelt (die automatischen Achsenmarken lagen
innerhalb eines Tages und formatierten sich zum selben Text). Der
Zeitraum-Umschalter änderte sichtbar nichts, weil 14, 30 und 90 Tage
dasselbe Bild ergaben. Und die Gewichtskurve war auf den ersten Tag mit
kcal-Eintrag zugeschnitten, blieb also auf zwei Punkte zusammengestrichen,
obwohl 90 Werte vorlagen.
**Die Lehre:** ein Diagramm zeigt einen *Zeitraum*, keine *Datenmenge*. Die
Datenlage bestimmt, was darin steht — nicht, wie breit es ist.
**Verworfen:** die Achse weiter aus den Daten ableiten und nur die
Beschriftung reparieren — das hätte den Umschalter wirkungslos gelassen.

## 2026-09-01 — kcal als Kurve, an jeder Lücke getrennt
Im Verlauf des Kalorienzählers standen erst Säulen; jetzt ist es eine Linie.
Dieselbe Kurve liegt zusätzlich über der Gewichtskurve im Gewicht-Tab.
**Warum getrennt:** `dailyTotals` liefert **nur Tage mit Einträgen** — fehlende
Tage sind unbekannt, nicht null. Eine durchgezogene Linie darüber hinweg würde
behaupten, dazwischen sei etwas gemessen worden. Dieselbe Entscheidung wie
`spanGaps: false` im Web. Ein einzelner Tag zwischen zwei Lücken bekommt einen
Punkt, sonst wäre er unsichtbar.
**Was die Säulenfarbe trug,** übernimmt jetzt ein roter Punkt an Tagen, die
mehr als 100 kcal über dem Ziel liegen — sonst ginge die Information mit den
Säulen verloren.

## 2026-09-01 — Diagrammfarben folgen dem Erscheinungsbild, der Rest von selbst
`Palette.adaptive(light:dark:)` statt fester Werte.
**Warum:** die Farben stammen aus den Weboberflächen, und die sind dunkel.
Dieselben hellen Pastelltöne auf weißem Grund haben zu wenig Kontrast — die
7-Tage-Kurve war kaum vom Hintergrund zu unterscheiden. Im Dunkeln bleibt es
exakt bei den Webwerten, damit dieselbe Kurve in App und Browser gleich
aussieht; im Hellen kommt die kräftigere Stufe derselben Farbe.
**Verworfen:** einen eigenen Farbsatz erfinden (dann sähen App und Browser
verschieden aus) und alles hell zu lassen (schlechter lesbar).

Alles andere — Karten, Listen, Leisten, Tacho-Spuren — folgt dem System schon,
weil durchgehend Systemfarben und `.thinMaterial` benutzt werden. Das war kein
Zufall, sondern der Grund, keine eigenen Grautöne zu setzen.

## 2026-09-01 — Der Simulator bekommt die Token über die Umgebung
`Access.seedFromEnvironment()`, nur unter `#if DEBUG`, gefüttert von
`tools/run-simulator.sh` aus dem macOS-Schlüsselbund.
**Warum:** ohne Zugang zeigen die nativen Tabs nur Fehlermeldungen, und
Layoutfehler sieht man erst mit echten Daten — die drei oben gefundenen hätte
kein Test gefunden. Von Hand eintippen wäre bei jedem Simulator-Neustart
fällig.
**Warum hinter `#if DEBUG`:** ein Token, das über eine Umgebungsvariable in
die App kommt, hat in einem Build für ein echtes Gerät nichts zu suchen.
**Verworfen:** Token in einer Datei im Repo (landet in Git), UI-Test zum
Eintippen (viel Maschinerie für ein Textfeld).

## 2026-09-01 — Die Gewichtskurve wird in die kcal-Skala hineingerechnet
Swift Charts kennt nur **eine** y-Skala. Das Gewicht wird deshalb linear in
den kcal-Bereich abgebildet und rechts mit eigenen Beschriftungen versehen.
**Warum:** die Zusammenschau „viel gegessen → Gewicht reagiert" ist der Grund,
warum die Kurve überhaupt im Kalorienzähler steht; ihr Verlauf stimmt durch die
Abbildung, und die rechte Achse sagt, welche Kilogramm dahinterstehen.
**Verworfen:** zwei getrennte Diagramme untereinander (der zeitliche Bezug geht
verloren, genau der ist aber der Punkt), und die Kurve wegzulassen.

## 2026-09-01 — Serverfehler behalten ihren Wortlaut
`APIError.http(Int, String?)` statt nur des Statuscodes.
**Warum:** die Backends begründen einen 400 im Klartext („Die Anteile müssen
zusammen 100 % ergeben, sind aber 96,0 %"). Diese Meldung wegzuwerfen und
„HTTP 400" anzuzeigen wäre die schlechtere von beiden. HTML-Antworten und alles
über 300 Zeichen werden verworfen — ein Stacktrace gehört nicht auf den
Bildschirm.

## 2026-09-01 — Die Aufteilung der Mahlzeiten wird im Client vorgeprüft
**Warum:** der Server nimmt sie nur vollständig und auf 100 % summierend an.
Das erst nach dem Sichern zu erfahren, obwohl beide Zahlen auf dem Bildschirm
stehen, wäre unnötig. Der Server prüft weiterhin selbst — die Vorprüfung ist
Bequemlichkeit, keine Absicherung.

## 2026-09-01 — Ein Diagramm mit Umschalter statt vier untereinander
Die Weboberflaeche zeigt 30 Tage, 90 Tage, 365 Tage und „all time" als vier
gestapelte Diagramme. Nativ ist es **eines** mit einem Segment-Umschalter.
**Warum:** auf einem Handy bedeuten vier Diagramme untereinander vor allem
Scrollweg; man sieht nie zwei davon gleichzeitig, der Vergleich, für den das
Stapeln gedacht ist, findet also ohnehin nicht statt.
**Verworfen:** vier Diagramme wie im Web (viel Scrollen), Wischen zwischen
Zeiträumen (kollidiert mit dem Wischen zwischen Tabs).

## 2026-09-01 — Das Linien-Zerlegen liegt neben der View, nicht darin
`WeightChartData` statt privater Methoden in `WeightChartView`.
**Warum:** das Zerlegen an der Vollständigkeitsgrenze ist die einzige Stelle
im Diagramm mit echter Logik — und ein Fehler darin sieht aus wie ein
Datenproblem, nicht wie ein Programmfehler. In einer View wäre sie nicht zu
testen; jetzt hängen fünf Tests daran. Einer davon hat prompt eine falsche
Annahme von mir aufgedeckt: das verbindende Stück gehört zum **früheren**
Punkt, genau wie im Web (`points[ctx.p1DataIndex]`).
**Verworfen:** in der View lassen und „sieht richtig aus" als Prüfung.

## 2026-09-01 — Kacheln als Enum statt als Tabelle von Closures
**Warum:** die Web-Registry ist ein Objekt aus Closures; in Swift wäre das
unter strikter Nebenläufigkeit eine nicht-`Sendable` Globale. Als Enum ist
jede Kachel an einer Stelle vollständig beschrieben, und der Compiler merkt,
wenn bei einer neuen Kachel ein Fall fehlt.

## 2026-09-01 — Das App-Icon wird erzeugt, nicht abgelegt
`tools/make-icon.swift` zeichnet die 1024er-PNG.
**Warum:** so ist nachvollziehbar, woraus das Icon besteht, und eine
Farbänderung ist eine Zeile statt einer neuen Datei aus einem
Grafikprogramm. Motiv ist ein Instrument mit dreigeteiltem Bogen — in den
Verlaufsfarben, die die Tachos des Kalorienzählers schon benutzen.
**Verworfen:** ein in einem Grafikprogramm gebautes Icon (nicht
nachvollziehbar, nicht diff-bar).

## 2026-09-01 — Hybrid statt „alles nativ"
Essen und Gewicht werden nativ, Finanzen bleibt WebView.
**Warum:** Weight und Food haben sauberes JSON-REST, da kostet nativ fast nur
UI-Arbeit. Das Finance Cockpit hat kein API und soll keins bekommen: seine
Seite wird täglich von einem Claude-Lauf neu gestaltet — eine feste
JSON-Struktur plus Rendering im Client würde genau diese Freiheit nehmen.
**Verworfen:** alles nativ (+2–3 Tage und ein Rückschritt beim Cockpit),
alles WebView (dann keine Widgets, kein HealthKit, keine Shortcuts).

## 2026-09-01 — Erst WebView, dann Tab für Tab nativ ersetzen
**Warum:** liefert ab Tag 1 eine benutzbare App und macht jeden Zwischenstand
lauffähig. Bricht die Arbeit ab, steht trotzdem etwas Fertiges da.
**Verworfen:** nativ von Anfang an — sechs Tage ohne benutzbares Ergebnis.

## 2026-09-01 — Gewicht vor Essen
**Warum:** der kleinere Tab (990 statt 1564 Zeilen Weboberfläche) und der
geradlinigere Datenfluss. Swift Charts einmal am einfachen Fall lernen, bevor
Mahlzeiten, Gerichte-CRUD und die Schnellerfassung drankommen.
**Verworfen:** Essen zuerst, weil es der meistgenutzte Tab ist — dafür wäre
der Einstieg der steilste Teil.

## 2026-09-01 — XcodeGen statt eingecheckter `.xcodeproj`
`project.yml` ist die Quelle, das Projekt wird erzeugt.
**Warum:** eine `pbxproj` ist eine mehrere tausend Zeilen lange Datei mit
generierten IDs — unlesbar im Diff, konfliktanfällig, und ein Agent, der eine
Datei hinzufügen soll, muss sie fehlerfrei patchen. Mit XcodeGen heißt „Datei
hinzufügen": Datei anlegen, `tools/bootstrap.sh`.
**Verworfen:** (a) `.xcodeproj` einchecken — siehe oben. (b) Xcode-16-
Synchronized-Groups, die dasselbe ohne Zusatzwerkzeug könnten, aber eine von
Hand geschriebene `pbxproj` als Startpunkt brauchen, die hier niemand
verifizieren kann, solange kein Xcode installiert ist. Wenn die
XcodeGen-Abhängigkeit später stört: dann ist der Umstieg ein Einzeiler-Commit.

## 2026-09-01 — Signatur bleibt bei Team `ZWFV263P59`
Kein Wechsel nötig: bei der Aufnahme als Einzelperson wird das bestehende Team
aufgewertet, die ID bleibt. `project.yml` musste dafür nicht angefasst werden.
**Erwartet hatte ich das Gegenteil** — eine zweite Team-ID — und habe deshalb
vorab vor Nebenwirkungen gewarnt, die es gar nicht gibt: Keychain-Einträge
sind an das Team-Präfix gebunden und wären bei einem Wechsel verloren gewesen,
und iOS hätte die App nicht über eine anders signierte drüberinstalliert. Beides
entfällt.
**Erkennungsmerkmal ist deshalb die Gültigkeit des Profils, nicht die ID:**
sieben Tage kostenlos, ein Jahr bezahlt.

## 2026-09-01 — Token im Keychain, Cookies beim Start gesetzt
**Warum:** die Backends kennen nur Cookie-Auth. Die App setzt die Cookies
selbst, statt den Browser-Weg `\/setup?token=…` nachzuspielen — ein Ritual
weniger pro Gerät, und das Token liegt an der einzigen Stelle, die dafür
gedacht ist.
**Verworfen:** Token im Code oder in einer `.plist` (landet im Repo bzw. im
App-Bundle und ist damit auslesbar).

## 2026-09-01 — Kein Offline-Cache
**Warum:** alle drei Dienste sind öffentlich über HTTPS erreichbar, die
Datenmengen sind winzig. Ein Cache brächte einen zweiten Datenstand samt
Konfliktauflösung für ein Problem, das es noch nicht gibt.
**Neu bewertet am 03.09.2026** (siehe oben): ein Zwischenspeicher mit Datum
und ein Postausgang — aber weiterhin kein zweiter Datenstand mit eigener Logik.

## 2026-09-01 — Bezeichner englisch, Kommentare deutsch
**Warum:** deckt sich mit den Java-Backends (englische Typen, `WeightPoint`,
`DaySummary`) und mit Felix' Doku-Sprache. Kommentare erklären das Warum.
