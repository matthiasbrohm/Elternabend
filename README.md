# Elternabend

Das Gilden-Addon von **Elternabend** für **WoW Forever**: Raid, Soft-Reserve, Plündermeister, Gruppensuche, Berufe mit Aufträgen, Ruhmeshalle und mehr in einem Addon, im Design von [gilde-elternabend.de](https://www.gilde-elternabend.de/). Gargul oder andere Addons werden nicht gebraucht.

> „Die Kinder schlafen. Die Helden erwachen.“

## Installation

### Mit WowUp (empfohlen, Updates per Klick)
1. [WowUp](https://wowup.io/) installieren und als Spielversion **WoW Forever** wählen.
2. **Get Addons → Install from URL** öffnen und diese Adresse eintragen: `https://github.com/matthiasbrohm/Elternabend`
3. Fertig. Neue Versionen zeigt WowUp ab jetzt selbst an und installiert sie mit einem Klick.

### Von Hand
1. Unter [Releases](https://github.com/matthiasbrohm/Elternabend/releases/latest) oder auf [gilde-elternabend.de/addon.php](https://www.gilde-elternabend.de/addon.php) die neueste ZIP-Datei herunterladen.
2. Entpacken und den Ordner nach `World of Warcraft/_forever_/Interface/AddOns/Elternabend/` kopieren (der Ordnername muss so heißen wie die Datei `Elternabend.toc`).

Am besten installieren es alle Raidmitglieder: Dann sehen alle die Soft-Reserves im Tooltip und bekommen einen Hinweis, wenn ihr Item ausgewürfelt wird.

### Neue Version veröffentlichen (Gildenleitung)
1. Versionsnummer in `Elternabend.toc` (`## Version:`) erhöhen, z. B. auf `4.2.2`.
2. Die Änderungen auf den Branch `main` hochladen.
3. Fertig: Die GitHub-Action legt automatisch das Release `4.2.2` an und hängt `Elternabend-4.2.2.zip` und `Elternabend-4.2.2-forever.zip` (für WowUp) an. WowUp meldet das Update danach bei allen.

Vor dem Release laufen die Tests (siehe unten). Schlägt einer fehl, entsteht kein Release – so landet ein kaputtes Addon nicht per WowUp bei der ganzen Gilde.

### Entwickeln und testen
**Tests ohne WoW (Sekunden):** Der Ordner `tests/` enthält ein kleines WoW zum Nachspielen. Es lädt das Addon wie der Client (Dateien in der Reihenfolge der `.toc`), spult die Zeit vor, spielt Events und Addon-Nachrichten ein und zeichnet auf, was beim Spieler ankommt: Chatzeilen, Töne, geöffnete Fenster, gesendeter Chat, Addon-Nachrichten – und jeden Lua-Fehler.

```
brew install luajit                    # einmalig (macOS)
luajit tests/run.lua                   # alle Tests
luajit tests/run.lua Gildenchat        # nur Tests, deren Name „Gildenchat“ enthält
tests/beobachten.sh                    # bei jedem Speichern neu
```

- `laden_test.lua`: Das Addon lädt und läuft eine Stunde ohne Lua-Fehler (allein, in der Gilde, in der Gruppe, als Offizier im Raid).
- `befehle_test.lua`: Jeder `/ea`-Befehl und jeder Reiter läuft ohne Lua-Fehler.
- `gilde_test.lua`: Twinks im Chat, Antworten auf HELLO und VER, Aufträge, die Begrüßung.
- `einstellungen_test.lua`: jeder Schalter aus „Einstellungen“ (aus → nichts mehr davon, an → wie bisher), die Umstellung alter Einstellungen und „Ruhig“ über eine Stunde Gildenleben.

Ein neuer Test sieht so aus:
```lua
test("neuer Auftrag: Ton und Chatzeile", function()
    local w = login({ guild = "Elternabend" })     -- einloggen, Optionen: group, raid, officer, roster, …
    w:receive("ORDER\tauftrag1\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    w:advance(2)                                   -- 2 Sekunden vorspulen
    seen(w, "sound", ".")                          -- print, sound, window, chat, comm, screen, popup
    seen(w, "print", "Neuer Auftrag von Beta")
    noErrors(w)
end)
```
Was die Tests nicht prüfen: Aussehen und Anordnung im Fenster und alles, was nur der echte Client kann (geschützte Funktionen, Kampfsperre). Dafür ist das Spiel da.

**Im Spiel ohne Kopieren und Neustart:** Den Addon-Ordner einmal durch einen Verweis auf dieses Repository ersetzen:
```
ln -s ~/Pfad/zu/Elternabend "/Applications/World of Warcraft/_forever_/Interface/AddOns/Elternabend"
```
Danach reicht nach jeder Änderung an einer `.lua`-Datei ein `/reload`. Neu starten muss WoW nur bei neuen Dateien in der `.toc` und bei neuen Bildern. WowUp sollte diesen Ordner dann nicht mehr verwalten, sonst ersetzt ein Update den Verweis.

## Bedienung
`/ea` oder ein Klick auf das Wappen an der Minimap öffnet das Fenster (Rechtsklick: direkt die Gilde). Auch am Blizzard-Fenster „Gilde & Communitys“ hängt rechts unter den Reitern ein Wappen-Knopf: Linksklick öffnet den Reiter Gilde, Rechtsklick die Startseite.

„Raid“ fasst Übersicht, Soft-Reserve, Plündermeister, Loot, Taktik und Ruhmeshalle zusammen; sie liegen als Unterreiter in einer zweiten Leiste. Den Reiter „Webseite“ sehen nur Offiziere und Gildenleitung.

| Reiter | Inhalt |
|---|---|
| **Raid » Übersicht** | Kacheln für Raid, Anwesenheit (Klassen im Tooltip), Beutemethode und Soft-Reserves. Liste aller Spieler mit Gruppe, Rolle, Klasse, Rang, Anmeldung (dabei, Ersatzbank, fehlt noch, nicht angemeldet), Status, Addon-Version, Vorbereitung und Soft-Reserves. Knöpfe für Bereitschaftscheck, Vorbereitung und Pause. |
| **Raid » Soft-Reserve** | Alle Reservierungen nach Boss, mit Suche. „An Gruppe senden“ verteilt die Liste (nur Leitung und Assistenten). |
| **Raid » Plündermeister** | Beute aus der Leiche mit den SR-Spielern. Würfeln, Würfe auswerten, Item per Klick vergeben. |
| **Gruppen** | Gruppensuche in der Gilde: Gesuch eintragen, melden, einladen. |
| **Raid » Loot** | Alle im Raid vergebenen Items, als CSV; die Leitung erzeugt hier auch den Bericht für die Webseite. |
| **Raid » Ruhmeshalle** | Die Erstkills der Gilde: Boss, Schwierigkeit, Raid, Datum und wer dabei war. |
| **Webseite** (nur Leitung) | Raid aus dem Raidplaner laden und den Raid-Bericht für die Webseite erzeugen. |

Die Würfelregeln entsprechen dem Raidplaner:
- Reserviertes Item: Nur wer es reserviert hat, würfelt (`/roll 100`). Hat es nur eine Person reserviert, bekommt sie es direkt (Knopf „An SR“).
- Nicht reserviert: Hauptspezialisierung `/roll 100` vor Off-Spec und Twinks `/roll 99`.

## Zusammenarbeit mit der Webseite
Ein Addon kann im Spiel nicht ins Internet. Der Austausch läuft deshalb über Text zum Kopieren und Einfügen. Felder sind mit `;` getrennt, eine Zeile pro Eintrag. Unbekannte Zeilen werden ignoriert, damit das Format später wachsen kann.

### Webseite → Addon (Raid aus dem Raidplaner)
Der Raidplaner gibt für einen Raid diesen Text aus; im Spiel unter **Webseite → Raid einfügen**:

```
#ELTERNABEND-RAID 1
raid;42;Hyjal Summit;hyjal;2026-11-12 21:00
spieler;Deltana;Paladin;tank;dabei
spieler;Beta;Priester;heal;dabei
spieler;Ronbuhjaa;Jäger;dd;ersatz
sr;Deltana;30904;Savior's Grasp;Rage Winterchill
sr;Beta;30911;Scepter of Purification;Anetheron
gruppe;1;Deltana;Beta
termin;42;Hyjal Summit;1794517200;180;12;20;offen
#ENDE
```

| Zeile | Felder |
|---|---|
| `raid` | Raid-ID, Titel, Vorlage (`barrow`, `hyjal`, `onyxia`), Datum und Uhrzeit |
| `spieler` | Charaktername, Klasse (deutsch oder englisch), Rolle (`tank`, `heal`, `dd`), Status (`dabei`, `ersatz`, `vielleicht`, `abgemeldet`) |
| `sr` | Charaktername, Item-ID, Itemname, Boss (optional) |
| `gruppe` | Nummer der Raidgruppe (1–8), danach bis zu fünf Charakternamen |
| `termin` | Raid-ID, Titel, Start (Unix-Zeit), Dauer in Minuten, Zusagen, Plätze, Status – alle kommenden Raids, für den Kalender |

**Ein Text für alles:** Dieser eine Text bringt Aufstellung, Raidgruppen, Soft-Reserves und die Raidtermine für den Kalender mit. Fügt ihn ein Offizier ein, verteilt das Addon die Termine gleich an die Gilde (nur wenn sich etwas geändert hat). Beide Einfüge-Fenster – „Raid einfügen“ und „Raidtermine einfügen“ – nehmen beide Texte an.

### Addon → Webseite (Raid-Bericht)
Das Addon schreibt im Raid automatisch mit (startet beim Betreten einer Raid-Instanz). Unter **Webseite → Bericht erzeugen** entsteht:

```
#ELTERNABEND-BERICHT 1
raid;42;Hyjal Summit;1794517200;1794528000;Deltana
anwesend;Beta;Priester;178;dabei
anwesend;Deltana;Paladin;180;dabei
boss;1794518400;618;Rage Winterchill;1
beute;1794518500;30904;Savior's Grasp;Deltana;SR;87
#ENDE
```

| Zeile | Felder |
|---|---|
| `raid` | Raid-ID aus dem Raidplaner (leer, wenn keiner geladen war), Instanz, Start und Ende (Unix-Zeit), Plündermeister |
| `anwesend` | Charaktername, Klasse, Minuten im Raid, Anmeldestatus (`dabei`, `ersatz`, `vielleicht`, `abgemeldet` oder `nicht angemeldet`) |
| `boss` | Zeit, Encounter-ID, Bossname, `1` = besiegt / `0` = Wipe |
| `beute` | Zeit, Item-ID, Itemname, Gewinner, Art (`SR`, `MS`, `OS/Twink`, `direkt`), Wurf |

Auch ein CSV-Export von softres.it wird weiterhin erkannt.

## Taktikbilder
Der Reiter **Taktik** zeigt Taktikbilder zu jedem Boss. „Groß anzeigen“ öffnet das Bild groß, „Dem Raid zeigen“ (Leitung und Assistenten) öffnet es bei allen mit Addon.

Ein Addon kann keine Bilder aus dem Internet laden oder verschicken. Die Bilder werden deshalb mit dem Addon ausgeliefert:
1. Bild in den Ordner `Taktik-Werkstatt/bilder/` legen (JPG, PNG oder WebP).
2. In `Taktik-Werkstatt/taktiken.txt` eine Zeile ergänzen: `datei;raid;boss;kurztext`.
3. `python3 Taktik-Werkstatt/taktik-bilder.py` ausführen (macOS). Das Skript legt die Bilder als TGA in `Taktik/` und schreibt `Taktik.lua`.
4. Neue Addon-Version an alle verteilen. Neue Bilder erkennt WoW erst nach einem Neustart des Spiels, nicht schon mit `/reload`.

„Dem Raid zeigen“ verschickt nur die Kennung des Bildes. Wer eine ältere Addon-Version hat, bekommt den Hinweis, das Addon zu aktualisieren.

## Der Gilde beitreten per Knopf
**Gerade keine Zeit für Anfragen?** Im Anfrage-Fenster schaltet **„Stumm“** Fenster und Ton aus (ebenso im Reiter Invite „Fenster bei Anfragen“ oder `/ea anfragen`). Die Anfragen gehen nicht verloren: Sie sammeln sich still im Reiter Invite, mit Plakette am Reiter und an der Minimap. In Dungeons und Raids ist das Fenster von selbst stumm (abschaltbar im Reiter Invite); nach dem Verlassen meldet das Addon, was gewartet hat.

Wer das Addon hat, aber noch nicht in der Gilde ist, sieht im Start-Reiter den Knopf **„Der Gilde beitreten“**. Ein Klick schreibt `ginv` in einen versteckten, passwortgeschützten Chat-Kanal („ElternabendTreff“). Alle Mitglieder mit Addon, die einladen dürfen, sitzen im Hintergrund darin; bei ihnen erscheint das Gildenanfrage-Fenster mit dem Befehl zum Kopieren. Im Chat sieht man den Kanal nicht – auch keine Meldungen, wer ihn betritt oder verlässt. Wer anfragt, tritt dem Kanal erst mit dem Klick auf den Knopf bei und verlässt ihn nach zwei Minuten wieder; Charaktere ohne Gilde sitzen also nicht dauerhaft darin. Sobald die Person beigetreten ist, verschwindet die Anfrage bei allen. Landet der Kanal beim Einloggen vor Allgemein und Handel (etwa auf Nummer 1), schiebt das Addon ihn automatisch ans Ende der Kanalliste.

Zusätzlich flüstert der Knopf `ginv` an die Namen in `Join.INVITERS` (oben in `Join.lua`) – als Rückfallebene. Wer davon offline ist, bekommt nichts; die Meldung „Kein Spieler namens …“ blendet das Addon aus.

## Gildeneinladung per Flüstern
Wer dich mit `ginv` anflüstert (Stichwörter im Reiter **Invite** einstellbar, den nur sieht, wer in die Gilde einladen darf), landet in der Anfrageliste. Es zählt nur das Stichwort allein, höchstens mit „bitte“, „pls“ o. Ä. dahinter: „ginv bitte“ und „Gilde?“ sind Anfragen, „Gilde heute Abend?“ nicht. Dann erscheint ein kleines Fenster mit dem fertigen Befehl `/ginvite Anna Sturmwind` zum Kopieren: ins Feld klicken, **Cmd+C** (Windows: Strg+C), dann im Chat **Enter, Cmd+V, Enter**.
- **Den Befehl musst du selbst abschicken.** WoW Forever behält Gildeneinladungen der Blizzard-Oberfläche vor: Weder Addons noch Makros dürfen einladen, und ein Addon darf auch nichts in die Eingabezeile schreiben – sonst blockiert WoW sogar den selbst abgeschickten Befehl („Funktion, die der Blizzard-UI vorbehalten ist“). Das haben wir ausgiebig getestet.
- Sobald WoW „Ihr habt … eingeladen“ meldet, verschwindet die Anfrage, und die Person bekommt eine Antwort per Flüstern. Eine automatische Begrüßung im Gildenchat gibt es nicht mehr – mit vielen Addons in der Gilde kam sie mehrfach.
- „Einladen“ im Reiter **Invite** und die Taste „Nächste Gildenanfrage einladen“ (Tastaturbelegung → Elternabend) öffnen das Fenster mit dem Befehl gleich markiert.
- Man braucht einen Gildenrang, der einladen darf. Das Addon „InviteOnWhisper“ sollte nicht gleichzeitig auf `ginv` reagieren, sonst kommen doppelte Fenster.

## Start: Begrüßung und Gildeninfos
Der Reiter **Start** ist der erste beim Öffnen. Beim allerersten Start in der Gilde öffnet sich das Fenster damit von selbst – einmal pro Account, nicht auf jedem Twink. Er zeigt:
- eine Begrüßung mit dem Vornamen und kurz, wer die Gilde ist,
- die **Nachricht des Tages** live aus dem Spiel (die Gildenleitung ändert sie wie gewohnt im Gildenfenster),
- die **Raidzeiten** und – falls geladen – den nächsten Raid aus dem Raidplaner,
- **Discord** und **Webseite** zum Kopieren (WoW kann keine Links öffnen: ins Feld klicken, Strg+C),
- eine Übersicht, **was das Addon kann**, jeweils mit „Öffnen“.

Neue Mitglieder sehen den Start-Reiter automatisch einmal: beim ersten Einloggen mit dem Addon und nach dem Beitritt zur Gilde Elternabend.
Die festen Texte (Raidzeiten, Links) stehen in `Info.lua` und kommen mit jeder Addon-Version.

## Pause für den Raid
Die Raidleitung (Leiter oder Assistent) startet im Raid-Reiter mit **Pause 5 Min** oder `/ea pause [Minuten]` eine Pause. Alle mit Addon sehen oben einen großen Countdown, die anderen bekommen eine Schlachtzugswarnung mit der Uhrzeit, wann es weitergeht. Die Leitung kann im Countdown verlängern (+2 Min) oder beenden (`/ea weiter`).

## Vorbereitung und Raid-Erinnerung
Jedes Addon prüft den eigenen Charakter: Fläschchen (oder Elixier/Phiole), Essen („Satt“), Haltbarkeit der Rüstung (unter 30 % = reparieren) und Verzauberungen an Umhang, Brust, Handgelenken, Beinen, Füßen und Waffe. Beim Bereitschaftscheck kommt das automatisch, sonst mit dem Knopf **Vorbereitung** (`/ea vorbereitung`). Die Spalte „Vorbereitung“ zeigt „alles da“ oder was fehlt (Fl = Fläschchen, Rep = reparieren, Vz = Verzauberungen); als Leitung wird danach im Raidchat angesagt, was fehlt.

Wer einen Raid aus dem Raidplaner einfügt, verteilt dessen Termin an die Gilde. 15 Minuten vor Beginn erinnert das Addon alle mit einer Bildschirmmeldung und sagt dir, was dir noch fehlt.

## Gruppensuche
Im Reiter **Gruppen** einträgst du, wofür du Mitspieler suchst und wie viele Tanks, Heiler und DDs (Klick: mehr, Rechtsklick: weniger). Die Gilde sieht das Gesuch sofort (auch im Chat, abschaltbar mit `/ea gruppenhinweis`). Andere wählen es aus und melden sich als Tank, Heiler oder DD; du siehst die Meldungen und lädst mit einem Klick ein. Gesuche verschwinden nach 90 Minuten, beim Ausloggen oder mit **Beenden** – und von selbst, sobald deine Gruppe voll ist: Das Addon merkt sich beim Start, wie groß die Gruppe werden soll (wer schon drin ist plus die gesuchten Plätze), und schließt das Gesuch, wenn so viele Spieler in der Gruppe sind – auch wenn du per Hand eingeladen hast.

Mit dem Häkchen **„Auch im Gildenchat posten“** (standardmäßig an) schreibt das Addon beim Start einmal eine Zeile in den Gildenchat, z. B. „Suche Gruppe für DM: 1 Tank, 2 DD – gemütlich. Mit Addon über /ea gruppen melden, sonst anflüstern!“ So sehen auch Mitglieder ohne Addon das Gesuch und melden sich per Flüstern. Addon-Nutzer bekommen dann keine zweite Meldung.

## Ruhmeshalle
Fällt ein Raidboss zum ersten Mal in einer Gildengruppe (mindestens die Hälfte aus der Gilde), hält das Addon fest: Boss, Schwierigkeit, Raid, Datum und wer dabei war. Die Einträge werden an die ganze Gilde verteilt und beim Einloggen abgeglichen. Zu sehen unter **Raid » Ruhmeshalle** oder mit `/ea ruhm`.

## Kind wach, gleich zurück
Solange du in einer Gruppe bist, steht der **Elternknopf** auf dem Bildschirm (verschiebbar):
- Kleiner Knopf „Kind wach“: **Linksklick 5 Minuten, Rechtsklick 10 Minuten**. Während du weg bist, zeigt er die Restzeit – Linksklick „wieder da“, Rechtsklick 5 Minuten mehr. Die Gruppe sieht, dass du kurz weg bist, mit Timer – am Elternknopf und im Raid-Reiter. Für Spieler ohne Addon geht zusätzlich eine Zeile in den Gruppenchat.
- „+5“ verlängert, „Wieder da“ beendet. Nach Ablauf zeigt der Timer „überfällig“.
- Wer später in die Gruppe kommt, sieht deinen Status trotzdem.
- Eigene Taste: Tastaturbelegung → Elternabend → „Kind wach (5 Min) / Wieder da“.
- Während Bosskämpfen sperrt das Spiel Chat- und Addon-Nachrichten. Ein Klick wird dann gemerkt und nach dem Kampf verschickt.

## Plündermeister-Reiter
Der Reiter erscheint nur für Plündermeister, Leitung und Assistenten – oder für alle, solange gerade Beute ansteht oder gewürfelt wird. Mit `/ea loot` lässt er sich jederzeit öffnen.

## Berufe
Im Reiter **Berufe** siehst du, wer in der Gilde welche Berufe hat – und suchst gezielt: „Heiltrank“ eintippen zeigt alle, die ihn herstellen können, und wer davon online ist. Ein Klick auf einen Charakter zeigt alle seine Rezepte, ein Rechtsklick öffnet ein Flüsterfenster.
- Rechts neben der Suche filterst du nach einem **Beruf**: Wähle z. B. „Lederverarbeitung“, dann siehst du alle, die ihn haben, mit Stufe und Anzahl der Rezepte – die höchste Stufe zuerst. Der Filter gilt auch für die Suche und die Rezeptliste eines Charakters.
- **Nach Rezepten** (Knopf neben dem Filter): jedes Rezept einmal, daneben alle, die es herstellen können – wer online ist, steht grün vorne. Im Tooltip siehst du den Gegenstand wie im Spiel und die nötigen Materialien; ein Klick zeigt alle Hersteller, dort schickst du per Klick einen Auftrag.
- **Nach Rüstungsplatz** (Knopf „Alle Plätze“): zeigt nur Rezepte für einen Platz – zum Beispiel alles für den Kopf, zusammen mit dem Berufsfilter etwa alle Leder-Kopfteile der Lederverarbeitung. In der Rezeptliste steht der Platz in einer eigenen Spalte (bei Rüstung und Waffen mit der Art, z. B. „Kopf · Leder“); „Nach Platz sortieren“ ordnet die Liste von Kopf bis Fuß. „Verschiedenes“ zeigt alles, was man nicht anlegt (Rüstungssets, Tränke, Verzauberungen …).
- **Gebundenes:** Was beim Aufheben gebunden wird, kann der Hersteller nicht weitergeben – solche Rezepte sind von Haus aus ausgeblendet. Im Menü „Alle Berufe“ holt „Auch Gebundenes zeigen“ sie zurück.
- **Sonderrezepte** erkennst du am Rezept-Symbol: Die lernt man nicht beim Lehrer, sondern über ein Rezept (Muster, Pläne, Bauplan, Formel …) von einem Händler, als Beute oder aus einer Quest – z. B. die Rote Leinentasche. Im Filter-Menü zeigt „Nur Sonderrezepte“ ausschließlich diese. Die Zuordnung stammt aus den Daten von AtlasLootClassic.
- **Für die Webseite exportieren** (rechts unter „Meine Berufe“): erstellt einen Text mit allen Berufen, Stufen und Rezepten der Gilde – samt Materialien und Werten der hergestellten Gegenstände. Offiziere fügen ihn auf [gilde-elternabend.de/berufe.php](https://www.gilde-elternabend.de/berufe.php) unter „Aus dem Addon importieren“ ein.
- Deine Rezepte liest das Addon aus, sobald du **einmal dein Berufsfenster öffnest**, und teilt sie über den Gildenkanal. Jedes Addon speichert, was es empfängt – auch Rezepte von Mitgliedern, die gerade offline sind.
- Sammelberufe (Angeln, Kräuterkunde, Bergbau, Kürschnerei) werden nicht angezeigt.
- „Berufe der Gilde neu anfragen“ bittet alle, die gerade online sind, ihre Berufe zu schicken.
- Zu sehen sind nur Mitglieder mit Addon.

### Aufträge
Klick auf ein Rezept (in der Suche oder in der Rezeptliste eines Charakters) schickt dem Hersteller einen Auftrag mit kurzer Notiz. Ist der Charakter nicht online, geht der Auftrag an einen anderen Charakter desselben Spielers – oder wartet, bis einer online kommt. Der Hersteller sieht seine Aufträge in der Karte „Aufträge“, nimmt sie an, lehnt ab oder meldet „fertig“. Erledigte Aufträge verschwinden nach 14 Tagen.

## Pinnwand
Das schwarze Brett der Gilde (`/ea pinnwand`). Jedes Mitglied heftet Zettel an – als **Info**, **Aktion** (mit Termin), **Suche**, **Biete**, **Hilfe gesucht** oder **Danke** – und wählt, an wen er geht: alle, Offiziere, einen Rang, eine Klasse oder eine einzelne Person. Ein Zettel hat eine Überschrift (bis 80 Zeichen) und eine mehrzeilige Beschreibung (bis 2000 Zeichen); Antworten dürfen bis 400 Zeichen lang sein. Zettel hängen 1 Tag bis 2 Wochen (Aktionen bis kurz nach dem Termin) und verschwinden dann von selbst.

**Gegenstände im Zettel:** Steht der Cursor in der Beschreibung oder im Antwortfeld, fügt ein Umschalt-Klick auf einen Gegenstand (Tasche, Berufsfenster, Chat) ihn in den Text ein – etwa ein gefundenes Muster. Im Zettel erscheint er in der Farbe seiner Qualität: Drüberfahren zeigt den Tooltip, ein Klick zeigt ihn groß, Umschalt-Klick verlinkt ihn im Chat. Auf der Webseite steht der Name hervorgehoben in eckigen Klammern.

**Nur für die Gilde:** Pinnwand, Berufe, Gruppensuche und die Raidtermine im Kalender sieht nur ein Charakter, der in der Gilde ist. Den Reiter Raid (mit Soft-Reserve, Taktik, Loot und Ruhmeshalle) sehen außerdem Gäste, solange sie in einer Gruppe oder einem Schlachtzug sind. Die Daten sind zwar für den ganzen Account gespeichert, ein Charakter ohne Gilde oder in einer anderen Gilde bekommt die Reiter aber nicht zu sehen – und gibt auch nichts davon weiter. Wechselt jemand dauerhaft die Gilde (60 Tage kein Charakter mehr in der alten), beginnt das Addon in der neuen ohne die alten Daten.

- Andere melden sich mit einem Klick („Bin dabei“, „Ich helfe“, „Interesse“ …) oder schreiben eine kurze Antwort dran.
- Der Ersteller hakt ab oder nimmt den Zettel ab; Offiziere (Rang 1–3) können zusätzlich anpinnen und jeden Zettel abnehmen.
- Offiziere können einen Zettel an alle mit **„Auf der Webseite dauerhaft behalten“** markieren (beim Anheften oder rechts im Zettel): Im Spiel läuft er normal ab, auf der Webseite bleibt er hängen, bis ihn ein Offizier dort abnimmt.
- Pro Spieler sind höchstens 5 Zettel gleichzeitig offen (Offiziere 10).
- Persönliche Zettel sehen nur Absender und Empfänger; der Empfänger bekommt ihn auch, wenn er gerade offline ist.
- Beim Einloggen gibt es einen Hinweis auf neue Zettel, im Start-Reiter steht, was hängt.

**So funktioniert es ohne Server:** Neue Zettel gehen sofort über den Gildenkanal an alle mit Addon. Beim Einloggen gleicht das Addon seine Zettel mit einem anderen Mitglied ab und holt, was fehlt. Ein Zettel erreicht also auch Leute, die später einloggen – solange jemand online ist, der ihn kennt. Die Daten sind nicht verschlüsselt; wer das Addon hat, könnte sie technisch auslesen.

**Webseite:** Offiziere klicken unten auf „Für die Webseite“ und fügen den Text auf `gilde-elternabend.de/pinnwand.php` mit dem Offizierspasswort ein. Übernommen werden nur Zettel an alle.

## Design
Oben rechts im Fenster öffnet **Design** (oder `/ea design`) die Auswahl. Jede Zeile zeigt eine kleine Vorschau:

- **Elternabend** – Nachtblau und Gold, das Design der Gilde (Standard)
- **Allianz** – Königsblau und Silber
- **Horde** – Dunkelrot und Bronze, mit glühender Glut statt Sternen
- **Klassisch** – dunkles Leder und Blizzard-Gelb

Das gewählte Design gilt nur für dich und wird nach dem Neuladen der Oberfläche übernommen (Knopf „Jetzt neu laden“).

## Raidgruppen
Die Fünfergruppen für einen Raid plant die Gildenleitung auf der Webseite, das Addon baut sie im Spiel nach.

1. **Webseite:** Im Raidplaner beim Raid (mit Offizierspasswort) den Bereich „Raidgruppen planen“ öffnen. Der Vorschlag stellt Tanks und Nahkämpfer nach vorne, Zauberer nach hinten und verteilt die Heiler. Zum Ändern einen Spieler anklicken und dann den Zielplatz – belegte Plätze tauschen. „Gruppen speichern“ legt die Aufstellung fest; ohne Speichern gilt der Vorschlag.
2. **Übernehmen:** Den Text unter „Für das Addon Elternabend“ kopieren und im Spiel mit „Raid einfügen“ einfügen – die Gruppen stecken mit drin.
3. **Im Spiel:** Unter **Raid » Raidgruppen** (`/ea raidgruppen`) stehen die acht Gruppen. Wer fehlt oder in der falschen Gruppe steht, ist markiert.
   - **Fehlende einladen** lädt geplante Spieler ein, die online, aber noch nicht in der Gruppe sind.
   - **Gruppen bauen** sortiert den Schlachtzug in die geplanten Gruppen (Leitung oder Assistenz nötig). Nicht eingeplante Spieler kommen auf freie Plätze.
   - **Im Raid ansagen** schreibt die Gruppen in den Raidchat.

## Lagerfeuer-Buffs
Die Raid-Übersicht hat eine Spalte **Lagerfeuer**: wie viele Lagerfeuer-Buffs jemand hat und wie lange sie noch halten (z. B. „6 · 42 Min“; orange unter 15 Minuten, „–“ ohne Buff). Der Tooltip nennt die einzelnen Buffs. Gemeldet wird es zusammen mit der Vorbereitung – beim Klick auf „Vorbereitung“ und bei jedem Bereitschaftscheck. Die Leitung bekommt angesagt, wem der Buff fehlt oder bald abläuft. Erkannt werden die Buffs an ihrer Zauber-ID; `/ea lagerfeuer` zeigt, was das Addon am eigenen Charakter findet.

## Kalender
Der Reiter **Kalender** (`/ea kalender`) zeigt einen Monat auf einen Blick, ein Klick auf einen Tag zeigt die Einzelheiten rechts daneben:

- **Raids** aus dem Raidplaner der Webseite – mit Uhrzeit, Dauer und Zusagen.
- **Dunkelmond-Jahrmarkt** – von wann bis wann und, soweit der Ingame-Kalender es verrät, wo er steht.
- **Zu den Waffen** – das PvP-Wochenende mit dem Bonus-Schlachtfeld.
- **Gildenkalender** – Ereignisse, die jemand in Blizzards Gildenkalender eingetragen hat.
- **Weitere Feiertage** wie Schlotternächte oder der Angelwettbewerb.

Jede Art lässt sich unten rechts ein- und ausblenden. Im Start-Reiter steht, ob gerade Jahrmarkt oder PvP-Wochenende ist und wann der nächste Raid beginnt; die Raid-Erinnerung kurz vor dem Start gilt auch für diese Termine.

**Raidtermine ins Spiel holen:** Ein Offizier öffnet auf `gilde-elternabend.de/raidplaner.php` (mit Offizierspasswort) den Bereich „Termine fürs Addon“, kopiert den Text und fügt ihn im Kalender mit **Raidtermine einfügen** ein. Das Addon schickt die Termine an alle in der Gilde; wer später einloggt, holt sie sich von einem anderen Mitglied. Angenommen werden nur Termine von Offizieren, die neueren gewinnen.

## Notizen
Im Reiter **Notizen** lassen sich beliebig viele Notizen anlegen. Jede kann als kleines Fenster auf den Bildschirm geheftet werden und bleibt dort, auch wenn das Addon-Fenster zu ist – auch nach dem Neu-Einloggen.
- Verschieben mit der Maus, Größe über die Ecke unten rechts.
- Hintergrund von 100 % (deckend) bis 0 % (ganz durchsichtig); bei wenig Hintergrund bekommt die Schrift einen Rand, damit sie lesbar bleibt.
- „Fixiert“: Die Notiz lässt Mausklicks durch und zeigt keine Knöpfe – praktisch für den Kampf.
- Schriftgröße mit A- und A+.

## Gilde: Mitglieder, Mains und Twinks
Wer wessen Twink ist, regelt das Addon selbst – **ohne Offiziersnotiz**. In WoW Forever dürfen Addons Offiziersnotizen nicht schreiben (auch nicht per `/run`), deshalb liegt die Zuordnung im Addon und wird in der Gilde verteilt:

- **Selbst melden:** Spieler legen mit „Diesen Charakter als Main festlegen“ (oder `/ea main`) ihren Main fest. Das Addon kennt alle ihre Charaktere auf dem Account und meldet sie der Gilde – die Zuordnung gilt sofort.
- **Beim Einloggen:** Loggt ein Twink ein, steht der Main gleich in der Chatzeile dabei – „[Alpha Elternabend] ist jetzt online. (Twink von Beta Lux)“.
- **Im Gilden- und Offizierschat:** Schreibt ein Twink, steht der Vorname des Mains in Klammern vor der Nachricht – „[Alpha Elternabend]: (Beta) Hat jemand Lust auf Barrow Deeps?“. Mains bleiben unmarkiert; Flüstern, Gruppe und Schlachtzug bleiben, wie sie sind.
- **Offiziere ordnen zu:** Rechtsklick auf einen Charakter » **„Twink von …“**, dann den Main aus der Liste wählen (Suche, wer online ist, steht oben). „Ist kein Twink (Main)“ hebt eine Zuordnung auf. Für Mitglieder ohne Addon und für Twinks auf einem anderen Account.
- **Verteilung:** Jede Änderung geht sofort an alle in der Gilde mit Addon; wer später einloggt, holt sich den Stand von einem anderen Mitglied. Zuordnungen von Offizieren gehen vor Selbstmeldungen, sonst gewinnt die neueste. Eine Selbstmeldung von einem Twink zählt nicht für Offiziersrechte.
- **Alte Offiziersnotizen** mit dem Namen des Mains werden weiter gelesen, solange es im Addon keine Zuordnung gibt.
- **Zuletzt zugeordnet** (rechts, für Offiziere) zeigt, wer zuletzt was eingetragen hat.

Der Reiter **Gilde** zeigt allen Gildenmitgliedern:
- jeden Spieler mit seinen Twinks darunter, Rang, Stufe, Klasse und ob er online ist – auch „online als …“, wenn er gerade einen Twink spielt,
- **Charaktere eines Spielers**: Ein Klick auf einen Spieler zeigt rechts unten seinen Main und alle Twinks (nochmal klicken: zurück zu den eigenen Charakteren),
- für Offiziere Unstimmigkeiten: Rang „Twink“ ohne Main, Main nicht (mehr) in der Gilde, Twink ohne Rang „Twink“. Den Rang setzt ihr per Rechtsklick über „Befördern/Zurückstufen“.

- **Filter** neben der Namenssuche: „Nur online“ (alphabetisch) oder ein Rang, z. B. alle Initianden.
- **Rechtsklick** auf einen Namen: anflüstern oder in die Gruppe einladen – ist jemand mit einem Twink online, geht beides an diesen Twink.
- **Rang ändern** (nur wer im Spiel befördern bzw. zurückstufen darf): Im Rechtsklick-Menü stehen „Befördern: …“ und „Zurückstufen: …“ mit dem jeweils nächsten Rang – pro Klick eine Stufe. Blizzard erlaubt Addons das Befördern nicht direkt – der Menüpunkt löst deshalb `/gpromote` bzw. `/gdemote` aus, als hättest du es selbst eingetippt. Im Kampf ist der Menüpunkt ausgeblendet.

### Stufenbereich
Neben „Alle Spieler“ steht im Reiter **Gilde** der Knopf **„Alle Stufen“**: Er filtert die Liste nach Stufenbereich (1–10, 11–20 … 51–60) – wie in der Klassenliste auf der Webseite. In Klammern steht, wie viele Charaktere der Gilde gerade in dem Bereich sind. Gezeigt werden die Spieler, die dort einen Charakter haben; von ihren Twinks nur die passenden, die Stufe ist hervorgehoben. Zusammen mit „Nur online“ sieht man, wer gerade da ist und einen Charakter zum gemeinsamen Leveln hätte.

## Gildenwappen
Das Wappen erscheint im Addon-Menü, oben links im Fenster und am Minimap-Button. Es liegt als `Media/Wappen.tga` im Addon. Ein neues Wappen: Bild als `Grafik/wappen.webp` ablegen und `python3 Grafik/wappen.py` ausführen.

## Leitung: Gildenchronik
Den Reiter **Leitung** (`/ea leitung`) sehen nur Offiziere und Gildenleitung. Er hält fest, was sich in der Gilde tut:

- **Chronik** mit Filter: Eintritte (mit wem eingeladen hat), Austritte (ausgetreten oder entfernt – und von wem), Rangänderungen, Charaktere mit Stufe 60 und **„Wieder da“** – Spieler, die nach langer Pause wieder online sind. Dann gibt es auch eine Meldung im Chat.
- **Die Gilde in Zahlen:** Spieler, Charaktere, gerade online, Stufe 60, Ein- und Austritte der letzten 30 Tage, Klassenverteilung.
- **Jubiläen:** Aus den Eintritten in der Chronik meldet das Addon, wer seit einem Monat, 100 Tagen, einem halben Jahr oder einem (weiteren) Jahr dabei ist – einmal im Chat und als Eintrag in der Chronik. Ein Klick auf ein Jubiläum oder auf „Stufe 60“ schlägt einen Glückwunsch für den Gildenchat vor; abschicken muss man ihn selbst.
- **Lange nicht online:** Spieler, die mit keinem ihrer Charaktere in der eingestellten Zeit da waren (Knopf oben rechts: 1, 2, 3, 6 oder 12 Monate; Standard 3 Monate). Dieselbe Schwelle gilt für „Wieder da“.
- **Klassenliste für die Webseite:** Der Knopf „Für die Webseite“ (oder `/ea klassenliste`) erstellt einen Text mit allen Mitgliedern – Name, Klasse, Stufe, Rang und wer wessen Twink ist. Kopieren und auf gilde-elternabend.de unter **Gilde » Klassenliste** bei „Für die Gildenleitung“ einfügen. Wann jemand zuletzt online war und die Notizen werden nicht übertragen.

Die Chronik entsteht aus dem Vergleich der Gildenliste mit dem zuletzt gemerkten Stand und aus Blizzards Gildenprotokoll (die letzten 100 Einträge – damit ist sie beim ersten Öffnen schon gefüllt). Sie liegt auf dem eigenen Rechner; jeder Offizier führt seine eigene. Was passiert, während kein Offizier online ist, wird beim nächsten Einloggen bemerkt und – soweit Blizzards Protokoll es noch kennt – mit der richtigen Zeit nachgetragen.

## Spielzeiten
Im Reiter **Gilde** öffnet „Meine Spielzeiten …“ (oder `/ea spielzeiten`) ein kleines Raster: Wochentage × Vormittag, Nachmittag, Abend, Spät – dazu eine kurze Notiz wie „meist ab 20:30“. Die Addons reichen die Angaben in der Gilde weiter. Im Tooltip der Gildenliste steht dann „Spielt meist: abends Di, Do · spät Sa“ und, was ihr gemeinsam habt („Wie du: …“). Der Dialog zeigt rechts, wer zu denselben Zeiten spielt – die mit der größten Überschneidung zuerst.

## Erste Schritte
Für Neue gibt es auf der Startseite die Zeile **Erste Schritte** (oder `/ea schritte`): Discord beitreten, Main festlegen, Berufe erfassen, Spielzeiten eintragen, Raidtermine ansehen. Main, Berufe und Spielzeiten haken sich von selbst ab; die Zeile verschwindet, sobald alles erledigt ist. Die Gildenleitung sieht im Tooltip der Gildenliste und unter **Leitung » „Erste Schritte“**, wer noch etwas offen hat – und welche Neuen der letzten 30 Tage sich noch gar nicht gemeldet haben (kein Addon oder eine ältere Version).

## Einstellungen
Oben rechts im Fenster öffnet **„Einstellungen“** (oder `/ea einstellungen`) eine Liste mit Schaltern für alles, was das Addon außerhalb seines Fensters am Spiel verändert – wer etwas davon nicht möchte, schaltet es einzeln ab:

- **Im Chat:** Main vor Nachrichten von Twinks, Main hinter der Einlog-Meldung, Zettel an dich (und Antworten auf deine Zettel), neue Zettel an alle, neue Gruppengesuche, „Kind wach“ im Gruppenchat, Statusmeldungen („Raid-Protokoll läuft“, Pings anderer, die ganze Soft-Reserve-Liste – deine eigenen Reserves kommen immer).
- **Auf dem Bildschirm:** Elternknopf – immer in der Gruppe oder nur, solange jemand weg ist –, Knopf an der Minimap, Knopf am Gildenfenster, Soft-Reserves im Tooltip, Erinnerung vor dem Raid (als Zeile im Chat und auf Wunsch groß in der Bildschirmmitte), Quizfenster, wenn die Leitung ein Quiz startet, Fenster bei Gildenanfragen, Fenster beim Plündern.
- **Töne:** „Töne, wenn jemand auf dich wartet“ (deine Soft-Reserve wird ausgewürfelt, Pause, jemand will in deine Gruppe) und „Übrige Töne“ (Aufträge, Zettel an dich, Taktikbild, Raid-Erinnerung, Gildenanfragen).

Drei Knöpfe stellen alles auf einmal:
- **„Ruhig“:** Information ja, Unterbrechung nein. Nichts öffnet sich von selbst (Quiz und Gildenanfragen warten auf `/ea quiz` bzw. den Reiter Invite), kein Knopf an der Minimap, der Elternknopf nur, solange jemand weg ist, die Raid-Erinnerung als Zeile im Chat, Töne nur, wenn jemand auf dich wartet. Twinks im Chat, Zettel an dich, Gruppengesuche, Soft-Reserves im Tooltip und das Taktikbild der Leitung bleiben.
- **„Alles an“:** wie bisher.
- **„Alles aus“:** ein reines Gildenfenster, das sich nur noch mit `/ea` öffnet.

Der Austausch mit der Gilde (Berufe, Twinks, Pinnwand, Kalender, Antworten auf Bereitschafts- und Versionsabfragen) läuft in jedem Fall weiter. Wer vor dieser Version „Töne“ oder die Pinnwand-Meldungen abgeschaltet hatte, hat danach beide neuen Teile davon aus.

## Quiz
Für Zeltlager, Lagerfeuer und Wartezeiten: Im Reiter **Raid » Übersicht** öffnet „Quiz“ (oder `/ea quiz`) das Quizfenster. Die Leitung der Gruppe (Raidleitung und Assistenten, in der Fünfergruppe der Anführer) startet die Runde für alle: Das Addon zieht zehn Fragen zufällig aus hundert, bei allen mit Addon geht das Fenster auf, und jeder beantwortet dieselben Fragen – vier Antworten zur Auswahl, 20 Sekunden je Frage. Die Uhr läuft erst nach dem Klick auf „Los geht's“.

Am Ende meldet jedes Addon sein Ergebnis; alle sehen die Rangliste (mehr Richtige zuerst, bei Gleichstand die schnellere Zeit), und die Leitung sagt mit einem Klick die ersten drei im Gruppenchat an. Fragen, die schon dran waren, kommen erst wieder, wenn alle hundert gestellt wurden. Ohne Gruppe ist das Quiz eine Proberunde für einen allein.

Die Fragen stehen in `QuizFragen.lua` (Frage, richtige Antwort, drei falsche). Neue Fragen hinten anhängen und `rev` erhöhen – alle in der Gruppe brauchen denselben Stand.

## Abgleich mit der Webseite über die Mac-App
Ein Addon kann nicht ins Internet – deshalb läuft der Austausch mit gilde-elternabend.de sonst über Kopieren und Einfügen. Die kleine Mac-App **Elternabend Abgleich** (Ordner `Mac-App`, für die Gildenleitung) nimmt das ab:

- **Spiel → Webseite:** Beim Ausloggen und bei `/reload` legt das Addon Klassenliste, Pinnwand, Berufe und den Raid-Bericht (sobald das Raid-Protokoll beendet ist) in die gespeicherte Variable `ElternabendSync`. Die App lädt hoch, was sich geändert hat.
- **Webseite → Spiel:** Die App schreibt den nächsten Raid (Anmeldungen, Raidgruppen, Soft-Reserves, Termine) in die Datei `Abgleich.lua` im Addon-Ordner. Das Addon übernimmt ihn beim Einloggen oder nach `/reload` – aber nicht von selbst, solange ein Raid läuft. `/ea abgleich` zeigt den Stand und holt die Daten von Hand.

Ohne die App passiert nichts davon: `Abgleich.lua` bleibt leer, und es wird nichts zusätzlich gespeichert. Hochgeladen wird nur mit einem Charakter der Gildenleitung.

## Tasten
Unter **Optionen » Tastaturbelegung » Elternabend** (eigener Abschnitt, unten in der Liste) lassen sich Tasten vergeben: „Fenster öffnen / schließen“ und je eine für die Reiter Gilde, Gruppen, Raid, Kalender und Pinnwand. Ein zweiter Druck auf dieselbe Taste schließt das Fenster wieder. Dazu kommen die Tasten „Kind wach / Wieder da“ und „Nächste Gildenanfrage einladen“.

## Befehle
| Befehl | Wirkung |
|---|---|
| `/ea start` | Begrüßung und Gildeninfos |
| `/ea import` | Raid aus dem Raidplaner einfügen |
| `/ea taktik` | Taktikbilder öffnen |
| `/ea invite` | Gildenanfragen öffnen (nur wer einladen darf) |
| `/ea gilde` | Mitglieder mit Mains und Twinks |
| `/ea main` | Diesen Charakter als Main festlegen |
| `/ea berufe` | Berufe und Rezepte der Gilde |
| `/ea gruppen` | Gruppensuche in der Gilde |
| `/ea gruppenhinweis` | Neue Gruppengesuche im Chat an/aus |
| `/ea ruhm` | Ruhmeshalle mit den Erstkills |
| `/ea pause [Minuten]` | Pause für den ganzen Raid (Leitung), `/ea weiter` beendet sie |
| `/ea vorbereitung` | Fläschchen, Essen, Rüstung und Verzauberungen prüfen |
| `/ea notizen` | Notizen öffnen |
| `/ea kind [Minuten]` | Kind wach, gleich zurück (Standard 5 Minuten) |
| `/ea da` | Wieder da |
| `/ea knopf` | Elternknopf ein/aus |
| `/ea kindchat` | Kind-Status im Gruppenchat ein/aus |
| `/ea ginv` | Flüster-Einladung an/aus |
| `/ea bericht` | Raid-Bericht für die Webseite |
| `/ea roll [Itemlink]` | Item aus den Taschen auswürfeln (Vergabe wird „per Handel“ notiert) |
| `/ea rolltime 30` | Würfeldauer in Sekunden |
| `/ea quality 3` | Mindestqualität im Plündermeister-Reiter (3 = Selten, 4 = Episch) |
| `/ea rw` | Schlachtzugswarnung an/aus |
| `/ea minimap` | Minimap-Button ein/aus |
| `/ea gildenknopf` | Wappen-Knopf am Blizzard-Gildenfenster ein/aus |
| `/ea leistung` | Zeigt, wie oft und wie lange das Addon die Gildenliste auswertet (bei Rucklern) |
| `/ea pinnwand` | Pinnwand öffnen (auch `/ea zettel`) |
| `/ea design` | Design des Addons wählen |
| `/ea leitung` | Gildenchronik für Offiziere: Ein- und Austritte, Rückkehrer, lange Inaktive |
| `/ea klassenliste` | Klassenliste für die Webseite erstellen (nur Gildenleitung) |
| `/ea spielzeiten` | Eigene Spielzeiten eintragen und sehen, wer zur selben Zeit spielt |
| `/ea schritte` | Die „Ersten Schritte“ für neue Mitglieder zeigen |
| `/ea einstellungen` | Chat-Zusätze, Knöpfe, Meldungen und Töne einzeln an- und abschalten |
| `/ea quiz` | Quiz öffnen: in der Gruppe startet es die Leitung für alle, allein ist es eine Proberunde |
| `/ea anfragen` | Fenster und Ton für Gildenanfragen aus- oder einschalten (Anfragen sammeln sich im Reiter Invite) |
| `/ea abgleich` | Stand des Abgleichs über die Mac-App zeigen und den Raid von der Webseite übernehmen |
| `/ea lagerfeuer` | Zeigt, welche Lagerfeuer-Buffs das Addon an dir erkennt (mit Zauber-IDs) |
| `/ea raidgruppen` | Geplante Raidgruppen ansehen und im Schlachtzug bauen |
| `/ea kalender` | Kalender mit Raids, Jahrmarkt und PvP-Wochenende |
| `/ea sync` | Soft-Reserves erneut an die Gruppe senden |

## Namen mit Vor- und Nachnamen
In WoW Forever hat jeder Charakter einen Vor- und einen Nachnamen („Anna Sturmwind“). Einladen und Anflüstern klappt nur mit dem vollen Namen. Das Addon arbeitet deshalb überall mit „Vorname Nachname“:
- Gildeneinladungen gehen genau an den Namen, mit dem die Person geflüstert hat.
- Raid, Würfe und Plündermeister nutzen den vollen Namen aus dem Spiel.
- Hat jemand im Raidplaner oder auf softres.it nur den Vornamen eingetragen, wird er trotzdem zugeordnet, solange der Vorname im Raid eindeutig ist.

## Retail
Das Addon läuft auch in Retail-WoW, denn beide nutzen denselben Client. Dort steht der zweite Teil eines Namens für den Realm statt für den Nachnamen; das Addon erkennt das selbst. Einen Plündermeister gibt es in Retail nicht mehr: Würfelrunden funktionieren, die Vergabe wird dann als „per Handel“ notiert.

## Hinweise zu WoW Forever
WoW Forever nutzt den Retail-Client. Während Kämpfen und Bossbegegnungen sperrt er Chat- und Addon-Nachrichten und verschleiert manche Werte. Das Addon wartet in dieser Zeit und sendet Ansagen danach. Würfelrunden deshalb erst nach dem Kampf starten.
Ob der Plündermeister in WoW Forever Items direkt zuteilen kann, zeigt sich zum Start. Falls nicht, wird die Vergabe als „per Handel“ notiert und das Item gehandelt.
