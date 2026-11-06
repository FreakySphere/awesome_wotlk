local addonName, Flash = ...
local L = Flash.L

local _G = _G
local type = type
local tonumber = tonumber
local format = string.format
local unpack = unpack
local pairs = pairs

local CreateFrame = CreateFrame
local UIParent = UIParent
local PlaySound = PlaySound
local SlashCmdList = SlashCmdList

local FRAME_WIDTH = 430

-- ------------------------------------------------------------------------------------------------
-- What the client can do. FlashWindow and IsWindowFocused ship with every awesome_wotlk, so this
-- addon works on any fork; it only needs *a* patched client.
-- ------------------------------------------------------------------------------------------------
local CAP = {}
Flash.CAP = CAP

CAP.modVersion = tonumber(_G.AwesomeWotlk) or 0
CAP.brandVersion = _G.FreakySphere
CAP.isPatched = CAP.modVersion > 0
CAP.hasWindowAPI = type(_G.FlashWindow) == "function" and type(_G.IsWindowFocused) == "function"
CAP.unlocked = CAP.isPatched and CAP.hasWindowAPI

function CAP.status()
    if not CAP.isPatched then return "unpatched" end
    if not CAP.hasWindowAPI then return "missing" end
    return "ok"
end

function CAP.clientLabel()
    if not CAP.isPatched then return L.STATUS_CLIENT_NONE end
    if CAP.brandVersion then return format(L.STATUS_CLIENT_FS, tostring(CAP.brandVersion), CAP.modVersion) end
    return format(L.STATUS_CLIENT_FORK, CAP.modVersion)
end

local STATUS_STYLE = {
    ok = { bar = {0.30, 0.82, 0.46}, bg = {0.09, 0.22, 0.13, 0.60} },
    missing = { bar = {1.00, 0.72, 0.22}, bg = {0.26, 0.19, 0.06, 0.60} },
    unpatched = { bar = {0.92, 0.32, 0.32}, bg = {0.26, 0.08, 0.08, 0.60} },
}

-- ------------------------------------------------------------------------------------------------
-- Saved variables
-- ------------------------------------------------------------------------------------------------
-- Every alert ships on: the master switch, combat, whisper, party invite and ready check. A fresh
-- install therefore flashes for all four events with nothing to configure.
local DEFAULTS = {
    enabled = true,
    onCombat = true,
    onWhisper = true,
    onInvite = true,
    onReadyCheck = true,
}

-- Bumped whenever a shipped default changes. v2 turned the party invite and ready check alerts on.
local DEFAULTS_VERSION = 2

local function ensureDB()
    local db = _G.FlashDB
    if type(db) ~= "table" then db = {} end
    for key, value in pairs(DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    -- A saved variable written by an older version still holds the old default, which would otherwise
    -- outlive the change forever. Only a value still sitting on that old default is moved; anything
    -- the user set by hand is left alone.
    if db.defaultsVersion == nil then
        if db.onInvite == false then db.onInvite = true end
        if db.onReadyCheck == false then db.onReadyCheck = true end
        db.defaultsVersion = DEFAULTS_VERSION
    end
    _G.FlashDB = db
    Flash.DB = db
    return db
end

-- ------------------------------------------------------------------------------------------------
-- Behaviour
-- ------------------------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
eventFrame:RegisterEvent("READY_CHECK")

-- One place decides whether a flash may happen: the option must be on, the master switch must be on,
-- and the client must actually have the API.
local function maybeFlash(optionKey)
    local db = Flash.DB
    if not db or not db.enabled or not db[optionKey] then return end
    if not CAP.unlocked then return end
    if _G.IsWindowFocused() then return end
    _G.FlashWindow()
end

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        maybeFlash("onCombat")
    elseif event == "CHAT_MSG_WHISPER" then
        maybeFlash("onWhisper")
    elseif event == "PARTY_INVITE_REQUEST" then
        maybeFlash("onInvite")
    elseif event == "READY_CHECK" then
        maybeFlash("onReadyCheck")
    end
end)

-- ------------------------------------------------------------------------------------------------
-- Window
-- ------------------------------------------------------------------------------------------------
local options = {}

local function setBackdrop(frame, bg, border)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border))
end

