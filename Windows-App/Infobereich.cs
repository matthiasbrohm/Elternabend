using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace ElternabendAbgleich
{
    /// <summary>Das Mond-Symbol im Infobereich mit Menü (Gegenstück zum Menüleisten-Symbol der Mac-App)</summary>
    sealed class Infobereich : ApplicationContext
    {
        readonly Abgleich abgleich = new Abgleich();
        readonly NotifyIcon symbol;
        readonly ContextMenuStrip menue = new ContextMenuStrip();
        readonly Timer takt = new Timer { Interval = 5000 };
        readonly Control ui = new Control();
        readonly Icon mond = LadeIcon("mond.ico"), mondLaeuft = LadeIcon("mond-laeuft.ico"), mondProblem = LadeIcon("mond-problem.ico");
        string letzteSignatur = "";
        DateTime? geplant;
        string letzteMeldung = "";

        public Infobereich()
        {
            ui.CreateControl();
            var _ = ui.Handle; // für BeginInvoke aus dem Hintergrund

            menue.Opening += (s, e) => { MenueBauen(); e.Cancel = false; };
            symbol = new NotifyIcon { Icon = mond, Visible = true, ContextMenuStrip = menue, Text = "Elternabend Abgleich" };
            // Auch ein Linksklick öffnet das Menü
            symbol.MouseUp += (s, e) =>
            {
                if (e.Button != MouseButtons.Left) return;
                typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic)?.Invoke(symbol, null);
            };

            abgleich.Geaendert += () =>
            {
                try { if (ui.IsHandleCreated) ui.BeginInvoke((Action)Aktualisieren); }
                catch (InvalidOperationException) { }
            };
            abgleich.PasswortWert = Passwort.Lesen();
            letzteMeldung = Einstellungen.Text("meldung") ?? "";
            Aktualisieren();

            // Beim allerersten Start: mit Windows starten (lässt sich im Menü abschalten)
            if (!Einstellungen.Ja("eingerichtet"))
            {
                Einstellungen.Ja("eingerichtet", true);
                try { Autostart.An = true; } catch (Exception) { }
            }

            letzteSignatur = abgleich.Signatur();
            takt.Tick += (s, e) => Tick();
            takt.Start();

            if (abgleich.PasswortWert == null)
            {
                var spaeter = new Timer { Interval = 800 };
                spaeter.Tick += (s, e) => { spaeter.Stop(); spaeter.Dispose(); PasswortFragen(); };
                spaeter.Start();
            }
            else
            {
                abgleich.Starten();
            }
        }

        static Icon LadeIcon(string name)
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
                return s != null ? new Icon(s, SystemInformation.SmallIconSize) : SystemIcons.Application;
        }

        /// <summary>Alle 5 Sekunden: Hat das Spiel gespeichert? Sonst alle 10 Minuten nach Neuem auf der Webseite sehen.</summary>
        void Tick()
        {
            string s = abgleich.Signatur();
            if (s != letzteSignatur)
            {
                letzteSignatur = s;
                geplant = DateTime.Now.AddSeconds(3); // kurz warten, bis die Datei fertig geschrieben ist
            }
            else if (geplant.HasValue && DateTime.Now >= geplant.Value)
            {
                geplant = null;
                abgleich.Starten();
            }
            else if (!geplant.HasValue && (DateTime.Now - abgleich.LetzterStart).TotalSeconds > 600)
            {
                abgleich.Starten();
            }
        }

        void Aktualisieren()
        {
            symbol.Icon = abgleich.Laeuft ? mondLaeuft : (abgleich.HatProblem ? mondProblem : mond);
            string text = "Elternabend Abgleich – " + abgleich.Ueberblick();
            symbol.Text = text.Length > 63 ? text.Substring(0, 62) + "…" : text; // Windows erlaubt nur 63 Zeichen

            // Neues Problem? Einmal kurz Bescheid geben.
            string meldung = abgleich.Laeuft ? letzteMeldung : (Einstellungen.Text("meldung") ?? "");
            if (meldung != letzteMeldung)
            {
                letzteMeldung = meldung;
                if (meldung != "") symbol.ShowBalloonTip(8000, "Elternabend Abgleich", meldung, ToolTipIcon.Warning);
            }
        }

        // ---------------------------------------------------------------- Menü

        void MenueBauen()
        {
            menue.Items.Clear();
            void Info(string titel) => menue.Items.Add(new ToolStripMenuItem(titel) { Enabled = false });
            void Knopf(string titel, Action aktion, bool an = false)
            {
                var i = new ToolStripMenuItem(titel) { Checked = an };
                i.Click += (s, e) => aktion();
                menue.Items.Add(i);
            }

            Info("Elternabend Abgleich " + App.Version);
            Info(abgleich.Ueberblick());
            menue.Items.Add(new ToolStripSeparator());
            foreach (string zeile in abgleich.Zeilen()) Info(zeile);
            menue.Items.Add(new ToolStripSeparator());
            Knopf("Jetzt abgleichen", () => abgleich.Starten());
            Knopf(abgleich.PasswortWert == null ? "Offizierspasswort eingeben …" : "Offizierspasswort ändern …", PasswortFragen);
            Knopf("WoW-Ordner: " + (abgleich.WowOrdner ?? "nicht gefunden – wählen …"), OrdnerWaehlen);
            bool autostart = false;
            try { autostart = Autostart.An; } catch (Exception) { }
            Knopf("Mit Windows starten", AutostartUmschalten, autostart);
            menue.Items.Add(new ToolStripSeparator());
            Knopf("gilde-elternabend.de öffnen", () => Process.Start(new ProcessStartInfo(Web.Basis) { UseShellExecute = true }));
            Knopf("Beenden", Beenden);
        }

        void PasswortFragen()
        {
            using (var f = new PasswortFenster())
            {
                if (f.ShowDialog() == DialogResult.OK && f.Wert != "")
                {
                    Passwort.Speichern(f.Wert);
                    abgleich.NeuesPasswort(f.Wert);
                }
            }
        }

        void OrdnerWaehlen()
        {
            using (var d = new FolderBrowserDialog())
            {
                d.Description = "Wähle den Ordner „World of Warcraft“ (darin liegen Ordner wie _classic_ oder _retail_).";
                d.ShowNewFolderButton = false;
                string jetzt = abgleich.WowOrdner;
                if (jetzt != null) d.SelectedPath = jetzt;
                if (d.ShowDialog() != DialogResult.OK) return;
                abgleich.SetzeOrdner(d.SelectedPath);
                if (abgleich.Installationen().Count == 0)
                    MessageBox.Show("In diesem Ordner liegt kein WoW mit dem Addon Elternabend. Bitte den Ordner „World of Warcraft“ wählen.",
                                    "Hier habe ich das Addon nicht gefunden", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                letzteSignatur = abgleich.Signatur();
                abgleich.Starten();
            }
        }

        void AutostartUmschalten()
        {
            try { Autostart.An = !Autostart.An; }
            catch (Exception e)
            {
                MessageBox.Show(e.Message, "Das hat nicht geklappt", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        void Beenden()
        {
            takt.Stop();
            symbol.Visible = false;
            symbol.Dispose();
            ExitThread();
        }
    }

    /// <summary>Fenster für das Offizierspasswort</summary>
    sealed class PasswortFenster : Form
    {
        readonly TextBox feld = new TextBox { UseSystemPasswordChar = true, Width = 300 };
        public string Wert => feld.Text;

        public PasswortFenster()
        {
            Text = "Offizierspasswort – Elternabend Abgleich";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ShowInTaskbar = true;
            TopMost = true;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(14);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            var text = new Label
            {
                AutoSize = true,
                MaximumSize = new Size(320, 0),
                Text = "Das Passwort, mit dem die Gildenleitung auf gilde-elternabend.de Listen einfügt. "
                     + "Es wird verschlüsselt für dieses Windows-Konto gespeichert und nur an gilde-elternabend.de geschickt.",
            };
            var ok = new Button { Text = "Speichern", DialogResult = DialogResult.OK, AutoSize = true };
            var abbrechen = new Button { Text = "Abbrechen", DialogResult = DialogResult.Cancel, AutoSize = true };
            var knoepfe = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 10, 0, 0) };
            knoepfe.Controls.Add(abbrechen);
            knoepfe.Controls.Add(ok);
            var stapel = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill };
            stapel.Controls.Add(text);
            stapel.Controls.Add(feld);
            stapel.Controls.Add(knoepfe);
            Controls.Add(stapel);
            AcceptButton = ok;
            CancelButton = abbrechen;
            Shown += (s, e) => { Activate(); feld.Focus(); };
        }
    }
}
