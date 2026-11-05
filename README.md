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

## Bedienung
`/ea` oder ein Klick auf das Wappen an der Minimap öffnet das Fenster (Rechtsklick: direkt die Gilde).

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
#ENDE
```

| Zeile | Felder |
|---|---|
| `raid` | Raid-ID, Titel, Vorlage (`barrow`, `hyjal`, `onyxia`), Datum und Uhrzeit |
| `spieler` | Charaktername, Klasse (deutsch oder englisch), Rolle (`tank`, `heal`, `dd`), Status (`dabei`, `ersatz`, `vielleicht`, `abgemeldet`) |
| `sr` | Charaktername, Item-ID, Itemname, Boss (optional) |

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
Wer das Addon hat, aber noch nicht in der Gilde ist, sieht im Start-Reiter den Knopf **„Der Gilde beitreten“**. Die Anfrage geht an alle, die gerade online sind, das Addon haben und einladen dürfen; bei ihnen erscheint das Gildenanfrage-Fenster. Wer zuerst „Einladen“ klickt, lädt ein – bei den anderen verschwindet die Anfrage. Der Anfragende sieht, bei wie vielen Einladenden sie angekommen ist, oder dass gerade niemand online ist.
Technisch läuft das über einen versteckten, passwortgeschützten Chat-Kanal („ElternabendTreff“), dem das Addon im Hintergrund beitritt; im Chat ist er nicht zu sehen.

## Gildeneinladung per Flüstern
Wer dich mit `ginv` anflüstert (Stichwörter im Reiter **Invite** einstellbar, den nur sieht, wer in die Gilde einladen darf), landet in der Anfrageliste, und es erscheint ein kleines Fenster mit dem fertigen Befehl `/ginvite Anna Sturmwind` zum Kopieren: ins Feld klicken, **Cmd+C** (Windows: Strg+C), dann im Chat **Enter, Cmd+V, Enter**.
- **Den Befehl musst du selbst abschicken.** WoW Forever behält Gildeneinladungen der Blizzard-Oberfläche vor: Weder Addons noch Makros dürfen einladen, und ein Addon darf auch nichts in die Eingabezeile schreiben – sonst blockiert WoW sogar den selbst abgeschickten Befehl („Funktion, die der Blizzard-UI vorbehalten ist“). Das haben wir ausgiebig getestet.
- Sobald WoW „Ihr habt … eingeladen“ meldet, verschwindet die Anfrage, und die Person bekommt eine Antwort per Flüstern. Wer beitritt, wird nach etwa 10 Sekunden im Gildenchat begrüßt (beides abschaltbar).
- „Einladen“ im Reiter **Invite** und die Taste „Nächste Gildenanfrage einladen“ (Tastaturbelegungen → AddOns → Elternabend) öffnen das Fenster mit dem Befehl gleich markiert.
- Man braucht einen Gildenrang, der einladen darf. Das Addon „InviteOnWhisper“ sollte nicht gleichzeitig auf `ginv` reagieren, sonst kommen doppelte Fenster.

## Start: Begrüßung und Gildeninfos
Der Reiter **Start** ist der erste beim Öffnen. Er zeigt:
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
Im Reiter **Gruppen** einträgst du, wofür du Mitspieler suchst und wie viele Tanks, Heiler und DDs (Klick: mehr, Rechtsklick: weniger). Die Gilde sieht das Gesuch sofort (auch im Chat, abschaltbar mit `/ea gruppenhinweis`). Andere wählen es aus und melden sich als Tank, Heiler oder DD; du siehst die Meldungen und lädst mit einem Klick ein. Gesuche verschwinden nach 90 Minuten, beim Ausloggen oder mit **Beenden**.

Mit dem Häkchen **„Auch im Gildenchat posten“** (standardmäßig an) schreibt das Addon beim Start einmal eine Zeile in den Gildenchat, z. B. „Suche Gruppe für DM: 1 Tank, 2 DD – gemütlich. Mit Addon über /ea gruppen melden, sonst anflüstern!“ So sehen auch Mitglieder ohne Addon das Gesuch und melden sich per Flüstern. Addon-Nutzer bekommen dann keine zweite Meldung.

## Ruhmeshalle
Fällt ein Raidboss zum ersten Mal in einer Gildengruppe (mindestens die Hälfte aus der Gilde), hält das Addon fest: Boss, Schwierigkeit, Raid, Datum und wer dabei war. Die Einträge werden an die ganze Gilde verteilt und beim Einloggen abgeglichen. Zu sehen unter **Raid » Ruhmeshalle** oder mit `/ea ruhm`.

## Kind wach, gleich zurück
Solange du in einer Gruppe bist, steht der **Elternknopf** auf dem Bildschirm (verschiebbar):
- „Kind wach · 5 Min“, „10“ oder „15“: Die Gruppe sieht, dass du kurz weg bist, mit Timer – am Elternknopf und im Raid-Reiter. Für Spieler ohne Addon geht zusätzlich eine Zeile in den Gruppenchat.
- „+5“ verlängert, „Wieder da“ beendet. Nach Ablauf zeigt der Timer „überfällig“.
- Wer später in die Gruppe kommt, sieht deinen Status trotzdem.
- Eigene Taste: Tastaturbelegungen → AddOns → Elternabend → „Kind wach (5 Min) / Wieder da“.
- Während Bosskämpfen sperrt das Spiel Chat- und Addon-Nachrichten. Ein Klick wird dann gemerkt und nach dem Kampf verschickt.

## Plündermeister-Reiter
Der Reiter erscheint nur für Plündermeister, Leitung und Assistenten – oder für alle, solange gerade Beute ansteht oder gewürfelt wird. Mit `/ea loot` lässt er sich jederzeit öffnen.

## Berufe
Im Reiter **Berufe** siehst du, wer in der Gilde welche Berufe hat – und suchst gezielt: „Heiltrank“ eintippen zeigt alle, die ihn herstellen können, und wer davon online ist. Ein Klick auf einen Charakter zeigt alle seine Rezepte, ein Rechtsklick öffnet ein Flüsterfenster.
- Deine Rezepte liest das Addon aus, sobald du **einmal dein Berufsfenster öffnest**, und teilt sie über den Gildenkanal. Jedes Addon speichert, was es empfängt – auch Rezepte von Mitgliedern, die gerade offline sind.
- Sammelberufe (Angeln, Kräuterkunde, Bergbau, Kürschnerei) werden nicht angezeigt.
- „Berufe der Gilde neu anfragen“ bittet alle, die gerade online sind, ihre Berufe zu schicken.
- Zu sehen sind nur Mitglieder mit Addon.

### Aufträge
Klick auf ein Rezept (in der Suche oder in der Rezeptliste eines Charakters) schickt dem Hersteller einen Auftrag mit kurzer Notiz. Ist der Charakter nicht online, geht der Auftrag an einen anderen Charakter desselben Spielers – oder wartet, bis einer online kommt. Der Hersteller sieht seine Aufträge in der Karte „Aufträge“, nimmt sie an, lehnt ab oder meldet „fertig“. Erledigte Aufträge verschwinden nach 14 Tagen.

## Notizen
Im Reiter **Notizen** lassen sich beliebig viele Notizen anlegen. Jede kann als kleines Fenster auf den Bildschirm geheftet werden und bleibt dort, auch wenn das Addon-Fenster zu ist – auch nach dem Neu-Einloggen.
- Verschieben mit der Maus, Größe über die Ecke unten rechts.
- Hintergrund von 100 % (deckend) bis 0 % (ganz durchsichtig); bei wenig Hintergrund bekommt die Schrift einen Rand, damit sie lesbar bleibt.
- „Fixiert“: Die Notiz lässt Mausklicks durch und zeigt keine Knöpfe – praktisch für den Kampf.
- Schriftgröße mit A- und A+.

## Gilde: Mitglieder, Mains und Twinks
Vereinbarung: **Die Offiziersnotiz enthält nur den Namen des Mains.** Leer = Main, „Anna Sturmwind“ = Twink von Anna Sturmwind. Die Notiz liegt auf dem Blizzard-Server; alle Offiziere sehen sie auch ohne Addon im Gildenfenster.

Der Reiter **Gilde** zeigt allen Gildenmitgliedern, wer welche Twinks hat. Offiziere (Ränge, die Offiziersnotizen lesen dürfen) sehen zusätzlich:
- jeden Spieler mit seinen Twinks darunter, Rang, Stufe, Klasse und ob er online ist – auch „online als …“, wenn er gerade einen Twink spielt,
- Unstimmigkeiten: Rang „Twink“ ohne Main, Main nicht (mehr) in der Gilde, Twink ohne Rang „Twink“,
- **Charaktere eines Spielers**: Ein Klick auf einen Spieler zeigt rechts unten seinen Main und alle Twinks (nochmal klicken: zurück zu den eigenen Charakteren).
- **Kopieren**: Jede Zeile hat einen Knopf „Kopieren“. Er legt den Namen markiert ins Kopierfeld rechts oben – Strg+C, dann im Blizzard-Gildenmenü beim Twink in die Offiziersnotiz einfügen und den Rang „Twink“ setzen. Selbst schreiben kann das Addon nichts: Offiziersnotizen, Ränge und die Zwischenablage sind im aktuellen Client für Addons gesperrt.
- **Vorschläge aus dem Addon**: Spieler legen mit „Diesen Charakter als Main festlegen“ (oder `/ea main`) ihren Main fest. Das Addon kennt alle ihre Charaktere auf dem Account und meldet sie den Offizieren als „Twink » Main“. „Kopieren“ legt den Main-Namen bereit; sobald die Notiz im Gildenmenü stimmt, verschwindet der Vorschlag. Nur der Spieler selbst kann für seine Charaktere melden.

**Alle Gildenmitglieder** sehen die Übersicht ebenfalls. Offiziersnotizen kann das Spiel nur Offizieren zeigen; deshalb verteilt das Addon der Gildenleitung und der Offiziere die Zuordnung über den Gildenkanal (bei Änderungen sofort, sonst höchstens alle 15 Minuten, und auf Nachfrage beim Einloggen). Die anderen speichern den letzten Stand und sehen oben, von wann er ist. Angenommen wird eine Zuordnung nur von den obersten drei Gildenrängen (Rang 1 bis 3). Zuordnen, Vorschläge und Hinweise auf Unstimmigkeiten gibt es nur für Offiziere. Twinks auf einem anderen Battle.net-Account erkennt das Addon nicht; die tragen Offiziere von Hand ein.

## Gildenwappen
Das Wappen erscheint im Addon-Menü, oben links im Fenster und am Minimap-Button. Es liegt als `Media/Wappen.tga` im Addon. Ein neues Wappen: Bild als `Grafik/wappen.webp` ablegen und `python3 Grafik/wappen.py` ausführen.

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
