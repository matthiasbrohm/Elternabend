using System.Collections.Generic;
using System.Text;

namespace ElternabendAbgleich
{
    /// <summary>
    /// Liest aus einer SavedVariables-Datei von WoW eine flache Tabelle der Form
    ///   Name = {
    ///   ["schluessel"] = "Text",
    ///   ["zahl"] = 123,
    ///   }
    /// (gleiches Verfahren wie in der Mac-App)
    /// </summary>
    public static class LuaSaved
    {
        public static Dictionary<string, string> Table(string name, byte[] b)
        {
            var marker = Encoding.UTF8.GetBytes(name + " = {");
            int start = FindAtLineStart(marker, b);
            if (start < 0) return null;
            int i = start + marker.Length;
            int n = b.Length;
            var output = new Dictionary<string, string>();

            while (i < n)
            {
                // Leerraum und Kommas überspringen
                while (i < n && (b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x2C)) i++;
                if (i >= n) return null;
                if (b[i] == 0x7D) return output; // }
                if (b[i] == 0x2D && i + 1 < n && b[i + 1] == 0x2D) // Kommentar bis zum Zeilenende
                {
                    while (i < n && b[i] != 0x0A) i++;
                    continue;
                }

                // Schlüssel: ["name"] oder name
                string key;
                if (b[i] == 0x5B) // [
                {
                    i++;
                    if (i >= n || b[i] != 0x22) return null;
                    if (!ReadString(b, i, out key, out int next)) return null;
                    i = next;
                    if (i >= n || b[i] != 0x5D) return null; // ]
                    i++;
                }
                else
                {
                    int s = i;
                    while (i < n && IsIdent(b[i])) i++;
                    if (i <= s) return null;
                    key = Encoding.UTF8.GetString(b, s, i - s);
                }
                while (i < n && (b[i] == 0x20 || b[i] == 0x09)) i++;
                if (i >= n || b[i] != 0x3D) return null; // =
                i++;
                while (i < n && (b[i] == 0x20 || b[i] == 0x09)) i++;
                if (i >= n) return null;

                if (b[i] == 0x22) // "Text"
                {
                    if (!ReadString(b, i, out string v, out int next)) return null;
                    output[key] = v;
                    i = next;
                }
                else if (b[i] == 0x7B) // verschachtelte Tabelle: überspringen
                {
                    int depth = 0;
                    while (i < n)
                    {
                        if (b[i] == 0x22)
                        {
                            if (!ReadString(b, i, out _, out int next)) return null;
                            i = next;
                            continue;
                        }
                        if (b[i] == 0x7B) depth++;
                        if (b[i] == 0x7D)
                        {
                            depth--;
                            if (depth == 0) { i++; break; }
                        }
                        i++;
                    }
                }
                else // Zahl, true, false, nil
                {
                    int s = i;
                    while (i < n && b[i] != 0x2C && b[i] != 0x0A && b[i] != 0x0D && b[i] != 0x7D) i++;
                    output[key] = Encoding.UTF8.GetString(b, s, i - s).Trim(' ', '\t');
                }
            }
            return null;
        }

        static bool IsIdent(byte c)
        {
            return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
        }

        static int FindAtLineStart(byte[] marker, byte[] b)
        {
            int n = b.Length, m = marker.Length;
            if (m == 0 || n < m) return -1;
            for (int i = 0; i <= n - m; i++)
            {
                if (b[i] != marker[0] || (i != 0 && b[i - 1] != 0x0A)) continue;
                int j = 1;
                while (j < m && b[i + j] == marker[j]) j++;
                if (j == m) return i;
            }
            return -1;
        }

        /// <summary>Liest ein Lua-Zeichenketten-Literal ab dem öffnenden Anführungszeichen.</summary>
        static bool ReadString(byte[] b, int quote, out string text, out int next)
        {
            int i = quote + 1;
            int n = b.Length;
            var o = new List<byte>();
            text = null;
            next = 0;
            while (i < n)
            {
                byte c = b[i];
                if (c == 0x22)
                {
                    text = Encoding.UTF8.GetString(o.ToArray());
                    next = i + 1;
                    return true;
                }
                if (c != 0x5C) // kein Backslash
                {
                    o.Add(c);
                    i++;
                    continue;
                }
                i++;
                if (i >= n) return false;
                byte e = b[i];
                switch (e)
                {
                    case 0x6E: o.Add(0x0A); i++; break; // \n
                    case 0x72: o.Add(0x0D); i++; break; // \r
                    case 0x74: o.Add(0x09); i++; break; // \t
                    case 0x61: o.Add(0x07); i++; break;
                    case 0x62: o.Add(0x08); i++; break;
                    case 0x66: o.Add(0x0C); i++; break;
                    case 0x76: o.Add(0x0B); i++; break;
                    case 0x0A: o.Add(0x0A); i++; break; // Backslash am Zeilenende
                    default:
                        if (e >= 0x30 && e <= 0x39) // \ddd
                        {
                            int v = 0, digits = 0;
                            while (i < n && digits < 3 && b[i] >= 0x30 && b[i] <= 0x39)
                            {
                                v = v * 10 + (b[i] - 0x30);
                                i++;
                                digits++;
                            }
                            o.Add(unchecked((byte)v));
                        }
                        else
                        {
                            o.Add(e); // \" \\ \'
                            i++;
                        }
                        break;
                }
            }
            return false;
        }

        /// <summary>Text als Lua-Zeichenkette (für die Datei, die das Addon lädt)</summary>
        public static string Quote(string s)
        {
            var sb = new StringBuilder("\"");
            foreach (char c in s)
            {
                switch (c)
                {
                    case '\\': sb.Append("\\\\"); break;
                    case '"': sb.Append("\\\""); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': break;
                    case '\0': break;
                    default: sb.Append(c); break;
                }
            }
            return sb.Append('"').ToString();
        }
    }
}
