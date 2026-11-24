-- BiSFinder gear planner: a full set of gear (what you wear, with any items swapped in), its stats and score, and the
-- best set you can put together from the items you have (worn, bags, bank).
local ADDON, BF = ...

local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local GetSlotItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

-- the planner's slots, paper doll order. key = the row of BF.SLOTS whose item types fit.
BF.GEAR_SLOTS = {
  { inv = 1, name = "Head", key = "HEAD" }, { inv = 2, name = "Neck", key = "NECK" },
  { inv = 3, name = "Shoulder", key = "SHOULDER" }, { inv = 15, name = "Back", key = "BACK" },
  { inv = 5, name = "Chest", key = "CHEST" }, { inv = 9, name = "Wrist", key = "WRIST" },
  { inv = 10, name = "Hands", key = "HANDS" }, { inv = 6, name = "Waist", key = "WAIST" },
  { inv = 7, name = "Legs", key = "LEGS" }, { inv = 8, name = "Feet", key = "FEET" },
  { inv = 11, name = "Ring 1", key = "FINGER" }, { inv = 12, name = "Ring 2", key = "FINGER" },
  { inv = 13, name = "Trinket 1", key = "TRINKET" }, { inv = 14, name = "Trinket 2", key = "TRINKET" },
  { inv = 16, name = "Main Hand", key = "MAINHAND" }, { inv = 17, name = "Off Hand", key = "OFFHAND" },
  { inv = 18, name = "Ranged", key = "RANGED" },
}
local SLOT_DEF = {}
for _, sd in ipairs(BF.SLOTS) do SLOT_DEF[sd.key] = sd end

---------------------------------------------------------------------------------------------------------------------
-- Items: the saved data, or read now (asked from the game when it is not loaded yet)
---------------------------------------------------------------------------------------------------------------------
local waiting = {}
local redrawPending
local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BANKFRAME_CLOSED")

function BF.ItemRec(id)
  if not id or id == 0 then return nil end
  local rec = BF.db.items[id]
  if rec then return rec end
  rec = BF.ReadItem(id)
  if rec then BF.db.items[id] = rec; return rec end
  waiting[id] = true
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

