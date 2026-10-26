# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

## 2026-10-26 — Fokus: „Heute" im To-Do-Tab
Felix: „ich habe immer eine ganze Menge in der Todo-App stehen“ - er will einzelne Aufgaben
per Klick in „Heute“ holen, dort ordnen, was zuerst drankommt, und Aufgaben ohne Liste
anlegen. In iOS eine Unterseite von To-Do, im Web ein Reiter direkt neben „To-Do“.
Entschieden in der Fragerunde:
- **Kein Tagesreset:** was geholt ist, bleibt, bis es erledigt oder rausgenommen ist.
  Verworfen: jeden Morgen leer (Offenes fällt in seine Liste zurück) und „leer, aber Gestern
  zum Übernehmen anbieten“. Erledigtes steht bis Mitternacht durchgestrichen unten.
- **Unteraufgaben auch einzeln:** eine geholte Aufgabe bringt ihre Unteraufgaben mit,
  eine Unteraufgabe lässt sich aber auch allein holen (dann „Uni › Hausarbeit“ darunter).
  Verworfen: nur Hauptaufgaben; jede Zeile für sich ohne Unteraufgaben.
- **Umschalter in der Titelzeile** (`To-Do | Heute`, Felix: „auf der gleichen Ebene wie
  To-Do“), gemerkt über Neustarts. Verworfen: Heute als erste Wischseite vor den Bereichen;
  ein Knopf, der Heute als eigene Seite öffnet; der Umschalter als eigene Zeile unter dem
  Titel. Folge: der Name des Bereichs steht jetzt über der Liste („Uni · 3 offen“) statt im
  Titel.
- **Holen per Sonne in jeder Zeile** (grau: nicht in Heute, orange: drin), dazu im Menü
  „Nach Heute holen“ - wie im Browser. Zuerst hatte Felix „Wischen nach rechts + Menü“
  gewählt (Sonne nur an geholten, damit die Listen ruhig bleiben). Das ging nicht: das
  blätternde TabView der Bereiche nimmt sich jede waagerechte Geste, im UI-Test landete das
  Wischen in „Uni“ statt bei der Aktion - das trifft auch das alte „Löschen“ per Wischen
  nach links. Felix hat dann die Sonne gewählt. Verworfen: nur das Menü (zwei Schritte statt
  eines Klicks); Bereiche ohne Blättern (Wechsel über ein Menü am Namen), damit beide
  Wischgesten gehen. Im Browser stand erst der Text „Heute“ neben „Löschen“ - der schob die
  Knöpfe jeder Zeile unter den Titel, darum auch dort die Sonne.
- **Ordnen über „Ordnen“** neben der Kopfzeile: die Griffe von iOS (≡), „Fertig“ beendet.
  Geplant war nur langes Drücken und Ziehen ohne Bearbeiten-Modus - das hängt auf dem iPhone
  davon ab, ob die Liste Ziehen zulässt (ab Werk aus), und ließ sich nicht prüfen: XCUITest
  bewegt in dieser Liste nicht einmal die Griffe. Die Griffe gehen sicher; `onMove` gilt für
  beides, zieht das lange Drücken auf dem Gerät doch, umso besser. Im Browser zieht man am
  Griff ⠿ direkt. Rausnehmen bzw. Löschen (ohne Bereich) liegt
  in Heute auf dem Wischen nach links - dort blättert nichts.
- **„Heute“ als Liste von Kennungen beim Dienst**, nicht als Feld an der Aufgabe: die
  Reihenfolge ist ein `PUT /api/today`, ohne Ränge, die beim Einfügen umgerechnet werden
  müssten. Im Overlay ebenso eine Liste, die Einträge selbst kommen aus den Bereichen
  (Aufgaben ohne Bereich in einem namenlosen Bereich, der nie als Seite erscheint).

## 2026-10-23 (18:00) — Healthy: die Uhr-Komplikation zeigt den Rest in der Mitte
Felix: „hatte ich nicht gesagt, ich möchte, dass im Health-Widget auf der Uhr die übrigen und
nicht die verbrauchten kcal in der Mitte angezeigt werden?“ - mit „iOS-Widget“ (15:30) war auch
die Uhr gemeint; dort war die Komplikation bewusst stehen geblieben.
- **Mitte: der Rest** (`KcalGaugeView.center`), drüber mit Plus davor (`+120`) wie im runden
  Ring des Sperrbildschirms - für „drüber“ ist im runden Feld kein Platz. Gilt für die
  Komplikation und die Uhr-App, die dieselbe Ansicht zeigt.
- **Der Bogen bleibt**: links 0 (grün), rechts das Tagesziel (orange), gefüllt mit dem
  Gegessenen - wie auf dem iPhone. Verworfen: den Bogen mit dem Rest füllen (er liefe vom
  vollen Ziel rückwärts, gegen die 0 links).
- Damit ist die Entscheidung vom 14.10. („Mitte gegessen“) zurückgenommen.

## 2026-10-23 (abends) — Healthy: „Defizit Tag“, das Defizit jedes Tages als Kurve
Felix: „eine zusätzliche Defizit-Kurve, die den tatsächlichen Wert anzeigt“ - in allen
Oberflächen, also im Essen-Verlauf und im Gewicht-Diagramm (Vertrag §5).
- **Nur abgeschlossene Tage** (Felix, in der Fragerunde): heute fehlt, auch als Prognose;
  Tage ohne Wert (nicht getrackt, keine Uhr) sind Lücke. Verworfen: heute als Prognose
  gestrichelt angehängt - der Wert ändert sich über den Tag, die Kurve soll zeigen, was war.
- **Wie „kcal Tag“ zu „kcal ⌀“:** blasse dünne Linie in der Defizit-Farbe (55 %), Schalter
  direkt hinter „Defizit ⌀“, nur angeboten, ohne Verbrauch nicht da. Verworfen: vorgewählt -
  die Tageswerte springen um über tausend kcal, das Mittel sagt, wie die Woche lief.
- **Eine Skala für beide Defizit-Kurven**, die Tageswerte zählen nur, solange ihre Kurve an
  ist; die Nulllinie steht einmal. Verworfen: eine eigene Skala für die Tageswerte - dieselben
  kcal lägen auf zwei Höhen, und rechts stünden zwei Defizit-Achsen. Der Preis: mit beiden
  Kurven wird „Defizit ⌀“ flacher.
- **Kein Debug-Schalter für die Kurven im Essen-Verlauf**: der UI-Test
  `testFoodHistoryOffersTheDailyDeficit` tippt „Defizit Tag“ an. Verworfen: `COCKPIT_SERIES`
  auch im Essen-Tab auswerten - ein Schalter mit zwei Bedeutungen.

## 2026-10-23 (15:30) — Healthy: die Heute-Kachel zeigt den Rest statt des Gegessenen
Felix: „im iOS-Widget hätte ich gerne die noch übrigen kcal und nicht mehr die verzehrten“.
Gegessenes zeigte nur noch die große Sperrbildschirm-Kachel „Heute“; die Kalorien-Kacheln
zeigen schon den Rest.
- **Unter dem kcal-Ring steht der Rest in den Worten der Kalorien-Kachel**: `750` `kcal übrig`,
  drüber `120` `kcal drüber` (`RemainingCalories.remainingValue`/`remainingUnit`, beide Kacheln
  nehmen sie). Verworfen: nur die Zahl mit „kcal“ - neben „8.123 Schritte“ (zum Ziel hin)
  läse sich der Rest wie Gegessenes; das Plus des kleinen runden Rings („+120“) - dort ist es
  dem Platz geschuldet, hier passt das Wort.
