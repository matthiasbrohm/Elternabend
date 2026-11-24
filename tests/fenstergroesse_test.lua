-- Fenstergröße: Einstellung, /ea größe, Strg + Mausrad

test("Fenstergröße: einstellbar von 60 bis 120 %, bleibt gespeichert", function()
    local w = login({ guild = "Elternabend" })
    local ns = w.ns
    w.env.UIParent.GetWidth = function() return 1920 end
    ns.UI:Show("start")
    local f = ns.UI.frame
    equal(ns.UI:WindowScale(), 100)
    ns.UI:SetWindowScale(80)
    equal(ns.db.settings.windowScale, 80)
    check(math.abs(f:GetScale() - 0.8) < 0.001, "Skalierung " .. tostring(f:GetScale()))
    ns.UI:SetWindowScale(50)
    equal(ns.UI:WindowScale(), 60)
    ns.UI:SetWindowScale(200)
    equal(ns.UI:WindowScale(), 120)
    -- per Befehl
    w:slash("/ea größe 85")
    equal(ns.UI:WindowScale(), 85)
    seen(w, "print", "Fenstergröße: 85 %%")
    -- Einstellungen zeigen den Regler mit dem aktuellen Wert
    ns.UI:ShowOptions()
    equal(ns.UI.optionsDialog.sizeSlider:GetValue(), 85)
    -- kleiner Bildschirm: passt sich trotzdem an
    w.env.UIParent.GetWidth = function() return 800 end
    ns.UI:SetWindowScale(100)
    check(f:GetScale() < 0.7, "nicht an kleinen Bildschirm angepasst")
    noErrors(w)
end)
