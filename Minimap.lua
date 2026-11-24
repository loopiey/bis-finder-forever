-- BiSFinder minimap button, made with the standard minimap button library (LibDBIcon) so that button bars and
-- collectors find it, plus the entry in the game's addon menu by the minimap.
local ADDON, BF = ...

local ICON = "Interface\\AddOns\\BiSFinder\\Media\\minimap.tga"   -- Media/minimap.tga, 64x64
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)

local function tooltipLines(tt)
  tt:AddLine("BiSFinder")
  tt:AddLine("Left-click: best items", 1, 1, 1)
  tt:AddLine("Right-click: my plan", 1, 1, 1)
end

local function click(button)
  if button == "RightButton" then BF.Open("plan") else BF.Toggle() end
end

function BF.CreateMinimapButton()
  if not (LDB and DBI) or DBI:IsRegistered("BiSFinder") then return end
  -- an older saved position (degrees) carries over
  local m = BF.db.minimap
  if m.minimapPos == nil and m.angle then m.minimapPos = m.angle end
  m.angle = nil
  local obj = LDB:NewDataObject("BiSFinder", {
    type = "launcher",
    text = "BiSFinder",
    icon = ICON,
    OnClick = function(_, button) click(button) end,
    OnTooltipShow = function(tt) tooltipLines(tt); tt:AddLine("Drag: move this button", 0.7, 0.7, 0.7) end,
  })
  DBI:Register("BiSFinder", obj, m)
end

-- where the button is now: shown or hidden, and which frame holds it (the minimap, or a button bar / collector)
function BF.MinimapStatus()
  if not (LDB and DBI) then return "the minimap library did not load" end
  local b = DBI.GetMinimapButton and DBI:GetMinimapButton("BiSFinder") or _G.LibDBIcon10_BiSFinder
  if not b then return "not made yet" end
  local p = b:GetParent()
  local where = p and (p.GetName and p:GetName()) or "no frame"
  local tex = b.icon and b.icon:GetTexture()
  return (b:IsShown() and "shown" or "hidden") .. ", inside " .. tostring(where) .. ", icon " .. tostring(tex or "missing")
end

-- /bis minimap: show or hide the button, then say where it is
function BF.ToggleMinimapButton()
  local m = BF.db.minimap
  m.hide = not m.hide
  if DBI then if m.hide then DBI:Hide("BiSFinder") else DBI:Show("BiSFinder") end end
  BF.say((m.hide and "Minimap button hidden. /bis minimap shows it again." or "Minimap button shown.")
    .. " (" .. BF.MinimapStatus() .. ")")
end

-- the game's addon menu next to the minimap (## AddonCompartmentFunc in the .toc)
function BiSFinder_OnCompartmentClick(_, button) click(button) end
function BiSFinder_OnCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT"); tooltipLines(GameTooltip); GameTooltip:Show()
end
function BiSFinder_OnCompartmentLeave() GameTooltip:Hide() end
