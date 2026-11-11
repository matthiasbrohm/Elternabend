import XCTest
@testable import ElternabendAbgleich

final class AbgleichTests: XCTestCase {
    /// So schreibt WoW die gespeicherten Variablen (Auszug)
    private let gespeichert = #"""

ElternabendDB = {
["notiz"] = "ElternabendSync = { nur ein Text }",
["plan"] = {
["id"] = "x",
},
}
ElternabendSync = {
["mitglieder"] = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;1;Beta Lux\nm;Beta \"Lux\";PRIEST;Priester;60;Offizier;2;\n#ENDE",
["berufe"] = "EAB2^7^Beta^1^C~Beta~Schneider~300~300~1~1,2",
["v"] = 1,
["pinnwand"] = "EAPW1^5^Beta\nN^ab^Beta^1^2^info^0^0^offen^Titel mit \\ und ä^Text^0",
["zeit"] = 1794424346,
["addon"] = "4.10.0",
["bericht"] = "#ELTERNABEND-BERICHT 1\nraid;abcdef12;X;1;2;Beta",
}
"""#

    func testTabelleLesen() throws {
        let t = try XCTUnwrap(LuaSaved.table(named: "ElternabendSync", in: Data(gespeichert.utf8)))
        XCTAssertEqual(t.count, 7)
        XCTAssertEqual(t["zeit"], "1794424346")
        XCTAssertEqual(t["v"], "1")
        XCTAssertEqual(t["mitglieder"], "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;1;Beta Lux\nm;Beta \"Lux\";PRIEST;Priester;60;Offizier;2;\n#ENDE")
        XCTAssertEqual(t["pinnwand"], "EAPW1^5^Beta\nN^ab^Beta^1^2^info^0^0^offen^Titel mit \\ und ä^Text^0")
        XCTAssertEqual(t["bericht"], "#ELTERNABEND-BERICHT 1\nraid;abcdef12;X;1;2;Beta")
    }

    func testTabelleFehlt() {
        XCTAssertNil(LuaSaved.table(named: "ElternabendSync", in: Data("ElternabendDB = {\n[\"a\"] = 1,\n}\n".utf8)))
        XCTAssertNil(LuaSaved.table(named: "ElternabendSync", in: Data("ElternabendSync = {\n[\"a\"] = \"abgeschnitten".utf8)))
        XCTAssertEqual(LuaSaved.table(named: "ElternabendSync", in: Data("ElternabendSync = {\n}\n".utf8))?.count, 0)
    }

    func testHinUndZurueck() throws {
        for s in ["", "einfach", "mit \"Anführung\" und \\ Schrägstrich", "Zeile 1\nZeile 2\n", "Umlaute äöüß – „so“ 🌙", "raid;a;b\nsr;x;1;Item;Boss"] {
            let datei = "X = {\n[\"a\"] = " + LuaSaved.quote(s) + ",\n[\"n\"] = 5,\n}\n"
            let t = try XCTUnwrap(LuaSaved.table(named: "X", in: Data(datei.utf8)))
            XCTAssertEqual(t["a"], s)
            XCTAssertEqual(t["n"], "5")
        }
    }

    func testAbdruck() {
        // Klassenliste: Zeit und Exporteur in der Kopfzeile zählen nicht, Mitglieder schon
        let a = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;100;Beta Lux\nm;Beta Lux;PRIEST;Priester;60;Offizier;2;\n#ENDE"
        let b = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;999;Alpha\nm;Beta Lux;PRIEST;Priester;60;Offizier;2;\n#ENDE"
        let c = "#ELTERNABEND-MITGLIEDER 1\ngilde;Elternabend;100;Beta Lux\nm;Beta Lux;PRIEST;Priester;59;Offizier;2;\n#ENDE"
        XCTAssertEqual(Abgleich.abdruck("mitglieder", a), Abgleich.abdruck("mitglieder", b))
        XCTAssertNotEqual(Abgleich.abdruck("mitglieder", a), Abgleich.abdruck("mitglieder", c))

        // Pinnwand: erste Zeile (Zeit, Exporteur) zählt nicht
        XCTAssertEqual(Abgleich.abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^x"), Abgleich.abdruck("pinnwand", "EAPW1^77^Alpha\nN^ab^x"))
        XCTAssertNotEqual(Abgleich.abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^x"), Abgleich.abdruck("pinnwand", "EAPW1^5^Beta\nN^ab^y"))

        // Berufe: Felder 2 und 3 (Zeit, Exporteur) zählen nicht
        XCTAssertEqual(Abgleich.abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider"), Abgleich.abdruck("berufe", "EAB2^8^Alpha^1^C~Beta~Schneider"))
        XCTAssertNotEqual(Abgleich.abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider"), Abgleich.abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schmied"))
        XCTAssertNotEqual(Abgleich.abdruck("berufe", "EAB2^7^Beta^1^C~Beta~Schneider"), Abgleich.abdruck("berufe", "EAB2^7^Beta^2^C~Beta~Schneider"))

        // Raid-Bericht: zählt ganz
        XCTAssertNotEqual(Abgleich.abdruck("bericht", "a"), Abgleich.abdruck("bericht", "b"))
    }
}
