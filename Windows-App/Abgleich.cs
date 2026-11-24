using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Microsoft.Win32;

namespace ElternabendAbgleich
{
    /// <summary>Ein WoW-Ordner mit Addon und/oder gespeicherten Daten (z. B. „_classic_“)</summary>
    public sealed class Installation
    {
        public string Name;
        public List<string> Saved = new List<string>(); // …\WTF\Account\<Konto>\SavedVariables\Elternabend.lua
        public string Addon;                             // …\Interface\AddOns\Elternabend (oder null)
    }

    /// <summary>
    /// Der eigentliche Abgleich – derselbe Ablauf wie in der Mac-App:
    ///   Spiel → Webseite: Klassenliste, Pinnwand, Berufe, Raid-Bericht (aus den SavedVariables, sobald das Spiel speichert)
    ///   Webseite → Spiel: nächster Raid und offene Gruppensuchen (als Abgleich.lua in den Addon-Ordner)
    /// </summary>
    public sealed class Abgleich
    {
        enum Ergebnis { Ok, Passwort, Gesperrt, Abgelehnt, Netz }

        public sealed class Teil
        {
            public string Key, Titel;
            public Teil(string key, string titel) { Key = key; Titel = titel; }
        }

        /// <summary>Was das Addon für die Webseite bereitlegt (Schlüssel in der Tabelle „ElternabendSync“)</summary>
        public static readonly Teil[] Teile =
        {
            new Teil("mitglieder", "Klassenliste"),
            new Teil("pinnwand", "Pinnwand"),
            new Teil("berufe", "Berufe"),
            new Teil("bericht", "Raid-Bericht"),
        };

        readonly Web web = new Web();
        readonly object sperre = new object();
        string passwort;
        bool laeuft;

        public DateTime LetzterStart { get; private set; } = DateTime.MinValue;
        /// <summary>Wird aus dem Hintergrund aufgerufen, wenn sich der Stand ändert</summary>
        public event Action Geaendert;

        public string PasswortWert
        {
            get { lock (sperre) return passwort; }
            set { lock (sperre) passwort = value; }
        }

        public bool Laeuft
        {
            get { lock (sperre) return laeuft; }
        }

        // ---------------------------------------------------------------- WoW-Ordner

        public string WowOrdner
        {
            get
            {
                string p = Einstellungen.Text("wowOrdner");
                if (!string.IsNullOrEmpty(p) && Directory.Exists(p)) return p;
                foreach (string v in Vorschlaege())
                {
                    try
                    {
                        if (Directory.Exists(v) && InstallationenIn(v).Count > 0) return v;
                    }
                    catch (Exception) { }
                }
                return null;
            }
        }

        public void SetzeOrdner(string pfad) => Einstellungen.Setzen("wowOrdner", pfad);