- **Der Ring füllt sich weiter mit dem Gegessenen** gegen das Ziel, wie beim runden kcal-Ring.
  Verworfen: ein Ring, der sich leert - er liefe gegen den Schritte-Ring daneben.
- ~~Die Uhr-Komplikation bleibt bei „gegessen in der Mitte“~~ - falsch verstanden, siehe
  18:00: auch auf der Uhr steht jetzt der Rest.

## 2026-10-23 (nachmittags) — Sport-Uhr: Zählseite nach dem ersten Ausprobieren
Felix' Entscheidungen:
- **Die anderen oben, wir unten** - wie das Feld von unserer Seite aus. Verworfen: wir oben (so
  war es zuerst).
- **Der Aufschlag merkt sich den Spieler, links oder rechts.** Je Team schlägt abwechselnd der
  linke und der rechte Spieler auf; der Ball steht in der Hälfte des aufschlagenden Teams auf
  dessen Seite und läuft über die Sätze weiter. Verworfen: die Seite, von der innerhalb eines
  Spiels aufgeschlagen wird (erster Punkt rechts, dann abwechselnd).
- **Anfangs rechts, Antippen des Balls tauscht** - beim ersten Aufschlagspiel eines Teams und
  wenn ein Team zu Satzbeginn die Reihenfolge ändert. Verworfen: links oder rechts vor dem Start
  wählen (das andere Team ginge so ohnehin erst bei seinem ersten Aufschlagspiel).
- **Versehentliche Punkte direkt auf der Zählseite zurücknehmen.**

Ohne Rückfrage entschieden:
- **„Zurück“ links in der Zeile zwischen den Hälften**, die Steuerseite behält ihres. Verworfen:
  nur auf der Steuerseite - mitten im Spiel ein Wischen zu weit weg. Es nimmt die letzte Aktion
  zurück, auch ein Antippen des Balls.
- **Im Tie-Break wechseln die Spieler reihum wie in den Spielen**, und danach geht es so weiter.
  Die Regel lässt beiden Teams zu Satzbeginn die Wahl - dafür ist das Antippen da.
- **Die Zählseite lässt unten Platz für die Seitenpunkte.** Verworfen: bis an den Rand (so war es,
  und die runden Ecken des Displays schnitten die untere Hälfte an).
- **Ein gemerkter Stand von vorher lädt weiter** (`storedServers` fehlt → rechts), damit ein
  laufendes Match ein Update übersteht.

## 2026-10-23 — Sport: eigene App für Padel und Gym, eigene Uhr-App, Ergebnisse von der Uhr
Felix' Entscheidungen:
- **Eigene App „Sport“** (`com.fherrmann.sport`) mit Padel und Gym; der Gym-Tab zieht aus
  Healthy aus. Verworfen: Padel als weiterer Tab in Healthy (Healthy ist Essen, Gewicht,
  Recovery) und Padel weiter nur als Seite des Dienstes.
- **Padel-Tab nativ.** Verworfen: die Seite des Dienstes im WebView (schneller gebaut, aber
  ohne letzten Stand ohne Netz und fremd neben dem Gym-Tab).
- **Eigene Uhr-App „Sport“**; die Uhr-App von Healthy behält nur die kcal-Komplikation und
  verliert HealthKit ganz. Verworfen: das Krafttraining in Healthys Uhr-App lassen -
  `HKHealthStore.startWatchApp` weckt nur die Uhr-App der eigenen App, der Gym-Tab in Sport
  könnte sie nicht starten.
- **Training auf der Uhr:** Pausenzeit (einmal Vibrieren 90 s nach dem letzten Satz),
  Geräteliste zum Wechseln (wenn eins besetzt ist), Sätze abhaken. Nicht gewählt: Gewicht auf
  der Uhr ändern, einen Satz zurücknehmen.
- **Padel-Match auf der Uhr** als Training in Health (vor allem die kcal), mit Seiten für
  Werte, Musik und Punkte; Golden oder Silver Point einstellbar; wer aufschlägt, läuft über
  das Satzende weiter. Das Ergebnis landet von selbst an der Playtomic-Buchung zu dieser Zeit,
  sobald Playtomic das Eintragen erlaubt.

Ohne Rückfrage entschieden:
- **Zuordnung und Eintragen macht der Padel-Dienst**, die Uhr schickt nur Beginn, Ende, Regel
  und Sätze (`POST /api/results`). Verworfen: die App trägt selbst bei Playtomic ein - die
  Playtomic-API erreicht nur der Heimserver, und die Anmeldung dort liegt beim Dienst.
- **Die Uhr schickt selbst und zugleich übers iPhone**, der Dienst nimmt jede Kennung nur
  einmal an. Verworfen: nur einer der Wege - beim Padel hat die Uhr meist nur das iPhone als
  Netz, und `transferUserInfo` erreicht das iPhone auch, wenn Sport dort nicht läuft.
- **Abgegeben werden nur fertige Sätze, und nur, wenn alle gültig sind** (6 mit zwei Spielen
  Abstand, 7:5, 7:6). Beenden geht jederzeit; ein angefangener Satz fällt weg. Verworfen: den
  laufenden Satz mitschicken - bei Playtomic stünde dann ein Ergebnis, das nie gespielt wurde,
  und der Dienst nimmt ihn ohnehin nicht an (`ResultService.validate`).
- **Silver Point = beim ersten 40:40 Vorteil, beim zweiten entscheidet der nächste Punkt.**
  Verworfen: der „Star Point“ (zweimal Vorteil, erst das dritte 40:40 entscheidet) - Felix
  nannte Golden und Silver.
- **Ein Match zählt bis zwei gewonnene Sätze**, danach nimmt die Uhr keinen Punkt mehr an.
  Verworfen: offen weiterzählen - Playtomic kennt drei Sätze (`Set-1` bis `Set-3`), gespielt
  wird auf zwei gewonnene.
- **Die Farbe eines Mitspielers kommt vom Dienst** (`partnerColor`), die App kennt keine Namen
  - das Repo ist öffentlich, und Seite und App färben so gleich. Verworfen: Farben je Name in
  der App.
- **Padel-Tab in Reihenfolge und Wortlaut der Seite** (`padel/…/static/app.js`): nächster
  Termin, Gebucht, Ergebnisse, Geplant, Serien, Plätze. Verworfen: eine eigene Gliederung -
  zwei Ansichten mit verschiedenen Wörtern für denselben Zustand.
- **Ein Match startet auf der Uhr, nicht gespiegelt.** Verworfen: vom iPhone starten wie das
  Krafttraining - beim Padel liegt das iPhone in der Tasche.

## 2026-10-22 — Recovery: Abstand statt Rang, letzte 30 Nächte, Temperatur, Effekte je Baustein
Felix' Entscheidungen (Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §2, §3.2, §4.1, §5; gerechnet
im Weight Tracker, die App zeigt nur):
- **Score = Abstand zum Normalbereich** (Composite in Standardabweichungen, logistisch auf 1–99,
  50 = typisch). Verworfen: der Rang unter den Baseline-Nächten (seit 10.10.) — auf Dauer jede
  dritte Nacht rot, und die schlechteste der Baseline bekam immer 1, egal wie schlecht.
- **Grün ab 50** (typisch oder besser), rot bis 33 (mehr als eine Standardabweichung darunter).
  Verworfen: die Whoop-Grenzen 33/67 (Gelb = normal, Grün nur etwa jede sechste Nacht).
