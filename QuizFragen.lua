-- Elternabend: Fragen für das Quiz (Raid, Zeltlager, Lagerfeuer)
--
-- Aufbau je Zeile: Frage, richtige Antwort, drei falsche Antworten. Gemischt wird
-- erst beim Anzeigen. Neue Fragen immer hinten anhängen und „rev“ erhöhen: Beim Start
-- einer Runde gehen nur die Nummern der Fragen an die Gruppe, deshalb müssen alle
-- denselben Stand haben.
local _, ns = ...

ns.QuizFragen = { rev = 1, list = {
    -- Orte der Allianz
    { "In welcher Stadt wohnen die Zwerge tief im Berg?", "Eisenschmiede", "Sturmwind", "Darnassus", "Gnomeregan" },
    { "Wie heißt das Gasthaus in Goldhain?", "Zur Höhle des Löwen", "Zum Pfeifenden Schwein", "Zur Güldenen Rose", "Zum Roten Raben" },
    { "Welches Verkehrsmittel verbindet Sturmwind mit Eisenschmiede?", "Die Tiefenbahn", "Der Zeppelin", "Die Postkutsche", "Das Greifenkarussell" },
    { "Auf welchem Weltenbaum liegt Darnassus?", "Teldrassil", "Nordrassil", "Vordrassil", "Shaladrassil" },
    { "In welchem Gebiet liegt Goldhain?", "Wald von Elwynn", "Westfall", "Dämmerwald", "Rotkammgebirge" },
    { "In welchem Gebiet liegt Seenhain?", "Rotkammgebirge", "Dämmerwald", "Wald von Elwynn", "Arathihochland" },
    { "Welche Stadt liegt im ewig dunklen Dämmerwald?", "Dunkelhain", "Seenhain", "Süderstade", "Thelsamar" },
    { "In welchem verschneiten Gebiet beginnen Zwerge und Gnome ihr Abenteuer?", "Dun Morogh", "Winterquell", "Alteracgebirge", "Loch Modan" },
    { "Von welchem Hafen im Sumpfland legen die Schiffe nach Kalimdor ab?", "Hafen von Menethil", "Beutebucht", "Ratschet", "Süderstade" },
    { "Welche Goblinstadt liegt an der Südspitze des Schlingendorntals?", "Beutebucht", "Gadgetzan", "Ratschet", "Ewige Warte" },
    { "In welcher Wüste liegt Gadgetzan?", "Tanaris", "Silithus", "Ödland", "Desolace" },
    { "Welche Hafenstadt der Allianz liegt in den Düstermarschen?", "Theramore", "Auberdine", "Süderstade", "Beutebucht" },
    { "In welchem Krater leben noch Dinosaurier?", "Un'Goro-Krater", "Sengende Schlucht", "Schimmernde Ebene", "Ödland" },
    { "Wie heißt der Turm des Magiers Medivh?", "Karazhan", "Burg Schattenfang", "Nethergarde", "Uldaman" },
    { "In welchem Gebiet steht das Dunkle Portal?", "Verwüstete Lande", "Sümpfe des Elends", "Brennende Steppe", "Gebirgspass der Totenwinde" },
    { "Welche Stadt der Magier gehört den Kirin Tor?", "Dalaran", "Stratholme", "Theramore", "Gilneas" },

    -- Völker, Reittiere, Welten
    { "Welches Reittier gehört zu den Gnomen?", "Roboschreiter", "Widder", "Nachtsäbler", "Pferd" },
    { "Auf welchem Tier reiten die Zwerge?", "Widder", "Roboschreiter", "Kodo", "Pferd" },
    { "Auf welchem Tier reiten die Nachtelfen?", "Nachtsäbler", "Widder", "Wolf", "Raptor" },
    { "Wie heißt die Welt, auf der unsere Abenteuer spielen?", "Azeroth", "Draenor", "Argus", "Kalimdor" },
    { "Aus welcher Welt kamen die Orcs?", "Draenor", "Azeroth", "Argus", "Nordend" },

    -- Berühmte Gestalten
    { "Wer ist der König der Zwerge von Eisenschmiede?", "Magni Bronzebart", "Muradin Bronzebart", "Brann Bronzebart", "Dagran Thaurissan" },
    { "Wer führt die Gnome an?", "Hochtüftler Mekkadrill", "Robogenieur Thermadraht", "Millhaus Manasturm", "Erfinder Zahnrad" },
    { "Wer ist die Hohepriesterin der Nachtelfen?", "Tyrande Wisperwind", "Maiev Schattensang", "Jaina Prachtmeer", "Sylvanas Windläufer" },
    { "Wer ist der Zwillingsbruder des Erzdruiden Malfurion?", "Illidan", "Arthas", "Cenarius", "Kael'thas" },
    { "Wie heißt der Sohn von König Varian Wrynn?", "Anduin", "Arthas", "Uther", "Bolvar" },
    { "Welche Drachin verbirgt sich hinter Lady Katrana Prestor?", "Onyxia", "Ysera", "Alexstrasza", "Sindragosa" },
    { "Wie heißt Onyxias Bruder, der Herr des Pechschwingenhorts?", "Nefarian", "Ragnaros", "Vaelastrasz", "Malygos" },
    { "Welcher Paladin war der Lehrmeister von Prinz Arthas?", "Uther der Lichtbringer", "Tirion Fordring", "Bolvar Fordragon", "Alexandros Mograine" },
    { "Wie heißt die verfluchte Runenklinge von Arthas?", "Frostgram", "Aschenbringer", "Donnerzorn", "Blutschrei" },
    { "Welche einstige Waldläufergeneralin wurde zur Bansheekönigin?", "Sylvanas Windläufer", "Tyrande Wisperwind", "Jaina Prachtmeer", "Lady Vashj" },
    { "Welcher Orc gründete Orgrimmar?", "Thrall", "Grom Höllschrei", "Orgrim Schicksalshammer", "Gul'dan" },
    { "Welche Magierin herrscht über Theramore?", "Jaina Prachtmeer", "Tyrande Wisperwind", "Aegwynn", "Katrana Prestor" },
    { "Welcher Dämonenlord wurde am Berg Hyjal besiegt?", "Archimonde", "Kil'jaeden", "Mannoroth", "Sargeras" },
    { "Wie heißt die Dämonenarmee, die Azeroth bedroht?", "Die Brennende Legion", "Die Geißel", "Der Schattenhammer", "Das Syndikat" },
    { "Welcher Drachenaspekt hütet die Zeit?", "Nozdormu", "Ysera", "Malygos", "Neltharion" },
    { "Welche Farbe hat der Drachenschwarm von Alexstrasza?", "Rot", "Blau", "Grün", "Bronze" },

    -- Klassen
    { "Welche Klasse zähmt wilde Tiere als Begleiter?", "Jäger", "Druide", "Schamane", "Hexenmeister" },
    { "Welche Klasse verwandelt sich in Bär und Katze?", "Druide", "Jäger", "Schurke", "Schamane" },
    { "Welche Klasse verwandelt Gegner in Schafe?", "Magier", "Hexenmeister", "Priester", "Druide" },
    { "Welche Klasse beschwört Wichtel und Leerwandler?", "Hexenmeister", "Magier", "Priester", "Schamane" },
    { "Welche Klasse knackt verschlossene Truhen?", "Schurke", "Krieger", "Jäger", "Magier" },
    { "Welche Klasse kämpft mit Wut statt mit Mana?", "Krieger", "Paladin", "Priester", "Magier" },
    { "Welcher Zauber macht einen Paladin für kurze Zeit unverwundbar?", "Gottesschild", "Handauflegung", "Segen der Könige", "Hammer der Gerechtigkeit" },
    { "Was zaubert ein Magier für durstige Mitspieler herbei?", "Wasser", "Gesundheitssteine", "Verbände", "Kakao" },
    { "Was verteilt ein Hexenmeister vor dem Bosskampf?", "Gesundheitssteine", "Wasser", "Verbände", "Brötchen" },

    -- Dungeons, Bosse und Bewohner
    { "Welcher Gnoll macht den Wald von Elwynn unsicher?", "Hogger", "Mor'Ladim", "Prinzessin", "Fressbart" },
    { "Wer führt die Defias-Bruderschaft in den Todesminen an?", "Edwin van Cleef", "Kapitän Grünhaut", "Rhahk'Zor", "Hogger" },
    { "Was rufen die Kobolde, wenn man ihnen zu nahe kommt?", "„Du nicht nehmen Kerze!“", "„Mehr Arbeit?“", "„Zeit ist Geld, mein Freund!“", "„Ich habe Hunger!“" },
    { "In welchem Gebiet liegt der Eingang zu den Todesminen?", "Westfall", "Rotkammgebirge", "Dämmerwald", "Wald von Elwynn" },
    { "Woran erkennt man die Defias-Bruderschaft?", "Am roten Halstuch", "Am schwarzen Umhang", "An der goldenen Maske", "Am grünen Hut" },
    { "Welcher Dungeon liegt mitten in Sturmwind?", "Das Verlies", "Die Todesminen", "Burg Schattenfang", "Uldaman" },
    { "Welche verstrahlte Stadt ist die verlorene Heimat der Gnome?", "Gnomeregan", "Uldaman", "Gadgetzan", "Kharanos" },
    { "Wer verriet die Gnome und herrscht nun in Gnomeregan?", "Robogenieur Thermadraht", "Hochtüftler Mekkadrill", "Edwin van Cleef", "Erzmagier Arugal" },
    { "Wer erweckt im Scharlachroten Kloster ihren gefallenen Champion wieder?", "Hochinquisitorin Weißsträhne", "Jaina Prachtmeer", "Baroness Anastari", "Katrana Prestor" },
    { "Wer haust in Burg Schattenfang?", "Erzmagier Arugal", "Kel'Thuzad", "Medivh", "Edwin van Cleef" },
    { "Welcher Feuerfürst wartet am Ende des Geschmolzenen Kerns?", "Ragnaros", "Nefarian", "Onyxia", "Hakkar" },
    { "Wer ruft Ragnaros im Geschmolzenen Kern herbei?", "Majordomus Exekutus", "Lucifron", "Garr", "Baron Geddon" },
    { "In welchem Berg liegen Geschmolzener Kern und Pechschwingenhort?", "Schwarzfels", "Berg Hyjal", "Steinkrallengebirge", "Rotkammgebirge" },
    { "Welche Zwergenprinzessin steht in den Schwarzfelstiefen an der Seite von Imperator Thaurissan?", "Moira Bronzebart", "Jaina Prachtmeer", "Katrana Prestor", "Theradras" },
    { "In welchem Gebiet liegt Onyxias Hort?", "Düstermarschen", "Brennende Steppe", "Winterquell", "Tanaris" },
    { "In welcher Trollstadt im Schlingendorntal wird der Blutgott Hakkar verehrt?", "Zul'Gurub", "Zul'Farrak", "Zul'Aman", "Zul'Drak" },
    { "Wie heißt die fliegende Totenstadt über den Pestländern?", "Naxxramas", "Acherus", "Karazhan", "Scholomance" },
    { "Welcher Lich herrscht über Naxxramas?", "Kel'Thuzad", "Arthas", "Ras Frostraunen", "Baron Totenschwur" },
    { "Welcher Alte Gott lauert in Ahn'Qiraj?", "C'Thun", "Yogg-Saron", "N'Zoth", "Hakkar" },
    { "In welcher Stadt begann mit der „Säuberung“ der Weg von Prinz Arthas in die Finsternis?", "Stratholme", "Sturmwind", "Dalaran", "Süderstade" },
    { "Welche Fischwesen erkennt man schon von Weitem an ihrem Gurgeln?", "Murlocs", "Naga", "Makrura", "Furbolgs" },
    { "Welcher gefürchtete Dinosaurier streift durch den Un'Goro-Krater?", "Teufelssaurier", "Donnerechse", "Kodo", "Felshetzer" },

    -- Berufe und Gegenstände
    { "Welcher Beruf braut aus Kräutern Elixiere?", "Alchemie", "Kräuterkunde", "Kochkunst", "Verzauberkunst" },
    { "Welcher Beruf kann Gegenstände entzaubern?", "Verzauberkunst", "Alchemie", "Schneiderei", "Ingenieurskunst" },
    { "Mit welchem Beruf baut man Bomben und Zielfernrohre?", "Ingenieurskunst", "Schmiedekunst", "Bergbau", "Lederverarbeitung" },
    { "Was braucht man zum Kürschnern?", "Kürschnermesser", "Spitzhacke", "Angelrute", "Schmiedehammer" },
    { "Was braucht man für den Bergbau?", "Spitzhacke", "Kürschnermesser", "Schaufel", "Brecheisen" },
    { "Mit welchem Nebenberuf stellt man Verbände her?", "Erste Hilfe", "Kochkunst", "Angeln", "Schneiderei" },
    { "Welches Kraut kann schon ein Anfänger der Kräuterkunde pflücken?", "Friedensblume", "Schwarzer Lotus", "Traumblatt", "Golddorn" },
    { "Aus welchen beiden Metallen entsteht Bronze?", "Kupfer und Zinn", "Eisen und Silber", "Kupfer und Eisen", "Zinn und Gold" },
    { "Welcher Stoff ist der einfachste?", "Leinenstoff", "Wollstoff", "Seidenstoff", "Runenstoff" },
    { "Wie viele Silberstücke ergeben ein Goldstück?", "100", "10", "50", "1000" },
    { "Welche Farbe haben epische Gegenstände?", "Lila", "Blau", "Grün", "Orange" },
    { "Welche Farbe haben legendäre Gegenstände?", "Orange", "Lila", "Gold", "Rot" },
    { "Was bedeutet „Beim Aufheben gebunden“?", "Der Gegenstand lässt sich nicht mehr handeln", "Er geht nie kaputt", "Er ist doppelt so stark", "Er verschwindet beim Ausloggen" },

    -- Spielbegriffe, Feste und Kurioses
    { "Wohin bringt dich dein Ruhestein?", "Zu deinem Gasthaus", "Zum nächsten Friedhof", "In die Hauptstadt", "Zum Raidleiter" },
    { "Was bedeutet „AFK“?", "Nicht an der Tastatur", "Alle für Kekse", "Auf fremdem Kontinent", "Angriff folgt gleich" },
    { "Welche Aufgabe hat der Tank?", "Die Gegner auf sich ziehen", "Die Gruppe heilen", "Den meisten Schaden machen", "Die Beute verteilen" },
    { "Was ist ein „Wipe“?", "Die ganze Gruppe stirbt", "Ein besonders schneller Bosskill", "Ein Putzlappen für den Bildschirm", "Eine Pause im Raid" },
    { "Was bekommst du, wenn du im Gasthaus ausloggst?", "Erholungsbonus auf Erfahrung", "Zusätzliches Gold", "Mehr Taschenplatz", "Einen zweiten Ruhestein" },
    { "Was zeigt ein gelbes Ausrufezeichen über einem NSC?", "Er hat eine Quest für dich", "Er ist ein Händler", "Er ist feindlich", "Er repariert Rüstung" },
    { "Wer bringt beim Winterhauchfest die Geschenke?", "Altvater Winter", "Väterchen Frost", "Der Weihnachtsgoblin", "Onkel Nefarian" },
    { "Wem gehört der Dunkelmond-Jahrmarkt?", "Silas Dunkelmond", "Gelbin Mekkadrill", "Baron Revilgaz", "Gazlowe" },
    { "Welche Tiere verkauft die „verrückte Katzenlady“ im Wald von Elwynn?", "Katzen", "Papageien", "Schlangen", "Eulen" },
    { "Was hatte Leeroy Jenkins am Ende wenigstens noch?", "Hähnchen", "Pizza", "Epische Beute", "Einen Plan" },
    { "Wie viele Spieler passen höchstens in einen Schlachtzug?", "40", "10", "25", "50" },
    { "Bis zu welcher Stufe kann ein Held aufsteigen?", "60", "40", "70", "80" },

    -- Elternabend
    { "Um wie viel Uhr beginnen unsere Raids?", "21 Uhr", "19 Uhr", "20 Uhr", "22 Uhr" },
    { "Wie lautet unser Gildenmotto?", "„Die Kinder schlafen. Die Helden erwachen.“", "„Erst Zähne putzen, dann Bosse putzen.“", "„Leise looten, laut lachen.“", "„Kein Wipe vor dem Sandmännchen.“" },
    { "Für welche Fraktion kämpft Elternabend?", "Für die Allianz", "Für die Horde", "Für beide", "Für die Goblins" },
    { "Was meldet der Elternknopf im Addon der Gruppe?", "„Kind wach, gleich zurück“", "„Bin Kaffee holen“", "„Bitte Pause“", "„Ich brauche Heilung“" },
    { "Mit welchem Befehl öffnest du unser Gildenaddon?", "/ea", "/eltern", "/kind", "/gilde" },
    { "An welchem See schlagen wir unser Zeltlager auf?", "Kristallsee", "Immerruhsee", "Spiegelsee", "Loch Modan" },
    { "Wer ist der gefährlichste Gegner eines Elternabend-Raids?", "Ein aufgewachtes Kind", "Ragnaros", "Onyxia", "Hogger" },
} }
