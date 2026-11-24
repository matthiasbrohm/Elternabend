# Elternabend Abgleich (Windows)

Gegenstück zur Mac-App: eine kleine App für den Infobereich von Windows (unten rechts neben der Uhr). Sie gleicht das Addon **Elternabend** mit gilde-elternabend.de ab – ohne Kopieren und Einfügen. Gleicher Ablauf und gleiche Webseiten-Schnittstelle wie die Mac-App (siehe `Mac-App/LIESMICH.md`).

| Richtung | Was | Wann |
|---|---|---|
| Spiel → Webseite | Klassenliste, Pinnwand, Berufe, Raid-Bericht | sobald das Spiel speichert (`/reload`, Ausloggen, Beenden) |
| Webseite → Spiel | nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves, Terminen; offene Gruppensuchen | alle 10 Minuten und nach jedem Speichern; im Spiel aktiv nach `/reload` oder Einloggen |

## Einrichten
1. ZIP entpacken und `ElternabendAbgleich.exe` an einen festen Platz legen, z. B. in einen Ordner `C:\Programme\Elternabend` oder in „Dokumente“.
2. Doppelklick. Die App ist nicht von Microsoft signiert; beim ersten Mal zeigt Windows deshalb „Der Computer wurde durch Windows geschützt“ – auf **„Weitere Informationen“** und dann **„Trotzdem ausführen“** klicken.
3. Das Offizierspasswort eingeben. Es liegt danach verschlüsselt im Windows-Konto (nur dieses Konto auf diesem PC kann es lesen) und geht nur an gilde-elternabend.de.
4. Unten rechts neben der Uhr erscheint der Mond (eventuell unter dem kleinen Pfeil ^). Klick darauf zeigt, was zuletzt abgeglichen wurde. Findet die App WoW nicht von selbst, dort den Ordner „World of Warcraft“ wählen.
5. Im Spiel einmal `/reload` (das Addon bemerkt die App), danach ein zweites `/reload` oder ausloggen – ab dann läuft es von allein.

Die App startet ab dem ersten Mal automatisch mit Windows (im Menü abschaltbar: „Mit Windows starten“).

Mond-Symbol: golden = alles in Ordnung, blauer Punkt = Abgleich läuft, roter Punkt = Problem (Klick zeigt, was los ist).

## Bauen
Über GitHub Actions („Windows-App bauen“, `windows-latest`): `dotnet run --project Windows-App/Tests` prüft das Lesen der gespeicherten Variablen, danach entsteht `ElternabendAbgleich.exe` (.NET Framework 4.8 – ist auf Windows 10 und 11 schon dabei, nichts extra zu installieren).