local function createRow(parent, offset, key)
    local check = CreateFrame("CheckButton", "FlashOption_"..key, parent, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", 18, offset)
    check:SetHeight(24)

    local label = _G[check:GetName().."Text"]
    label:SetText(L["OPT_"..key])
    label:SetTextColor(0.95, 0.95, 0.95)

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    desc:SetJustifyH("LEFT")
    desc:SetWidth(FRAME_WIDTH - 76)
    desc:SetTextColor(unpack({0.60, 0.60, 0.60}))
    desc:SetText(L["OPT_"..key.."_DESC"])

    check.key = key
    check.label = label
    check.desc = desc
    check:SetScript("OnClick", function(self)
        if not CAP.unlocked then
            self:SetChecked(not self:GetChecked())
            Flash:Print(L.MSG_LOCKED)
            return
        end
        Flash.DB[key] = self:GetChecked() and true or false
        PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end)

    options[#options + 1] = check
    return offset - (22 + desc:GetStringHeight() + 12)
end

function Flash:CreateMainFrame()
    if self.Frame then return self.Frame end

    local frame = CreateFrame("Frame", "FlashFrame", UIParent, "UIPanelDialogTemplate")
    self.Frame = frame
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    title:SetPoint("TOP", 0, -8)
    title:SetText(L.TITLE)

    -- Status banner, same language as the AwesomeCVar one
    local banner = CreateFrame("Frame", nil, frame)
    banner:SetPoint("TOPLEFT", 16, -30)
    banner:SetPoint("TOPRIGHT", -16, -30)
    banner:SetHeight(48)
    setBackdrop(banner, {0.15, 0.15, 0.15, 0.6}, {0.4, 0.4, 0.4, 0.8})

    local accent = banner:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", 3, -3)
    accent:SetPoint("BOTTOMLEFT", 3, 3)

    local bannerTitle = banner:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    bannerTitle:SetPoint("TOPLEFT", 14, -9)
    bannerTitle:SetJustifyH("LEFT")

    local bannerDetail = banner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    bannerDetail:SetPoint("TOPLEFT", bannerTitle, "BOTTOMLEFT", 0, -3)
    bannerDetail:SetJustifyH("LEFT")
    bannerDetail:SetWidth(FRAME_WIDTH - 60)
    bannerDetail:SetTextColor(unpack({0.60, 0.60, 0.60}))

    local bannerWarn = banner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    bannerWarn:SetPoint("TOPLEFT", bannerDetail, "BOTTOMLEFT", 0, -4)
    bannerWarn:SetJustifyH("LEFT")
    bannerWarn:SetWidth(FRAME_WIDTH - 60)
    bannerWarn:SetTextColor(unpack({0.95, 0.44, 0.44}))
    bannerWarn:SetText(L.WARN_LOCKED)

    local status = CAP.status()
    local style = STATUS_STYLE[status]
    banner:SetBackdropColor(unpack(style.bg))
    banner:SetBackdropBorderColor(style.bar[1], style.bar[2], style.bar[3], 0.45)
    accent:SetTexture(style.bar[1], style.bar[2], style.bar[3], 1)
    bannerTitle:SetTextColor(style.bar[1], style.bar[2], style.bar[3])
    bannerTitle:SetText(status == "ok" and L.STATUS_TITLE_OK or L.STATUS_TITLE_LOCKED)
    bannerDetail:SetText(CAP.clientLabel())

    if status == "ok" then
        bannerWarn:Hide()
        banner:SetHeight(48)
    else
        banner:SetHeight(52 + bannerWarn:GetStringHeight())
    end

    local offset = -30 - banner:GetHeight() - 14
    offset = createRow(frame, offset, "enabled")
    offset = createRow(frame, offset, "onCombat")
    offset = createRow(frame, offset, "onWhisper")
    offset = createRow(frame, offset, "onInvite")
    offset = createRow(frame, offset, "onReadyCheck")

    local testButton = CreateFrame("Button", "FlashTestButton", frame, "UIPanelButtonTemplate")
    testButton:SetSize(110, 22)
    testButton:SetPoint("BOTTOMLEFT", 16, 16)
    testButton:SetText(L.BTN_TEST)
    testButton:SetScript("OnClick", function()
        if not CAP.unlocked then
            Flash:Print(L.MSG_LOCKED)
            return
        end
        _G.FlashWindow()
        Flash:Print(L.MSG_TEST)
    end)

    local defaultsButton = CreateFrame("Button", "FlashDefaultsButton", frame, "UIPanelButtonTemplate")
    defaultsButton:SetSize(110, 22)
    defaultsButton:SetPoint("LEFT", testButton, "RIGHT", 8, 0)
    defaultsButton:SetText(_G.DEFAULTS)
    defaultsButton:SetScript("OnClick", function()
        if not CAP.unlocked then
            Flash:Print(L.MSG_LOCKED)
            return
        end
        for key, value in pairs(DEFAULTS) do Flash.DB[key] = value end
        Flash:Refresh()
        PlaySound("igMainMenuOptionFaerTab")
    end)

    local closeButton = CreateFrame("Button", "FlashCloseButton", frame, "UIPanelButtonTemplate")
    closeButton:SetSize(110, 22)
    closeButton:SetPoint("BOTTOMRIGHT", -16, 16)
    closeButton:SetText(_G.OKAY or L.BTN_CLOSE)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    frame:SetHeight(-offset + 58)
    frame:SetScript("OnShow", function() Flash:Refresh() end)

    table.insert(UISpecialFrames, "FlashFrame")
    return frame
end

function Flash:Refresh()
    local db = Flash.DB
    if not db then return end
    for _, check in pairs(options) do
        check:SetChecked(db[check.key] and true or false)
        if CAP.unlocked then
            check:Enable()
            check:SetAlpha(1)
            check.label:SetTextColor(0.95, 0.95, 0.95)
        else
            check:Disable()
            check:SetAlpha(0.45)
            check.label:SetTextColor(0.55, 0.55, 0.55)
        end
    end
end

function Flash:Print(message)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00"..L.TITLE..":|r "..message)
    end
end

function Flash:Toggle()
    local frame = self:CreateMainFrame()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

-- ------------------------------------------------------------------------------------------------
-- Load
-- ------------------------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if event ~= "ADDON_LOADED" or name ~= addonName then return end
    self:UnregisterEvent(event)

    ensureDB()
    Flash:CreateMainFrame()
    Flash:Refresh()

    if not CAP.unlocked then
        Flash:Print(CAP.status() == "unpatched" and L.MSG_LOCKED or L.MSG_MISSING_API)
    end
end)

SLASH_FLASH1 = "/flash"
SlashCmdList["FLASH"] = function() Flash:Toggle() end
