// Tests für Elternabend Abgleich (Windows) – dieselben Fälle wie Mac-App/Tests/AbgleichTests.swift.
using System;
using System.Text;
using ElternabendAbgleich;

static class Tests
{
    static int fehler;

    static void Gleich(string erwartet, string ist, string was)
    {
        if (erwartet == ist) return;
        fehler++;
        Console.WriteLine("FEHLER " + was + ": erwartet «" + erwartet + "», bekommen «" + ist + "»");
    }

    static void Wahr(bool b, string was)
    {
        if (b) return;
        fehler++;
        Console.WriteLine("FEHLER " + was);
    }

    // So schreibt WoW die gespeicherten Variablen (Auszug)
    const string Gespeichert = "\n" +
        "ElternabendDB = {\n" +
        "[\"notiz\"] = \"ElternabendSync = { nur ein Text }\",\n" +
        "[\"plan\"] = {\n" +
        "[\"id\"] = \"x\",\n" +
        "},\n" +
        "}\n" +
        "ElternabendSync = {\n" +
        "[\"mitglieder\"] = \"#ELTERNABEND-MITGLIEDER 1\\ngilde;Elternabend;1;Beta Lux\\nm;Beta \\\"Lux\\\";PRIEST;Priester;60;Offizier;2;\\n#ENDE\",\n" +
        "[\"berufe\"] = \"EAB2^7^Beta^1^C~Beta~Schneider~300~300~1~1,2\",\n" +
        "[\"v\"] = 1,\n" +
        "[\"pinnwand\"] = \"EAPW1^5^Beta\\nN^ab^Beta^1^2^info^0^0^offen^Titel mit \\\\ und ä^Text^0\",\n" +
        "[\"zeit\"] = 1794424346,\n" +
        "[\"addon\"] = \"4.10.0\",\n" +
        "[\"bericht\"] = \"#ELTERNABEND-BERICHT 1\\nraid;abcdef12;X;1;2;Beta\",\n" +
        "}\n";

    static int Main()
    {
        // Tabelle lesen
        var t = LuaSaved.Table("ElternabendSync", Encoding.UTF8.GetBytes(Gespeichert));
        Wahr(t != null, "Tabelle nicht gefunden");
        if (t != null)
        {
            Gleich("7", t.Count.ToString(), "Anzahl");
            Gleich("1794424346", t["zeit"], "zeit");
            Gleich("1", t["v"], "v");
            Gleich("#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;1;Beta Lux\nm;Beta \"Lux\";PRIEST;Priester;60;Offizier;2;\n#ENDE", t["mitglieder"], "mitglieder");
            Gleich("EAPW1^5^Beta\nN^ab^Beta^1^2^info^0^0^offen^Titel mit \\ und ä^Text^0", t["pinnwand"], "pinnwand");
            Gleich("#ELTERNABEND-BERICHT 1\nraid;abcdef12;X;1;2;Beta", t["bericht"], "bericht");
        }

        // Tabelle fehlt oder ist abgeschnitten
        Wahr(LuaSaved.Table("ElternabendSync", Encoding.UTF8.GetBytes("ElternabendDB = {\n[\"a\"] = 1,\n}\n")) == null, "fehlende Tabelle gefunden");
        Wahr(LuaSaved.Table("ElternabendSync", Encoding.UTF8.GetBytes("ElternabendSync = {\n[\"a\"] = \"abgeschnitten")) == null, "abgeschnittene Tabelle gelesen");
        Gleich("0", LuaSaved.Table("ElternabendSync", Encoding.UTF8.GetBytes("ElternabendSync = {\n}\n"))?.Count.ToString(), "leere Tabelle");

        // Hin und zurück
        foreach (string s in new[] { "", "einfach", "mit \"Anführung\" und \\ Schrägstrich", "Zeile 1\nZeile 2\n", "Umlaute äöüß – „so“ 🌙", "raid;a;b\nsr;x;1;Item;Boss" })
        {
            string datei = "X = {\n[\"a\"] = " + LuaSaved.Quote(s) + ",\n[\"n\"] = 5,\n}\n";
            var x = LuaSaved.Table("X", Encoding.UTF8.GetBytes(datei));
            Gleich(s, x?["a"], "hin und zurück");
            Gleich("5", x?["n"], "Zahl nach Text");
        }

        // Fingerabdruck
        string a = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;100;Beta Lux\nm;Beta Lux;PRIEST;Priester;60;Offizier;2;\n#ENDE";
        string b = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;999;Alpha\nm;Beta Lux;PRIEST;Priester;60;Offizier;2;\n#ENDE";
        string c = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;100;Beta Lux\nm;Beta Lux;PRIEST;Priester;59;Offizier;2;\n#ENDE";
        Wahr(Abgleich.Abdruck("mitglieder", a) == Abgleich.Abdruck("mitglieder", b), "Klassenliste: Kopfzeile zählt");
        Wahr(Abgleich.Abdruck("mitglieder", a) != Abgleich.Abdruck("mitglieder", c), "Klassenliste: Änderung nicht erkannt");
        Wahr(Abgleich.Abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^x") == Abgleich.Abdruck("pinnwand", "EAPW1^77^Alpha\nN^ab^x"), "Pinnwand: Kopfzeile zählt");
        Wahr(Abgleich.Abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^x") != Abgleich.Abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^y"), "Pinnwand: Änderung nicht erkannt");
        Wahr(Abgleich.Abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider") == Abgleich.Abdruck("berufe", "EAB2^8^Alpha^1^C~Beta~Schneider"), "Berufe: Zeit zählt");
        Wahr(Abgleich.Abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider") != Abgleich.Abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schmied"), "Berufe: Änderung nicht erkannt");
        Wahr(Abgleich.Abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider") != Abgleich.Abdruck("berufe", "EAB2^7^Beta^2^C~Beta~Schneider"), "Berufe: Feld 4 zählt nicht");
        Wahr(Abgleich.Abdruck("bericht", "a") != Abgleich.Abdruck("bericht", "b"), "Bericht");
        // Gleicher Fingerabdruck wie die Mac-App (SHA-256 als Hex)
        Gleich("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Abgleich.Sha("abc"), "SHA-256");

        // Abgleich.lua: das Addon muss die Datei laden können – Inhalt zurücklesen
        string lua = Abgleich.Inhalt("raid;abcd1234;Hyjalgipfel;hyjal;2026-11-28 21:00\nspieler;Beta \"Lux\";Paladin", "#ELTERNABEND-GRUPPEN 1", 1794424346);
        var g = LuaSaved.Table("ElternabendAbgleich", Encoding.UTF8.GetBytes(lua));
        Gleich("raid;abcd1234;Hyjalgipfel;hyjal;2026-11-28 21:00\nspieler;Beta \"Lux\";Paladin", g?["raid"], "Abgleich.lua raid");
        Gleich("1794424346", g?["zeit"], "Abgleich.lua zeit");

        Console.WriteLine(fehler == 0 ? "Alle Tests bestanden." : fehler + " Tests fehlgeschlagen.");
        return fehler == 0 ? 0 : 1;
    }
}