- **Baseline = die letzten 30 Nächte**, höchstens ein Jahr zurück. Verworfen: die 60 Tage davor (mit
  einer Uhr, die nicht jede Nacht getragen wird, kamen oft keine 14 Nächte zusammen) und die letzten
  60 Nächte (träger).
- **Schlaf raus, Handgelenktemperatur rein** (einseitig, 10 %; HRV 55, Puls 25, Atem 10). Der
  Schlaf bleibt als Zeile mit Gewicht 0. Verworfen: nur eins von beiden, oder alles wie bisher.
- **Effekte: Punkte + Bausteine** — die Recovery-Punkte bleiben die Hauptzahl mit Sternen, darunter
  „HRV +9 % · RHF −1,9 bpm“ ohne Sterne. Verworfen: nur Bausteine (HRV als Hauptzahl, Holm über
  mehr Zeilen, keine Recovery-Punkte) und nur Punkte.

Ohne Rückfrage entschieden (App):
- **Ein Baustein mit Gewicht 0 bekommt einen grauen Balken** (Schlaf immer, beim Kalibrieren
  alle) — man sieht, was zählt, ohne Text. Verworfen: ein Hinweis „zählt nicht“ (kein Erklärtext)
  und die Schlaf-Zeile ausblenden (Felix wollte sie behalten).
- **Temperatur mit zwei Nachkommastellen** („35,84 °C“, „⌀ 35,80 °C“). Verworfen: eine wie beim
  Atem — „35,8 °C“ gegen „⌀ 35,8 °C“ sähe nach keiner Abweichung aus, wo eine ist.
- **Die Temperatur zählt, wenn die Messung die Phase überlappt**, nicht nur, wenn sie darin
  beginnt: die Uhr schreibt eine Messung über den ganzen Schlaf, die vor dem Einschlafen beginnen
  kann. Ohne Leserecht liefert HealthKit still nichts — die Nacht geht dann ohne Temperatur raus,
  kein Abbruch wie bei einer gescheiterten HRV-Abfrage.
- **Die Rückholung der 425 Nächte läuft einmal erneut, über einen neuen Cursor**
  (`health.nights.backfillCursor.temperature`), damit die alten Nächte die Temperatur bekommen.
  Verworfen: den alten Cursor löschen (dieselbe Wirkung, aber der neue Name sagt, warum).
- **Was auf null rundet, steht ohne Vorzeichen** („HRV 0 %“, „RHF 0,0 bpm“) — wie überall
  (`GermanNumber`), kein „−0“.

## 2026-10-19 — Gewicht-Diagramm: „Distanz z. Target“
Felix' Entscheidungen (Vertrag `weight-app/docs/HEALTHY-CONTRACT.md` §5):
- **Gewicht ⌀ 7 minus Zielkurve**, in „Alles“ ⌀ 30 - der senkrechte Abstand der beiden
  gezeichneten Linien, glatt und am Rand gepunktet wie das Mittel. Verworfen: das rollierende
  7-Tage-Residuum wie die Kachel (endet genau auf deren Wert, läuft aber gut drei Tage hinter dem
  ⌀ 7 her) und der rohe Messwert minus Zielkurve (springt von Tag zu Tag).
- **Nur angeboten**, nicht vorgewählt - das vertraute Bild bleibt. Verworfen: vorgewählt.
- **Name „Distanz z. Target“** wie die Kachel „Differenz z. Target“, auch hier, wo die Zielkurve
  „Zielkurve“ heißt. Verworfen: „Residuum ⌀“.
- **Pink** (`#C2255C` / `#F06595`). Verworfen: das Rot der Zielkurve (zwei rote Linien) und Türkis
  (zwischen Messwert-Blau und ⌀-7-Grün).

Ohne Rückfrage entschieden:
- **Eigene Skala mit Nulllinie wie das Defizit**, Schritte 0,5 / 1 / 2 kg. Auf der kg-Achse wäre ein
  Abstand von ein paar hundert Gramm ein flacher Strich.
- **Innen links, wenn rechts belegt ist.** Innen rechts steht dann schon das Defizit; zwei
  Beschriftungen am selben Rand überdeckten sich.
- **Kein eigenes Feld beim Dienst.** Die App zieht zwei gelieferte Werte voneinander ab. Das ist
  keine Rechenregel, die zwischen iOS und Android auseinanderlaufen könnte.
- **`DeficitScale` → `ZeroLineScale`** statt einer zweiten, fast gleichen Skala.

## 2026-10-19 — Gym: Notiz am Gerät, Spanne, Wiederholungen je Satz
Anlass war ein Trainingsplan mit Spannen („3 × 8–10“), der je Satz Gewicht und Wiederholungen
und je Gerät die Sitzeinstellung festhält. Felix' Entscheidungen (Vertrag
`weight-app/docs/HEALTHY-CONTRACT.md` §6, Abschnitt „Notiz, Spanne, Sätze einzeln“):
- **Notiz je Gerät** (`GymMachine.note`, bis 200 Zeichen): hängt am Gerät, gilt also in jedem
  Tag damit. Ein Eingabefeld im Training direkt unter dem Gerät (Platzhalter „Notiz“) - dort
  tippt Felix im ersten Training die Sitzeinstellung ein - und eins im Blatt des Geräts; die Uhr
  zeigt sie als kleine Zeile. Verworfen: die Notiz auch in der Übersicht - gebraucht wird sie
  am Gerät, und die Übersicht bleibt bei Plan und Haken.
- **Spanne als `repsMin`, `reps` bleibt die obere Grenze** („Das Ziel steht da“): ältere Apps
  zeigen und haken weiter mit `reps`. Eingestellt im Blatt mit „mindestens“ unter
  „Wiederholungen“; gleich der oberen Grenze heißt keine Spanne.
- **Im Training ändern „−“ und „+“ mit Spanne nur den nächsten Satz**, vorbelegt ist die obere
  Grenze, nach jedem Haken und beim Gerätewechsel wieder; daneben klein die Spanne. Ohne
  Spanne bleibt die Zahl der Plan wie bisher. Der Stepper ist derselbe „− n +“ wie sonst und
  geht auch unter und über die Spanne (1–100). Verworfen: eine Reihe Zahlknöpfe, je
  Wiederholungszahl der Spanne einer, statt des Steppers.
- **Auf der Uhr dreht die Krone die Wiederholungen**, „Satz erledigt“ schickt sie mit
  (`setDone` mit `reps`). Verworfen: die Spanne auf der Uhr nur anzeigen - dann hakte jeder Satz
  von der Uhr mit der oberen Grenze ab, und man müsste am iPhone nachbessern.
- **„letztes Mal“ und der Verlauf zeigen jeden Satz** mit dem schwersten Gewicht: alle gleich
  „2×10 · 40 kg“ (die Zahl der Sätze mit diesem Gewicht), sonst „10, 9 · 40 kg“. Ob alle Sätze
  die obere Grenze geschafft haben, zeigt der schwerste allein nicht.

Ohne Rückfrage entschieden:
- **Zum Entfernen einer Spanne schickt die App `repsMin` = `reps`**, nicht `null` - `null`
  heißt beim Dienst „bleibt“. Bis die Antwort da ist, steht das so auch in der App; wird danach
  „Wiederholungen“ erhöht, wandert `repsMin` mit (`GymExercise.withReps`) - sonst entstünde
  aus der eben entfernten Spanne eine neue. Eine Spanne zeigt die App nur bei 1 ≤ `repsMin` <
  `reps` (0 heißt beim Dienst auch keine).
