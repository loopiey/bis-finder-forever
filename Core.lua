-- BiSFinder core: which items exist and where they come from (Data/Sources.lua), their stats (asked from the game and
-- kept in BiSFinderDB), the stat weights of a talent tree (Data/Weights.lua), the best items per slot, sets and the plan.
local ADDON, BF = ...
BF.VERSION = "1.0.0"

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local RequestLoad = C_Item and C_Item.RequestLoadItemDataByID

function BF.say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99BiSFinder|r: " .. tostring(msg)) end

---------------------------------------------------------------------------------------------------------------------
-- What each class can wear (mail / plate from level 40)
---------------------------------------------------------------------------------------------------------------------
local ARMOR_MAX = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }
local RELIC = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }   -- libram, idol, totem
-- weapon subclasses: 0 1H axe, 1 2H axe, 2 bow, 3 gun, 4 1H mace, 5 2H mace, 6 polearm, 7 1H sword, 8 2H sword,
-- 10 staff, 13 fist, 15 dagger, 16 thrown, 18 crossbow, 19 wand
local function set(...) local t = {}; for _, v in ipairs({ ... }) do t[v] = true end; return t end
local WEAPONS = {
  WARRIOR = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18),
  PALADIN = set(0, 1, 4, 5, 6, 7, 8),
  HUNTER  = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18),
  ROGUE   = set(2, 3, 4, 7, 13, 15, 16, 18),
  PRIEST  = set(4, 10, 15, 19),
  SHAMAN  = set(0, 1, 4, 5, 10, 13, 15),
  MAGE    = set(7, 10, 15, 19),
  WARLOCK = set(7, 10, 15, 19),
  DRUID   = set(4, 5, 10, 13, 15),
}

-- Rows of the window. inv = inventory slots to compare against; score = the slot the weights treat it as.
BF.SLOTS = {
  { key = "HEAD",     name = "Head",      locs = set("INVTYPE_HEAD"), inv = { 1 } },
  { key = "NECK",     name = "Neck",      locs = set("INVTYPE_NECK"), inv = { 2 } },
  { key = "SHOULDER", name = "Shoulder",  locs = set("INVTYPE_SHOULDER"), inv = { 3 } },
  { key = "BACK",     name = "Back",      locs = set("INVTYPE_CLOAK"), inv = { 15 } },
  { key = "CHEST",    name = "Chest",     locs = set("INVTYPE_CHEST", "INVTYPE_ROBE"), inv = { 5 } },
  { key = "WRIST",    name = "Wrist",     locs = set("INVTYPE_WRIST"), inv = { 9 } },
  { key = "HANDS",    name = "Hands",     locs = set("INVTYPE_HAND"), inv = { 10 } },
  { key = "WAIST",    name = "Waist",     locs = set("INVTYPE_WAIST"), inv = { 6 } },
  { key = "LEGS",     name = "Legs",      locs = set("INVTYPE_LEGS"), inv = { 7 } },
  { key = "FEET",     name = "Feet",      locs = set("INVTYPE_FEET"), inv = { 8 } },
  { key = "FINGER",   name = "Rings",     locs = set("INVTYPE_FINGER"), inv = { 11, 12 }, pair = true },
  { key = "TRINKET",  name = "Trinkets",  locs = set("INVTYPE_TRINKET"), inv = { 13, 14 }, pair = true },
  { key = "TWOHAND",  name = "Two-Hand",  locs = set("INVTYPE_2HWEAPON"), inv = { 16, 17 }, score = 16, both = true },
  { key = "MAINHAND", name = "Main Hand / One-Hand", locs = set("INVTYPE_WEAPON", "INVTYPE_WEAPONMAINHAND"), inv = { 16 }, score = 16 },
  { key = "OFFHAND",  name = "Off Hand",  locs = set("INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE"), inv = { 17 }, score = 17 },
  { key = "RANGED",   name = "Ranged / Wand / Relic", locs = set("INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC"), inv = { 18 }, score = 18 },
}
local ALL_LOCS = {}
for _, s in ipairs(BF.SLOTS) do for loc in pairs(s.locs) do ALL_LOCS[loc] = true end end


---------------------------------------------------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------------------------------------------------
local db, cdb
-- classic = old drops whose loot tables may have changed, unknown = no known source: both off to start
local DEFAULT_FILTERS = { dungeon = true, raid = true, quest = true, rep = true, crafted = true, vendor = true, bislist = true, pvp = true, classic = false, unknown = false }

local function clientBuild()
  local _, build = GetBuildInfo()
  return tostring(build)
end

function BF.InitDB()
  BiSFinderDB = type(BiSFinderDB) == "table" and BiSFinderDB or {}
  db = BiSFinderDB
  if db.build ~= clientBuild() then   -- a patch can change item stats: ask again
    db.items, db.missing, db.sets, db.build = {}, {}, {}, clientBuild()
  end
  db.items, db.missing = db.items or {}, db.missing or {}
  if (db.scanVersion or 1) < 2 then db.missing, db.scanVersion = {}, 2 end
  if db.scanVersion < 3 then db.items, db.missing, db.scanVersion = {}, {}, 3 end   -- 1.5: items now carry their set
  db.sets = db.sets or {}
  BiSFinderCharDB = type(BiSFinderCharDB) == "table" and BiSFinderCharDB or {}
  cdb = BiSFinderCharDB
  cdb.filters = cdb.filters or {}
  if (cdb.filterVersion or 1) < 2 then cdb.filters, cdb.filterVersion = {}, 2 end   -- 1.3: new source groups
  for k, v in pairs(DEFAULT_FILTERS) do if cdb.filters[k] == nil then cdb.filters[k] = v end end
  if cdb.hideFaction == nil then cdb.hideFaction = true end
  cdb.mode = cdb.mode or "now"
  cdb.custom = cdb.custom or {}
  cdb.picks = cdb.picks or {}       -- [talent tree name] = { [slotKey] = { itemID, ... } }
  cdb.view = cdb.view or "list"
  cdb.topN = cdb.topN or 3          -- items shown per slot (1 - 10)
  cdb.viewSpec = cdb.viewSpec or {} -- [class] = talent tree picked when looking at another class
  db.minimap = db.minimap or { minimapPos = 220 }
  BF.db, BF.cdb = db, cdb
end

---------------------------------------------------------------------------------------------------------------------
-- Talent tree and weights
---------------------------------------------------------------------------------------------------------------------
local function playerClass() local _, c = UnitClass("player"); return c end

-- The window can show any class, not only the one played. The plan and the worn items are for this character only.
BF.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local viewClass   -- nil = the class played (not saved: the window opens on your own class after a reload)
function BF.PlayerClass() return playerClass() end
function BF.ViewClass()
  if viewClass and BF.GEAR_WEIGHTS and BF.GEAR_WEIGHTS[viewClass] then return viewClass end
  return playerClass()
