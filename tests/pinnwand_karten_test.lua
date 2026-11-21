-- Pinnwand: Zettel als Karteikarten (Standard) oder als Liste – oben umschaltbar, die Wahl bleibt gemerkt.

local function Gilde()
    local w = login({
        guild = "Elternabend",
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true },
            { name = "Greta Glutherz", online = true },
        },
    })
    w:advance(30)
    w:clear()
    return w
end

local function Zettel(w)
    local B = w.ns.Board
    local ok1, a = B:Post({ cat = "aktion", title = "Gemeinsam nach Uldaman", text = "Wer kommt mit?", when = B.Now() + 7200 })
    local ok2, b = B:Post({ cat = "dank", title = "Danke für die Taschen", text = "" })
    check(ok1 and ok2, "Zettel lassen sich nicht anheften")
    return a, b
end

local function Sichtbar(p)
    local n = 0
    for _, c in ipairs(p.cardList) do if c:IsShown() then n = n + 1 end end
    return n
end

test("Pinnwand: Karteikarten sind Standard, mit Art, Überschrift, Absender und Rückmelde-Knopf", function()
    local w = Gilde()
    local a = Zettel(w)
    w.ns.UI:Show("pinnwand")
    local p = w.ns.UI.panels.pinnwand
    check(p.cards:IsShown(), "Karteikarten nicht sichtbar")
    check(not p.empty:IsShown(), "Leer-Hinweis trotz Zetteln")
    equal(Sichtbar(p), 2)
    local card
    for _, c in ipairs(p.cardList) do if c.data and c.data.id == a.id then card = c end end
    check(card, "Karte zum Zettel fehlt")
    equal(card.chipText:GetText(), "AKTION")
    equal(card.title:GetText(), "Gemeinsam nach Uldaman")
    check(card.meta:GetText():find("an |?.*alle"), "Empfänger fehlt: " .. tostring(card.meta:GetText()))
    check(card.react:IsShown() and not card.reacted:IsShown(), "Knopf falsch vor der Rückmeldung")
    equal(card.react:GetText(), "Bin dabei")
    -- Ich bin dabei: der Knopf wird golden und zählt mit
    card.react:Click()
    w:advance(1)
    check(w.ns.Board:HasReacted(w.ns.db.board.notes[a.id]), "Rückmeldung nicht gespeichert")
    check(card.reacted:IsShown() and not card.react:IsShown(), "goldener Knopf fehlt")
    equal(card.reacted:GetText(), "Bin dabei  ·  1")
    -- Klick auf die Karte: rechts steht der Zettel
    card:Click("LeftButton")
    equal(p.selected, a.id)
    equal(p.dTitle:GetText(), "Gemeinsam nach Uldaman")
    noErrors(w)
end)

test("Pinnwand: Umschalter auf Liste und zurück, die Wahl bleibt gemerkt", function()
    local w = Gilde()
    Zettel(w)
    w.ns.UI:Show("pinnwand")
    local p = w.ns.UI.panels.pinnwand
    p.viewList:Click()
    equal(w.ns.db.board.view, "list")
    check(not p.cards:IsShown(), "Karteikarten noch sichtbar")
    check(p.empty:GetParent() ~= p.cards, "Leer-Hinweis hängt noch an den Karten")
    p.viewCards:Click()
    equal(w.ns.db.board.view, "cards")
    check(p.cards:IsShown(), "Karteikarten wieder weg")
    equal(Sichtbar(p), 2)
    noErrors(w)
end)

test("Pinnwand: leere Pinnwand zeigt den Hinweis auch bei Karteikarten", function()
    local w = Gilde()
    w.ns.UI:Show("pinnwand")
    local p = w.ns.UI.panels.pinnwand
    check(p.empty:IsShown(), "Hinweis fehlt")
    equal(Sichtbar(p), 0)
    noErrors(w)
end)