- **Die Notiz wird auf 200 Zeichen gekürzt, gezählt wie in Java (UTF-16)**, bevor sie rausgeht:
  eine längere lehnte der Dienst ab, und mit der Ablehnung verschwände die ganze Notiz.
- **Die Krone gehört den Wiederholungen, sobald die Seite des Geräts zu sehen ist** (und es
  eine Spanne gibt) - kein Antippen vorher; ein grüner Rahmen um die Zahl zeigt es (watchOS
  zeichnet für diese Ansicht keinen eigenen). Dafür blättert man auf dieser Seite mit Wischen.
  Verworfen: erst die Zahl antippen, dann drehen - ein Schritt mehr, und wer es vergisst,
  blättert mit der Krone zu „Beenden“.
- **Auf schmalen iPhones (390 Punkt) rückt die Spanne unter „Wiederholungen“**, statt das Wort
  zu trennen (`ViewThatFits`).

## 2026-10-14 (abends) — Gym-Habit in coHabit
Felix: „ein Gym-Habit, das ich 2× die Woche abhaken will, automatisch abgehakt, wenn man einen
Gym-Tag beendet hat, und in der Recovery-Auswertung“. In der Fragerunde gewählt:
- **Von Hand und automatisch.** Deshalb eine Health-Metrik `GYM` wie die kcal aus Healthy
  (HEALTH-Einträge, die der Dienst schreibt; Haken von Hand bleiben möglich) und **keine**
  automatische Quelle wie „Track food“ – die verbietet Haken von Hand. Verworfen: nur automatisch.
- **Neue Option „Gym aus Healthy“ beim Anlegen** in allen drei Clients (nur bei einer Serie, Haken
  ohne Wert). Verworfen: nur Felix' Habit einmal direkt anlegen.
- **Beim Öffnen von coHabit** (und alle 15 Minuten): `GymSync.refresh` an `/today`, `/widget`,
  `/cohabits`, Detail und klassischer Liste, höchstens einmal je Minute, 2 s Frist. Nicht an
  `/me/days`: dort fragt gerade der Weight Tracker, und ein Training von heute zählt in den Effekten
  erst gegen die Recovery von morgen. Verworfen: nur der 15-Minuten-Takt.
- Ohne Rückfrage entschieden: **Wer ein Gym-Habit anlegt, hat damit zugestimmt** (bei den kcal
  schaltet man die Einwilligung danach selbst ein); Beigetretene stimmen selbst zu. Es zählt nur ein
  **beendetes** Training. Die Recovery bekommt das Habit über `/me/days` wie jedes Co-Habit, als
  Ja/Nein-Reihe (ab dem Start, von Hand oder aus Healthy) – kein eigener Prädiktor im Weight
  Tracker, sonst stünde Gym doppelt da.

## 2026-10-14 (Nachtrag) — Gym: Wochentage, Geräteliste, Gewicht als Zahl
Felix nach dem ersten Ausprobieren, in der Fragerunde gewählt:
- **Wochentage beim Bearbeiten wählen** (je Tag Mo–So, auch mehrere): „dienstags bekommt man
  den Dienstag“. Ohne Treffer bleibt es beim nächsten Tag in der Reihe; haben mehrere Tage
  den Wochentag, gewinnt der, der in der Reihe dran ist. **Gerechnet in der App**
  (`GymState.suggestedDay`), nicht im Dienst: im Gym ohne Netz kann der Stand von gestern
  sein, das Datum des Handys stimmt immer. Verworfen: Tage heißen Wochentage (kein freier
  Name mehr); aus dem Verlauf lernen (nichts einzustellen, greift aber erst nach Wochen).
- **Geräteliste: Maschinen und freie Übungen, deutsch, nach Muskelgruppe** (rund 65), mit
  Suche; eigene Geräte gehen weiter. **Die Liste liefert der Weight Tracker** (`catalog` in
  `GET /api/gym`): eine Liste für iOS und Android, ergänzen ohne neue App-Fassung - und keine
  Gerätenamen in diesem öffentlichen Repo. Gewählt wird ein Name; gibt es ihn schon als
  Gerät, nimmt die App das (der Verlauf bleibt beisammen). Verworfen: nur Maschinen; die
  Geräte eines bestimmten Studios; englische Namen.
- **Gewicht als Zahl** statt „− n +“ in 2,5-kg-Schritten (Sätze und Wiederholungen bleiben
  „− n +“). Gespeichert wird beim Verlassen des Felds bzw. mit „Fertig“ über der Tastatur,
  nicht je Ziffer.
- **Android bekommt alles** (1.7).

## 2026-10-14 — Healthy: Gym-Tab, Uhr-App, Sperrbildschirm-Schritte; Evaluation und Einkauf nach Fokus
Felix' Wünsche vom 14.10. (Plan `~/.claude/plans/hier-ein-paar-dinge-vast-wand.md`), in
der Fragerunde gewählt:
- **Gym-Daten beim Weight Tracker** (je Person `gym.json`, Vertrag
  `weight-app/docs/HEALTHY-CONTRACT.md` §6), jeder Schreibweg ein PUT mit der Kennung der
  App, damit Haken offline in der Warteschlange warten (`GymChange`, `GymOverlay`). Verworfen:
  nur auf dem iPhone wie die Evaluation - einfacher und immer offline, aber beim Löschen der
  App wäre der Verlauf weg, und Android könnte nie mitmachen.
- **Live-Werte von der Apple Watch:** „Training starten“ weckt die Uhr-App
  (`startWatchApp`), die die `HKWorkoutSession` führt und aufs iPhone spiegelt
  (`WorkoutMirror`); das Training landet über die Uhr in Health. Verworfen: nur iPhone (das
  iPhone hat keinen Pulssensor; aus Health käme der Puls mit Minuten Verzögerung, kein
  Training in Health). `HKLiveWorkoutBuilder` gibt es auf iOS erst ab 26 - das iPhone nutzt
  nur die Botschaften der Uhr.
- **Uhr zeigt Werte + aktuelles Gerät**, ein Satz lässt sich dort abhaken. Abgehakt wird
  trotzdem nur auf dem iPhone (es schreibt allein zum Dienst): „Satz erledigt“ trägt eine
  Kennung, die Uhr wiederholt, bis das iPhone quittiert, dann über `transferUserInfo`.
  Verworfen: nur Werte auf der Uhr.
- **Verlauf: „letztes Mal …“ + Diagramm auf Tipp**; **nächster Tag in der Reihe vorgewählt**
  (rechnet der Dienst, `nextDayId`); **im Training geändertes Gewicht wird der neue Plan**.
  Verworfen: nur „letztes Mal“; immer den Tag wählen; Gewicht nur für dieses Training.
- **Ob ein Training läuft, merkt sich die App** (`ActiveWorkout`), nicht der Dienst: ein
  Besuch, der nur durch Abhaken entstand, ist kein Training.
- **Uhr-App ohne App-Gruppe:** Uhr-App und Komplikation teilen den Schlüsselbund der Uhr
  (derselbe Gruppenname wie auf dem iPhone, `Keychain.swift` bleibt unverändert). Den Token
  schickt das iPhone per WatchConnectivity - **der Haupt-Token `fh_private` liegt damit auch
  auf der Uhr**, damit die Komplikation selbst beim Kalorienzähler fragen kann (wie die
  iPhone-Kachel, 02.09.). Verworfen: Komplikation nur aus dem Stand, den das iPhone schickt
  (ohne laufendes iPhone stünde sie still, etwa nach einer Schnellerfassung im Browser).
