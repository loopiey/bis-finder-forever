-- BiSFinder window: classes down the left, talent trees on top, Now / Endgame, the best items per slot, the plan,
-- a source filter panel and the stat weight editor.
local ADDON, BF = ...

local f, content, rows, lines, bars, editor, panel
local classButtons, specButtons, tabButtons, filterChecks = {}, {}, {}, {}
local lastDraw = 0

local FRAME_W, FRAME_H = 880, 680       -- size to start with; the window can be resized from its bottom right corner
local MIN_W, MIN_H, MAX_W, MAX_H = 820, 460, 1600, 1400
local SIDE = 64                         -- width of the class bar on the left
local X0 = SIDE + 14                    -- left edge of everything right of the class bar
local CW = FRAME_W - X0 - 40            -- width of the list (follows the window size)

local FILTERS = {
  { "dungeon", "Dungeons" }, { "raid", "Raids" }, { "quest", "Quests" }, { "rep", "Reputation & sets" },
  { "crafted", "Crafted" }, { "vendor", "Vendors & currency" }, { "bislist", "World drops" }, { "pvp", "PvP (honor)" },
  { "classic", "Old drops (may be gone)" }, { "unknown", "Unknown source" },
}

local STAT_LABELS = {
  { "str", "Strength" }, { "agi", "Agility" }, { "sta", "Stamina" }, { "int", "Intellect" }, { "spi", "Spirit" },
  { "ap", "Attack Power" }, { "rap", "Ranged Attack Power" }, { "fap", "Feral Attack Power" },
  { "sp", "Spell Power" }, { "heal", "Healing Power" }, { "mp5", "Mana per 5 sec" }, { "hp5", "Health per 5 sec" },
  { "hit", "Hit (per 1%)" }, { "crit", "Crit (per 1%)" }, { "haste", "Haste (per 1%)" }, { "exp", "Expertise (per 1%)" },
  { "def", "Defense (per point)" }, { "dodge", "Dodge (per 1%)" }, { "parry", "Parry (per 1%)" }, { "block", "Block (per 1%)" },
  { "bv", "Block Value" }, { "armor", "Armor" }, { "dpsmelee", "Weapon DPS (main hand)" }, { "dpsoh", "Weapon DPS (off hand)" },
  { "dps", "Weapon DPS (ranged)" }, { "dpswand", "Wand DPS" }, { "arcane", "Arcane spell damage" }, { "fire", "Fire spell damage" },
  { "frost", "Frost spell damage" }, { "holy", "Holy spell damage" }, { "nature", "Nature spell damage" }, { "shadow", "Shadow spell damage" },
  { "spen", "Spell Penetration" }, { "arpen", "Armor Penetration" }, { "hp", "Health" }, { "mana", "Mana" },
}

-- talent tree icons (the game's own spell icons)
local I = "Interface\\Icons\\"
local SPEC_ICONS = {
  WARRIOR = { Arms = "Ability_Warrior_SavageBlow", Fury = "Ability_Warrior_InnerRage", Protection = "Ability_Warrior_DefensiveStance" },
  PALADIN = { Holy = "Spell_Holy_HolyBolt", Protection = "Ability_Paladin_ShieldoftheTemplar", Retribution = "Spell_Holy_AuraOfLight" },
  HUNTER  = { ["Beast Mastery"] = "Ability_Hunter_BestialDiscipline", Marksmanship = "Ability_Hunter_FocusedAim", Survival = "Ability_Hunter_Camouflage" },
  ROGUE   = { Assassination = "Ability_Rogue_Eviscerate", Combat = "Ability_BackStab", Subtlety = "Ability_Stealth" },
  PRIEST  = { Discipline = "Spell_Holy_PowerWordShield", Holy = "Spell_Holy_GuardianSpirit", Shadow = "Spell_Shadow_ShadowWordPain" },
  SHAMAN  = { Elemental = "Spell_Nature_Lightning", Enhancement = "Spell_Shaman_ImprovedStormstrike", Restoration = "Spell_Nature_MagicImmunity" },
  MAGE    = { Arcane = "Spell_Holy_MagicalSentry", Fire = "Spell_Fire_FireBolt02", Frost = "Spell_Frost_FrostBolt02" },
  WARLOCK = { Affliction = "Spell_Shadow_DeathCoil", Demonology = "Spell_Shadow_Metamorphosis", Destruction = "Spell_Shadow_RainOfFire" },
  DRUID   = { Balance = "Spell_Nature_StarFall", ["Feral (Cat)"] = "Ability_Druid_CatForm", Restoration = "Spell_Nature_HealingTouch", ["Feral (Bear)"] = "Ability_Racial_BearForm" },
}
local QUESTION = 134400

local function fmt(v) return string.format("%.1f", v or 0) end
local function hex(r, g, b) return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255) end
local function classColor(cls)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end
local function className(cls)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or (cls:sub(1, 1) .. cls:sub(2):lower())
end
local function classIcon(cls) return I .. "ClassIcon_" .. cls:sub(1, 1) .. cls:sub(2):lower() end
local function specIcon(cls, name)
  local n = SPEC_ICONS[cls] and SPEC_ICONS[cls][name]
  return n and (I .. n) or QUESTION
