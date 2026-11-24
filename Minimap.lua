-- BiSFinder minimap button, made with the standard minimap button library (LibDBIcon) so that button bars and
-- collectors find it, plus the entry in the game's addon menu by the minimap.
local ADDON, BF = ...

local ICON = "Interface\\AddOns\\BiSFinder\\Media\\minimap.tga"   -- Media/minimap.tga, 64x64
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local DBI = LibStub and LibStub("LibDBIcon-1.0", true)

local function tooltipLines(tt)
  tt:AddLine("BiSFinder")
  tt:AddLine("Left-click: best items (again: close)", 1, 1, 1)
  tt:AddLine("Right-click: my plan (again: close)", 1, 1, 1)
end

-- left-click: best items, right-click: my plan. Clicking the view that is already open closes the window;
-- clicking the other one switches to it.
local function click(button)
  BF.ToggleView(button == "RightButton" and "plan" or "list")
end

-- Some UI packs run two minimap button managers at once (EllesmereUI Minimap and the OneForAll collector bar).
-- One of them hides the button / sets it fully transparent while the other has already moved it into its bar,
-- so the button stayed missing until /bis minimap was used twice, and then showed as an empty slot.
-- While the button sits in a named button bar that is not the minimap itself, keep it shown and opaque
-- unless the player hid it with /bis minimap.
local function inButtonBar(b)
  local p = b:GetParent()
  local name = p and p.GetName and p:GetName()
  return type(name) == "string" and not name:find("^Minimap") and not name:find("^MiniMap")
end

local function protectButton(b)
  if not b or b.bfProtected then return end
  b.bfProtected = true
  local busy
  local function fix()
    if busy or BF.db.minimap.hide or not inButtonBar(b) then return end
    busy = true
    if not b:IsShown() then b:Show() end      -- another manager's Show hook may set alpha 0 here,
    if b:GetAlpha() < 1 then b:SetAlpha(1) end -- so the alpha is put back afterwards
    busy = false
  end
  hooksecurefunc(b, "Hide", fix)
  hooksecurefunc(b, "Show", fix)
  hooksecurefunc(b, "SetAlpha", fix)
  BF.FixMinimapButton = fix
  -- the bar takes the button some seconds after login, while it may already be hidden: look again then,
  -- and each time the bar opens
  local hookedBar
  local function check()
    local p = b:GetParent()
    if not hookedBar and p and p ~= Minimap and p.HookScript and inButtonBar(b) then
      hookedBar = true
      p:HookScript("OnShow", fix)
    end
    fix()
  end
  for _, t in ipairs({ 2, 6, 16, 30 }) do C_Timer.After(t, check) end
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
  local b = DBI.GetMinimapButton and DBI:GetMinimapButton("BiSFinder") or _G.LibDBIcon10_BiSFinder
  -- wait for login: the button managers collect buttons after PLAYER_LOGIN
  local w = CreateFrame("Frame")
  w:RegisterEvent("PLAYER_LOGIN")
  w:SetScript("OnEvent", function(self) self:UnregisterAllEvents(); protectButton(b) end)
  if IsLoggedIn and IsLoggedIn() then protectButton(b) end
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
  if not m.hide and BF.FixMinimapButton then BF.FixMinimapButton() end
  BF.say((m.hide and "Minimap button hidden. /bis minimap shows it again." or "Minimap button shown.")
    .. " (" .. BF.MinimapStatus() .. ")")
end

-- the game's addon menu next to the minimap (## AddonCompartmentFunc in the .toc)
function BiSFinder_OnCompartmentClick(_, button) click(button) end
function BiSFinder_OnCompartmentEnter(_, frame)
  GameTooltip:SetOwner(frame, "ANCHOR_LEFT"); tooltipLines(GameTooltip); GameTooltip:Show()
end
function BiSFinder_OnCompartmentLeave() GameTooltip:Hide() end
