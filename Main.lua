local ADDON, BF = ...

SLASH_BISFINDER1 = "/bis"
SLASH_BISFINDER2 = "/bisfinder"
SlashCmdList.BISFINDER = function(msg, ...)
  local original = msg
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "rescan" then
    BF.db.items, BF.db.missing = {}, {}
    wipe(BF.notFound)
    BF.ResetSourceCache()
    BF.dataVersion = BF.dataVersion + 1
    BF.say("Item data cleared. Open the window to read it again.")
  elseif msg:match("^check") then
    local q = (msg:match("^check%s+(.+)$") or "")
    -- keep the original case / link of what was typed
    local raw = (original or ""):match("^%s*[Cc][Hh][Ee][Cc][Kk]%s+(.+)$") or q
    for _, line in ipairs(BF.Explain(raw)) do BF.say(line) end
  elseif msg == "minimap" then
    BF.ToggleMinimapButton()
  elseif msg == "help" then
    BF.say("/bis - open the window. /bis check <item> - why an item is or is not shown. /bis minimap - show or hide the minimap button. /bis rescan - read all items again.")
  else
    BF.Toggle()
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
  "CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "BAG_UPDATE_DELAYED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
local pending
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      BF.InitDB()
      BF.CreateMinimapButton()
      self:UnregisterEvent("ADDON_LOADED")
    end
    return
  end
  -- gear, bags, level or talents changed: draw again once things settle
  if event == "PLAYER_EQUIPMENT_CHANGED" then BF.gearVersion = (BF.gearVersion or 0) + 1
  elseif event ~= "BAG_UPDATE_DELAYED" and event ~= "PLAYER_LEVEL_UP" then BF.ClearTreeCache() end
  if not (BF.IsShown and BF.IsShown()) then return end   -- the window is closed: nothing to do
  if BF.Draw and not pending then
    pending = true
    C_Timer.After(0.5, function() pending = false; BF.Draw() end)
  end
end)