- **kcal-Komplikation im Stil der Temperatur:** links 0 (grün), Mitte gegessen, rechts das
  Tagesziel (orange), Bogen mit Verlauf. Felix erst „Rest in der Mitte“, dann korrigiert.
- **Schritte auf dem Sperrbildschirm: das Größere aus Health-Stand und Schrittzähler**
  (`StepsMirror`, `StepsNow`). Gesperrt kommt eine Kachel nicht an Health heran; die App legt
  jeden Health-Stand im Schlüsselbund ab, und **seit heute weckt Health die App stündlich für
  Schritte** - nur fürs Ablegen, ohne Upload. Das nimmt „keine Hintergrundzustellung für
  Schritte“ (`syncSteps`) teilweise zurück. Verworfen: nur Health (oft eine Stunde alt); nur
  Schrittzähler (ohne Uhr-Schritte).
- **Große Sperrbildschirm-Kachel: zwei Ringe nebeneinander** (kcal gegessen, Schritte).
  Verworfen: zwei Zeilen mit Balken.
- **Evaluation und Einkauf ziehen nach Fokus**, Healthy hat Dashboard · Essen · Gewicht · Gym.
  Die Antworten liegen nur in Healthys Container; **übergeben durch den geteilten
  Schlüsselbund** (`EvaluationHandoff`, `EvaluationImport`): Healthy bietet die Bytes an,
  bis Fokus mit dem SHA-256 quittiert, und **behält seine Datei als Sicherung**; Fokus
  überschreibt keine Antworten, die es schon hat (dann liegt die aus Healthy daneben als
  `evaluation-healthy.json`). Verworfen: eine App-Gruppe für Healthy (neue Provisionierung,
  Risiko beim Installieren, wie 12.10.); Export/Import von Hand über Dateien.
- **Fokus bekommt `NSFaceIDUsageDescription`** - Healthy hatte den Satz für die Evaluation
  nie (iOS fiel dort still auf den Code zurück).
- **Alles auf einmal ausrollen** (`~/Server-Projects/deploy-healthy-gym.sh`), Felix' Wahl
  statt vier Runden.

## 2026-10-12 — Healthy: Essen und Gewicht ohne Netz sofort sichtbar, Summen vorläufig
Runde 4 der Änderungen vom 12.10. (Felix: „alle Apps“; in der Fragerunde gewählt:
offline eingetragenes Essen **zählt vorläufig** in den Tagessummen). Wie To-Do und
Einkaufsliste (Eintrag „Ohne Netz“ unten) über die Warteschlange:
- **Essen** (`FoodChange`): Eintragen (gemerktes oder neues Gericht, Bestätigen der
  Schnellerfassung), Berichtigen, Löschen stehen sofort da, mit Uhr am Eintrag. Die
  Kennung vergibt die App (`id` in `POST /api/food/entries`, Kalorienzähler seit
  `d1359a7`), so lässt sich ein wartender Eintrag schon berichtigen.
- **Vorläufige Summen** (`FoodOverlay`): Zahl des Dienstes plus die Differenz der
  wartenden Einträge (je 100 g × Menge), für Tachos, „kcal übrig“, Halbkarte im
  Dashboard und Kalorien-Kachel, jeweils mit „vorläufig“. Lockert die Regel „die App
  rechnet nichts nach“ **nur für diese Summe** - die Kurve „kcal Tag“, Verlauf und
  Mittel zählen weiter nur, was der Dienst kennt.
- **Kachel über die geteilte Keychain-Gruppe** (`PendingFoodMirror`) statt einer neuen
  App-Gruppe: Healthy und die Kachel haben die Gruppe `com.fherrmann.shared` schon;
  eine App-Gruppe bräuchte neue Provisionierung, und scheiterte die, ginge das
  Installieren schief. Die Kachel legt die wartenden Einträge selbst über den Tag, den
  sie holt (schon Angekommenes zählt so nicht doppelt); ohne Netz zeigt sie, was die
  App zuletzt für heute zeigte.
- **Gewicht von Hand** (`WeightChange`): je Tag das neueste, sofort als „82,4 kg am
  12.10. – wartet“ unter den Kacheln; die Kacheln rechnet weiter der Dienst. Der
  Abgleich mit Apple Health bleibt, wie er ist (er merkt sich selbst, was ankam).
- **Prüfen wie der Dienst, bevor etwas wartet** (`FoodEntryRules`, Gewicht > 0): ohne
  Netz käme eine Ablehnung erst beim Senden, vielleicht Stunden später, und der
  Eintrag verschwände wieder. Befund aus dem Test: ein neues Gericht ohne Eiweiß nahm
  das Formular an, der Kalorienzähler nicht („proteinG is required“) - jetzt bleibt
  „Eintragen“ aus, bis alle vier Werte je 100 g da sind.
- **Verworfen:** die Kacheln aus dem wartenden Gewicht nachrechnen (Mittel, Residuum
  - das wäre ein zweiter Rechenweg); wartendes Essen auch in den Verlauf (eine Kurve,
  die nach dem Senden springt, sähe nach Fehler aus).

## 2026-10-12 — Healthy: Logbook direkt im Dashboard, jeder Tipp speichert
Felix (Änderungsrunde 12.10., Wunsch 2.2): „nicht als Untermenü, sondern direkt
im Dashboard, bedienbarer, im Zweifel wie Whoop“; in der Fragerunde gewählt:
**jeder Tipp speichert**. Löst den Eintrag vom 09.10. („Seite im Dashboard,
Speichern von Hand“) ab. Vertrag `HEALTHY-CONTRACT.md` §4.2.
- **Im Dashboard unter den Halbkarten Gewicht | kcal**, darunter die Effekte als
  eigene Karte. Die Recovery bleibt eine Seite; der Tipp auf die Erinnerung
  scrollt zum Logbook (`DashboardAnchor`). **Verworfen:** Logbook ganz oben -
  die Zahlen des Tages sind der erste Blick, das Eintragen der zweite.
- **Offen ist nicht „nein“.** Ein Tag kann halb beantwortet sein; offen ist
  eine Zeile nur umrandet. Ja und Nein in derselben Farbe - keine Antwort ist
  hier gut oder schlecht. Ein zweiter Tipp auf die gewählte Antwort macht die
  Zeile wieder offen, gedrückt halten → „Zurücksetzen“.
- **Mengen mit − Zahl +** statt Tastatur; aus „offen“ gibt + eine 1 und − eine
  0; ein Tipp auf die Zahl öffnet die Eingabe für große und Kommawerte.
  Geschickt wird nach 0,5 s Ruhe - fünfmal + ist ein Aufruf.
- **Gestern, solange gestern offen ist, sonst heute** - neu bestimmt, wenn das
  Dashboard erscheint, die App zurückkommt und um Mitternacht. Ein Punkt an
  „Gestern“, solange dort etwas offen ist. Heute ist jetzt eintragbar (der
  Wert zählt erst, wenn der Tag vorbei ist - aber wer abends einträgt, soll
  nicht bis morgen warten). Weiter zurück mit ‹, keine scrollende Leiste.
- **Ein Wert je Aufruf, über die Warteschlange** (`LogbookChange`, Fall
  `.logbook` auf der Spur des Weight Trackers): sofort zu sehen, ohne Netz mit
  Uhr, später gesendet; je Tag und Verhaltensweise gilt der neueste. Lehnt der
  Dienst ab, springt die Zeile zurück, die Meldung nennt Verhalten und Tag.
  Leeren schickt `{"value": null}` statt DELETE - ein wartendes DELETE liefe
  sonst nach einem neueren Wert hinterher. `LogbookMemory`, `LogbookDraft`
  und die Logbook-Karte sind weg.