---------------------------------------------------------------------------------------------------------------------
-- What you have: worn, bags, and the bank (remembered from the last time the bank was open)
---------------------------------------------------------------------------------------------------------------------
local bankOpen = false
local function readBank()
  local ids = {}
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = b end
  for _, bag in ipairs(bags) do
    for slot = 1, (GetNumSlots and GetNumSlots(bag) or 0) do
      local id = GetSlotItemID(bag, slot)
      if id then ids[#ids + 1] = id end
    end
  end
  BF.cdb.bank = ids
end

ev:SetScript("OnEvent", function(_, event, id, success)
  if event == "GET_ITEM_INFO_RECEIVED" then
    if not waiting[id] then return end
    waiting[id] = nil
    if success ~= false then
      local rec = BF.ReadItem(id)
      if rec then BF.db.items[id] = rec end
    end
    if not redrawPending and BF.IsShown and BF.IsShown() and BF.cdb.view == "gear" then
      redrawPending = true
      C_Timer.After(0.3, function() redrawPending = false; BF.Draw() end)
    end
  elseif event == "BANKFRAME_OPENED" then bankOpen = true; readBank()
  elseif event == "BANKFRAME_CLOSED" then bankOpen = false
  elseif bankOpen then readBank()
  end
end)

-- { [itemID] = count } of everything worn, in the bags, or in the bank
function BF.OwnedItems()
  local have = {}
  local function add(id) if id then have[id] = (have[id] or 0) + 1 end end
  for inv = 1, 19 do if inv ~= 4 then add(GetInventoryItemID("player", inv)) end end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (GetNumSlots and GetNumSlots(bag) or 0) do add(GetSlotItemID(bag, slot)) end
  end
  for _, id in ipairs(BF.cdb.bank or {}) do add(id) end
  return have
end

function BF.WhereIs(id)
  for inv = 1, 19 do if GetInventoryItemID("player", inv) == id then return "worn" end end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, (GetNumSlots and GetNumSlots(bag) or 0) do if GetSlotItemID(bag, slot) == id then return "bags" end end
  end
  for _, b in ipairs(BF.cdb.bank or {}) do if b == id then return "bank" end end
end

---------------------------------------------------------------------------------------------------------------------
-- Which item fits which slot
---------------------------------------------------------------------------------------------------------------------
local function dualWield() return BF.CanDualWield(BF.PlayerClass()) end
function BF.FitsSlot(inv, rec)
  if not rec or not rec.loc then return false end
  local loc = rec.loc
  if inv == 16 then return loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND" or loc == "INVTYPE_2HWEAPON" end
  if inv == 17 then
    if loc == "INVTYPE_SHIELD" then return BF.SHIELD_CLASSES[BF.PlayerClass()] == true end
    if loc == "INVTYPE_WEAPON" then return dualWield() end
    return loc == "INVTYPE_WEAPONOFFHAND" or loc == "INVTYPE_HOLDABLE"
  end
  for _, gs in ipairs(BF.GEAR_SLOTS) do
    if gs.inv == inv then return SLOT_DEF[gs.key].locs[loc] == true end
  end
  return false
end
local function isTwoHand(id)
  if not id then return false end
  local _, _, _, loc = GetItemInfoInstant(id)
  return loc == "INVTYPE_2HWEAPON"
end

-- can this character wear it (class, armor type; level: now, or 60 in the Endgame tab)?
function BF.CanWear(rec, mode)
  return rec and BF.Usable(BF.PlayerClass(), UnitLevel("player") or 1, mode or BF.cdb.mode, rec) and true or false
end
-- the weights of the planner: your talent tree, in the tab shown
function BF.GearWeights(mode) return (BF.Weights(BF.SpecIndex(), mode or BF.cdb.mode)) end

---------------------------------------------------------------------------------------------------------------------
-- Sets of gear: { [inv] = itemID }
---------------------------------------------------------------------------------------------------------------------
function BF.WornGear()
  local g = {}
  for _, gs in ipairs(BF.GEAR_SLOTS) do g[gs.inv] = GetInventoryItemID("player", gs.inv) end
  return g
end

-- the planner: what you wear, with the player's swaps (BF.cdb.planner[inv] = itemID, or 0 for an empty slot)
function BF.PlannedGear()
  local g = BF.WornGear()
  local sw = BF.cdb.planner or {}
  for inv, id in pairs(sw) do
    if id == g[inv] then sw[inv] = nil else g[inv] = (id ~= 0) and id or nil end
  end
  BF.cdb.planner = sw
  return g
end

-- put an item in a slot of the planner (nil = back to what you wear, 0 = empty)
function BF.SetPlanned(inv, id)
  BF.cdb.planner = BF.cdb.planner or {}
  local sw = BF.cdb.planner
  sw[inv] = id
  if id and id ~= 0 then
    if inv == 16 and isTwoHand(id) then sw[17] = 0 end                 -- a two-hander takes both hands
    if inv == 17 and isTwoHand(BF.PlannedGear()[16]) then sw[16] = 0 end
  elseif id == nil and inv == 17 and isTwoHand(GetInventoryItemID("player", 16)) then
    sw[16] = nil
  end
end
function BF.ResetPlanner() BF.cdb.planner = {} end

-- try an item: the slot it fits (rings / trinkets: the weaker one), then the planner opens
function BF.TryItem(id)
  local rec = BF.ItemRec(id)
  if not rec then return false end
  local W = BF.GearWeights()
  local g = BF.PlannedGear()
  local best, bestVal
  for _, gs in ipairs(BF.GEAR_SLOTS) do
    if BF.FitsSlot(gs.inv, rec) then
      local cur = BF.ItemRec(g[gs.inv])
      local v = cur and BF.Score(W, cur.s, gs.inv, cur) or -1
      if not best or v < bestVal then best, bestVal = gs.inv, v end
    end
  end
  if not best then return false end
  BF.SetPlanned(best, id)
  return true
end

---------------------------------------------------------------------------------------------------------------------
-- Value of a set of gear: item scores plus the set bonuses it reaches; and its stat totals
---------------------------------------------------------------------------------------------------------------------
local KEYS, RATING = BF.GEAR_STAT_KEYS or {}, BF.GEAR_RATING or {}

-- score, stats { key = value } (ratings as %), set bonuses reached { "Set name (n): bonus" }
function BF.GearValue(W, gear)
  local total, stats, sets, bonusLines = 0, {}, {}, {}
  for inv, id in pairs(gear) do
    local rec = BF.ItemRec(id)
    if rec then
      total = total + BF.Score(W, rec.s, inv, rec)
      for k, v in pairs(rec.s or {}) do
        local key = KEYS[k]
        if key and type(v) == "number" then
          if key == "shit" then key = "hit" elseif key == "scrit" then key = "crit" end
          stats[key] = (stats[key] or 0) + (RATING[KEYS[k]] and v / RATING[KEYS[k]] or v)
        end
      end
      if rec.set then sets[rec.set] = (sets[rec.set] or 0) + 1 end
    end
  end
  for setID, n in pairs(sets) do
    local info = BF.db.sets[setID]
    for _, b in ipairs(info and info.b or {}) do
      if b[1] <= n then
        local st = BF.ParseBonus(b[2])
        if st then
          total = total + BF.BonusValue(W, st)
          for k, v in pairs(st) do stats[k] = (stats[k] or 0) + v end
        end
        bonusLines[#bonusLines + 1] = info.n .. " (" .. b[1] .. "): " .. b[2]
      end
    end
  end
  return total, stats, bonusLines
end

---------------------------------------------------------------------------------------------------------------------
-- The best set from your own items
---------------------------------------------------------------------------------------------------------------------
local function valid(gear, have)
  local function twice(a, b) return a and a == b and (have[a] or 0) < 2 end
  if twice(gear[11], gear[12]) or twice(gear[13], gear[14]) or twice(gear[16], gear[17]) then return false end
  if gear[17] and isTwoHand(gear[16]) then return false end
  return true
end

-- returns the gear and how many of your items are still loading
function BF.BestOwnedGear()
  local W = BF.GearWeights("now")
  local have = BF.OwnedItems()
  local fits, loading = {}, 0
  for _, gs in ipairs(BF.GEAR_SLOTS) do fits[gs.inv] = {} end
  for id in pairs(have) do
    local rec = BF.ItemRec(id)
    if not rec then loading = loading + 1
    elseif BF.CanWear(rec, "now") then
      for _, gs in ipairs(BF.GEAR_SLOTS) do
        if BF.FitsSlot(gs.inv, rec) then table.insert(fits[gs.inv], { id = id, v = BF.Score(W, rec.s, gs.inv, rec) }) end
      end
    end
  end
  for _, list in pairs(fits) do table.sort(list, function(a, b) return a.v > b.v end) end
  -- start: the best item per slot
  local gear = {}
  local function pick(inv, skip)
    for _, c in ipairs(fits[inv]) do
      if not (skip and c.id == skip and (have[c.id] or 0) < 2) then return c.id end
    end
  end
  for _, gs in ipairs(BF.GEAR_SLOTS) do
    if gs.inv == 12 then gear[12] = pick(12, gear[11])
    elseif gs.inv == 14 then gear[14] = pick(14, gear[13])
    elseif gs.inv ~= 16 and gs.inv ~= 17 then gear[gs.inv] = pick(gs.inv) end
  end
  -- hands: the best two-hander, or the best main hand + off hand
  local two, mh
  for _, c in ipairs(fits[16]) do
    if isTwoHand(c.id) then two = two or c else mh = mh or c end
  end
  local oh = mh and pick(17, mh.id) or pick(17)
  local ohv = 0
  for _, c in ipairs(fits[17]) do if c.id == oh then ohv = c.v; break end end
  if two and two.v >= (mh and mh.v or 0) + ohv then gear[16] = two.id
  else gear[16] = mh and mh.id; gear[17] = oh end
  -- then swap single items while that adds up to more (set bonuses can make a weaker piece worth it)
  local best = BF.GearValue(W, gear)
  for _ = 1, 3 do
    local better = false
    for _, gs in ipairs(BF.GEAR_SLOTS) do
      local inv = gs.inv
      for _, c in ipairs(fits[inv]) do
        if c.id ~= gear[inv] then
          local old, old17 = gear[inv], gear[17]
          gear[inv] = c.id
          if inv == 16 and isTwoHand(c.id) then gear[17] = nil end
          local v = valid(gear, have) and BF.GearValue(W, gear) or -1
          if v > best + 0.01 then best, better = v, true
          else gear[inv], gear[17] = old, old17 end
        end
      end
    end
    if not better then break end
  end
  return gear, loading
end

-- fill the planner with the best set from your items
function BF.PlanBestOwned()
  local gear, loading = BF.BestOwnedGear()
  local worn = BF.WornGear()
  BF.cdb.planner = {}
  for _, gs in ipairs(BF.GEAR_SLOTS) do
    local inv = gs.inv
    if gear[inv] ~= worn[inv] then BF.cdb.planner[inv] = gear[inv] or 0 end
  end
  return loading
end

-- items to offer for a slot: yours that fit, then the best ones from the list (BF.lastAll, filled by ranking)
function BF.SlotOptions(inv, max)
  local W = BF.GearWeights()
  local out, seen = {}, {}
  local function add(id, owned)
    if seen[id] then return end
    local rec = BF.ItemRec(id)
    if rec and BF.FitsSlot(inv, rec) and BF.CanWear(rec) then
      seen[id] = true
      out[#out + 1] = { id = id, v = BF.Score(W, rec.s, inv, rec), owned = owned }
    end
  end
  for id in pairs(BF.OwnedItems()) do add(id, true) end
  local keys = { BF.GEAR_SLOTS_KEY[inv] }
  if inv == 16 then keys[2] = "TWOHAND" end
  local listed = {}
  for _, k in ipairs(keys) do
    for id, sc in pairs(BF.lastAll and BF.lastAll[k] or {}) do listed[#listed + 1] = { id = id, sc = sc } end
  end
  table.sort(listed, function(a, b) return a.sc > b.sc end)
  local n = 0
  for _, e in ipairs(listed) do
    if n >= (max or 10) then break end
    if not seen[e.id] then add(e.id, false); n = n + 1 end
  end
  table.sort(out, function(a, b) return a.v > b.v end)
  return out
end
BF.GEAR_SLOTS_KEY = {}
for _, gs in ipairs(BF.GEAR_SLOTS) do BF.GEAR_SLOTS_KEY[gs.inv] = gs.key end