end
local function trim(tex) tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

local function backdrop(frame, a)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.05, 0.05, 0.07, a or 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
  else
    local bg = frame:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.05, 0.07, a or 0.95)
  end
end

---------------------------------------------------------------------------------------------------------------------
-- List pieces: text lines, slot bars, item rows (made once, reused)
---------------------------------------------------------------------------------------------------------------------
local function getLine(i)
  local h = lines[i]
  if h then return h end
  h = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetJustifyH("LEFT")
  lines[i] = h
  return h
end

-- slots the player folded away (click the slot name), kept per character
local function collapsed() BF.cdb.collapsed = BF.cdb.collapsed or {}; return BF.cdb.collapsed end

local function getBar(i)
  local b = bars[i]
  if b then return b end
  b = CreateFrame("Button", nil, content)
  b:SetHeight(22)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.06)
  b.edge = b:CreateTexture(nil, "ARTWORK"); b.edge:SetPoint("TOPLEFT"); b.edge:SetPoint("BOTTOMLEFT"); b.edge:SetWidth(3)
  b.arrow = b:CreateTexture(nil, "ARTWORK"); b.arrow:SetSize(14, 14); b.arrow:SetPoint("LEFT", 8, 0)
  b.left = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); b.right:SetPoint("RIGHT", -8, 0)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.05)
  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function(self)
    local key = self.collapseKey
    if not key then return end
    local c = collapsed()
    if IsShiftKeyDown() then   -- shift-click: fold or open every slot
      local fold = not c[key]
      for _, sd in ipairs(BF.SLOTS) do c[sd.key] = fold or nil end
      c.SETS = fold or nil
    else
      c[key] = (not c[key]) or nil
    end
    BF.Draw()
  end)
  b:SetScript("OnEnter", function(self)
    if not self.collapseKey then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(collapsed()[self.collapseKey] and "Click: show this slot" or "Click: hide this slot", 1, 1, 1)
    GameTooltip:AddLine("Shift-click: hide or show all slots", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  bars[i] = b
  return b
end

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, content)
  r:SetHeight(36)
  r.fill = r:CreateTexture(nil, "BACKGROUND"); r.fill:SetPoint("TOPLEFT"); r.fill:SetPoint("BOTTOMLEFT")
  r.bg = r:CreateTexture(nil, "BORDER"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.2, 0.8, 0.4, 0.14); r.bg:Hide()
  r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); r.rank:SetPoint("LEFT", 2, 0); r.rank:SetWidth(22)
  r.rank:SetJustifyH("CENTER")
  r.border = r:CreateTexture(nil, "ARTWORK"); r.border:SetSize(32, 32); r.border:SetPoint("LEFT", 26, 0)
  r.icon = r:CreateTexture(nil, "OVERLAY"); r.icon:SetSize(30, 30); r.icon:SetPoint("CENTER", r.border, "CENTER"); trim(r.icon)
  r.check = r:CreateTexture(nil, "OVERLAY", nil, 7); r.check:SetSize(16, 16); r.check:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 5, -5)
  r.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready"); r.check:Hide()
  r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.info:SetPoint("TOPRIGHT", -8, -4); r.info:SetJustifyH("RIGHT")
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); r.name:SetPoint("TOPLEFT", r.border, "TOPRIGHT", 8, -1)
  r.name:SetPoint("RIGHT", r.info, "LEFT", -8, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.src = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); r.src:SetPoint("BOTTOMLEFT", r.border, "BOTTOMRIGHT", 8, 1)
  r.src:SetPoint("RIGHT", -8, 0); r.src:SetJustifyH("LEFT"); r.src:SetWordWrap(false)
  local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.07)
  r:RegisterForClicks("LeftButtonUp")
  r:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:AddLine(" ")
    if self.score then GameTooltip:AddLine("Score: " .. fmt(self.score), 0.2, 1, 0.6) end
    if self.slotKey then
      if BF.IsOwnClass() then
        GameTooltip:AddLine(self.picked and "Click: remove from my plan" or "Click: add to my plan", 0.6, 0.8, 1)
      else
        GameTooltip:AddLine("The plan is for your own class.", 0.6, 0.6, 0.6)
      end
    end
    if self.srcText and self.srcText ~= "" then GameTooltip:AddLine(self.srcText, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self)
    if not self.id then return end
    local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(self.id)
    if not link then return end
    if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link)
    elseif IsModifiedClick("DRESSUP") then DressUpItemLink(link)
    elseif self.slotKey and f.specName and BF.IsOwnClass() then
      BF.TogglePick(f.specName, self.slotKey, self.id)
      BF.Draw()
    end
  end)
  rows[i] = r
  return r