- **Die Erinnerung zählt Antworten**, nicht gespeicherte Tage: „gestern offen“
  kommt, solange am Vortag eine aktive Verhaltensweise keinen Wert hat; ein
  wartender Wert gilt als beantwortet.
- **Effekte: Zeitraum gemerkt** (30 · 90 · 180 · 365), die drei stärksten,
  „Alle Effekte (n)“ klappt an Ort und Stelle auf. Neu geholt höchstens alle
  15 Minuten - nach einem Tipp ändern sie sich nicht merklich.
- **Verworfen:** ein Knopf „Tag abschließen“ - genau der Schritt, der Felix an
  der alten Seite gestört hat; und Ja/Nein als Schalter (ein Schalter kennt
  kein „offen“).

## 2026-10-12 — coHabit: Tageslimit aus dem Logbook statt eigener Einträge
Felix (Wunsch 2.1): ein Habit „höchstens 4 am Tag“, das in coHabit **und** im
Logbook eingetragen werden kann und dieselbe Zahl zeigt. Umgesetzt als
**Abstinenz mit Tageslimit** (Vertrag `COHABIT-CONTRACT.md` §2.5a, §5.2c):
- **Die Zahl liegt nur im Logbook.** coHabit liest sie über den Dienst und
  schreibt beim Zählen dorthin (`PUT /cohabits/{id}/count/{date}`, absolut).
  **Verworfen:** coHabit speichert die Zahl und das Logbook spiegelt sie -
  zwei Ablagen, die auseinanderlaufen, und ein Umzug der bisherigen Werte.
- **Abstinenz, nicht automatischer Streak:** heute zählt mit, ein Tag über dem
  Limit bricht die Serie sofort, kein „gefährdet“ um 20 Uhr. Ein automatischer
  Streak wäre ab 00:00 „erledigt“ und das Überschreiten erst morgen zu sehen.
- **Karte wie ein Streak** (große Zahl, „+“ rechts oben, darunter „heute 2 von
  4 …“) - neben der seitlichen Zahl der Abstinenz-Karte wäre für das „+“ kein
  Platz (so auch Web und Android). Detail: unten „− 3 +“ für heute, „Letzte
  Tage“ zum Korrigieren. Klassische Liste: „2/4“ und „+“.
- **Zählen:** absolut nach 0,5 s Ruhe, je Tag ein Aufruf zur Zeit
  (`LimitCounter`). Ohne Netz oder wenn das Logbook nicht antwortet (503)
  wartet die Zahl im Postausgang (`limitCount`, je Tag die neueste); was dort
  schon wartet, überholt kein direkter Aufruf. Eine Ablehnung dreht zurück.
- **Ohne Logbook keine Zahl:** Kennzahl „–“, kein „+“, kein Zähler - nie eine
  erfundene 0.
- **Anlegen** vorerst nur per Skript (`habits/deploy/create-limit-habit.sh`);
  Bearbeiten zeigt nur „Höchstens pro Tag“ und das Verhalten.

