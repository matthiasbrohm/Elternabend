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
`/ea` oder ein Klick auf das Wappen an der Minimap öffnet das Fenster (Rechtsklick: direkt die Gilde). Kleine Plaketten am Minimap-Knopf zeigen, was Neues da ist – jede Sorte in ihrer Farbe und an ihrer Ecke, sodass mehrere gleichzeitig zu sehen sind: **rot** oben rechts neue Gruppensuchen (und still wartende Gildenanfragen), **gelb** oben links neue Zettel an der Pinnwand, **grün** unten links neue Herstellungsaufträge an dich, bis du sie annimmst oder ablehnst. Dieselben Farben stehen an den Reitern Gruppen, Pinnwand und Berufe. Auch am Blizzard-Fenster „Gilde & Communitys“ hängt rechts unter den Reitern ein Wappen-Knopf: Linksklick öffnet den Reiter Gilde, Rechtsklick die Startseite.

„Raid“ fasst Übersicht, Soft-Reserve, Plündermeister, Loot, Taktik und Ruhmeshalle zusammen; sie liegen als Unterreiter in einer zweiten Leiste. Den Reiter „Webseite“ sehen nur Offiziere und Gildenleitung.

| Reiter | Inhalt |
|---|---|
| **Raid » Übersicht** | Kacheln für Raid, Anwesenheit (Klassen im Tooltip), Beutemethode und Soft-Reserves. Liste aller Spieler mit Gruppe, Rolle, Klasse, Rang, Anmeldung (dabei, Ersatzbank, fehlt noch, nicht angemeldet), Status, Addon-Version, Vorbereitung und Soft-Reserves. Knöpfe für Bereitschaftscheck, Rollenabfrage (alle wählen Tank, Heiler oder Schaden; nur Leitung und Assistenten), Vorbereitung, Pause und **Countdown** 5 oder 10 Sekunden (Blizzards große Zahl bei allen in der Gruppe, z. B. vor dem Pull; im Schlachtzug nur Leitung und Assistenten). |
| **Raid » Soft-Reserve** | Alle Reservierungen nach Boss, mit Suche. „An Gruppe senden“ verteilt die Liste und den ganzen Raid (nur Leitung und Assistenten). |
| **Raid » Plündermeister** | Beute aus der Leiche mit den SR-Spielern. Würfeln, Würfe auswerten, Item per Klick vergeben. |
| **Gruppen** | Gruppensuche in der Gilde, mit zwei Unterreitern: **Offene Gruppen** (melden, sehen, wer schon dabei ist) und **Eigene Gruppe** (Gesuch eintragen, einladen). |
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
wunsch;Beta;30904;1
prio;30904;Beta,Deltana
dkpregel;10
dkp;Beta;50
termin;42;Hyjal Summit;1794517200;180;12;20;offen
#ENDE
```

| Zeile | Felder |
|---|---|
| `raid` | Raid-ID, Titel, Vorlage (`barrow`, `hyjal`, `onyxia`), Datum und Uhrzeit |
| `spieler` | Charaktername, Klasse (deutsch oder englisch), Rolle (`tank`, `heal`, `dd`), Status (`dabei`, `ersatz`, `vielleicht`, `abgemeldet`) |
| `sr` | Charaktername, Item-ID, Itemname, Boss (optional) |
| `gruppe` | Nummer der Raidgruppe (1–8), danach bis zu fünf Charakternamen |
| `wunsch` | Loot-Wunschliste: Charaktername, Item-ID, Platz auf seiner Wunschliste (1 = am wichtigsten) – nur offene Wünsche |
| `prio` | Loot-Wunschliste: Item-ID, Charakternamen mit Komma in der Reihenfolge, in der das Item vergeben wird |
| `dkpregel` | DKP: Mindestgebot |
| `dkp` | DKP: Charaktername, Punktestand |
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

**Neu oder Twink?** Nach dem ersten Klick fragt das Addon: **„Ich bin neu“** oder **„Ich bin ein Twink“**. Ein Twink schickt `ginv twink <Main>` statt `ginv` – den Main kennt das Addon aus deinen anderen Charakteren auf diesem Account, die schon in der Gilde sind. Bei den Einladenden steht die Anfrage dann als „Twink von …“, und die Gilde bekommt Bescheid, damit niemand den Twink wie einen neuen Spieler begrüßt. Nach dem Beitritt meldet sich der Twink selbst seinem Main zu (wie „Das sind meine Charaktere“) und schreibt eine Zeile in den Gildenchat: „Hallo zusammen, ich bin ein neuer Twink von …“. Ohne Addon geht es auch: `ginv twink Beta Lux` flüstern. Eingeladen wird vom Twink aus – nicht vom Main.

Zusätzlich flüstert der Knopf `ginv` an die Namen in `Join.INVITERS` (oben in `Join.lua`) – als Rückfallebene. Wer davon offline ist, bekommt nichts; die Meldung „Kein Spieler namens …“ blendet das Addon aus.

## Gildeneinladung per Flüstern
Wer dich mit `ginv` anflüstert (Stichwörter im Reiter **Invite** einstellbar, den nur sieht, wer in die Gilde einladen darf), landet in der Anfrageliste. Es zählt nur das Stichwort allein, höchstens mit „bitte“, „pls“ o. Ä. dahinter: „ginv bitte“ und „Gilde?“ sind Anfragen, „Gilde heute Abend?“ nicht. Dann erscheint ein kleines Fenster mit dem fertigen Befehl `/ginvite Anna Sturmwind` zum Kopieren: ins Feld klicken, **Cmd+C** (Windows: Strg+C), dann im Chat **Enter, Cmd+V, Enter**.
- **Den Befehl musst du selbst abschicken.** WoW Forever behält Gildeneinladungen der Blizzard-Oberfläche vor: Weder Addons noch Makros dürfen einladen, und ein Addon darf auch nichts in die Eingabezeile schreiben – sonst blockiert WoW sogar den selbst abgeschickten Befehl („Funktion, die der Blizzard-UI vorbehalten ist“). Das haben wir ausgiebig getestet.
- Sobald WoW „Ihr habt … eingeladen“ meldet, verschwindet die Anfrage, und die Person bekommt eine Antwort per Flüstern. Eine automatische Begrüßung im Gildenchat gibt es nicht mehr – mit vielen Addons in der Gilde kam sie mehrfach.
- „Einladen“ im Reiter **Invite** und die Taste „Nächste Gildenanfrage einladen“ (Tastaturbelegung → Elternabend) öffnen das Fenster mit dem Befehl gleich markiert.
- Man braucht einen Gildenrang, der einladen darf. Das Addon „InviteOnWhisper“ sollte nicht gleichzeitig auf `ginv` reagieren, sonst kommen doppelte Fenster.

## Start: Begrüßung und Gildeninfos
Der Reiter **Start** ist der erste beim Öffnen. Beim allerersten Start in der Gilde öffnet sich das Fenster damit von selbst – einmal pro Account, nicht auf jedem Twink. Er zeigt:
- eine Begrüßung mit dem Vornamen, darunter deine **Stufe-60-Prognose** („Stufe 60 bei deinem Tempo etwa am 14.12.2026“ – nur für dich, ohne Rangliste: gemessen wird, wie viel Erfahrung du pro Spielstunde sammelst und wie lange du im Schnitt pro Tag spielst; AFK zählt nicht, die erste Prognose kommt nach etwa einer Stunde Spielzeit) und die **Gildeninformation** aus dem Spiel (der Text, den die Gildenleitung im Gildenfenster unter „Gildeninformation“ pflegt). Ist sie leer oder gibt das Spiel sie nicht heraus, steht dort kurz, wer die Gilde ist,
- die **Nachricht des Tages** live aus dem Spiel. Wer sie ändern darf, hat daneben den Knopf **„Ändern“** (höchstens 128 Zeichen, eine Zeile; gesetzt wird sie über den Chatbefehl des Spiels – deutsch /gndt, englisch /gmotd –, denn das direkte Setzen ist für Addons gesperrt – im Kampf geht es nicht),
- beide Felder bekommen rechts einen Rollbalken, sobald der Text nicht hineinpasst (Mausrad oder Regler ziehen),
- die **Raidzeiten** und – falls geladen – den nächsten Raid aus dem Raidplaner,
- **Discord** und **Webseite** zum Kopieren (WoW kann keine Links öffnen: ins Feld klicken, Strg+C),
- eine Übersicht, **was das Addon kann**, jeweils mit „Öffnen“ – darunter die **Stufenaufstiege** der Gilde („Keela 19 » 20“, die drei neuesten; „Alle“ zeigt die letzten zwei Wochen). Jeder Client merkt sie sich aus der Gildenliste (bis zu 250); wer offline war, sieht danach, was inzwischen passiert ist – in „Alle“ als eigener Block „Während du offline warst (von … bis …)“, nach Namen sortiert – mit Klassenfarben und etwas größerer Schrift.

Neue Mitglieder sehen den Start-Reiter automatisch einmal: beim ersten Einloggen mit dem Addon und nach dem Beitritt zur Gilde Elternabend.
Die festen Texte (Raidzeiten, Links) stehen in `Info.lua` und kommen mit jeder Addon-Version.

## Neue Gildenmitglieder begrüßen
Tritt jemand der Gilde bei, schreibt **genau einer** die Begrüßung mit Vorstellungsrunde, Discord und Addon-Tipp (einer von 6 Texten, zufällig) – alle anderen schreiben nichts. Wer die lange schreibt, losen die Addons unsichtbar aus; wer gerade nicht an der Tastatur ist, macht nicht mit, und bleibt die lange aus, schreibt sie nach einer Weile der Nächste. Standardmäßig **aus**, weil das Addon hier in deinem Namen schreibt: Einstellungen » „Neue Gildenmitglieder begrüßen“. „Alles an“ schaltet es nicht ein.

## Gruß und Abschied im Gildenchat

Zwei Schalter in den Einstellungen, beide standardmäßig aus (sie schreiben in deinem Namen, „Alles an“ schaltet sie deshalb nicht ein): **Beim Einloggen grüßen** und **Beim Ausloggen verabschieden**. Den Text trägst du im Feld daneben ein; leer bleibt die Vorgabe („Hallo zusammen!“ bzw. „Ich bin dann mal weg – bis bald!“). Gegrüßt wird 15 Sekunden nach dem Einloggen, nicht nach /reload und höchstens alle 30 Minuten je Account. Den Abschied schreibt das Addon, sobald du ausloggst – über das Spielmenü, /camp, /logout oder „Spiel beenden“. Selbst ausloggen darf ein Addon nicht; es hängt sich nur an den Knopf des Spiels.

## Gildenkarte
Wer Einstellungen » **„Gildenkarte“** einschaltet, teilt seinen Standort mit der Gilde und sieht alle anderen, die ihn auch teilen, als Punkt in Klassenfarbe auf der Weltkarte (Name und Stufe beim Darüberfahren; wer mit in deiner Gruppe oder deinem Raid ist, hat schon den Punkt des Spiels und bekommt keinen zweiten) – praktisch für „wer ist in meiner Gegend und kommt mit?“. Standardmäßig **aus**, „Alles an“ schaltet sie nicht ein. In Dungeons, Raids und Schlachtfeldern wird nichts gesendet; Ausschalten nimmt dich sofort von den Karten der anderen. Gesendet wird nur über den Addon-Kanal der Gilde.

## Wenn das Spiel Chatnachrichten blockiert
Was das Addon nicht direkt aus einem Knopf heraus schreibt – die Nachmeldung der Gruppensuche, die Begrüßung neuer Mitglieder –, geht direkt raus. Sollte das Spiel so eine Nachricht einmal blockieren (manche Spielversionen erlauben Chat nur während eines Tastendrucks oder Klicks), merkt sich das Addon das und schickt sie – und alle weiteren – mit deiner nächsten Taste oder deinem nächsten Klick in die Spielwelt. Davon merkt man nichts; die Taste wirkt ganz normal.

## Pause für den Raid
Die Raidleitung (Leiter oder Assistent) startet im Raid-Reiter mit **Pause 5 Min** oder `/ea pause [Minuten]` eine Pause. Alle mit Addon sehen oben einen großen Countdown, die anderen bekommen eine Schlachtzugswarnung mit der Uhrzeit, wann es weitergeht. Die Leitung kann im Countdown verlängern (+2 Min) oder beenden (`/ea weiter`). Start, Verlängern und Ende überholen alle anderen Addon-Nachrichten in der Warteschlange; zusätzlich schließt die Chatzeile „[Elternabend] Pause vorbei“ der Leitung das Fenster sofort. „Weiter geht's!“ bleibt danach nur 5 Sekunden stehen oder lässt sich mit **OK** wegklicken.

## Vorbereitung und Raid-Erinnerung
Jedes Addon prüft den eigenen Charakter: Fläschchen (oder Elixier/Phiole), Essen („Satt“), Haltbarkeit der Rüstung (unter 30 % = reparieren) und Verzauberungen an Umhang, Brust, Handgelenken, Beinen, Füßen und Waffe. Beim Bereitschaftscheck kommt das automatisch, sonst mit dem Knopf **Vorbereitung** (`/ea vorbereitung`). Die Spalte „Vorbereitung“ zeigt „alles da“ oder was fehlt (Fl = Fläschchen, Rep = reparieren, Vz = Verzauberungen); als Leitung wird danach im Raidchat angesagt, was fehlt.

Wer einen Raid aus dem Raidplaner einfügt, verteilt dessen Termin an die Gilde. 15 Minuten vor Beginn erinnert das Addon alle mit einer Bildschirmmeldung und sagt dir, was dir noch fehlt.

## Gruppensuche
Der Reiter **Gruppen** hat zwei Unterreiter. **Offene Gruppen** (öffnet sich zuerst) zeigt die Gesuche der Gilde und die Suchen aus Discord und Webseite; rechts steht unter **„Wer ist dabei?“**, wer beim angeklickten Gesuch schon in der Gruppe, eingeladen oder gemeldet ist – mit Rolle und in Klassenfarbe. Das schickt der Suchende bei jeder Änderung mit (ab Version 4.30; bei älteren Versionen steht dort „Noch keine Angaben“).

Unter **Eigene Gruppe** wählst du mit **„Ich gehe mit als“**, in welcher Rolle du selbst mitkommst – das steht bei den anderen unter „Wer ist dabei?“ ganz oben. Dort trägst du auch ein, wofür du Mitspieler suchst und wie viele Tanks, Heiler und DDs (Klick: mehr, Rechtsklick: weniger). Der Knopf **Dungeons** neben dem Feld klappt eine Liste aller Dungeons mit empfohlenem Stufenbereich auf (passende für deine Stufe sind grün); ein Klick trägt den Namen ein. Das Feld bleibt frei beschreibbar – für PvP, Weltbosse oder Hogger. In der Liste der offenen Gruppen steht hinter jedem Dungeon gleich der empfohlene Stufenbereich – grün, wenn er zu deiner Stufe passt. Die Gilde sieht das Gesuch sofort (auch im Chat, abschaltbar mit `/ea gruppenhinweis`). Andere wählen es aus und melden sich als Tank, Heiler oder DD; du siehst die Meldungen und lädst mit einem Klick ein. Wer gerade mit einem anderen Charakter online ist – etwa als Jäger, aber mit seinem Tank mitkommen will –, wählt daneben bei **„Mit: …“** den Charakter, mit dem er kommt (alle eigenen Charaktere dieser Gilde, die schon einmal mit dem Addon eingeloggt waren). Der Suchende sieht dann „Beta Lux » Beta Eisenfuss – Tank“; klickt er auf Einladen, bekommt Beta Lux Bescheid, jetzt umzuloggen, und sobald Beta Eisenfuss online ist, meldet das Addon „Beta Eisenfuss ist jetzt online – du kannst einladen“. Unter „Gruppe suchen“ steht der Tipp, vorher kurz in die Gruppensuche im Discord und auf der Webseite zu schauen, damit niemand doppelt sucht. Gesuche verschwinden nach 90 Minuten, beim Ausloggen oder mit **Beenden** – und von selbst, sobald deine Gruppe voll ist: Das Addon merkt sich beim Start, wie groß die Gruppe werden soll (wer schon drin ist plus die gesuchten Plätze), und schließt das Gesuch, wenn so viele Spieler in der Gruppe sind – auch wenn du per Hand eingeladen hast. Kommt jemand per Hand dazu, sinken auch die gesuchten Plätze (seine Rolle, sonst zuerst DD). Unter „Eigene Gruppe“ steht das laufende Gesuch im Formular – ändern und „Aktualisieren“ klicken.

Mit dem Häkchen **„Auch im Gildenchat posten“** (standardmäßig an) schreibt das Addon beim Start einmal eine Zeile in den Gildenchat, z. B. „Suche Gruppe für DM: 1 Tank, 2 DD – gemütlich. Mit Addon über /ea gruppen melden, sonst anflüstern!“ So sehen auch Mitglieder ohne Addon das Gesuch und melden sich per Flüstern. Addon-Nutzer bekommen dann keine zweite Meldung. Lädst du danach jemanden über das Addon ein oder änderst die Zahl der Plätze, kommt eine kurze Zeile hinterher, z. B. „Halle der Thanen: noch 1 Tank und 1 DD gesucht – anflüstern oder /ea gruppen“. Ist die Gruppe voll, heißt es „Halle der Thanen: Gruppe ist voll, danke!“. Mehrere Einladungen kurz hintereinander ergeben nur eine Zeile; beendest du das Gesuch selbst, kommt nichts mehr.

Mit dem Häkchen **„Bei Anmeldung anflüstern lassen“** daneben (standardmäßig aus, auch in den Einstellungen; Idee von Saleos Garthran) flüstert dich jeder, der sich über das Addon für deine Gruppe meldet, zusätzlich an: „[Elternabend] Ich möchte als Tank mit zu Halle der Thanen“. So verpasst du keine Anmeldung, auch wenn das Fenster zu ist; läuft das Spiel im Hintergrund, blinkt außerdem die Taskleiste. Die Flüsternachricht kommt von allen mit Addon ab 4.38.0.

## Ruhmeshalle
Fällt ein Raidboss zum ersten Mal in einer Gildengruppe (mindestens die Hälfte aus der Gilde), hält das Addon fest: Boss, Schwierigkeit, Raid, Datum und wer dabei war. Die Einträge werden an die ganze Gilde verteilt und beim Einloggen abgeglichen. Zu sehen unter **Raid » Ruhmeshalle** oder mit `/ea ruhm`.

## Kind wach, gleich zurück
Solange du in einer Gruppe bist, steht der **Elternknopf** auf dem Bildschirm (verschiebbar):
- Kleiner Knopf „Kind wach“: **Linksklick 5 Minuten, Rechtsklick 10 Minuten**. Während du weg bist, zeigt er die Restzeit – Linksklick „wieder da“, Rechtsklick 5 Minuten mehr. Die Gruppe sieht, dass du kurz weg bist, mit Timer – am Elternknopf und im Raid-Reiter. Für Spieler ohne Addon geht zusätzlich eine Zeile in den Gruppenchat.
- „+5“ verlängert, „Wieder da“ beendet. Nach Ablauf zeigt der Timer „überfällig“.
- Wer später in die Gruppe kommt, sieht deinen Status trotzdem.
- Eigene Taste: Tastaturbelegung → Elternabend → „Kind wach (5 Min) / Wieder da“.
- Während Bosskämpfen sperrt das Spiel Chat- und Addon-Nachrichten. Ein Klick wird dann gemerkt und nach dem Kampf verschickt.

## Loot-Wunschlisten (Prio)
Neben Soft-Reserve kann ein Raid auch nach **Wunschliste** verteilt werden (Vorbild „That's My BiS“): Auf der Webseite (`wunschliste.php`) sortiert jeder pro Raid seine Wunsch-Items, die Gildenleitung legt pro Item die Reihenfolge fest. Steht in `raids.php` bei der Raid-Vorlage `'loot' => 'wunschliste'`, bringt der Raid-Text die Zeilen `wunsch` und `prio` mit. Im Spiel:
- **Tooltip** jedes Items: „Prio (Wunschliste): 1. Beta Lux #1, 2. Mira Mondschein #3 …“ – grün, wer gerade in der Gruppe ist (Einstellung „Soft-Reserves im Tooltip“).
- **Reiter Beute:** in der Spalte „Soft-Reserve / Prio“ steht, wer dran ist („Prio: Beta Lux · danach Mira Mondschein“); **„An Prio“** vergibt das Item direkt. Wer etwas bekommen hat, fällt aus der Prio, der Nächste rückt nach.
- **„An Gruppe senden“** schickt Soft-Reserves und Wunschliste zusammen an alle in der Gruppe; jeder bekommt gesagt, wo er als Nächstes dran ist.
- Erhaltene Items stehen wie immer im Raid-Bericht – beim Einfügen im Raidplaner hakt die Webseite sie auf den Wunschlisten ab.

## Raid für alle in der Gruppe
Lädt die Raidleitung den Raid (über die Abgleich-App oder den Raid-Text), geht er automatisch an alle in der Gruppe, die in der Gilde sind: Anmeldungen, Raidgruppen, Soft-Reserves und – je nach Raid – Wunschliste oder DKP. Wer später dazukommt, bekommt ihn beim Beitreten. Gäste bekommen nur die Soft-Reserves. Von Hand geht es mit „An Gruppe senden“.

## DKP (Bieterrunde)
Als dritte Möglichkeit kann ein Raid nach **DKP** verteilt werden. Steht in `raids.php` bei der Raid-Vorlage `'loot' => 'dkp'`, bringt der Raid-Text das Mindestgebot (`dkpregel`) und alle Punktestände (`dkp`) mit; Konten, Regeln und Verfall pflegt die Gildenleitung auf `dkp.php` – dort sieht jeder alle Kontostände, jede Buchung und wann der nächste Verfall kommt. Im Spiel:
- **Statt einer Würfelrunde** startet der Plündermeister im Reiter Beute mit „Bieten“ eine verdeckte **Bieterrunde**. Alle mit Addon bekommen ein Fenster mit Eingabefeld: Zahl eintippen, Enter – fertig (oder `/ea biete 30`). Wer kein Addon hat, flüstert dem Plündermeister „biete 30“.
- Nur der Plündermeister sieht die Gebote – so gibt es keine langen Bieterschlachten. Geprüft wird: im Raid, Mindestgebot erreicht, nicht mehr als die eigenen Punkte. Wer neu bietet, ersetzt sein altes Gebot.
- Das höchste Gebot gewinnt und zahlt sein Gebot. Im Raid-Bericht steht die Beute mit Art „DKP“ und Preis; beim Einfügen im Raidplaner bucht die Webseite Bosspunkte, Anwesenheit und die Preise.
- Die Raid-Übersicht zeigt in einem DKP-Raid statt der Soft-Reserves die Punkte jedes Spielers. `/ea dkp` listet die Punkte aller in der Gruppe. „An Gruppe senden“ verteilt die Punktestände mit.

## Plündermeister-Reiter
Der Reiter erscheint nur für Plündermeister, Leitung und Assistenten – oder für alle, solange gerade Beute ansteht oder gewürfelt wird. Mit `/ea loot` lässt er sich jederzeit öffnen (mit eingeschaltetem Würfelfenster: `/ea raid`).

## Würfelfenster (Bedarf und Gier)
Wer in Dungeons um Beute würfelt, sieht im Chat viele Zeilen durcheinander. Das **Würfelfenster** zeigt sie geordnet: je Gegenstand, wer **Bedarf**, **Gier** oder **Passen** gewählt hat, die Würfe (höchster zuerst), wer gewonnen hat (mit Stern markiert) und auf wen noch gewartet wird. Fährt man mit der Maus über den Gegenstand, erscheint sein Tooltip. Die letzten 40 Runden bleiben gespeichert, „Leeren“ räumt auf.

Standardmäßig ist es **aus**: einschalten unter **Einstellungen » Auf dem Bildschirm » Würfelfenster für Bedarf und Gier**. Danach öffnet und schließt es sich nur auf Wunsch – mit `/ea loot` (oder `/ea würfe`), einer eigenen Taste (siehe Tasten) oder Esc zum Schließen. Das Fenster lässt sich verschieben und am Griff unten rechts größer oder kleiner ziehen; Platz und Größe merkt es sich. Gelesen werden die Beute-Zeilen des Chats mit den Texten des Spiels, das klappt also in jeder Sprache. Ausprobieren ohne Gruppe: `/ea loot test` füllt das Fenster mit drei Beispiel-Gegenständen – gebaut aus den Texten des eigenen Spiels, also zugleich eine Probe, ob sie erkannt werden.

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


**Schlossknacken** (Idee von cbz64): Schurken erscheinen mit ihrer Stufe im Schlossknacken unter den Berufen – im Filter „Schlossknacken“ siehst du, wer dir eine Kassette öffnen kann. Das Addon liest die Stufe aus der Fertigkeitenliste.
## Gildenmarkt

Ein Auktionshaus nur für die Gilde (Reiter „Berufe“ » „Gildenmarkt“, `/ea markt`; Idee von Philipp Wobakoff). Alles zum Festpreis, ohne Gebühren:

- **Schaufenster** – bleibt dauerhaft stehen, Preis pro Stück (z. B. Tränke, Bufffood, Materialien). Den Vorrat zählt das Addon in deinen Taschen und deiner Bank und zeigt ihn an („12 da“, „ausverkauft“). Bist du 30 Tage nicht online, verschwindet es.
- **Einzelangebot** – ein Gegenstand oder Stapel mit Laufzeit 6, 12, 24 oder 48 Stunden (z. B. Ausrüstung). Der erste Kaufwunsch reserviert es.

**Einstellen:** „Angebot einstellen“, den Gegenstand aus der Tasche in das Feld ziehen, Art, Laufzeit, Menge und Preis wählen. Bei mehr als einem Stück gilt der Preis pro Stück. Das Angebot gehört dem Charakter, der die Ware hat.

**Mengenrabatt:** Bis zu zwei Staffeln, z. B. „ab 10 Stück: 45s, ab 20 Stück: 40s“. Der Käufer sieht beim Eingeben der Menge gleich Stückpreis und Summe, die Nachnahme rechnet mit dem Rabatt.

**Teilkauf:** Ein Einzelangebot mit mehreren Stück (z. B. 20 Leder) darf man auch teilweise kaufen, der Rest bleibt im Angebot. Wer nur komplett verkaufen will, setzt den Haken „nur komplett“.

**Kaufen:** Angebot anklicken, „Kaufen“ (beim Schaufenster mit Stückzahl). Der Kaufwunsch erreicht den Verkäufer auch, wenn er gerade offline ist – Angebote und Kaufwünsche wandern wie die Zettel der Pinnwand von Addon zu Addon. Der Verkäufer bekommt einen Hinweis und eine grüne Plakette.

**Übergabe:** Ein Addon kann keine Ware und kein Gold bewegen. Der Verkäufer öffnet einen Briefkasten und klickt beim Kaufwunsch auf „Brief vorbereiten“: Empfänger, Betreff und Nachnahme werden ausgefüllt und die Ware angelegt – nur noch abschicken. Der Käufer zahlt beim Öffnen des Briefs. Beim Abschicken steht der Kauf auf „verschickt“, der Käufer bekommt Bescheid. Wer lieber per Handelsfenster übergibt, klickt „Erledigt“. „Ablehnen“ gibt die Ware wieder frei.

## Pinnwand
Das schwarze Brett der Gilde (`/ea pinnwand`). Jedes Mitglied heftet Zettel an – als **Info**, **Aktion** (mit Termin), **Suche**, **Biete**, **Hilfe gesucht** oder **Danke** – und wählt, an wen er geht: alle, Offiziere, einen Rang, eine Klasse oder eine einzelne Person. Ein Zettel hat eine Überschrift (bis 80 Zeichen) und eine mehrzeilige Beschreibung (bis 2000 Zeichen); Antworten dürfen bis 400 Zeichen lang sein. Zettel hängen 1 Tag bis 2 Wochen (Aktionen bis kurz nach dem Termin) und verschwinden dann von selbst.

**Karteikarten oder Liste:** Oben neben „Neuer Zettel“ schaltest du die Ansicht um. Als **Karteikarten** (Standard) hängen die Zettel zu dritt nebeneinander – mit farbigem Schildchen für die Art, Überschrift, den ersten Zeilen Text, Absender und Empfänger, Termin oder Restlaufzeit und dem Rückmelde-Knopf („Bin dabei“, „Kann helfen“ …) samt Zähler; der Knopf wird golden, sobald du dich gemeldet hast. Die **Liste** zeigt dieselben Zettel kompakt in Zeilen. Ein Klick auf Karte oder Zeile öffnet den Zettel rechts, Rechtsklick flüstert den Absender an. Die Wahl bleibt gespeichert.

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
- **Klassisch** – dunkles Leder und Blizzard-Gelb, dazu die roten Knöpfe, Häkchen und Schieberegler des Spiels

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
- **Rang ändern** (nur wer im Spiel befördern bzw. zurückstufen darf): Im Rechtsklick-Menü stehen „Befördern: …“ und „Zurückstufen: …“ für jeden Rang, den du vergeben darfst. Blizzard erlaubt Addons weder das Befördern noch das Setzen eines Zielrangs – der Menüpunkt löst deshalb `/gpromote` bzw. `/gdemote` aus, als hättest du es selbst eingetippt, und das geht nur eine Stufe je Klick. Liegt der gewählte Rang weiter weg (etwa vom Initianden gleich zum Mitglied), erscheint unter dem Mauszeiger ein kleines Fenster mit dem Knopf **Weiter**: ein Klick je weiterer Stufe, bis das Ziel erreicht ist. Mehr Klicks, als Stufen fehlen, lässt es nicht zu. Nach jedem Wechsel fragt das Addon die Gildenliste nach, bis der neue Rang angekommen ist. Im Kampf ist der Menüpunkt ausgeblendet.

### Stufenbereich
Neben „Alle Spieler“ steht im Reiter **Gilde** der Knopf **„Alle Stufen“**: Er filtert die Liste nach Stufenbereich (1–10, 11–20 … 51–60) – wie in der Klassenliste auf der Webseite. In Klammern steht, wie viele Charaktere der Gilde gerade in dem Bereich sind. Gezeigt werden die Spieler, die dort einen Charakter haben; von ihren Twinks nur die passenden, die Stufe ist hervorgehoben. Zusammen mit „Nur online“ sieht man, wer gerade da ist und einen Charakter zum gemeinsamen Leveln hätte.

## Gildenwappen
Das Wappen erscheint im Addon-Menü, oben links im Fenster und am Minimap-Button. Es liegt als `Media/Wappen.tga` im Addon. Ein neues Wappen: Bild als `Grafik/wappen.webp` ablegen und `python3 Grafik/wappen.py` ausführen.

## Leitung: Gildenchronik
Den Reiter **Leitung** (`/ea leitung`) sehen nur Offiziere und Gildenleitung. Er hält fest, was sich in der Gilde tut:

- **Chronik** mit Filter: Eintritte (mit wem eingeladen hat), Austritte (ausgetreten oder entfernt – und von wem), Rangänderungen, Charaktere mit Stufe 60 und **„Wieder da“** – Spieler, die nach langer Pause wieder online sind. Dann gibt es auch eine Meldung im Chat. Ein Klick auf einen Eintrag öffnet das Flüsterfenster – z. B. um nach einem Austritt nachzufragen (klappt, solange er oder sie online ist).
- **Die Gilde in Zahlen:** Spieler, Charaktere, gerade online, Stufe 60, Ein- und Austritte der letzten 30 Tage, Klassenverteilung.
- **Jubiläen:** Aus den Eintritten in der Chronik meldet das Addon, wer seit einem Monat, 100 Tagen, einem halben Jahr oder einem (weiteren) Jahr dabei ist – einmal im Chat und als Eintrag in der Chronik. Ein Rechtsklick auf ein Jubiläum oder auf „Stufe 60“ schlägt einen Glückwunsch für den Gildenchat vor; abschicken muss man ihn selbst.
- **Lange nicht online:** Spieler, die mit keinem ihrer Charaktere in der eingestellten Zeit da waren (Knopf oben rechts: 1, 2, 3, 6 oder 12 Monate; Standard 3 Monate). Dieselbe Schwelle gilt für „Wieder da“.
- **Klassenliste für die Webseite:** Der Knopf „Für die Webseite“ (oder `/ea klassenliste`) erstellt einen Text mit allen Mitgliedern – Name, Klasse, Stufe, Rang und wer wessen Twink ist. Kopieren und auf gilde-elternabend.de unter **Gilde » Klassenliste** bei „Für die Gildenleitung“ einfügen. Wann jemand zuletzt online war und die Notizen werden nicht übertragen.

Die Chronik entsteht aus dem Vergleich der Gildenliste mit dem zuletzt gemerkten Stand und aus Blizzards Gildenprotokoll (die letzten 100 Einträge – damit ist sie beim ersten Öffnen schon gefüllt). Sie liegt auf dem eigenen Rechner; jeder Offizier führt seine eigene. Was passiert, während kein Offizier online ist, wird beim nächsten Einloggen bemerkt und – soweit Blizzards Protokoll es noch kennt – mit der richtigen Zeit nachgetragen.

## Spielzeiten
Der Reiter **Gilde** hat zwei Unterreiter: **Mitglieder** (die Gildenliste) und **Spielzeiten** (auch über „Meine Spielzeiten“ bei „Meine Charaktere“ oder `/ea spielzeiten`). Dort klickst du in einem großen Raster an, wann du meist spielst – Wochentage × Vormittag, Nachmittag, Abend, Spät –, dazu eine kurze Notiz wie „meist ab 20:30“, und speicherst. Angekreuzte Felder sind golden. Die Zahl in jedem Feld zeigt, wie viele aus der Gilde dann meist spielen; Drüberfahren nennt die Namen (mit „online“). Rechts stehen unter „Spielen zu ähnlichen Zeiten“ alle mit Überschneidung, die meisten gemeinsamen Zeiten zuerst („Beta Lux · 9 gemeinsame Zeiten · online“). Fährst du über einen Namen, sind links dessen Zeiten umrandet; ein Klick flüstert ihn an. Die Addons reichen die Angaben in der Gilde weiter, im Tooltip der Gildenliste steht „Spielt meist: abends Di, Do · spät Sa“ und, was ihr gemeinsam habt („Wie du: …“).

## Erste Schritte
## Raidwünsche
Unter **Gilde » Raidwünsche** sagt jeder, ob er raiden will („Ja, gern“, „Ab und zu“, „Eher nicht“), in welcher Rolle (Tank, Heiler, DD – mehrere möglich) und an welchen Tagen ab welcher Uhrzeit: 9:00, 10:00, 11:30, 14:00, 17:00, 19:00, 20:00 oder 21:00 Uhr (ein Raid dauert etwa zwei Stunden). Wer eine Zeit ankreuzt, ohne „Ja, gern“ gewählt zu haben, bekommt es automatisch. Die Zahl in jedem Feld zeigt, wie viele dann mitraiden würden; Drüberfahren nennt die Namen mit Rolle. Rechts steht die Auswertung für alle: wie viele raiden wollen, welche Rollen zusammenkommen und die beliebtesten Termine („Sa ab 10:00 · 9 würden mitraiden (1 Tank, 2 Heiler, 6 DD)“). Die Gildenleitung kann sie mit „Auswertung kopieren“ z. B. in den Discord stellen. Im Tooltip der Gildenliste steht der Raidwunsch ebenfalls. Die Startzeiten stehen in `Profile.RAID_TIMES` und lassen sich dort ändern.

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

## Abstimmung
Unter **Raid » Abstimmung** stellt die Leitung der Gruppe (im Schlachtzug Leiter oder Assistent) eine Frage – frei oder per Schnellwahl („Noch ein Boss?“, „Kurze Pause?“, „Nächste Woche weiter?“). Auf Wunsch steht die Frage auch im Raidchat. Bei allen mit Addon geht ein kleines Fenster mit drei Knöpfen auf: **Dafür**, **Dagegen**, **Passt beides** (abschaltbar in den Einstellungen, dann nur im Reiter). Umentscheiden geht bis zum Ende. Im Reiter sehen alle, wer wie gestimmt hat (Namen in Klassenfarbe) und wer noch fehlt. Haben alle abgestimmt, gibt das Addon der Leitung Bescheid; **„Ergebnis posten“** schreibt es in den Raidchat, z. B. „Ergebnis der Abstimmung „Noch ein Boss?“: 29 dafür, 1 dagegen, 10 passt beides“. Nach zehn Minuten endet eine Abstimmung von selbst.

## Quiz
Für Zeltlager, Lagerfeuer und Wartezeiten: Im Reiter **Raid » Übersicht** öffnet „Quiz“ (oder `/ea quiz`) das Quizfenster. Die Leitung der Gruppe (Raidleitung und Assistenten, in der Fünfergruppe der Anführer) startet die Runde für alle: Das Addon zieht zehn Fragen zufällig aus hundert, bei allen mit Addon geht das Fenster auf, und jeder beantwortet dieselben Fragen – vier Antworten zur Auswahl, 20 Sekunden je Frage. Die Uhr läuft erst nach dem Klick auf „Los geht's“.

Am Ende meldet jedes Addon sein Ergebnis; alle sehen die Rangliste (mehr Richtige zuerst, bei Gleichstand die schnellere Zeit), und die Leitung sagt mit einem Klick die ersten drei im Gruppenchat an. Fragen, die schon dran waren, kommen erst wieder, wenn alle hundert gestellt wurden. Ohne Gruppe ist das Quiz eine Proberunde für einen allein.

Die Fragen stehen in `QuizFragen.lua` (Frage, richtige Antwort, drei falsche). Neue Fragen hinten anhängen und `rev` erhöhen – alle in der Gruppe brauchen denselben Stand.

### Suchen aus Discord und Webseite
Offene Gruppensuchen aus dem Discord und dem Dungeonfinder der Webseite stehen im Reiter **Gruppen** unter den Gesuchen der Gilde – etwas blasser, rechts mit Startzeit und Quelle („heute 20:00 · Discord“ bzw. „· Webseite“). Melden kann man sich dort nur im Discord oder auf der Webseite; ein Klick auf die Zeile nennt den Weg. Weil ein Addon nicht ins Internet kann, holt die Mac-App (ab 1.1) die Suchen beim Abgleich und schreibt sie in `Abgleich.lua`. Das Addon dieses Rechners gibt sie nach dem Einloggen oder `/reload` über den Addon-Kanal an alle anderen weiter (und an jeden, der später einloggt). Es ist ein Schnappschuss: Im Tooltip steht, von wann. Suchen verschwinden 30 Minuten nach dem Start oder wenn der Schnappschuss älter als 6 Stunden ist. Ohne App und ohne jemanden online, der sie hat, bleibt der Reiter wie bisher.

## Abgleich mit der Webseite über die Mac-App
Ein Addon kann nicht ins Internet – deshalb läuft der Austausch mit gilde-elternabend.de sonst über Kopieren und Einfügen. Die kleine Mac-App **Elternabend Abgleich** (Ordner `Mac-App`, für die Gildenleitung) nimmt das ab:

- **Spiel → Webseite:** Beim Ausloggen und bei `/reload` legt das Addon Klassenliste, Pinnwand, Berufe und den Raid-Bericht (sobald das Raid-Protokoll beendet ist) in die gespeicherte Variable `ElternabendSync`. Die App lädt hoch, was sich geändert hat.
- **Webseite → Spiel:** Die App schreibt den nächsten Raid (Anmeldungen, Raidgruppen, Soft-Reserves, Termine) und die offenen Gruppensuchen aus Discord und Dungeonfinder in die Datei `Abgleich.lua` im Addon-Ordner. Das Addon übernimmt ihn beim Einloggen oder nach `/reload` – aber nicht von selbst, solange ein Raid läuft. `/ea abgleich` zeigt den Stand und holt die Daten von Hand.

Ohne die App passiert nichts davon: `Abgleich.lua` bleibt leer, und es wird nichts zusätzlich gespeichert. Hochgeladen wird nur mit einem Charakter der Gildenleitung.

## Tasten
Unter **Optionen » Tastaturbelegung » Elternabend** (eigener Abschnitt, unten in der Liste) lassen sich Tasten vergeben: „Fenster öffnen / schließen“ und je eine für die Reiter Gilde, Gruppen, Raid, Kalender und Pinnwand. Ein zweiter Druck auf dieselbe Taste schließt das Fenster wieder. Dazu kommen die Tasten „Kind wach / Wieder da“, „Nächste Gildenanfrage einladen“ und „Würfelfenster öffnen / schließen“ (wirkt nur, wenn das Würfelfenster eingeschaltet ist).

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
| `/ea loot` | Würfelfenster für Bedarf und Gier auf/zu (wenn eingeschaltet; sonst Reiter Plündermeister) |
| `/ea loot test` | Würfelfenster mit Beispielen ausprobieren, auch ohne Gruppe |
| `/ea roll [Itemlink]` | Item aus den Taschen auswürfeln (Vergabe wird „per Handel“ notiert) |
| `/ea biete 30` | In einer DKP-Bieterrunde bieten (verdeckt, das letzte Gebot zählt) |
| `/ea größe 80` | Fenstergröße in Prozent (60–120); geht auch mit Strg + Mausrad über dem Fensterkopf oder unter „Einstellungen“ |
| `/ea dkp` | DKP aller in der Gruppe anzeigen |
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
