using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;

namespace ElternabendAbgleich
{
    public sealed class WebAntwort
    {
        public int Status;
        public string Location = "";
        public string Body = "";
    }

    /// <summary>
    /// Schickt Formulare an gilde-elternabend.de – genau wie die Import-Felder auf der Webseite.
    /// Weiterleitungen werden nicht verfolgt: An ihrem Ziel („?m=import“) erkennt die App, ob es geklappt hat.
    /// </summary>
    public sealed class Web
    {
        public const string Basis = "https://gilde-elternabend.de/";
        readonly HttpClient http;

        public Web()
        {
            var handler = new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false };
            http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(120) };
            http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "ElternabendAbgleich/" + App.Version + " (Windows)");
        }

        /// <summary>Blockiert, bis die Antwort da ist – nur im Hintergrund aufrufen. Bei Netzproblemen: null und Grund.</summary>
        public WebAntwort Post(string seite, IEnumerable<KeyValuePair<string, string>> felder, out string fehler)
        {
            fehler = null;
            try
            {
                string body = string.Join("&", felder.Select(f => Kodiert(f.Key) + "=" + Kodiert(f.Value ?? "")));
                var inhalt = new StringContent(body, Encoding.UTF8, "application/x-www-form-urlencoded");
                using (var r = http.PostAsync(Basis + seite, inhalt).GetAwaiter().GetResult())
                {
                    return new WebAntwort
                    {
                        Status = (int)r.StatusCode,
                        Location = r.Headers.Location != null ? r.Headers.Location.OriginalString : "",
                        Body = r.Content.ReadAsStringAsync().GetAwaiter().GetResult() ?? "",
                    };
                }
            }
            catch (Exception e)
            {
                var innen = e;
                while (innen.InnerException != null) innen = innen.InnerException;
                fehler = innen.Message;
                return null;
            }
        }

        public static KeyValuePair<string, string> Feld(string k, string v) => new KeyValuePair<string, string>(k, v);

        /// <summary>Wie in der Mac-App: alles außer A–Z a–z 0–9 - . _ ~ wird als %XX (UTF-8) geschickt.</summary>
        static string Kodiert(string s)
        {
            var sb = new StringBuilder();
            foreach (byte b in Encoding.UTF8.GetBytes(s))
            {
                char c = (char)b;
                if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' || c == '~')
                    sb.Append(c);
                else
                    sb.Append('%').Append(b.ToString("X2"));
            }
            return sb.ToString();
        }
    }
}
