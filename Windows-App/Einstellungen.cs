using System;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32;

namespace ElternabendAbgleich
{
    /// <summary>Einstellungen und Stand des Abgleichs – in der Registry unter HKEY_CURRENT_USER (nur für dieses Windows-Konto).</summary>
    public static class Einstellungen
    {
        const string Pfad = @"Software\Gilde Elternabend\Abgleich";
        static readonly object Sperre = new object();

        public static string Text(string key)
        {
            lock (Sperre)
            {
                using (var r = Registry.CurrentUser.OpenSubKey(Pfad))
                    return r?.GetValue(key) as string;
            }
        }

        public static void Setzen(string key, string wert)
        {
            lock (Sperre)
            {
                using (var r = Registry.CurrentUser.CreateSubKey(Pfad))
                {
                    if (wert == null) r.DeleteValue(key, false);
                    else r.SetValue(key, wert, RegistryValueKind.String);
                }
            }
        }

        public static double Zahl(string key)
        {
            return double.TryParse(Text(key), NumberStyles.Float, CultureInfo.InvariantCulture, out double d) ? d : 0;
        }

        public static void Zahl(string key, double wert) => Setzen(key, wert.ToString("R", CultureInfo.InvariantCulture));

        public static bool Ja(string key) => Text(key) == "1";

        public static void Ja(string key, bool wert) => Setzen(key, wert ? "1" : "0");
    }

    /// <summary>
    /// Das Offizierspasswort liegt verschlüsselt in der Registry (Windows-Datenschutz-API, DPAPI):
    /// Lesen kann es nur dieses Windows-Konto auf diesem PC. Geschickt wird es nur an gilde-elternabend.de.
    /// </summary>
    public static class Passwort
    {
        static readonly byte[] Zusatz = Encoding.UTF8.GetBytes("gilde-elternabend.de/abgleich");

        public static string Lesen()
        {
            string s = Einstellungen.Text("passwort");
            if (string.IsNullOrEmpty(s)) return null;
            try
            {
                byte[] klar = ProtectedData.Unprotect(Convert.FromBase64String(s), Zusatz, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(klar);
            }
            catch (Exception)
            {
                return null;
            }
        }

        public static void Speichern(string pw)
        {
            if (string.IsNullOrEmpty(pw))
            {
                Einstellungen.Setzen("passwort", null);
                return;
            }
            byte[] geheim = ProtectedData.Protect(Encoding.UTF8.GetBytes(pw), Zusatz, DataProtectionScope.CurrentUser);
            Einstellungen.Setzen("passwort", Convert.ToBase64String(geheim));
        }
    }

    /// <summary>Beim Anmelden an Windows starten (Eintrag unter HKCU\…\Run)</summary>
    public static class Autostart
    {
        const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string Name = "Elternabend Abgleich";

        static string Befehl => "\"" + System.Windows.Forms.Application.ExecutablePath + "\"";

        public static bool An
        {
            get
            {
                using (var r = Registry.CurrentUser.OpenSubKey(Run))
                    return string.Equals(r?.GetValue(Name) as string, Befehl, StringComparison.OrdinalIgnoreCase);
            }
            set
            {
                using (var r = Registry.CurrentUser.CreateSubKey(Run))
                {
                    if (value) r.SetValue(Name, Befehl, RegistryValueKind.String);
                    else r.DeleteValue(Name, false);
                }
            }
        }
    }
}
