import Foundation

/// Liest aus einer SavedVariables-Datei von WoW eine flache Tabelle der Form
///   Name = {
///   ["schluessel"] = "Text",
///   ["zahl"] = 123,
///   }
enum LuaSaved {
    static func table(named name: String, in data: Data) -> [String: String]? {
        let b = [UInt8](data)
        let marker = Array((name + " = {").utf8)
        guard let start = findAtLineStart(marker, in: b) else { return nil }
        var i = start + marker.count
        let n = b.count
        var out: [String: String] = [:]

        while i < n {
            // Leerraum und Kommas überspringen
            while i < n, b[i] == 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x2C { i += 1 }
            guard i < n else { return nil }
            if b[i] == 0x7D { return out } // }
            if b[i] == 0x2D, i + 1 < n, b[i + 1] == 0x2D { // Kommentar bis zum Zeilenende
                while i < n, b[i] != 0x0A { i += 1 }
                continue
            }

            // Schlüssel: ["name"] oder name
            let key: String
            if b[i] == 0x5B { // [
                i += 1
                guard i < n, b[i] == 0x22, let (k, next) = readString(b, i) else { return nil }
                key = k
                i = next
                guard i < n, b[i] == 0x5D else { return nil } // ]
                i += 1
            } else {
                let s = i
                while i < n, isIdent(b[i]) { i += 1 }
                guard i > s else { return nil }
                key = String(decoding: b[s..<i], as: UTF8.self)
            }
            while i < n, b[i] == 0x20 || b[i] == 0x09 { i += 1 }
            guard i < n, b[i] == 0x3D else { return nil } // =
            i += 1
            while i < n, b[i] == 0x20 || b[i] == 0x09 { i += 1 }
            guard i < n else { return nil }

            if b[i] == 0x22 { // "Text"
                guard let (v, next) = readString(b, i) else { return nil }
                out[key] = v
                i = next
            } else if b[i] == 0x7B { // verschachtelte Tabelle: überspringen
                var depth = 0
                while i < n {
                    if b[i] == 0x22 {
                        guard let (_, next) = readString(b, i) else { return nil }
                        i = next
                        continue
                    }
                    if b[i] == 0x7B { depth += 1 }
                    if b[i] == 0x7D {
                        depth -= 1
                        if depth == 0 { i += 1; break }
                    }
                    i += 1
                }
            } else { // Zahl, true, false, nil
                let s = i
                while i < n, b[i] != 0x2C, b[i] != 0x0A, b[i] != 0x0D, b[i] != 0x7D { i += 1 }
                out[key] = String(decoding: b[s..<i], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private static func isIdent(_ c: UInt8) -> Bool {
        return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private static func findAtLineStart(_ marker: [UInt8], in b: [UInt8]) -> Int? {
        let n = b.count, m = marker.count
        guard m > 0, n >= m else { return nil }
        var i = 0
        while i <= n - m {
            if b[i] == marker[0], i == 0 || b[i - 1] == 0x0A {
                var j = 1
                while j < m, b[i + j] == marker[j] { j += 1 }
                if j == m { return i }
            }
            i += 1
        }
        return nil
    }

    /// Liest ein Lua-Zeichenketten-Literal ab dem öffnenden Anführungszeichen. Liefert Text und Position dahinter.
    private static func readString(_ b: [UInt8], _ quote: Int) -> (String, Int)? {
        var i = quote + 1
        let n = b.count
        var out = [UInt8]()
        while i < n {
            let c = b[i]
            if c == 0x22 { return (String(decoding: out, as: UTF8.self), i + 1) }
            if c != 0x5C { // kein Backslash
                out.append(c)
                i += 1
                continue
            }
            i += 1
            guard i < n else { return nil }
            let e = b[i]
            switch e {
            case 0x6E: out.append(0x0A); i += 1 // \n
            case 0x72: out.append(0x0D); i += 1 // \r
            case 0x74: out.append(0x09); i += 1 // \t
            case 0x61: out.append(0x07); i += 1
            case 0x62: out.append(0x08); i += 1
            case 0x66: out.append(0x0C); i += 1
            case 0x76: out.append(0x0B); i += 1
            case 0x0A: out.append(0x0A); i += 1 // Backslash am Zeilenende
            case 0x30...0x39: // \ddd
                var v = 0
                var digits = 0
                while i < n, digits < 3, b[i] >= 0x30, b[i] <= 0x39 {
                    v = v * 10 + Int(b[i] - 0x30)
                    i += 1
                    digits += 1
                }
                out.append(UInt8(truncatingIfNeeded: v))
            default: out.append(e); i += 1 // \" \\ \'
            }
        }
        return nil
    }

    /// Text als Lua-Zeichenkette (für die Datei, die das Addon lädt)
    static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": break
            case "\0": break
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }
}