end

-- fills a row with an item; x = left indent, frac = 0..1 length of the score bar behind it
local function fillRow(r, rec, x, y, frac)
  local width = CW - x - 4
  r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", x, y); r:SetWidth(width)
  r.icon:SetTexture(rec.ic or QUESTION)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rec.q or 1]
  if c then r.border:SetColorTexture(c.r, c.g, c.b, 1) else r.border:SetColorTexture(0.5, 0.5, 0.5, 1) end
  if frac and frac > 0 then
    local cr, cg, cb = classColor(BF.ViewClass())
    r.fill:SetColorTexture(cr, cg, cb, 0.10)
    r.fill:SetWidth(math.max(1, math.min(1, frac) * width)); r.fill:Show()
  else
    r.fill:Hide()
  end
  r:Show()
end

---------------------------------------------------------------------------------------------------------------------
-- Top: class, talent trees, tabs
---------------------------------------------------------------------------------------------------------------------
local function filterCount()
  local on = 0
  for _, d in ipairs(FILTERS) do if BF.cdb.filters[d[1]] then on = on + 1 end end
  return on
end

local function updateControls()
  local cls = BF.ViewClass()
  local own = BF.IsOwnClass()
  local r, g, b = classColor(cls)
  -- class bar
  for _, cb in ipairs(classButtons) do
    local sel = cb.cls == cls
    cb.icon:SetDesaturated(not sel)
    cb.icon:SetAlpha(sel and 1 or 0.65)
    cb.ring:SetShown(sel)
    if sel then cb.ring:SetColorTexture(r, g, b, 1) end
  end
  -- header
  f.classIcon:SetTexture(classIcon(cls)); trim(f.classIcon)
  f.className:SetText(className(cls))
  f.className:SetTextColor(r, g, b)
  f.headLine:SetColorTexture(r, g, b, 0.6)
  -- talent trees
  local specs = BF.Specs()
  local idx, auto = BF.SpecIndex()
  for i, sb in ipairs(specButtons) do
    local s = specs[i]
    sb:SetShown(s ~= nil)
    if s then
      sb.icon:SetTexture(specIcon(cls, s.name)); trim(sb.icon)
      sb.text:SetText(s.name)
      local sel = idx == i
      sb.under:SetShown(sel)
      sb.under:SetColorTexture(r, g, b, 1)
      sb.text:SetTextColor(sel and 1 or 0.7, sel and 1 or 0.7, sel and 1 or 0.7)
      sb.icon:SetDesaturated(not sel)
      sb.bg:SetColorTexture(1, 1, 1, sel and 0.10 or 0.04)
    end
  end
  if not own then
    f.sub:SetText("|cffbbbbbbLooking at another class. Worn items and the plan are for your own character.|r")
  elseif BF.cdb.spec then
    f.sub:SetText("|cffbbbbbbYour character - tree picked by you (click it again to follow your talents)|r")
  elseif idx then
    f.sub:SetText("|cffbbbbbbYour character - following your talents|r")
  else
    f.sub:SetText("|cffff8080Your character - no talents found, pick a tree|r")
  end
  -- tabs and buttons
  local level = UnitLevel("player") or 1
  tabButtons.now:SetText("Now (level " .. level .. ")")
  for k, tb in pairs(tabButtons) do if BF.cdb.mode == k then tb:LockHighlight() else tb:UnlockHighlight() end end
  f.topN:SetText(tostring(BF.TopN()))
  f.filterButton:SetText("Sources (" .. filterCount() .. "/" .. #FILTERS .. ")")
  f.viewButtons.plan:SetEnabled(own)
  for k, cb in pairs(filterChecks) do cb:SetChecked(k == "hideFaction" and BF.cdb.hideFaction or BF.cdb.filters[k]) end
  if filterChecks.raid then filterChecks.raid.label:SetText(BF.RaidsOpen() and "Raids" or "Raids (open 9 Dec)") end
end

---------------------------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------------------------
local cursor   -- { y, row, line, bar }

local function reset()
  for _, r in ipairs(rows) do r:Hide(); r.bg:Hide(); r.check:Hide(); r.slotKey = nil; r.rank:SetText("") end
  for _, h in ipairs(lines) do h:Hide() end
  for _, b in ipairs(bars) do b:Hide() end
  cursor = { y = -4, row = 0, line = 0, bar = 0 }
end

local function addLine(text, x, gap)
  cursor.line = cursor.line + 1
  local h = getLine(cursor.line)
  h:ClearAllPoints(); h:SetPoint("TOPLEFT", content, "TOPLEFT", x or 6, cursor.y); h:SetWidth(CW - (x or 6) - 8)
  h:SetText(text); h:Show()
  cursor.y = cursor.y - math.max(16, h:GetStringHeight() + (gap or 4))
end

-- key: a slot (or "SETS") that can be folded away by clicking the bar
local function addBar(left, right, key)
  cursor.bar = cursor.bar + 1
  local b = getBar(cursor.bar)
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", content, "TOPLEFT", 2, cursor.y); b:SetWidth(CW - 6)
  local r, g, bl = classColor(BF.ViewClass())
  b.edge:SetColorTexture(r, g, bl, 1)
  b.collapseKey = key
  b.left:ClearAllPoints()
  if key then
    b.arrow:SetTexture(collapsed()[key] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    b.arrow:Show(); b.left:SetPoint("LEFT", b.arrow, "RIGHT", 6, 0)
  else
    b.arrow:Hide(); b.left:SetPoint("LEFT", 10, 0)
  end
  b.left:SetText(left); b.right:SetText(right or "")
  b:Show()
  cursor.y = cursor.y - 26
end

local function nextRow()
  cursor.row = cursor.row + 1
  return getRow(cursor.row)
end

local function drawSets()
  local shown = 0
  local folded = collapsed().SETS
  for _, st in ipairs(BF.lastSets or {}) do
    if st.available >= 2 and shown < 6 then
      if shown == 0 then addBar("Sets", "|cff999999the best number of pieces against the best single items|r", "SETS") end
      shown = shown + 1
      if folded then break end
      local names = {}
      for _, p in ipairs(st.k >= 2 and st.pieces or {}) do
        local prec = BF.db.items[p.id]
        names[#names + 1] = prec and prec.n or "?"
      end
      local text
      if st.k >= 2 and st.gain > 0 then
        text = string.format("|cff33ff99%s: wear %d of %d pieces (%+.1f)|r\n|cffbbbbbb%s|r",
          st.name, st.k, st.available, st.gain, table.concat(names, ", "))
      else
        text = string.format("|cff999999%s: not worth it|r", st.name)
      end
      if #st.uncounted > 0 then text = text .. "\n|cff777777Not counted: " .. table.concat(st.uncounted, "; ") .. "|r" end
      addLine(text, 14)
    end
  end
  if shown > 0 then cursor.y = cursor.y - 6 end
end

function BF.Draw()
  if not (f and f:IsShown()) then return end
  lastDraw = GetTime()
  if not BF.IsOwnClass() and BF.cdb.view == "plan" then BF.cdb.view = "list" end
  updateControls()
  local idx = BF.SpecIndex()
  local results, specName = BF.Rank(BF.cdb.mode, idx)
  f.specName = specName
  f.title:SetText("BiSFinder - " .. className(BF.ViewClass()) .. " " .. (specName or "?") .. " - "
    .. (BF.cdb.mode == "endgame" and "Endgame (60)" or "Now"))
  reset()
  local n = BF.IsOwnClass() and BF.PickCount(specName) or 0
  f.viewButtons.plan:SetText("My plan (" .. n .. ")")
  for k, b in pairs(f.viewButtons) do if BF.cdb.view == k then b:LockHighlight() else b:UnlockHighlight() end end
  f.clearPlan:SetShown(BF.cdb.view == "plan" and n > 0)
  if BF.cdb.view == "plan" then BF.DrawPlan(idx, specName); return end

  drawSets()
  local own = BF.IsOwnClass()
  local any = false
  for _, sd in ipairs(BF.SLOTS) do
    local res = results[sd.key]
    if #res.top > 0 or (res.equipped or 0) > 0 then
      any = true
      local folded = collapsed()[sd.key]
      local right = own and ("worn: " .. fmt(res.equipped)) or ""
      if folded and res.top[1] then
        local brec = BF.db.items[res.top[1].id]
        right = "|cff999999best: " .. (brec and brec.n or "?") .. "|r" .. (right ~= "" and ("   " .. right) or "")
      end
      addBar(sd.name, right, sd.key)
      if #res.top == 0 and not folded then addLine("|cff999999nothing better found|r", 14) end
      local best = res.top[1] and res.top[1].score or 1
      for rank, t in ipairs(folded and {} or res.top) do
        local r = nextRow()
        local rec = BF.db.items[t.id]
        local src = BF.Source(t.id, rec)
        r.id, r.score, r.srcText, r.slotKey = t.id, t.score, src.text, sd.key
        r.picked = own and BF.IsPicked(specName, sd.key, t.id)
        fillRow(r, rec, 4, cursor.y, best > 0 and t.score / best or 0)
        r.bg:SetShown(r.picked); r.check:SetShown(r.picked)
        r.rank:SetText(rank)
        local worn = false
        for _, eid in ipairs(res.equippedIDs or {}) do if eid == t.id then worn = true end end
        local setTag = ""
        if rec.set and BF.db.sets[rec.set] then
          setTag = "  |cff8080ff[" .. (BF.inBestSet and BF.inBestSet[t.id] and "* " or "") .. "Set: " .. BF.db.sets[rec.set].n .. "]|r"
        end
        local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rec.q or 1]
        r.name:SetText((c and c.hex or "|cffffffff") .. rec.n .. "|r" .. (worn and "  |cff33ff99(equipped)|r" or "") .. setTag)
        local up = ""
        if own and not worn then
          if (res.equipped or 0) > 0 then
            local pct = (t.score - res.equipped) / res.equipped * 100
            up = pct >= 0 and string.format("  |cff33ff99+%.0f%%|r", pct) or string.format("  |cffff6060%.0f%%|r", pct)
          else
            up = "  |cff33ff99new|r"
          end
        end
        r.info:SetText(string.format("|cff999999ilvl|r %d  |cff999999req|r %d  |cffffd100%s|r%s", rec.il or 0, rec.rl or 0, fmt(t.score), up))
        r.src:SetText(src.text)
        cursor.y = cursor.y - 38
      end
      cursor.y = cursor.y - (folded and 2 or 8)
    end
  end
  if not any then
    if BF.IsScanning() then
      addLine("|cffbbbbbbReading the items for this class. The list fills in as they come in.|r", 8)
    else
      addLine("|cffbbbbbbNothing to show. Try ticking more sources.|r", 8)
    end
  end
  content:SetHeight(math.max(-cursor.y, 10))
  BF.DrawStatus()
end

function BF.DrawStatus()
  local p = BF.progress
  if BF.IsScanning() then
    local pct = p.total > 0 and math.floor(p.done / p.total * 100) or 0
    f.status:SetText(string.format("Reading items: %d / %d (%d%%)", p.done, p.total, pct))
    f.progress:SetWidth(math.max(1, (f:GetWidth() - 28) * pct / 100)); f.progress:Show()
  else
    f.progress:Hide()
    if BF.cdb.view == "plan" then
      f.status:SetText("Click an item to remove it. Done: worn or in your bags or bank.")
    elseif BF.IsOwnClass() then
      f.status:SetText("Click an item to add it to your plan. Shift-click: link in chat. Ctrl-click: try on.")
    else
      f.status:SetText("Shift-click: link in chat. Ctrl-click: try on.")
    end
  end
end

-- the plan: one numbered step per dungeon run / quest / craft / reputation / vendor, biggest upgrade first
function BF.DrawPlan(idx, specName)
  local steps, done = BF.Plan(BF.cdb.mode, idx)
  local function itemRow(id, info, sub, slotKey, dim)
    local r = nextRow()
    local rec = BF.db.items[id] or {}
    r.id, r.score, r.srcText, r.slotKey, r.picked = id, nil, BF.Source(id, BF.db.items[id]).text, slotKey, true
    fillRow(r, rec, 24, cursor.y, nil)
    r.icon:SetDesaturated(dim and true or false)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[rec.q or 1]
    r.name:SetText((dim and "|cff808080" or (c and c.hex or "|cffffffff")) .. (rec.n or ("Item " .. id)) .. "|r")
    r.info:SetText(info or ""); r.src:SetText(sub or "")
    r.check:SetShown(dim and true or false)
    cursor.y = cursor.y - 38
  end
  if #steps == 0 and #done == 0 then
    addBar("Your plan is empty")
    addLine("|cffbbbbbbOpen \"Best items\" and click the items you want. They are put in order here: the biggest upgrade " ..
      "first, with the dungeon, quest, craft or vendor for each.|r", 10)
  end
  for i, st in ipairs(steps) do
    addBar(string.format("|cffffffff%d.|r %s", i, st.label),
      st.gain > 0 and string.format("|cff33ff99+%.1f|r", st.gain) or "|cff999999no upgrade|r")
    for _, it in ipairs(st.items) do
      local slotName = ""
      for _, sd in ipairs(BF.SLOTS) do if sd.key == it.slotKey then slotName = sd.name end end
      local gain = it.gain > 0 and string.format("|cff33ff99+%.1f|r", it.gain) or "|cff999999no upgrade|r"
      local slots = (it.slotKey == "FINGER" or it.slotKey == "TRINKET") and 2 or 1
      local choice = (it.of or 1) > slots and string.format(" |cffffd100(choice %d of %d)|r", it.choice, it.of) or ""
      itemRow(it.id, gain, slotName .. choice .. ((it.what and it.what ~= "") and ("  -  " .. it.what) or ""), it.slotKey, false)
    end
    cursor.y = cursor.y - 6
  end
  if #done > 0 then
    addBar("|cff999999Done (worn or in your bags or bank)|r")
    for _, id in ipairs(done) do
      local slotKey
      for k, list in pairs(BF.cdb.picks[specName] or {}) do for _, p in ipairs(list) do if p == id then slotKey = k end end end
      itemRow(id, "|cff999999done|r", "", slotKey, true)
    end
  end
  content:SetHeight(math.max(-cursor.y, 10))
  BF.DrawStatus()
end

local function redrawSoon()
  if GetTime() - lastDraw > 2 then BF.Draw() end
end

local function startScan()
  BF.Scan(function() redrawSoon() end, function() BF.Draw() end)
end

---------------------------------------------------------------------------------------------------------------------
-- Stat weight editor
---------------------------------------------------------------------------------------------------------------------
local function customKey()
  local _, name = BF.BaseWeights(BF.SpecIndex(), BF.cdb.mode)
  return BF.CustomKey(name), name
end

local function showEditor()
  if not editor then
    editor = CreateFrame("Frame", "BiSFinderWeights", UIParent, "BasicFrameTemplateWithInset")
    editor:SetSize(560, 560); editor:SetPoint("LEFT", f, "RIGHT", 4, 0)
    editor:SetMovable(true); editor:EnableMouse(true); editor:RegisterForDrag("LeftButton")
    editor:SetScript("OnDragStart", editor.StartMoving); editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
    editor:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "BiSFinderWeights")
    if editor.CloseButton then editor.CloseButton:SetScript("OnClick", function() editor:Hide() end) end
    editor.title = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    editor.title:SetPoint("TOP", 0, -5)
    local d = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", 14, -30); d:SetWidth(530); d:SetJustifyH("LEFT")
    d:SetText("Points for each stat (hit, crit and haste per 1%). Grey = default. Type a number to change it, leave it empty for the default.")
    editor.boxes = {}
    for i, st in ipairs(STAT_LABELS) do
      local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
      local x, y = 14 + col * 272, -64 - row * 25
      local l = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      l:SetPoint("TOPLEFT", x, y - 4); l:SetText(st[2])
      local base = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      base:SetPoint("TOPLEFT", x + 150, y - 4)
      local eb = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
      eb:SetSize(55, 20); eb:SetPoint("TOPLEFT", x + 195, y); eb:SetAutoFocus(false); eb:SetMaxLetters(8)
      local function save(self)
        local key = customKey()
        local v = tonumber(((self:GetText() or ""):gsub(",", ".")))
        BF.cdb.custom[key] = BF.cdb.custom[key] or {}
        BF.cdb.custom[key][st[1]] = v
        if next(BF.cdb.custom[key]) == nil then BF.cdb.custom[key] = nil end
        BF.Draw()
      end
      eb:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
      eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
      eb:SetScript("OnEditFocusLost", save)
      editor.boxes[st[1]] = { eb = eb, base = base }
    end
    local reset = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    reset:SetSize(200, 24); reset:SetPoint("BOTTOM", 0, 12)
    reset:SetText("Reset to defaults")
    reset:SetScript("OnClick", function()
      BF.cdb.custom[customKey()] = nil
      editor:Refresh(); BF.Draw()
    end)
    function editor:Refresh()
      local base = BF.BaseWeights(BF.SpecIndex(), BF.cdb.mode)
      local key, name = customKey()
      local own = BF.cdb.custom[key] or {}
      self.title:SetText("Stat weights - " .. className(BF.ViewClass()) .. " " .. name .. " - "
        .. (BF.cdb.mode == "endgame" and "Endgame" or "Now"))
      for k, b in pairs(self.boxes) do
        b.base:SetText(base[k] and base[k] ~= 0 and fmt(base[k]) or "-")
        b.eb:SetText(own[k] and tostring(own[k]) or "")
      end
    end
  end
  editor:Refresh()
  editor:Show()
end

local function refreshEditor() if editor and editor:IsShown() then editor:Refresh() end end

---------------------------------------------------------------------------------------------------------------------
-- Source filter panel (opens under the "Sources" button)
---------------------------------------------------------------------------------------------------------------------
local function buildPanel()
  panel = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetFrameStrata("DIALOG")
  panel:SetPoint("TOPLEFT", f.filterButton, "BOTTOMLEFT", 0, -2)
  panel:EnableMouse(true)
  backdrop(panel)
  local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); t:SetPoint("TOPLEFT", 12, -10)
  t:SetText("Show items from")
  local y = -30
  for i, d in ipairs(FILTERS) do
    local col = (i - 1) % 2
    if col == 0 and i > 1 then y = y - 24 end
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 10 + col * 190, y)
    local l = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); l:SetPoint("LEFT", cb, "RIGHT", 2, 1); l:SetText(d[2])
    cb.label = l
    cb:SetScript("OnClick", function(self) BF.cdb.filters[d[1]] = self:GetChecked() and true or false; BF.Draw() end)
    filterChecks[d[1]] = cb
  end
  y = y - 32
  local hf = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  hf:SetSize(24, 24); hf:SetPoint("TOPLEFT", 10, y)
  local hl = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); hl:SetPoint("LEFT", hf, "RIGHT", 2, 1)
  hl:SetText("Hide items only the other faction can get")
  hf:SetScript("OnClick", function(self) BF.cdb.hideFaction = self:GetChecked() and true or false; BF.Draw() end)
  filterChecks.hideFaction = hf
  local all = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  all:SetSize(110, 20); all:SetPoint("BOTTOMLEFT", 12, 10); all:SetText("Default")
  all:SetScript("OnClick", function()
    for _, d in ipairs(FILTERS) do BF.cdb.filters[d[1]] = not (d[1] == "classic" or d[1] == "unknown") end
    BF.Draw()
  end)
  local close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  close:SetSize(80, 20); close:SetPoint("BOTTOMRIGHT", -12, 10); close:SetText("Done")
  close:SetScript("OnClick", function() panel:Hide() end)
  panel:SetSize(400, -y + 62)
  panel:Hide()
