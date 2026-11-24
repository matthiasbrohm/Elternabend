// Elternabend Abgleich – kleine App für den Infobereich von Windows (unten rechts neben der Uhr).
// Gleicht das Addon „Elternabend“ mit gilde-elternabend.de ab, ohne Kopieren und Einfügen:
//   Spiel → Webseite: Klassenliste, Pinnwand, Berufe, Raid-Bericht (liest die SavedVariables nach /reload oder Logout)
//   Webseite → Spiel: nächster Raid mit Anmeldungen, Raidgruppen, Soft-Reserves und Terminen (schreibt Abgleich.lua ins Addon)
// Gegenstück zur Mac-App im Ordner Mac-App – gleicher Ablauf, gleiche Webseiten-Schnittstelle.
using System;
using System.Net;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

namespace ElternabendAbgleich
{
    public static class App
    {
        public static readonly string Version = VersionLesen();

        static string VersionLesen()
        {
            var v = Assembly.GetExecutingAssembly().GetName().Version;
            return v == null ? "?" : v.Major + "." + v.Minor + (v.Build > 0 ? "." + v.Build : "");
        }

        [STAThread]
        static void Main()
        {
            using (var einmal = new Mutex(true, @"Local\ElternabendAbgleich", out bool erster))
            {
                if (!erster)
                {
                    MessageBox.Show("Elternabend Abgleich läuft schon.\n\nDas Mond-Symbol findest du unten rechts neben der Uhr – "
                                    + "eventuell unter dem kleinen Pfeil ^.", "Elternabend Abgleich", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new Infobereich());
            }
        }
    }
}
