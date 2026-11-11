# Elternabend Abgleich (Mac-App)

Kleine Menüleisten-App für die Gildenleitung. Sie gleicht das Addon **Elternabend** mit gilde-elternabend.de ab – ohne Kopieren und Einfügen.

| Richtung | Was | Wann |
|---|---|---|
| Spiel → Webseite | Klassenliste, Pinnwand, Berufe, Raid-Bericht | sobald das Spiel speichert (`/reload`, Ausloggen, Beenden) |
| Webseite → Spiel | nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves, Terminen | alle 10 Minuten und nach jedem Speichern; im Spiel aktiv nach `/reload` oder Einloggen |

## Einrichten
1. ZIP entpacken und **Elternabend Abgleich** in den Ordner „Programme“ ziehen.
2. Öffnen. Die App ist nicht bei Apple angemeldet; beim ersten Mal deshalb unter *Systemeinstellungen → Datenschutz & Sicherheit* auf **„Dennoch öffnen“** klicken.
3. Das Offizierspasswort eingeben. Es liegt danach im Schlüsselbund des Macs und geht nur an gilde-elternabend.de.
4. Oben in der Menüleiste erscheint der Mond. Im Menü steht, was zuletzt abgeglichen wurde. Findet die App WoW nicht von selbst, dort den Ordner „World of Warcraft“ wählen.
5. Im Spiel einmal `/reload` (das Addon bemerkt die App), danach ein zweites `/reload` oder ausloggen – ab dann läuft es von allein.

## Wie es funktioniert
- Das Addon schreibt beim Speichern die Tabelle `ElternabendSync` in `WTF/Account/<Konto>/SavedVariables/Elternabend.lua`. Die App liest sie und schickt die Texte an dieselben Import-Formulare, die es auf der Webseite gibt (`klassenliste.php`, `berufe.php`, `pinnwand.php`) bzw. an `abgleich.php` (Raid-Bericht).
- Hochgeladen wird nur, was sich geändert hat.
- Den Raid holt die App von `abgleich.php` und schreibt ihn als `Abgleich.lua` in den Addon-Ordner. Nach einem Addon-Update ist die Datei wieder leer; die App schreibt sie beim nächsten Durchgang neu.
- Stimmt das Passwort nicht, hört die App sofort auf und fragt nicht weiter – so greift die Sperre der Webseite nicht.

## Bauen
`./bauen.sh` auf einem Mac mit Xcode – oder automatisch über GitHub Actions („Mac-App bauen“). `swift test` prüft das Lesen der gespeicherten Variablen.
