-- Gruppensuche: Bei Anmeldungen angeflüstert werden (Idee von Saleos Garthran), standardmäßig aus

local function Welt()
    local w = login({ guild = "Elternabend", roster = {
        { name = "Greta Glutherz", online = true, class = "PRIEST" },
        { name = "Beta Lux", online = true, class = "PALADIN" },
    } })
    w:advance(40)
    return w
end

local function Whispers(w)
    for _ = 1, 6 do w:call(w.ns.HardwarePulse) end
    local list = {}
    for _, e in ipairs(w.log) do
        if e.kind == "chat" and e.text:find("^WHISPER ") then list[#list + 1] = e.text end
    end
    return list
end

test("Anflüstern lassen: standardmäßig aus, Gesuch ohne Kennzeichen, Melden flüstert nicht", function()
    local w = Welt()
    check(not w.ns.Opt("groupWhisper"), "standardmäßig an")
    w.ns.SetPreset("an")
    check(not w.ns.Opt("groupWhisper"), "„Alles an“ schaltet es ein")
    w:receive("LFG\tg1\tHalle der Thanen\t1\t0\t2\t\t0\t0", "GUILD", "Beta Lux")
    w:clear()
    w.ns.Groups:Join("g1", "dd")
    w:advance(2)
    seen(w, "comm", "LFGJOIN g1 dd")
    equal(#Whispers(w), 0)
    noErrors(w)
end)

test("Anflüstern lassen: Suchender schaltet es ein, Gesuch geht mit Kennzeichen neu raus", function()
    local w = Welt()
    local G = w.ns.Groups
    G:Post("Halle der Thanen", { tank = 1, heal = 1, dd = 3 }, "", "heal")
    w:advance(3)
    w:clear()
    w.ns.UI:Show("gruppe")
    local p = w.ns.UI.panels.gruppen
    w:call(p.whisperMe.onChange, true)
    w:advance(1)
    check(w.ns.db.groups.whisper, "nicht gespeichert")
    check(w.ns.Opt("groupWhisper"), "Einstellung nicht an")
    seen(w, "comm", "LFG " .. G.mine.id .. " Halle der Thanen .* w$")
    -- Anmeldung kommt: Taskleiste blinkt
    local flashed = false
    w.env.FlashClientIcon = function() flashed = true end
    w:receive(table.concat({ "LFGJOIN", G.mine.id, "dd", "PRIEST", "" }, "\t"), "WHISPER", "Greta Glutherz")
    check(flashed, "Taskleiste blinkt nicht")
    noErrors(w)
end)

test("Anflüstern lassen: Wer sich meldet, flüstert den Suchenden an", function()
    local w = Welt()
    w:receive("LFG\tg1\tHalle der Thanen\t1\t0\t2\tgemütlich\t0\t\tw", "GUILD", "Beta Lux")
    check(w.ns.Groups.list.g1.whisper, "Kennzeichen nicht erkannt")
    w:clear()
    w.ns.Groups:Join("g1", "tank")
    w:advance(2)
    local list = Whispers(w)
    equal(#list, 1)
    check(list[1]:find("^WHISPER Beta Lux %[Elternabend%] Ich möchte als Tank mit zu Halle der Thanen"), list[1])
    noErrors(w)
end)