end

---------------------------------------------------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------------------------------------------------
local function button(parent, w, h, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h); b:SetText(text); b:SetScript("OnClick", onClick)
  return b
end

local function build()
  f = CreateFrame("Frame", "BiSFinderFrame", UIParent, "BasicFrameTemplateWithInset")
  local size = BF.cdb.size
  f:SetSize(size and size[1] or FRAME_W, size and size[2] or FRAME_H)
  CW = f:GetWidth() - X0 - 40
  local pos = BF.cdb.pos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    BF.cdb.pos = { p, rp, x, y }   -- the window opens where it was left
  end)
  f:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "BiSFinderFrame")
  -- the template's X goes through HideUIPanel, which does nothing for this window: hide it ourselves
  if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.title:SetPoint("TOP", 0, -5)

  -- class bar on the left
  local side = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  side:SetPoint("TOPLEFT", 6, -26); side:SetPoint("BOTTOMLEFT", 6, 6); side:SetWidth(SIDE)
  side:SetColorTexture(0, 0, 0, 0.35)
  local me = BF.PlayerClass()
  for i, cls in ipairs(BF.CLASSES) do
    if BF.GEAR_WEIGHTS and BF.GEAR_WEIGHTS[cls] then
      local cb = CreateFrame("Button", nil, f)
      cb:SetSize(44, 44); cb:SetPoint("TOP", side, "TOP", 0, -10 - (#classButtons) * 52)
      cb.cls = cls
      cb.ring = cb:CreateTexture(nil, "BACKGROUND"); cb.ring:SetPoint("TOPLEFT", -2, 2); cb.ring:SetPoint("BOTTOMRIGHT", 2, -2)
      cb.icon = cb:CreateTexture(nil, "ARTWORK"); cb.icon:SetAllPoints(); cb.icon:SetTexture(classIcon(cls)); trim(cb.icon)
      local hl = cb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.15)
      if cls == me then
        local you = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        you:SetPoint("TOP", cb, "BOTTOM", 0, -1); you:SetText("you")
      end
      cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(hex(classColor(cls)) .. className(cls) .. "|r")
        if cls == me then GameTooltip:AddLine("Your class", 1, 1, 1) end
        GameTooltip:Show()
      end)
      cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
      cb:SetScript("OnClick", function()
        BF.SetViewClass(cls)
        refreshEditor()
        startScan()
        BF.Draw()
      end)
      classButtons[#classButtons + 1] = cb
    end
  end

  -- header: class icon and name, line under it
  f.classIcon = f:CreateTexture(nil, "ARTWORK"); f.classIcon:SetSize(40, 40); f.classIcon:SetPoint("TOPLEFT", X0, -32)
  f.className = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.className:SetPoint("TOPLEFT", f.classIcon, "TOPRIGHT", 10, -1)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("BOTTOMLEFT", f.classIcon, "BOTTOMRIGHT", 10, 2)

  f.viewButtons = {}
  f.viewButtons.plan = button(f, 120, 24, "My plan", function() BF.cdb.view = "plan"; BF.Draw() end)
  f.viewButtons.plan:SetPoint("TOPRIGHT", -16, -32)
  f.viewButtons.list = button(f, 120, 24, "Best items", function() BF.cdb.view = "list"; BF.Draw() end)
  f.viewButtons.list:SetPoint("RIGHT", f.viewButtons.plan, "LEFT", -4, 0)
  local wb = button(f, 120, 22, "Stat weights", function()
    if editor and editor:IsShown() then editor:Hide() else showEditor() end
  end)
  wb:SetPoint("TOPRIGHT", f.viewButtons.plan, "BOTTOMRIGHT", 0, -4)

  -- talent trees
  for i = 1, 4 do
    local sb = CreateFrame("Button", nil, f)
    sb:SetSize(158, 34)
    sb:SetPoint("TOPLEFT", X0 + (i - 1) * 164, -82)
    sb.bg = sb:CreateTexture(nil, "BACKGROUND"); sb.bg:SetAllPoints()
    sb.icon = sb:CreateTexture(nil, "ARTWORK"); sb.icon:SetSize(26, 26); sb.icon:SetPoint("LEFT", 5, 0)
    sb.text = sb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); sb.text:SetPoint("LEFT", sb.icon, "RIGHT", 7, 0)
    sb.text:SetPoint("RIGHT", -4, 0); sb.text:SetJustifyH("LEFT")
    sb.under = sb:CreateTexture(nil, "OVERLAY"); sb.under:SetPoint("BOTTOMLEFT"); sb.under:SetPoint("BOTTOMRIGHT"); sb.under:SetHeight(2)
    local hl = sb:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.08)
    sb:SetScript("OnClick", function() BF.SetSpec(i); refreshEditor(); BF.Draw() end)
    specButtons[i] = sb
  end

  -- second row: Now / Endgame, items per slot, sources
  local function tab(key, text, anchor)
    local b = button(f, 140, 24, text, function() BF.cdb.mode = key; refreshEditor(); BF.Draw() end)
    tabButtons[key] = b
    return b
  end
  tab("now", "Now"):SetPoint("TOPLEFT", X0, -126)
  tab("endgame", "Endgame (level 60)"):SetPoint("LEFT", tabButtons.now, "RIGHT", 4, 0)

  local nl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nl:SetPoint("LEFT", tabButtons.endgame, "RIGHT", 20, 0); nl:SetText("Items per slot:")
  local minus = button(f, 22, 22, "-", function() BF.cdb.topN = math.max(1, BF.TopN() - 1); BF.Draw() end)
  minus:SetPoint("LEFT", nl, "RIGHT", 6, 0)
  f.topN = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); f.topN:SetPoint("LEFT", minus, "RIGHT", 2, 0); f.topN:SetWidth(22)
  local plus = button(f, 22, 22, "+", function() BF.cdb.topN = math.min(10, BF.TopN() + 1); BF.Draw() end)
  plus:SetPoint("LEFT", f.topN, "RIGHT", 2, 0)

  f.filterButton = button(f, 150, 24, "Sources", function()
    if not panel then buildPanel(); updateControls() end
    panel:SetShown(not panel:IsShown())
  end)
  f.filterButton:SetPoint("LEFT", plus, "RIGHT", 20, 0)

  f.headLine = f:CreateTexture(nil, "ARTWORK")
  f.headLine:SetPoint("TOPLEFT", X0, -158); f.headLine:SetPoint("TOPRIGHT", -16, -158); f.headLine:SetHeight(1)

  -- list
  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", X0 - 4, -164); sf:SetPoint("BOTTOMRIGHT", -32, 30)
  content = CreateFrame("Frame", nil, sf); content:SetSize(CW, 10)
  sf:SetScrollChild(content)
  rows, lines, bars = {}, {}, {}

  -- bottom: help text and the reading progress
  f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.status:SetPoint("BOTTOMLEFT", X0, 12)
  f.progress = f:CreateTexture(nil, "ARTWORK"); f.progress:SetPoint("BOTTOMLEFT", 14, 6); f.progress:SetHeight(2)
  f.progress:SetColorTexture(0.2, 0.8, 0.4, 0.9); f.progress:Hide()
  f.clearPlan = button(f, 100, 20, "Clear plan", function()
    if f.specName then BF.ClearPicks(f.specName) end
    BF.Draw()
  end)
  f.clearPlan:SetPoint("BOTTOMRIGHT", -40, 6)

  -- resizing: drag the bottom right corner
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H); f:SetMaxResize(MAX_W, MAX_H) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local w, h = f:GetSize()
    BF.cdb.size = { math.floor(w + 0.5), math.floor(h + 0.5) }
    local p, _, rp, x, y = f:GetPoint()
    BF.cdb.pos = { p, rp, x, y }
    BF.Draw()
  end)
  local sizePending
  f:SetScript("OnSizeChanged", function(self, w)
    CW = (w or self:GetWidth()) - X0 - 40
    content:SetWidth(CW)
    if not sizePending then   -- redraw at most 10 times a second while dragging
      sizePending = true
      C_Timer.After(0.1, function() sizePending = false; BF.Draw() end)
    end
  end)

  f:SetScript("OnShow", function() BF.Draw() end)
  f:SetScript("OnHide", function() if panel then panel:Hide() end end)
end

function BF.Open(view)
  if not f then build(); f:Hide() end
  if view then BF.cdb.view = view end
  if view == "plan" then BF.SetViewClass(BF.PlayerClass()) end
  if f:IsShown() then BF.Draw() else f:Show() end
  if not BF.IsScanning() then startScan() end
end

function BF.Toggle()
  if not f then build(); f:Hide() end   -- a new frame starts shown: hide it so the first /bis opens it
  if f:IsShown() then f:Hide(); return end
  f:Show()
  if not BF.IsScanning() then startScan() end
end