end
function BF.IsOwnClass() return BF.ViewClass() == playerClass() end
function BF.SetViewClass(cls) viewClass = (cls ~= playerClass()) and cls or nil end

-- points per tree from the trait tree: the client's nodes sorted left to right and split at the two widest gaps
-- (the three classic trees stand side by side). nil when that does not look like three trees.
local function pointsFromTraits()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not ok or not configID then return end
  local ci = C_Traits.GetConfigInfo(configID)
  if not ci or not ci.treeIDs then return end
  local nodes = {}
  for _, treeID in ipairs(ci.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local ni = C_Traits.GetNodeInfo(configID, nodeID)
      if ni and ni.posX and ni.isVisible ~= false then
        nodes[#nodes + 1] = { x = ni.posX, r = ni.currentRank or ni.ranksPurchased or 0 }
      end
    end
  end
  if #nodes < 9 then return end
  table.sort(nodes, function(a, b) return a.x < b.x end)
  local gaps, smallest = {}, nil
  for i = 1, #nodes - 1 do
    local d = nodes[i + 1].x - nodes[i].x
    gaps[#gaps + 1] = { d = d, i = i }
    if d > 0 and (not smallest or d < smallest) then smallest = d end
  end
  table.sort(gaps, function(a, b) return a.d > b.d end)
  if not smallest or gaps[2].d <= smallest * 1.5 then return end
  local c1, c2 = math.min(gaps[1].i, gaps[2].i), math.max(gaps[1].i, gaps[2].i)
  local pts = { 0, 0, 0 }
  for i, n in ipairs(nodes) do
    local t = (i <= c1) and 1 or (i <= c2) and 2 or 3
    pts[t] = pts[t] + n.r
  end
  return pts
end

local function pointsFromTabs()
  if not GetTalentTabInfo then return end
  local pts = {}
  for i = 1, 3 do
    local ok, a, _, c, _, e = pcall(GetTalentTabInfo, i)
    if not ok then return end
    pts[i] = (type(a) == "string" and tonumber(c)) or tonumber(e) or 0
  end
  return pts
end

-- the talent tree with the most points (1-3), nil when none can be read or no points are spent. Kept until the
-- talents change (Main.lua calls BF.ClearTreeCache), so drawing the window does not walk the talent tree each time.
local treeCache, ptsCache
function BF.ClearTreeCache() treeCache, ptsCache = nil, nil end
function BF.DetectTree()
  if treeCache then return treeCache, ptsCache end
  local ok, pts = pcall(pointsFromTraits)
  if not ok or not pts then pts = pointsFromTabs() end
  if not pts then return nil end
  local tree, best = nil, 0
  for i = 1, 3 do if (pts[i] or 0) > best then tree, best = i, pts[i] end end
  treeCache, ptsCache = tree, pts   -- nil (no points yet) is not kept: asked again next time
  return tree, pts
end

function BF.Specs()
  local data = BF.GEAR_WEIGHTS and BF.GEAR_WEIGHTS[BF.ViewClass()]
  return data and data.specs or {}
end

-- the spec used: the one picked in the window, else the detected tree (another class: the one picked, else the first)
function BF.SpecIndex()
  local specs = BF.Specs()
  if not BF.IsOwnClass() then
    local i = cdb.viewSpec[BF.ViewClass()]
    return (i and specs[i]) and i or 1, false
  end
  if cdb.spec and specs[cdb.spec] then return cdb.spec, false end
  local tree = BF.DetectTree()
  if tree and specs[tree] then return tree, true end
  return nil, true
end

-- click on a talent tree: your own class toggles between that tree and "follow my talents"
function BF.SetSpec(i)
  if BF.IsOwnClass() then cdb.spec = (cdb.spec == i) and nil or i
  else cdb.viewSpec[BF.ViewClass()] = i end
end

-- where own stat weights are kept: by tree name for your class (as before), "CLASS:tree" for other classes
function BF.CustomKey(name)
  if BF.IsOwnClass() then return name end
  return BF.ViewClass() .. ":" .. name
end

local function curveAt(curve, level)
  local n = #curve
  local a, b = curve[1], curve[n]
  if level <= a[1] then b = a
  elseif level >= b[1] then a = b
  else
    for i = 1, n - 1 do
      if level >= curve[i][1] and level <= curve[i + 1][1] then a, b = curve[i], curve[i + 1]; break end
    end
  end
  local t = (b[1] > a[1]) and ((level - a[1]) / (b[1] - a[1])) or 0
  local out = {}
  for k, v in pairs(a[2]) do out[k] = v end
  for k in pairs(b[2]) do out[k] = out[k] or 0 end
  for k, va in pairs(out) do
    local v = va + ((b[2][k] or 0) - va) * t
    out[k] = (v > 0 and v < 0.02) and 0 or v
  end
  return out
end

-- base weights of a spec for a mode ("now" = at the player's level, "endgame" = level 60), before own changes
function BF.BaseWeights(specIndex, mode)
  local data = BF.GEAR_WEIGHTS and BF.GEAR_WEIGHTS[BF.ViewClass()]
  if not data then return {}, "Leveling" end
  local spec = specIndex and data.specs[specIndex]
  local level = (mode == "endgame") and 60 or (UnitLevel("player") or 1)
  local w = {}
  if spec and level >= 60 then
    for k, v in pairs(spec.raid) do w[k] = v end
  else
    w = curveAt(data.curves[spec and spec.curve or "Leveling"] or data.curves.Leveling, level)
  end
  return w, spec and spec.name or "Leveling"
end

-- weights in use: base, then the player's own changes for that spec (they count in both tabs)
function BF.Weights(specIndex, mode)
  local w, name = BF.BaseWeights(specIndex, mode)
  local own = cdb.custom[BF.CustomKey(name)]
  if own then for k, v in pairs(own) do w[k] = v end end
  -- Forever has one hit and one crit rating for melee and spells
  w.hit = math.max(w.hit or 0, w.shit or 0); w.crit = math.max(w.crit or 0, w.scrit or 0)
  return w, name
end

---------------------------------------------------------------------------------------------------------------------
-- Scoring: stats x weights; ratings are turned into % first, weapon DPS counts by hand, weapon speed adds a bonus
---------------------------------------------------------------------------------------------------------------------
local KEYS, RATING = BF.GEAR_STAT_KEYS or {}, BF.GEAR_RATING or {}
local SPEED_KIND = { twoHand = { 3.3, 2.8, 3.9 }, oneHand = { 2.4, 1.5, 2.9 }, dagger = { 1.7, 1.3, 1.9 }, ranged = { 2.8, 2.0, 3.2 } }

local function speedBonus(W, dpsValue, slot, rec)
  local pct = (slot == 16 and W.spdmh) or (slot == 17 and W.spdoh) or (slot == 18 and W.spdrg)
  if not pct or pct == 0 or dpsValue <= 0 or not rec.sp then return 0 end
  local kind = "ranged"
  if slot ~= 18 then
    kind = (rec.loc == "INVTYPE_2HWEAPON" and "twoHand") or (rec.c == 2 and rec.sc == 15 and "dagger") or "oneHand"
  end
  local k = SPEED_KIND[kind]
  return dpsValue * pct / 100 * (math.min(math.max(rec.sp, k[2]), k[3]) - k[1])
end

function BF.Score(W, stats, slot, rec)
  local total, dpsValue = 0, 0
  local isWand = rec and rec.c == 2 and rec.sc == 19
  for k, v in pairs(stats) do
    local s = KEYS[k]
    if s and type(v) == "number" then
      local wk = s
      if s == "dps" then
        if slot == 17 and W.dpsoh then wk = "dpsoh"
        elseif (slot == 16 or slot == 17) and W.dpsmelee then wk = "dpsmelee"
        elseif isWand and W.dpswand then wk = "dpswand" end
      end
      local w = W[wk] or 0
      if s == "hit" or s == "shit" then w = math.max(W.hit or 0, W.shit or 0)
      elseif s == "crit" or s == "scrit" then w = math.max(W.crit or 0, W.scrit or 0) end
      if k == "ITEM_MOD_SPELL_POWER_SHORT" then w = math.max(w, W.heal or 0) end
      if w > 0 then
        local val = RATING[s] and v / RATING[s] or v
        if slot == 17 and s == "dps" and wk ~= "dpsoh" then val = val * 0.5 end
        total = total + val * w
        if s == "dps" then dpsValue = dpsValue + val * w end
      end
    end
  end
  if rec and rec.sp then
    local wsp = (slot == 16 and W.speed) or (slot == 17 and W.speedoh) or 0
    if wsp ~= 0 and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT then
      total = total + (wsp > 0 and rec.sp * wsp or -wsp * math.max(0, 4 - rec.sp))
    end
    total = total + speedBonus(W, dpsValue, slot, rec)
  end
  return total
end

---------------------------------------------------------------------------------------------------------------------
-- Set bonuses: the plain stats in a bonus text count, procs and spell changes do not
---------------------------------------------------------------------------------------------------------------------
local STAT_WORDS = { Stamina = "sta", Strength = "str", Agility = "agi", Intellect = "int", Spirit = "spi",
  ["Attack Power"] = "ap", ["Ranged Attack Power"] = "rap", Armor = "armor", ["Defense"] = "def", ["Spell Power"] = "sp",
  ["Healing"] = "heal", ["Block Value"] = "bv" }
local SCHOOLS = { Arcane = "arcane", Fire = "fire", Frost = "frost", Holy = "holy", Nature = "nature", Shadow = "shadow" }
local pctCache = {}
-- { key = value } (keys as in Data/Weights.lua; crit / hit / haste / dodge / parry / block in %), or nil when nothing counts
function BF.ParseBonus(text)
  if pctCache[text] ~= nil then return pctCache[text] or nil end
  local t, out = text:gsub("%.$", ""), {}
  local function put(k, v) out[k] = (out[k] or 0) + v end
  local v = t:match("[Ii]ncreases damage and healing done by magical spells and effects by up to (%d+)")
  if v then put("sp", tonumber(v)) end
  local h, d = t:match("[Ii]ncreases healing done by up to (%d+) and damage done by up to (%d+)")
  if h then put("heal", tonumber(h)); put("sp", tonumber(d))
  else
    h = t:match("[Ii]ncreases healing done by spells and effects by up to (%d+)") or t:match("[Ii]ncreases healing done by up to (%d+)")
    if h then put("heal", tonumber(h)) end
  end
  local school, sd = t:match("[Ii]ncreases damage done by (%a+) spells and effects by up to (%d+)")
  if school and SCHOOLS[school] then put(SCHOOLS[school], tonumber(sd)) end
  local mp = t:match("(%d+) mana per 5 sec") or t:match("[Rr]estores (%d+) mana per 5")
  if mp then put("mp5", tonumber(mp)) end
  local hp = t:match("(%d+) health per 5 sec")
  if hp then put("hp5", tonumber(hp)) end
  local c = t:match("critical strike[%a ]* by ([%d%.]+)%%")
  if c then put("crit", tonumber(c)) end
  local hit = t:match("chance to hit[%a ]* by ([%d%.]+)%%")
  if hit then put("hit", tonumber(hit)) end
  local hs = t:match("[Ii]ncreases your attack and casting speed by ([%d%.]+)%%") or t:match("speed by ([%d%.]+)%%")
  if hs then put("haste", tonumber(hs)) end
  local def = t:match("Increased Defense %+(%d+)") or t:match("Defense skill by (%d+)")
  if def then put("def", tonumber(def)) end
  if not t:find(" against ", 1, true) then
    local n, word = t:match("^%+(%d+) (%a[%a ]*)$")
    if n and STAT_WORDS[word] then put(STAT_WORDS[word], tonumber(n)) end
  end
  local any = next(out) ~= nil
  pctCache[text] = any and out or false
  return any and out or nil
end
local PCT = { crit = true, hit = true, haste = true, dodge = true, parry = true, block = true, exp = true }
local function bonusValue(W, stats)
  local v = 0
  for k, n in pairs(stats) do
    local w = W[k] or 0
    if k == "sp" then w = math.max(w, W.heal or 0) end
    v = v + n * w   -- % stats: the weights are per 1 % already
  end
  return v
end

-- For every set: wear how many pieces? Each piece costs (best other item in that slot - the piece); the bonuses
-- reached pay back. all = { [slotKey] = { [itemID] = score } } of everything that passed (BF.Rank).
local function evaluateSets(W, all)
  local bySet = {}
  for slotKey, list in pairs(all) do
    for id, sc in pairs(list) do
      local rec = db.items[id]
      if rec and rec.set then
        local e = bySet[rec.set] or {}; bySet[rec.set] = e
        if not e[slotKey] or e[slotKey].score < sc then e[slotKey] = { id = id, score = sc } end
      end
    end
  end
  local out = {}
  for setID, pieces in pairs(bySet) do
    local info = db.sets[setID]
    if info then
      local deltas = {}
      for slotKey, p in pairs(pieces) do
        local best = 0
        for oid, osc in pairs(all[slotKey]) do
          local orec = db.items[oid]
          if osc > best and not (orec and orec.set == setID) then best = osc end
        end
        deltas[#deltas + 1] = { slot = slotKey, id = p.id, d = p.score - best }
      end
      table.sort(deltas, function(a, b) return a.d > b.d end)
      local bestK, bestNet, sum = 0, 0, 0
      local reach = {}
      for k = 1, #deltas do
        sum = sum + deltas[k].d
        local bonus = 0
        for _, b in ipairs(info.b) do
          if b[1] <= k then local st = BF.ParseBonus(b[2]); if st then bonus = bonus + bonusValue(W, st) end end
        end
        reach[k] = bonus
        if k >= 2 and sum + bonus > bestNet + 0.05 then bestK, bestNet = k, sum + bonus end
      end
      local maxPieces = #deltas
      local counted, uncounted = {}, {}
      for _, b in ipairs(info.b) do
        local line = "(" .. b[1] .. ") " .. b[2]
        if BF.ParseBonus(b[2]) and bonusValue(W, BF.ParseBonus(b[2])) > 0 then counted[#counted + 1] = line else uncounted[#uncounted + 1] = line end
      end
      local used = {}
      for k = 1, bestK do used[#used + 1] = deltas[k] end
      -- the gain of going for the set: pieces that are the best in their slot anyway would be worn without it
      local anyway = 0
      for _, d in ipairs(deltas) do if d.d > 0 then anyway = anyway + d.d end end
      local gain = bestK >= 2 and (bestNet - anyway) or 0
      if gain <= 0.05 then bestK, gain = 0, math.min(gain, 0) end   -- the set does not pay: wear the best single items
      out[#out + 1] = { id = setID, name = info.n, k = bestK, net = bestNet, gain = gain, pieces = used, available = maxPieces,
        bonus = reach[bestK] or 0, counted = counted, uncounted = uncounted, deltas = deltas }
    end
  end
  table.sort(out, function(a, b) return a.gain > b.gain end)
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- Reading one item from the game
---------------------------------------------------------------------------------------------------------------------
local classPat
local function toPattern(fmt, default)
  fmt = type(fmt) == "string" and fmt or default
  local p = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%d", "(%%d+)"):gsub("%%s", "(.+)")
  return "^" .. p .. "$"
end
local setBonusPat, setNamePat
local function clean(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- weapon speed, "Classes:" list, and for set items: set name and { { pieces, "bonus text" }, ... } as the game shows them
local function tooltipFacts(id, isWeapon, wantSet)
  local data = C_TooltipInfo and C_TooltipInfo.GetItemByID and C_TooltipInfo.GetItemByID(id)
  if not (data and data.lines) then return nil, nil end
  classPat = classPat or ("^" .. (type(ITEM_CLASSES_ALLOWED) == "string" and ITEM_CLASSES_ALLOWED or "Classes: %s")
    :gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", "(.+)") .. "$")
  setBonusPat = setBonusPat or toPattern(ITEM_SET_BONUS_GRAY, "(%d) Set: %s")
  setNamePat = setNamePat or toPattern(ITEM_SET_NAME, "%s (%d/%d)")
  local speed, classes, setName, bonuses
  for _, line in ipairs(data.lines) do
    local left = clean(line.leftText)
    local list = left:match(classPat)
    if list then classes = list end
    if isWeapon and not speed then
      local right = line.rightText or ""
      local v = right:match("(%d+[%.,]%d+)")
      if v and right:find(SPEED or "Speed", 1, true) then speed = tonumber((v:gsub(",", "."))) end
    end
    if wantSet then
      local n, text = left:match(setBonusPat)
      if n then bonuses = bonuses or {}; bonuses[#bonuses + 1] = { tonumber(n), text }
      elseif not setName then
        local sn = left:match(setNamePat)
        if sn then setName = sn end
      end
    end
  end
  return speed, classes, setName, bonuses
end

local function readItem(id)
  local name, link, quality, ilvl, reqLevel, _, _, _, loc, icon, _, classID, subID, bindType, _, setID = GetItemInfo(id)
  if not name then return nil end
  local stats = GetItemStats and GetItemStats(link) or {}
  local s = {}
  for k, v in pairs(stats) do if KEYS[k] and type(v) == "number" then s[k] = v end end
  local hasSet = type(setID) == "number" and setID > 0
  local speed, classes, setName, bonuses = tooltipFacts(id, classID == 2, hasSet)
  if hasSet and bonuses and db and not db.sets[setID] then db.sets[setID] = { n = setName or ("Set " .. setID), b = bonuses } end
  return { n = name, q = quality, il = ilvl, rl = reqLevel, loc = loc, ic = icon, c = classID, sc = subID, b = bindType,
           s = s, sp = speed, cl = classes, set = hasSet and setID or nil }
end

---------------------------------------------------------------------------------------------------------------------
-- Which items to look at: everything in Data/Sources.lua that this class could wear
---------------------------------------------------------------------------------------------------------------------
local candidatesBy = {}   -- [class] = list of item IDs that class could wear
local candidates          -- the list of the class shown
local function canEverWear(cls, classID, subID, loc)
  if not ALL_LOCS[loc] then return false end
  if classID == 4 then
    if loc == "INVTYPE_SHIELD" then return SHIELD[cls] == true end
    if loc == "INVTYPE_RELIC" then return RELIC[subID] == cls end
    if subID >= 1 and subID <= 4 and loc ~= "INVTYPE_CLOAK" then return subID <= (ARMOR_MAX[cls] or 1) end
    return true
  elseif classID == 2 then
    return WEAPONS[cls] and WEAPONS[cls][subID] or false
  end
  return false
end

function BF.BuildCandidates(onDone)
  local cls = BF.ViewClass()
  if candidatesBy[cls] then candidates = candidatesBy[cls]; onDone(#candidates, candidates); return end
  local ids = {}
  for _, list in ipairs({ BF.SRC or {}, BF.OLD or {}, BF.UNKNOWN or {} }) do
    for id in pairs(list) do ids[#ids + 1] = id end
  end
  table.sort(ids)
  local list = {}
  local k = 1
  local function filter()
    local stop = math.min(k + 1500, #ids)
    for j = k, stop do
      local id = ids[j]
      local _, _, _, loc, _, classID, subID = GetItemInfoInstant(id)
      if loc and (classID == 2 or classID == 4) and canEverWear(cls, classID, subID, loc) then
        list[#list + 1] = id
      end
    end
    k = stop + 1
    if k <= #ids then C_Timer.After(0, filter)
    else
      candidatesBy[cls] = list
      BF.dataVersion = BF.dataVersion + 1
      if BF.ViewClass() == cls then candidates = list end
      onDone(#list, list)
    end
  end
  filter()
end

---------------------------------------------------------------------------------------------------------------------
-- Asking the game for the items (throttled; results are kept, so later opens are instant)
---------------------------------------------------------------------------------------------------------------------
-- BF.dataVersion goes up whenever item data changes, so the window knows when it has to rank again.
BF.dataVersion = 0
-- At most IN_FLIGHT items are asked at once; one that has not come after WAIT seconds goes to the back of the queue,
-- up to ROUNDS times. Only an item the server says does not exist (GET_ITEM_INFO_RECEIVED with success = false) is
-- remembered as missing; a slow answer is never taken as "missing" (1.2: that hid items such as Truefaith Vestments).
local scanning, queue, qpos = false, nil, 1
-- 10 at a time every 0.2 s: at most 50 requests a second, gentle on the game and the server
local IN_FLIGHT, TICK, WAIT, ROUNDS = 10, 0.2, 20, 4
local rounds, notFound = {}, {}   -- this session: times re-queued; items that never came
BF.progress = { done = 0, total = 0 }
BF.notFound = notFound

local evf = CreateFrame("Frame")
evf:RegisterEvent("GET_ITEM_INFO_RECEIVED")
evf:SetScript("OnEvent", function(_, _, id, success)
  if success == false and type(id) == "number" and db then db.missing[id] = true end
end)

local again   -- the class shown changed during a scan: scan again when it ends
function BF.Scan(onProgress, onDone)
  if scanning then again = { onProgress, onDone }; return end
  local function start(list)
    queue, qpos, scanning = {}, 1, true
    for _, id in ipairs(list) do
      if not db.items[id] and not db.missing[id] and not notFound[id] then queue[#queue + 1] = id end
    end
    BF.progress.total = #list
    BF.progress.done = #list - #queue
    local waiting, inFlight = {}, 0   -- waiting[id] = time asked
    local function tick()
      local now = GetTime()
      for id, t in pairs(waiting) do
        local rec = readItem(id)
        if rec then
          db.items[id], waiting[id], inFlight = rec, nil, inFlight - 1
          BF.progress.done = BF.progress.done + 1
          BF.dataVersion = BF.dataVersion + 1
        elseif db.missing[id] then
          waiting[id], inFlight = nil, inFlight - 1
          BF.progress.done = BF.progress.done + 1
        elseif now - t > WAIT then
          waiting[id], inFlight = nil, inFlight - 1
          rounds[id] = (rounds[id] or 0) + 1
          if rounds[id] < ROUNDS then queue[#queue + 1] = id
          else notFound[id] = true; BF.progress.done = BF.progress.done + 1 end
        end
      end
      while qpos <= #queue and inFlight < IN_FLIGHT do
        local id = queue[qpos]; qpos = qpos + 1
        local rec = readItem(id)
        if rec then
          db.items[id] = rec
          BF.progress.done = BF.progress.done + 1
          BF.dataVersion = BF.dataVersion + 1
        elseif not db.missing[id] then
          if RequestLoad then pcall(RequestLoad, id) end
          waiting[id] = now
          inFlight = inFlight + 1
        end
      end
      if onProgress then onProgress(BF.progress.done, BF.progress.total) end
      if qpos > #queue and next(waiting) == nil then
        scanning = false
        if onDone then onDone() end
        if again then local a = again; again = nil; BF.Scan(a[1], a[2]) end
        return
      end
      C_Timer.After(TICK, tick)
    end
    tick()
  end
  scanning = true   -- also while the item list of the class is being built
  BF.BuildCandidates(function(_, list) start(list) end)
end
function BF.IsScanning() return scanning end
-- the item list of the class shown is ready (else it is built on the next scan)
function BF.HasCandidates()
  candidates = candidatesBy[BF.ViewClass()]
  return candidates ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Where an item comes from
---------------------------------------------------------------------------------------------------------------------
local srcCache = {}
local function myFactionNow() return UnitFactionGroup("player") end

-- The raids: Onyxia's Lair, Hyjal Summit and Barrow Deeps open on 9 December 2026, 00:00 UTC. Until then their loot
-- (and quests that need them) stay hidden; from then on they show by themselves.
local RAIDS_OPEN_AT = 1796774400
function BF.RaidsOpen()
  local now = GetServerTime and GetServerTime()
  return type(now) == "number" and now >= RAIDS_OPEN_AT
end
local CAT = { q = "quest", c = "crafted", r = "rep", s = "rep", d = "dungeon", l = "bislist", R = "raid", v = "vendor", p = "pvp" }

-- { cats = { dungeon = true, ... }, text = "...", other = only the other faction can get it, closed = raid not open yet,
-- groups = { { key = "Dungeon: X", what = "Boss" }, ... } for the plan }
function BF.Source(id, rec)
  local s = srcCache[id]
  if s then return s end
  s = { cats = {}, groups = {} }
  local texts = {}
  local mySide = myFactionNow() == "Alliance" and "A" or "H"
  local mine, other, closed = 0, 0, 0
  local raidItem = false
  for _, e in ipairs(BF.SRC and BF.SRC[id] or {}) do if e:sub(1, 2) == "R|" then raidItem = true end end
  local raidClosed = raidItem and not BF.RaidsOpen()
  for _, e in ipairs(BF.SRC and BF.SRC[id] or {}) do
    local cat, side, text = e:match("^(%a)|(%a?)|(.*)$")
    if cat and raidClosed then closed = closed + 1; cat = nil end
    if cat then
      if side == "" or side == mySide then
        mine = mine + 1
        s.cats[CAT[cat] or "unknown"] = true
        texts[#texts + 1] = text
        s.groups[#s.groups + 1] = BF.PlanGroup(cat, text)
      else
        other = other + 1
      end
    end
  end
  if mine == 0 and other == 0 and closed == 0 then
    local old = BF.OLD and BF.OLD[id]
    if old then
      s.cats.classic = true; texts[1] = old
      s.groups[1] = { key = "world", label = "World drops and chests", what = old }
    else
      s.cats.unknown = true; texts[1] = "Source not known yet"
      s.groups[1] = { key = "unknown", label = "Source not known yet", what = "" }
    end
  end
  if rec and rec.b == 2 and mine > 0 then texts[#texts + 1] = "Bind on Equip" end
  if mine == 0 and closed > 0 then s.closed = true; texts = { "Raid not open yet" } end
  s.other = other > 0 and mine == 0
  s.text = table.concat(texts, "  |  ")
  srcCache[id] = s
  return s
end

-- Dungeons with separate runs: boss -> the part of the dungeon it is in. Bosses not listed (and trash) stay with the
-- whole dungeon.
local WINGS = {
  Stratholme = {
    ["Hearthsinger Forresten"] = "Living", ["The Unforgiven"] = "Living", ["Timmy the Cruel"] = "Living",
    ["Malor the Zealous"] = "Living", ["Crimson Hammersmith"] = "Living", ["Cannon Master Willey"] = "Living",
    ["Archivist Galford"] = "Living", ["Balnazzar"] = "Living", ["Skul"] = "Living", ["Postmaster Malown"] = "Living",
    ["Magistrate Barthilas"] = "Undead", ["Stonespine"] = "Undead", ["Baroness Anastari"] = "Undead",
    ["Nerub'enkan"] = "Undead", ["Maleki the Pallid"] = "Undead", ["Ramstein the Gorger"] = "Undead",
    ["Black Guard Swordsmith"] = "Undead", ["Baron Rivendare"] = "Undead", ["Ezra Grimm"] = "Undead",
  },
}
local function dungeonStep(place, boss)
  local wing = WINGS[place] and WINGS[place][boss]
  if wing then place = place .. " (" .. wing .. ")" end
  return { key = "d:" .. place, label = "Run " .. place, what = boss == "Trash" and "trash" or boss }
end

-- Plan steps: where to go for an item. "Drop: Boss - Dungeon" -> one step per dungeon (all its bosses together),
-- every other source its own step.
function BF.PlanGroup(cat, text)
  local boss, place = text:match("^Drop: (.-) %- (.+)$")
  if boss then return dungeonStep(place, boss) end
  boss, place = text:match("^Raid: (.-) %- (.+)$")
  if boss then return { key = "R:" .. place, label = "Raid " .. place, what = boss } end
  if cat == "q" then return { key = "q:" .. text, label = text, what = "" } end
  if cat == "c" then return { key = "c:" .. text, label = text, what = "" } end
  if cat == "r" then
    local fac = text:match("^Reputation: ([^%(]-)%s*%(") or text:match("^Reputation: (.+)$") or text
    return { key = "r:" .. fac, label = "Reputation: " .. fac, what = text:match("%((.-)%)") or "" }
  end
  if cat == "s" then
    local where = text:match("^(.-) %- ")
    if where then
      local boss = text:match("%- (.-) %(") or ""
      local st = dungeonStep(where, boss)
      st.what = boss
      return st
    end
  end
  return { key = cat .. ":" .. text, label = text, what = "" }
end

-- Extra lines for the plan: where a recipe is and what it needs, where a quest starts (Data/Details.lua)
local function zoneName(mapID)
  local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  return info and info.name
end
-- kind "c": the recipe only, "q": the quest only
function BF.Details(id, kind)
  local out = {}
  local mySide = myFactionNow() == "Alliance" and "A" or "H"
  local c = kind ~= "q" and BF.CRAFT and BF.CRAFT[id]
  if c then
    local prof, req, reag, recipe, where = c[1], c[2], c[3], c[4], c[5]
    out[#out + 1] = prof .. (req > 0 and (" " .. req) or "") .. (reag ~= "" and (":  " .. reag) or "")
    local lines = {}
    for _, e in ipairs(where or {}) do
      local side, text = e:match("^(%a?)|(.*)$")
      if text and (side == "" or side == mySide) then lines[#lines + 1] = text end
    end
    if #lines > 0 then
      out[#out + 1] = (recipe ~= "" and (recipe .. ":  ") or "Recipe:  ") .. table.concat(lines, ";  ")
    end
  end
  local seen = {}
  for _, q in ipairs(kind ~= "c" and BF.QUEST and BF.QUEST[id] or {}) do
    local side, name, level, giver, mapID, x, y, pre = unpack(q)
    if (side == "" or side == mySide) and not seen[name] then
      seen[name] = true
      local zone = zoneName(mapID)
      local at = zone and (x and string.format("%s (%.1f, %.1f)", zone, x, y) or zone)
      local text = "Quest " .. name .. (level and (" (level " .. level .. ")") or "")
      if giver ~= "" then text = text .. " from " .. giver end
      if at then text = text .. " in " .. at end
      if pre and #pre > 0 then text = text .. ". First: " .. table.concat(pre, ", ") end
      out[#out + 1] = text
    end
  end
  return out
end

local function passesFilters(s)
  local f = cdb.filters
  if s.closed then return false, "the raid is not open yet" end
  if cdb.hideFaction and s.other then return false, "other faction only" end
  for k, on in pairs(f) do if on and s.cats[k] then return true end end
  local c = {}
  for k in pairs(s.cats) do c[#c + 1] = k end
  return false, "its source is unticked in the filters"
end

---------------------------------------------------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------------------------------------------------
-- can this character use the item in this tab? false + the reason when not
local function usable(cls, level, mode, rec)
  if not rec then return false, "the game has not sent this item's data" end
  if (rec.q or 0) < 1 then return false, "grey (poor) item" end
  local maxLevel = (mode == "endgame") and 60 or level
  if (rec.rl or 0) > maxLevel then return false, "requires level " .. rec.rl .. " (this tab: up to " .. maxLevel .. ")" end
  if rec.c == 4 and rec.sc >= 1 and rec.sc <= 4 and rec.loc ~= "INVTYPE_CLOAK" then
    local maxA = ARMOR_MAX[cls] or 1
    if maxA >= 3 and maxLevel < 40 then maxA = maxA - 1 end
    if rec.sc > maxA then return false, "armor type you cannot wear (yet)" end
  end
  if rec.cl then
    local m = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    local f = LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[cls]
    local ok = false
    for name in rec.cl:gmatch("[^,]+") do
      name = name:match("^%s*(.-)%s*$")
      if name == m or name == f then ok = true; break end
    end
    if not ok then return false, "only for: " .. rec.cl end
  end
  return true
end

local function canDualWield(cls)
  if type(CanDualWield) == "function" then
    local ok, v = pcall(CanDualWield)
    if ok and v ~= nil then return v and true or false end
  end
  return DUAL_WIELD[cls] == true
end

-- equipped value of a row (compared against the weaker ring / trinket; two-hand against main + off hand)
local function wornScore(W, inv, slotForScore)
  local link = GetInventoryItemLink("player", inv)
  if not link then return 0, nil end
  local id = GetInventoryItemID("player", inv)
  local stats = GetItemStats(link) or {}
  local rec = db.items[id] or { c = select(6, GetItemInfoInstant(id)), sc = select(7, GetItemInfoInstant(id)) }
  return BF.Score(W, stats, slotForScore or inv, rec), id
end

local function equippedValue(W, slotDef)
  local function one(inv)
    local link = GetInventoryItemLink("player", inv)
    if not link then return 0, nil end
    local id = GetInventoryItemID("player", inv)
    local stats = GetItemStats(link) or {}
    local rec = db.items[id] or { c = select(6, GetItemInfoInstant(id)), sc = select(7, GetItemInfoInstant(id)) }
    return BF.Score(W, stats, slotDef.score or inv, rec), id
  end
  if slotDef.pair then
    local a, ia = one(slotDef.inv[1]); local b, ib = one(slotDef.inv[2])
    return math.min(a, b), { ia, ib }
  elseif slotDef.both then
    local a, ia = one(16); local b, ib = one(17)
    local _, _, _, loc = ia and GetItemInfoInstant(ia)
    if loc == "INVTYPE_2HWEAPON" then return a, { ia } end
    return a + b, { ia, ib }
  end
  local v, id = one(slotDef.inv[1])
  return v, { id }
end

-- results[slotKey] = { equipped = value, equippedIDs = {...}, top = { { id, score }, ... } }
function BF.Rank(mode, specIndex)
  local cls = BF.ViewClass()
  local own = cls == playerClass()
  candidates = candidatesBy[cls]
  local level = UnitLevel("player") or 1
  local W, specName = BF.Weights(specIndex, mode)
  local dw
  if own then dw = canDualWield(cls) else dw = DUAL_WIELD[cls] == true end
  local results = {}
  for _, sd in ipairs(BF.SLOTS) do
    local eq, eqIDs = 0, {}
    if own then eq, eqIDs = equippedValue(W, sd) end   -- what another class wears is not known
    results[sd.key] = { equipped = eq, equippedIDs = eqIDs, top = {} }
  end
  local seenName = {}   -- [slotKey][item name] = best score so far
  BF.lastAll = {}   -- [slotKey] = { [itemID] = score } of everything that passed, for /bis check
  for _, sd in ipairs(BF.SLOTS) do BF.lastAll[sd.key] = {}; seenName[sd.key] = {} end
  for _, id in ipairs(candidates or {}) do
    local rec = db.items[id]
    if rec and usable(cls, level, mode, rec) then
      local src = BF.Source(id, rec)
      if passesFilters(src) then
        for _, sd in ipairs(BF.SLOTS) do
          local fits = sd.locs[rec.loc] or (sd.key == "OFFHAND" and dw and rec.loc == "INVTYPE_WEAPON")
          if fits and not (sd.key == "OFFHAND" and rec.loc == "INVTYPE_SHIELD" and not SHIELD[cls]) then
            local sc = BF.Score(W, rec.s, sd.score or sd.inv[1], rec)
            BF.lastAll[sd.key][id] = sc
            if sc > 0 then
              local top = results[sd.key].top
              -- one entry per item name (some items exist twice)
              local seen = seenName[sd.key]
              if not seen[rec.n] or seen[rec.n] < sc then
                seen[rec.n] = sc
                for i = #top, 1, -1 do if top[i].name == rec.n then table.remove(top, i) end end
                local pos = #top + 1
                for i = 1, #top do if sc > top[i].score then pos = i; break end end
                if pos <= BF.TopN() then
                  table.insert(top, pos, { id = id, score = sc, name = rec.n })
                  if #top > BF.TopN() then top[#top] = nil end
                end
              end
            end
          end
        end
      end
    end
  end
  BF.lastSets = evaluateSets(W, BF.lastAll)
  BF.inBestSet = {}
  for _, st in ipairs(BF.lastSets) do
    if st.k >= 2 and st.gain > 0 then for _, p in ipairs(st.pieces) do BF.inBestSet[p.id] = st.name end end
  end
  return results, specName, W
end

function BF.ResetSourceCache() wipe(srcCache) end
function BF.TopN() return math.max(1, math.min(10, (cdb and cdb.topN) or 3)) end

---------------------------------------------------------------------------------------------------------------------
-- The plan: items the player picked from the lists, turned into steps (a dungeon run, a quest, a craft ...) ordered by
-- how much they would add over what is worn now
---------------------------------------------------------------------------------------------------------------------
local SLOT_BY_KEY = {}
for _, sd in ipairs(BF.SLOTS) do SLOT_BY_KEY[sd.key] = sd end

local function pickTable(specName)
  cdb.picks[specName] = cdb.picks[specName] or {}
  return cdb.picks[specName]
end
function BF.IsPicked(specName, slotKey, id)
  for _, p in ipairs(pickTable(specName)[slotKey] or {}) do if p == id then return true end end
  return false
end
-- click on a row: pick it, or drop it when it is picked. Any number of picks per slot (up to 10): the plan shows them
-- all, best first, so there is a second choice when the first is hard to get.
function BF.TogglePick(specName, slotKey, id)
  local t = pickTable(specName)
  local list = t[slotKey] or {}
  for i, p in ipairs(list) do
    if p == id then table.remove(list, i); t[slotKey] = (#list > 0) and list or nil; return false end
  end
  if #list >= 10 then table.remove(list, 1) end
  list[#list + 1] = id
  t[slotKey] = list
  return true
end
function BF.ClearPicks(specName) cdb.picks[specName] = nil end
function BF.PickCount(specName)
  local n = 0
  for _, list in pairs(cdb.picks[specName] or {}) do n = n + #list end
  return n
end

local function owned(id)
  local count = 0
  local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
  if fn then local ok, c = pcall(fn, id, true); if ok and type(c) == "number" then count = c end end
  local eq = (C_Item and C_Item.IsEquippedItem) or IsEquippedItem
  if eq then local ok, v = pcall(eq, id); if ok and v then count = count + 1 end end
  return count > 0
end

-- steps = { { label, gain, items = { { id, gain, what, slotKey } } } } best first; done = { item IDs }
function BF.Plan(mode, specIndex)
  local W, specName = BF.Weights(specIndex, mode)
  local picks = pickTable(specName)
  local items, done = {}, {}
  for slotKey, list in pairs(picks) do
    local sd = SLOT_BY_KEY[slotKey]
    if sd then
      -- what each pick replaces: rings / trinkets the weaker worn one first, then the other
      local worn = {}
      if sd.pair then
        local a = wornScore(W, sd.inv[1], sd.score); local b = wornScore(W, sd.inv[2], sd.score)
        worn = { math.min(a, b), math.max(a, b) }
      elseif sd.both then
        local a, ia = wornScore(W, 16, 16); local b = wornScore(W, 17, 17)
        local _, _, _, loc = ia and GetItemInfoInstant(ia)
        worn = { (loc == "INVTYPE_2HWEAPON") and a or (a + b) }
      else
        worn = { (wornScore(W, sd.inv[1], sd.score)) }
      end
      local scored = {}
      for _, id in ipairs(list) do
        local rec = db.items[id]
        local sc = rec and BF.Score(W, rec.s, sd.score or sd.inv[1], rec) or 0
        scored[#scored + 1] = { id = id, score = sc }
      end
      table.sort(scored, function(x, y) return x.score > y.score end)
      for i, p in ipairs(scored) do
        if owned(p.id) then done[#done + 1] = p.id
        else
          local base = worn[i] or worn[#worn] or 0
          items[#items + 1] = { id = p.id, slotKey = slotKey, gain = p.score - base, score = p.score, choice = i, of = #scored }
        end
      end
    end
  end
  -- group into steps
  local steps, byKey = {}, {}
  for _, it in ipairs(items) do
    local rec = db.items[it.id]
    local src = BF.Source(it.id, rec)
    local g = src.groups[1] or { key = "unknown", label = "Source not known yet", what = "" }
    local key, label = g.key, g.label
    if key:sub(1, 2) == "c:" then   -- every craft is its own step, named after the item
      key = "c:" .. it.id
      label = "Craft " .. (rec and rec.n or "?") .. " (" .. (g.label:match("^Crafted: (.+)$") or g.label) .. ")"
    end
    local st = byKey[key]
    if not st then st = { key = key, label = label, gain = 0, items = {} }; byKey[key] = st; steps[#steps + 1] = st end
    it.what = g.what
    st.items[#st.items + 1] = it
    if it.gain > 0 then st.gain = st.gain + it.gain end
  end
  for _, st in ipairs(steps) do table.sort(st.items, function(x, y) return x.gain > y.gain end) end
  table.sort(steps, function(x, y) return x.gain > y.gain end)
  -- the player's own order (arrows on the steps): steps they moved keep their order, in the places those steps take
  -- up; new steps come in by their upgrade
  local order = cdb.planOrder and cdb.planOrder[specName]
  if order then
    local pos = {}
    for i, k in ipairs(order) do pos[k] = i end
    local places, listed = {}, {}
    for i, st in ipairs(steps) do if pos[st.key] then places[#places + 1] = i; listed[#listed + 1] = st end end
    table.sort(listed, function(x, y) return pos[x.key] < pos[y.key] end)
    for n, i in ipairs(places) do steps[i] = listed[n] end
  end
  return steps, done, specName
end

-- move a plan step up (dir -1) or down (+1); far = to the top / bottom. keys = the step keys as shown now.
function BF.MoveStep(specName, keys, key, dir, far)
  local order = {}
  for i, k in ipairs(keys) do order[i] = k end
  local i
  for n, k in ipairs(order) do if k == key then i = n end end
  if not i then return end
  local j = far and (dir < 0 and 1 or #order) or (i + dir)
  j = math.max(1, math.min(#order, j))
  table.remove(order, i); table.insert(order, j, key)
  cdb.planOrder = cdb.planOrder or {}
  cdb.planOrder[specName] = order
end
function BF.ResetOrder(specName) if cdb.planOrder then cdb.planOrder[specName] = nil end end
function BF.HasOrder(specName) return cdb.planOrder and cdb.planOrder[specName] ~= nil end

-- /bis check <item ID, link or name>: why an item is (not) in the list
function BF.Explain(q)
  local out = {}
  local function add(t) out[#out + 1] = t end
  local id = tonumber(q) or tonumber((q or ""):match("item:(%d+)"))
  if not id and q and q ~= "" then
    local lq = q:lower()
    for iid, rec in pairs(db.items) do if rec.n and rec.n:lower() == lq then id = iid; break end end
    if not id then
      for iid, rec in pairs(db.items) do if rec.n and rec.n:lower():find(lq, 1, true) then id = iid; break end end
    end
  end
  if not id then return { "No item found for \"" .. tostring(q) .. "\". Try its item ID, or shift-click the item." } end
  local rec = db.items[id]
  add("|cffffd100" .. (rec and rec.n or ("Item " .. id)) .. "|r (" .. id .. ")")
  local isCand = false
  for _, c in ipairs(candidates or {}) do if c == id then isCand = true; break end end
  if not candidates then add("Open the window (/bis) first.")
  elseif not isCand then
    local _, _, _, loc, _, classID, subID = GetItemInfoInstant(id)
    if not loc then add("- The game does not know this item.")
    elseif not (classID == 2 or classID == 4) or not ALL_LOCS[loc] then add("- Not gear you can wear.")
    elseif not canEverWear(BF.ViewClass(), classID, subID, loc) then add("- This class cannot wear this.")
    else add("- Not in the item lists, so it is not checked.") end
    return out
  end
  if not rec then
    if db.missing[id] then add("- The server says this item does not exist.")
    elseif notFound[id] then add("- The server did not send this item yet. Try /reload.")
    else add("- Still waiting for the server.") end
    return out
  end
  local mode = cdb.mode
  local ok, why = usable(BF.ViewClass(), UnitLevel("player") or 1, mode, rec)
  add("- Can use it (" .. (mode == "endgame" and "Endgame" or "Now") .. "): " .. (ok and "yes" or ("no, " .. why)))
  local src = BF.Source(id, rec)
  add("- Source: " .. (src.text ~= "" and src.text or "?"))
  local pass, pwhy = passesFilters(src)
  add("- Shown: " .. (pass and "yes" or ("no, " .. pwhy)))
  local stats = {}
  for k, v in pairs(rec.s or {}) do stats[#stats + 1] = (KEYS[k] or k) .. " " .. v end
  table.sort(stats)
  add("- Stats: " .. (#stats > 0 and table.concat(stats, ", ") or "none"))
  if rec.set then
    local info = db.sets[rec.set]
    add("- Set: " .. (info and info.n or ("set " .. rec.set)))
    for _, st in ipairs(BF.lastSets or {}) do
      if st.id == rec.set then
        add(st.k >= 2 and st.gain > 0 and string.format("  Wear %d of %d pieces: %+.1f", st.k, st.available, st.gain)
          or "  Not worth it for your talent tree")
      end
    end
  end
  if ok and pass and BF.lastAll then
    for _, sd in ipairs(BF.SLOTS) do
      local sc = BF.lastAll[sd.key] and BF.lastAll[sd.key][id]
      if sc then
        local better = 0
        for oid, osc in pairs(BF.lastAll[sd.key]) do if osc > sc and oid ~= id then better = better + 1 end end
        add(string.format("- %s: score %.1f, place %d", sd.name, sc, better + 1))
      end
    end
  end
  return out
end

-- for Gear.lua
BF.ReadItem, BF.Usable, BF.CanDualWield, BF.BonusValue = readItem, usable, canDualWield, bonusValue
BF.SHIELD_CLASSES = SHIELD