## 2026-10-12 — Ohne Netz: To-Do und Einkaufsliste sofort sichtbar, später synchron
Felix (12.10.): „Wenn man im Offline-Modus ein Todo anlegt oder abhakt, sieht man
gar nicht, ob das geklappt hat" — in der Einkaufsliste besonders ärgerlich, im
Supermarkt fehlt oft das Netz. Bis dahin wartete jede Änderung auf den Dienst
(bis zu 30 s Zeitlimit), Anlegen in Fokus ging ohne Netz gar nicht, und ein
abgelehnter Haken verschwand nur still beim nächsten Laden. Jetzt: **typisierte
Änderungen in einer Warteschlange** (`PendingChanges`), angezeigt als Overlay über
dem letzten Stand des Dienstes, sofort gesendet, ohne Netz gespeichert (auch über
einen Neustart) und später nachgesendet. **Lehnt der Dienst ab, fliegt die
Änderung raus — die Anzeige springt zurück — und eine Meldung nennt Eintrag und
Grund.** Die App vergibt die Kennungen neuer Einträge; todo und shopping nehmen sie
an und legen bei derselben nichts doppelt an. Löst den Eintrag vom 03.09. („letzter
Stand plus Postausgang, aber kein Nachrechnen") für To-Do und Einkauf ab; Healthy
und der Wald bleiben vorerst beim alten Postausgang (Runde 4 der Änderungen vom
12.10. zieht Essen und Gewicht nach).
**Verworfen:**
- *Beim alten Postausgang bleiben und nur die Uhr verbessern* — er kennt nur rohe
  Anfragen: nichts anzeigen, nichts zusammenfassen, keine Meldung mit Namen, und
  Anlegen braucht eine Kennung, die erst der Dienst vergab.
- *Ein `Idempotency-Key` mit gespeicherten Antworten beim Dienst* — gibt späteren
  Änderungen (Haken auf einem offline angelegten Eintrag) keine feste Kennung und
  wäre selbst ein zweiter Speicher.
- *Eine lokale Datenhaltung mit Abgleich* — ein zweiter Datenstand mit eigener
  Konfliktlogik; die Overlays bilden nur die Liste nach und gelten bis zur Antwort.
- *Bereiche, Erinnerungen, Gerichte und Regeln ebenfalls offline* — Schreibtisch-
  arbeit, die eine Antwort braucht (Name doppelt, Aufgabe beim Dienst unbekannt);
  dort bleiben Eingabe und Fehlermeldung, wie beim Wald-Kategorien-Entscheid
  vom 01.10.
- *Die Uhr statt des Hakens* (bisher) — man sah nicht, ob die Aufgabe jetzt
  erledigt war. Jetzt: der Haken zeigt den neuen Stand, eine kleine Uhr daran,
  solange der Dienst ihn nicht hat; während gesendet wird, keine Uhr (sonst
  blitzt sie bei jedem Haken).
- *Den Haken einer gleichnamig zusammengefassten Einkaufszeile als eigene Zeile
  zeigen* — der Dienst führt sie zusammen, die App zeigt es genauso.
- **Joana:** Bis ihre Einkaufsliste die neue Fassung hat, gilt bei ihr das alte
  Verhalten (und ihr „Abgehakte entfernen" aus dem Postausgang löscht beim
  Nachsenden alles Abgehakte).

## 2026-10-12 — Healthy: Defizit in Orange, im Gewicht-Diagramm vorgewählt
Felix hat entschieden (12.10.): Das Gewicht-Diagramm öffnet mit **Gewicht ⌀
(7 Tage, bei „Alles" 30), Zielkurve und „Defizit ⌀"**; „kcal ⌀" ist dort nur
noch angeboten. Das Petrol des Defizits lag ihm zu nah an der Farbe des
Gewichts (Grün des Mittels, Blau des Messwerts) - es ist jetzt **Orange**
`#E8590C` / `#FF922B`, auf allen Oberflächen (Vertrag §5), auch in der
Energie-Karte und im Essen-Verlauf. **Verworfen:** Violett (nah am Indigo des
Verbrauchs, im Essen-Verlauf vorgewählt, und am Lila des 30-Tage-Mittels bei
„Alles"), Magenta (nah am Rot von Zielkurve und Überschuss). Was Orange
kostet: im Bilanzbalken folgt es direkt auf das kcal-Gelb, in der Woche steht
es neben dem Rot des Überschusses - Felix prüft das auf dem Gerät.
- **Die Auswahl der Reihen ist nirgends gespeichert** (App `@State`, Web im
  Speicher, Android im ViewModel): die neue Vorgabe gilt ab dem nächsten Start,
  ohne Umzug.
- **`COCKPIT_SERIES`** schaltet seitdem eher `kcal` oder `expenditure` zu; das
  Defizit braucht den Schalter nicht mehr.

## 2026-10-10 — Healthy: Essen-Tab ohne Energiezeilen, Ziele fest wie vorher
Felix hat entschieden (10.10.): Im Essen-Tab sollen sich die Werte nicht
ändern, das Kalorienziel bleibt fest, das Defizit steht dort nicht als Text
darunter - „zu busy". Die Tageskarte zeigt wieder genau, was sie vor
`f0aadb5` zeigte: „Verzehrt … kcal" und „von … kcal" neben dem großen Tacho,
die Makros mit „von … g". Die Ziele kamen schon immer fest aus `day.targets`
des Kalorienzählers; was sich über den Tag bewegte, waren die Zeilen
„Verbrauch ≈ … · Uhr … · −8 %" und „Defizit ≈ … kcal" darunter (heute eine
Prognose). **Verbrauch und Defizit des Tages stehen nur noch in der
Energie-Karte des Dashboards**; der Essen-Verlauf behält „Verbrauch ⌀" und
„Defizit ⌀" samt Fläche. **Verworfen:** die Zeilen kleiner oder eingeklappt
behalten - auch dann stünden unter dem festen Ziel Zahlen, die sich ändern,
und das Defizit als Text, und beides will Felix dort nicht.
- **Ziehen im Essen-Tab lädt wieder nur Tag und Verlauf**, ohne Health-Abgleich
  (`HealthSync.syncEnergy` ist weg) - er war nur für die Zeilen da (09.10.,
  „Ziehen im Essen-Tab holt nur die Energie aus Health"). **Verworfen:** ihn
  behalten - er schickt vor allem den Verbrauch von heute, und den zeigt der
  Tab nicht mehr; die Kurven mitteln nur abgeschlossene Tage.
- **Ohne Kalorienzähler steht der Verbrauch des Tages nirgends mehr.** Die
  Energie-Karte fehlt dann (09.10., „Balken + Woche"); ihr Grund dort, „der
  Verbrauch steht im Essen-Tab", gilt seit heute nicht mehr.
- **Die Kurven im Essen-Verlauf bleiben vorgewählt** (Felix, 10.10., auf
  Nachfrage). **Verworfen:** sie nur anbieten - Felix wollte die Defizit-Kurve
  dort ausdrücklich, „zu busy" galt den Zeilen unter dem Ziel.

## 2026-10-09 — Healthy: Vorführmodus auch für Essen- und Gewicht-Tab
`COCKPIT_DASHBOARD_DEMO=1` ersetzte bisher nur Dashboard, Recovery, Logbook
und die Energie. Essen- und Gewicht-Tab luden weiter die echten Tage, Verläufe
und Gewichte - `run-simulator.sh` gibt die echten Token mit, und ein Bild vom
Essen-Tab zeigte echte Einträge. Jetzt lesen auch diese beiden Tabs im
Vorführmodus nur `DashboardDemo` (eine Weiche in `FoodStore.load`,
`loadHistory`, `show`, `prefetchNeighbours` und `WeightStore.load`, `select`),
und Eintragen, Speichern und Löschen tun dort nichts. Die kcal je Tag und ihr
Mittel passen zur erfundenen Energie, damit Fläche und „Defizit ⌀" im Bild
übereinstimmen; im Gewicht-Tab steht neben den drei Energie-Kacheln nur
„Aktuell", damit das Diagramm ganz in den ersten Bildschirm passt.
**Verworfen:** lokal gestartete Dienste mit eingespielten
Daten - für jede Aufnahme zwei Dienste, und deren kcal passten nicht zur
erfundenen Energie, Fläche und Linie widersprächen sich.
- **`COCKPIT_SERIES=deficit`** schaltet im Gewicht-Tab Reihen zu - „Defizit
  ⌀" ist dort nur angeboten, und `simctl` kann nicht tippen. **Verworfen:**
  ein weiterer UI-Test, der den Schalter antippt - für ein Bild ein ganzer
  Testlauf.

## 2026-10-09 — Healthy: „Defizit ⌀" als eigene Linie und als Fläche
Felix hat entschieden (09.10., Runde 2): Das Defizit steht in den Verläufen
**als eigene Linie** („Defizit ⌀" aus `deficitAvg7`, eigene Skala mit
Nulllinie) **und als eingefärbte Fläche** zwischen „Verbrauch ⌀" und „kcal ⌀"
(Defizit- bzw. Überschuss-Farbe). Im Essen-Verlauf **vorgewählt**, im
Gewicht-Diagramm **nur angeboten** - wie „Verbrauch ⌀". Vertrag §5.
**Verworfen:** nur die Fläche (sie zählt auch halb erfasste Tage mit, die
Linie nur getrackte) oder nur die Linie (die Lücke zwischen den Kurven bliebe
ungedeutet). In der App:
- **Die Skala rechnet wie das Web** (`DeficitScale`): schließt 0 ein, Grenzen
  auf 250er, ab 1.500 kcal Spanne auf 500er Schritte, mindestens zwei
  Schritte; die Kurve wird in die Achse des Diagramms hineingerechnet wie das
  Gewicht. **Verworfen:** die automatischen Marken von Swift Charts - App und
  Web zeigten verschiedene Zahlen.
- **Rechte Seite frei → außen wie die kg-Skala**, mit kleinem Titel „Defizit"
  darüber (`chartYAxisLabel`). **Rechte Seite belegt** (kg im Essen-Verlauf,
  kcal im Gewicht-Diagramm) **→ klein innen am rechten Rand**, nur 0 und die
  beiden runden Ränder, ohne Titel, gezeichnet im `chartBackground`
  (`DeficitInsideLabels`) - hinter den Kurven, damit die Sprechblase sie
  verdeckt und nicht umgekehrt; die Zahl steht knapp über ihrer Höhe, damit
  sie die Nulllinie nicht durchkreuzt. **Verworfen:** eine zweite Achse rechts
  - Swift Charts setzt je Seite eine Spalte, die Zahlen lägen übereinander;
  das `chartOverlay` (die Zahlen lagen dort über der Sprechblase).
- **Die Fläche besteht aus Stücken einer Farbe** (`EnergyBand`): je Stück eine
  `AreaMark`-Reihe, getrennt an jeder Lücke einer der beiden Kurven und am
  Schnittpunkt, der zwischen zwei Tagen genau ausgerechnet wird (die Linien
  sind gerade, `.linear`). Zuerst gezeichnet, also hinter allen Linien.
  **Verworfen:** eine durchgehende Fläche mit Farbwechsel am Tagesrand (der
  Vertrag will den Schnittpunkt) und eine Fläche über Lücken hinweg (die
  Linien sind dort auch getrennt).
- **Die Nulllinie ist fein gestrichelt** (1 Punkt, `[3, 3]`), die Kurve selbst
  2,2 Punkte und erst am offenen Rand gestrichelt (`[4, 4]` wie „Verbrauch
  ⌀"). **Verworfen:** gepunktet wie „kcal ⌀" - der Vertrag sagt gestrichelt.
- **Der Schalter „Defizit ⌀" erscheint mit „Verbrauch ⌀"**, also sobald es im
  Zeitraum einen Verbrauch gibt. **Verworfen:** nur mit Werten von
  `deficitAvg7` - ein Zeitraum ohne getrackten Tag verlöre dann auch die
  Fläche, die es dort gibt.

## 2026-10-09 — Healthy: Energie-Karte „Balken + Woche"
Felix hat entschieden (09.10., Runde 2): Die Energie-Karte im Dashboard zeigt
groß die Bilanz von heute, darunter einen **Bilanzbalken** (gegessen gegen
Verbrauch) und die **Woche** als sieben Balken von einer Nulllinie aus - genau
wie im Healthy-Vertrag §5 beschrieben, Android baut dasselbe. **Verworfen:** die
einzeilige Karte aus Runde 1 („Verbrauch ≈ 2.840 · gegessen 2.150 · Defizit ≈
690 kcal") - eine Zahlenreihe sagt nicht, wie die Woche lief. In der App:
- **Was gezeichnet wird, rechnet `EnergyCardModel`** (Anteile, Höhen, Lage der
  Nulllinie, Beschriftungen), die View setzt nur um. **Verworfen:** die
  Rechnung in der View - jeder Sonderfall (nichts gegessen, Überschuss, Tag
  ohne Wert, Prognose, leere Woche) wäre nur im Bild prüfbar, und der
  Simulator bekommt keine Health-Daten.
- **Heute kommt aus der Summary, ersatzweise aus der Woche.** Beide Abfragen
  fallen für sich aus; scheitert nur die Summary, steht derselbe Tag auch in
  `GET /api/energy`. „⌀ 7 T" ist dann „–". **Verworfen:** nur die Summary -
  die Karte verlöre Kopfzeile und Balken, obwohl die Zahl da ist.
- **Die Woche wird gerundet, bevor die Richtung feststeht**: was auf 0 rundet,
  ist kein Überschuss - dieselbe Regel wie beim Wort in der Kopfzeile.
  **Verworfen:** das rohe Vorzeichen (ein Tag „Defizit 0 kcal" bekäme einen
  roten Stummel und schöbe die Nulllinie).
- **Ohne Kalorienzähler fehlt die Karte** (Vertrag §5 Punkt 5: ohne Defizit
  heute und ohne Wert in der Woche). **Verworfen:** als Rest nur den Verbrauch
  zeigen wie in Runde 1 - ohne Aufnahme ist das keine Bilanz, und der
  Verbrauch steht im Essen-Tab.
- **Balken als einfache Formen, nicht Swift Charts.** **Verworfen:** `BarMark` -
  Achsen, Ränder und Gesten für einen 52 Punkte hohen Streifen in einer Karte,
  die selbst ein Knopf ist.
- **Die Marke des Verbrauchs ist 3 Punkte breit und steht über den Balken
  hinaus.** **Verworfen:** eine Haarlinie in Balkenhöhe - am Ende des Balkens
  ging sie in der Defizit-Farbe unter.
- **Die Woche zeigt nur volle Tage** (Felix, 09.10., Vertrag §5 Punkt 4): die
  sieben Tage D−7 … D−1, „⌀ 7 T" über dieselben Tage; heute steht schon im
  Bilanzbalken. Geholt wird D−7 … heute - heute dient nur als Ersatz, wenn die
  Summary fehlt. **Verworfen:** heute wie bisher blasser mit (morgens ist die
  Prognose fast der ganze Verbrauch und staucht die übrigen Balken) und heute
  gekappt (ein abgeschnittener Balken sähe aus wie ein Wert).
- **Ein Tag mit 0 oder fast 0 bekommt einen 2 Punkte hohen Strich**
  (`EnergyCardModel.barLength`, wie Android 2 dp), damit er sich vom Tag ohne
  Wert unterscheidet. **Verworfen:** nichts zeichnen (0 sähe aus wie
  „nicht getrackt").

## 2026-10-09 — Healthy holt 425 Nächte zurück, nicht 365
Felix hat entschieden (09.10., vor dem Ausrollen): Die einmalige Rückholung
holt 425 Nächte. Der längste Logbook-Zeitraum ist ein Jahr, und der Weight
Tracker rechnet jede Nacht gegen die 60 Nächte davor (Healthy-Vertrag §3.2) -
mit nur 365 hätten die ältesten gut zwei Monate dieses Jahres keinen Score.
**Verworfen:** 365 (Lücke vorne im Jahr); die ganze Historie (keine Rechnung
braucht Nächte, die älter als 425 Tage sind, und die erste Rückholung dauerte
länger). Später erweitern ginge auf iOS von selbst weiter (Cursor), auf
Android nicht (Merker „fertig") - deshalb vor dem ersten Ausrollen.

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
- **Über Mitternacht zurück auf gestern** (`LogbookDraft.day`): bleibt die
  Seite offen oder kommt sie nach Mitternacht wieder in den Vordergrund, und
  beim Tipp auf die Erinnerung, steht wieder „gestern" da - außer ein
  angefangener, nicht gespeicherter Tag liegt noch in der Frist (Befund aus
  dem Android-Review, 09.10.). **Verworfen:** den gewählten Tag stehen lassen -
  er rutschte jeden Morgen weiter nach hinten, bis der Dienst das Speichern
  mit „Außerhalb der Nachtragsfrist." ablehnt.
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
  (`minimumScaleFactor`), als nach einem „·" umzubrechen. *Abgelöst am selben
  Tag durch „Balken + Woche" (oben).* **Verworfen:** drei
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
  1–400 ms, Puls 20–220, Atem 3–60, Minuten über 1.440 auch bei Wach- und
  Stadienzeit; Energie aktiv außerhalb 0–10.000, Ruhe 0–5.000 - fehlen beide,
  fällt der Tag weg). Eine einzige solche Zahl lässt beim Dienst die ganze
  Anfrage mit 400 scheitern (Befund aus dem Android-Review, 09.10.).
  **Verworfen:** schicken und den Fehler hinnehmen - dann fehlten alle 14
  Nächte bzw. 30 Tage Energie, bis der Wert aus dem Fenster fällt.
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

## 2026-10-05 — Wald: Kategorie nachtragen – Tag antippen, und auch beim wachsenden Baum
Felix hatte vor einem 55-Minuten-Baum die Kategorie vergessen; nachträglich
ging das bisher nur über den Dienst von Hand. Entschieden hat er:
- **Tag antippen öffnet ein Blatt mit den Bäumen des Tages** (Uhrzeit, Dauer,
  Kategorie, ältester zuerst); ein Baum antippen öffnet das bekannte
  Kategorie-Blatt (`ForestCategorySheet`, Zweck `.tree`), Wählen schickt
  `PUT /api/focus/sessions/{id}` (Dienst ab Branch `tree-category`).
  **Verworfen:** (a) die Tageszeile im Wald aufklappen, je Baum ein Menü; (b)
  Langdruck auf die Tageszeile mit einem Untermenü je Baum – nichts Neues zu
  sehen, aber versteckt. Die Liste selbst zeigt weiter Tage (siehe 01.10., (c)).
- **Auch während der Session**: die Kategorie in der Karte des wachsenden
  Baums ist ein Knopf (zeigt auch „Ohne Kategorie"), die Wahl geht am Ende mit
  dem Baum raus und gilt als zuletzt benutzt. **Verworfen:** nur nachträglich –
  „kein Abbrechen, keine Verlängerung" bleibt, die Kategorie ändert an der
  Session nichts.

Ebenso entschieden, ohne echte Wahl: Ändern nur mit Netz und **ohne**
Postausgang (wie Anlegen/Umbenennen); ein Baum, den der Dienst noch nicht kennt
(wartet im Postausgang), lässt sich im Blatt nicht antippen – sonst reichte der
Postausgang ihn danach mit der alten Kategorie nach und die Änderung wäre weg.

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