        /// <summary>Wo WoW unter Windows meist liegt – zuerst, was der Blizzard-Installer in der Registry vermerkt</summary>
        static IEnumerable<string> Vorschlaege()
        {
            foreach (string key in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            {
                string p = null;
                try
                {
                    using (var r = Registry.LocalMachine.OpenSubKey(key))
                        p = r?.GetValue("InstallPath") as string;
                }
                catch (Exception) { }
                if (string.IsNullOrEmpty(p)) continue;
                p = p.TrimEnd('\\', '/');
                string name = Path.GetFileName(p);
                if (name.StartsWith("_") && name.EndsWith("_")) p = Path.GetDirectoryName(p);
                yield return p;
            }
            DriveInfo[] laufwerke;
            try { laufwerke = DriveInfo.GetDrives(); } catch (Exception) { laufwerke = new DriveInfo[0]; }
            foreach (var d in laufwerke)
            {
                bool ok;
                try { ok = d.DriveType == DriveType.Fixed && d.IsReady; } catch (Exception) { ok = false; }
                if (!ok) continue;
                string root = d.RootDirectory.FullName;
                foreach (string sub in new[] { @"Program Files (x86)\World of Warcraft", @"Program Files\World of Warcraft", "World of Warcraft",
                                               @"Games\World of Warcraft", @"Spiele\World of Warcraft", @"Blizzard\World of Warcraft",
                                               @"Battle.net\World of Warcraft", @"Program Files (x86)\Battle.net\World of Warcraft" })
                    yield return Path.Combine(root, sub);
            }
        }

        public List<Installation> Installationen()
        {
            string root = WowOrdner;
            return root == null ? new List<Installation>() : InstallationenIn(root);
        }

        static List<Installation> InstallationenIn(string root)
        {
            var kandidaten = new List<string> { root };
            try
            {
                kandidaten.AddRange(Directory.GetDirectories(root).Where(d => Path.GetFileName(d).StartsWith("_")));
            }
            catch (Exception) { }
            var output = new List<Installation>();
            foreach (string k in kandidaten)
            {
                var inst = new Installation { Name = Path.GetFileName(k) };
                string konten = Path.Combine(k, "WTF", "Account");
                try
                {
                    if (Directory.Exists(konten))
                        foreach (string a in Directory.GetDirectories(konten))
                        {
                            string f = Path.Combine(a, "SavedVariables", "Elternabend.lua");
                            if (File.Exists(f)) inst.Saved.Add(f);
                        }
                }
                catch (Exception) { }
                string addon = Path.Combine(k, "Interface", "AddOns", "Elternabend");
                if (File.Exists(Path.Combine(addon, "Elternabend.toc"))) inst.Addon = addon;
                if (inst.Saved.Count > 0 || inst.Addon != null) output.Add(inst);
            }
            return output;
        }

        /// <summary>
        /// Ändert sich, sobald das Spiel seine Daten neu gespeichert hat (/reload, Logout, Beenden) –
        /// oder wenn Abgleich.lua im Addon-Ordner ersetzt wurde (Addon-Update): Dann schreibt die App sie gleich neu.
        /// </summary>
        public string Signatur()
        {
            var teile = new List<string>();
            foreach (var i in Installationen())
            {
                var dateien = new List<string>(i.Saved);
                if (i.Addon != null) dateien.Add(Path.Combine(i.Addon, "Abgleich.lua"));
                foreach (string f in dateien)
                {
                    long t = 0;
                    try { if (File.Exists(f)) t = File.GetLastWriteTimeUtc(f).Ticks; } catch (Exception) { }
                    teile.Add(f + "@" + t);
                }
            }
            return string.Join("|", teile);
        }

        // ---------------------------------------------------------------- Anzeige

        public string Ueberblick()
        {
            if (Laeuft) return "Abgleich läuft …";
            string meldung = Einstellungen.Text("meldung") ?? "";
            if (meldung != "") return "⚠ " + meldung;
            double t = Einstellungen.Zahl("letzter");
            return t > 0 ? "Letzter Abgleich: " + Zeit(t) : "Noch kein Abgleich";
        }

        public bool HatProblem => (Einstellungen.Text("meldung") ?? "") != "";

        public List<string> Zeilen()
        {
            var output = Teile.Select(t => t.Titel + ": " + (Einstellungen.Text("status." + t.Key) ?? "noch nichts vom Addon")).ToList();
            output.Add("Raid fürs Addon: " + (Einstellungen.Text("status.raid") ?? "noch nicht geholt"));
            return output;
        }

        static readonly DateTime Epoche = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        public static double Jetzt() => (DateTime.UtcNow - Epoche).TotalSeconds;

        public static string Zeit(double t)
        {
            var datum = Epoche.AddSeconds(t).ToLocalTime();
            var de = new CultureInfo("de-DE");
            return datum.Date == DateTime.Today ? "heute " + datum.ToString("HH:mm", de) + " Uhr" : datum.ToString("dd.MM. HH:mm", de) + " Uhr";
        }

        // ---------------------------------------------------------------- Ablauf

        public void NeuesPasswort(string pw)
        {
            PasswortWert = pw;
            Einstellungen.Ja("passwortFalsch", false);
            Einstellungen.Zahl("gesperrtBis", 0);
            Starten();
        }

        /// <summary>Startet einen Durchgang im Hintergrund. Läuft schon einer, passiert nichts.</summary>
        public void Starten()
        {
            lock (sperre)
            {
                if (laeuft) return;
                laeuft = true;
            }
            LetzterStart = DateTime.Now;
            Geaendert?.Invoke();
            ThreadPool.QueueUserWorkItem(_ =>
            {
                string meldung;
                try { meldung = Lauf(); }
                catch (Exception e) { meldung = "Unerwarteter Fehler: " + e.Message; }
                Einstellungen.Setzen("meldung", meldung);
                lock (sperre) laeuft = false;
                Geaendert?.Invoke();
            });
        }

        /// <summary>Ein Durchgang. Liefert die Meldung für das Menü (leer = alles in Ordnung).</summary>
        string Lauf()
        {
            string pw = PasswortWert;
            if (string.IsNullOrEmpty(pw)) return "Bitte das Offizierspasswort eingeben.";
            if (Einstellungen.Ja("passwortFalsch")) return "Das Offizierspasswort stimmt nicht – bitte neu eingeben.";
            double bis = Einstellungen.Zahl("gesperrtBis");
            if (bis > Jetzt()) return "Die Webseite hat nach falschen Passwörtern gesperrt – weiter " + Zeit(bis) + ".";
            var inst = Installationen();
            if (inst.Count == 0) return "WoW mit dem Addon Elternabend nicht gefunden – bitte den WoW-Ordner wählen.";

            var probleme = new List<string>();

            // 1. Spiel → Webseite
            var daten = NeuesteDaten(inst);
            if (daten != null)
            {
                foreach (var t in Teile)
                {
                    if (!daten.TryGetValue(t.Key, out string text) || string.IsNullOrEmpty(text)) continue;
                    string h = Abdruck(t.Key, text);
                    if (h == Einstellungen.Text("hash." + t.Key) || h == Einstellungen.Text("abgelehnt." + t.Key)) continue;
                    var e = Hochladen(t.Key, text, pw, out string grund);
                    switch (e)
                    {
                        case Ergebnis.Ok:
                            Einstellungen.Setzen("hash." + t.Key, h);
                            Einstellungen.Setzen("status." + t.Key, "hochgeladen " + Zeit(Jetzt()));
                            break;
                        case Ergebnis.Passwort:
                            Einstellungen.Ja("passwortFalsch", true);
                            return "Das Offizierspasswort stimmt nicht – bitte neu eingeben.";
                        case Ergebnis.Gesperrt:
                            return Sperren();
                        case Ergebnis.Abgelehnt:
                            Einstellungen.Setzen("abgelehnt." + t.Key, h); // erst wieder versuchen, wenn sich der Inhalt ändert
                            Einstellungen.Setzen("status." + t.Key, "nicht übernommen – " + grund + " (" + Zeit(Jetzt()) + ")");
                            probleme.Add(t.Titel);
                            break;
                        case Ergebnis.Netz:
                            Einstellungen.Setzen("status." + t.Key, "Webseite nicht erreichbar – " + grund);
                            probleme.Add(t.Titel);
                            break;
                    }
                }
            }

            // 2. Webseite → Spiel
            // Offene Gruppensuchen aus Discord und Dungeonfinder (für den Reiter „Gruppen“). Fehlt die Antwort,
            // bleibt der Reiter einfach ohne diese Hinweise.
            string gruppen = "";
            var g = web.Post("abgleich.php", new[] { Web.Feld("aktion", "gruppen"), Web.Feld("offizier", pw) }, out _);
            if (g != null && g.Status == 200 && g.Body.StartsWith("#ELTERNABEND-GRUPPEN", StringComparison.Ordinal)) gruppen = g.Body;

            var a = web.Post("abgleich.php", new[] { Web.Feld("aktion", "raid"), Web.Feld("offizier", pw) }, out string netz);
            if (a == null)
            {
                Einstellungen.Setzen("status.raid", "Webseite nicht erreichbar – " + netz);
                probleme.Add("Raid");
            }
            else
            {
                if (a.Status == 429) return Sperren();
                if (a.Status == 403 && a.Body.Contains("opw"))
                {
                    Einstellungen.Ja("passwortFalsch", true);
                    return "Das Offizierspasswort stimmt nicht – bitte neu eingeben.";
                }
                if (a.Status == 200 && a.Body.StartsWith("#ELTERNABEND-RAID", StringComparison.Ordinal))
                    RaidSchreiben(a.Body, gruppen, inst);
                else if (a.Status == 200 && a.Body.StartsWith("KEIN-RAID", StringComparison.Ordinal))
                    RaidSchreiben("", gruppen, inst);
                else
                {
                    Einstellungen.Setzen("status.raid", "Antwort der Webseite nicht verstanden (HTTP " + a.Status + ")");
                    probleme.Add("Raid");
                }
            }

            Einstellungen.Zahl("letzter", Jetzt());
            return probleme.Count == 0 ? "" : "Problem bei: " + string.Join(", ", probleme);
        }

        string Sperren()
        {
            double bis = Jetzt() + 16 * 60;
            Einstellungen.Zahl("gesperrtBis", bis);
            return "Die Webseite hat nach falschen Passwörtern gesperrt – weiter " + Zeit(bis) + ".";
        }

        /// <summary>Die jüngsten Daten des Addons (bei mehreren Konten oder WoW-Versionen zählt der neueste Stand)</summary>
        static Dictionary<string, string> NeuesteDaten(List<Installation> inst)
        {
            Dictionary<string, string> beste = null;
            double besteZeit = -1;
            foreach (var i in inst)
                foreach (string f in i.Saved)
                {
                    byte[] data;
                    try { data = File.ReadAllBytes(f); } catch (Exception) { continue; }
                    var t = LuaSaved.Table("ElternabendSync", data);
                    if (t == null) continue;
                    t.TryGetValue("zeit", out string zs);
                    double z = double.TryParse(zs, NumberStyles.Float, CultureInfo.InvariantCulture, out double zz) ? zz : 0;
                    if (z > besteZeit)
                    {
                        besteZeit = z;
                        beste = t;
                    }
                }
            return beste;
        }

        /// <summary>
        /// Fingerabdruck ohne die Teile, die sich bei jedem Speichern ändern (Zeitstempel, wer exportiert hat) –
        /// so wird nur hochgeladen, wenn sich wirklich etwas geändert hat.
        /// </summary>
        public static string Abdruck(string key, string text)
        {
            string kern = text;
            switch (key)
            {
                case "mitglieder":
                    kern = string.Join("\n", text.Split('\n').Where(z => !z.StartsWith("gilde;", StringComparison.Ordinal)));
                    break;
                case "pinnwand":
                    int ende = text.IndexOf('\n');
                    kern = ende >= 0 ? text.Substring(ende + 1) : "";
                    break;
                case "berufe":
                    var f = text.Split(new[] { '^' }, 4);
                    if (f.Length == 4) kern = f[0] + "^" + f[3];
                    break;
            }
            return Sha(kern);
        }

        public static string Sha(string s)
        {
            using (var sha = SHA256.Create())
                return string.Concat(sha.ComputeHash(Encoding.UTF8.GetBytes(s)).Select(b => b.ToString("x2")));
        }

        Ergebnis Hochladen(string key, string text, string pw, out string grund)
        {
            grund = "";
            WebAntwort a;
            string netz;
            switch (key)
            {
                case "mitglieder":
                    a = web.Post("klassenliste.php", new[] { Web.Feld("aktion", "import"), Web.Feld("export", text), Web.Feld("offizier", pw) }, out netz);
                    break;
                case "berufe":
                    a = web.Post("berufe.php", new[] { Web.Feld("aktion", "import"), Web.Feld("export", text), Web.Feld("offizier", pw) }, out netz);
                    break;
                case "pinnwand":
                    a = web.Post("pinnwand.php", new[] { Web.Feld("export", text), Web.Feld("offizier", pw) }, out netz);
                    break;
                default:
                    a = web.Post("abgleich.php", new[] { Web.Feld("aktion", "bericht"), Web.Feld("bericht", text), Web.Feld("offizier", pw) }, out netz);
                    break;
            }
            if (a == null)
            {
                grund = netz;
                return Ergebnis.Netz;
            }
            if (a.Status == 429) return Ergebnis.Gesperrt;
            if (a.Location.Contains("m=opw") || (a.Status == 403 && a.Body.Contains("opw"))) return Ergebnis.Passwort;
            if (key == "bericht")
            {
                if (a.Status == 200 && a.Body.StartsWith("OK", StringComparison.Ordinal)) return Ergebnis.Ok;
                string zeile = a.Body.Split('\n').FirstOrDefault() ?? "";
                grund = Grund(zeile.Replace("FEHLER ", ""), a.Status);
                return Ergebnis.Abgelehnt;
            }
            if (a.Status >= 300 && a.Status < 400 && a.Location.Contains("m=import")) return Ergebnis.Ok;
            string code = "";
            int p = a.Location.IndexOf("m=", StringComparison.Ordinal);
            if (p >= 0) code = new string(a.Location.Substring(p + 2).TakeWhile(c => c != '&' && c != '#').ToArray());
            grund = Grund(code, a.Status);
            return Ergebnis.Abgelehnt;
        }

        static string Grund(string code, int status)
        {
            switch (code)
            {
                case "format":
                case "kein-bericht": return "die Webseite hat den Text nicht erkannt";
                case "leer": return "der Text enthält keine Einträge";
                case "gross":
                case "bericht-gross": return "der Text ist zu groß";
                case "alt": return "das Addon ist zu alt für die Webseite";
                case "setup": return "die Webseite ist noch nicht eingerichtet";
                case "kein-raid": return "dieser Raid steht nicht (mehr) im Raidplaner";
                case "schreiben": return "die Webseite konnte nicht speichern";
                case "": return "HTTP " + status;
                default: return code;
            }
        }

        /// <summary>
        /// Schreibt die Daten der Webseite als Abgleich.lua in den Addon-Ordner. Das Addon liest sie beim nächsten
        /// Einloggen oder /reload. „raid“ ist leer, wenn kein Raid ansteht. „gruppen“: offene Gruppensuchen
        /// aus Discord und Dungeonfinder (leer, wenn die Webseite keine liefert).
        /// </summary>
        void RaidSchreiben(string raid, string gruppen, List<Installation> inst)
        {
            string h = Sha(raid);
            if (h != Einstellungen.Text("raidHash"))
            {
                Einstellungen.Setzen("raidHash", h);
                Einstellungen.Zahl("raidZeit", Math.Floor(Jetzt()));
            }
            long zeit = (long)Einstellungen.Zahl("raidZeit");
            string inhalt = Inhalt(raid, gruppen, zeit);

            int geschrieben = 0, aktuell = 0, zuAlt = 0, fehler = 0;
            var utf8 = new UTF8Encoding(false);
            foreach (var i in inst)
            {
                if (i.Addon == null) continue;
                string toc;
                try { toc = File.ReadAllText(Path.Combine(i.Addon, "Elternabend.toc"), utf8); } catch (Exception) { toc = ""; }
                if (!toc.Contains("Abgleich.lua")) { zuAlt++; continue; }
                string datei = Path.Combine(i.Addon, "Abgleich.lua");
                try
                {
                    if (File.Exists(datei) && File.ReadAllText(datei, utf8) == inhalt) { aktuell++; continue; }
                    string temp = datei + ".neu";
                    File.WriteAllText(temp, inhalt, utf8);
                    if (File.Exists(datei)) File.Replace(temp, datei, null);
                    else File.Move(temp, datei);
                    geschrieben++;
                }
                catch (Exception)
                {
                    fehler++;
                }
            }

            // Name des Raids aus der Zeile „raid;ID;Name;Vorlage;Datum“
            string name = "kein Raid geplant";
            foreach (string zeile in raid.Split('\n'))
            {
                if (!zeile.StartsWith("raid;", StringComparison.Ordinal)) continue;
                var f = zeile.Split(';');
                if (f.Length >= 5) name = f[2] + " (" + f[4].Trim() + ")";
                break;
            }
            string status;
            if (fehler > 0) status = name + " – konnte nicht in den Addon-Ordner schreiben";
            else if (geschrieben + aktuell == 0)
                status = zuAlt > 0 ? "Addon-Version ohne Abgleich – bitte das Addon aktualisieren" : "Addon Elternabend nicht gefunden";
            else status = name + " – Stand " + Zeit(zeit);
            Einstellungen.Setzen("status.raid", status);
        }

        /// <summary>Inhalt von Abgleich.lua (gleiche Form wie bei der Mac-App, nur „app“ nennt Windows)</summary>
        public static string Inhalt(string raid, string gruppen, long zeit)
        {
            return "-- Geschrieben von der App „Elternabend Abgleich“ (Windows) – bitte nicht von Hand ändern.\n"
                 + "-- Daten von gilde-elternabend.de: nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves und Terminen,\n"
                 + "-- dazu die offenen Gruppensuchen aus Discord und Dungeonfinder.\n"
                 + "ElternabendAbgleich = {\n"
                 + "    v = 1,\n"
                 + "    app = " + LuaSaved.Quote(App.Version + " Windows") + ",\n"
                 + "    zeit = " + zeit.ToString(CultureInfo.InvariantCulture) + ",\n"
                 + "    raid = " + LuaSaved.Quote(raid) + ",\n"
                 + "    gruppen = " + LuaSaved.Quote(gruppen) + ",\n"
                 + "}\n";
        }
    }
}
