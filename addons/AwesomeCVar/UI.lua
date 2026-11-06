local addonName, ACVar = ...
local L = ACVar.L
local CONSTANTS = ACVar.CONSTANTS
local CVARS = ACVar.CVARS
local CATEGORY_ORDER = ACVar.CATEGORY_ORDER

local _G = _G
local ipairs = ipairs
local abs = math.abs
local max = math.max
local min = math.min
local floor = math.floor
local concat = table.concat
local huge = math.huge
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local tostring = tostring
local format = string.format
local gmatch = string.gmatch
local gsub = string.gsub
local unpack = unpack

local CreateFrame = CreateFrame
local HideUIPanel = HideUIPanel
local PlaySound = PlaySound
local UIParent = UIParent
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_SetText = UIDropDownMenu_SetText
local UIDropDownMenu_Initialize = UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton = UIDropDownMenu_AddButton
local CloseDropDownMenus = CloseDropDownMenus
local PanelTemplates_SetTab = PanelTemplates_SetTab
local PanelTemplates_SetNumTabs = PanelTemplates_SetNumTabs

local RESET_TEXT_PADDING = 14
local RESET_MIN_WIDTH = 100

local function getFrameName(prefix, suffix)
    return addonName.."_"..prefix..(suffix or "")
end

local function createButton(parent, name, text, width, height, template)
    local button = CreateFrame("Button", name, parent, template or "UIPanelButtonTemplate")
    button:SetWidth(width or CONSTANTS.FRAME.BUTTON_WIDTH)
    button:SetHeight(height or CONSTANTS.FRAME.BUTTON_HEIGHT)
    button:SetText(text)
    local fontString = button:GetFontString()
    if fontString and fontString:GetWidth() > ((width or CONSTANTS.FRAME.BUTTON_WIDTH) - 16) then
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", button, "LEFT", 8, 0)
        fontString:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    end
    return button
end

local function createPopupFrame(name, title, message, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "DialogBoxFrame")
    frame:SetPoint("CENTER")
    frame:SetWidth(width or CONSTANTS.FRAME.POPUP_WIDTH)
    frame:SetHeight(height or CONSTANTS.FRAME.POPUP_HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:Hide()
    frame:SetBackdropColor(0, 0, 0, 0.8)

    if _G[name.."Button"] then
        _G[name.."Button"]:Hide()
    end

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("TOP", 0, -16)
    titleText:SetText(title)

    local messageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("TOP", titleText, "BOTTOM", 0, -10)
    messageText:SetWidth(frame:GetWidth() - 40)
    messageText:SetJustifyH("CENTER")
    messageText:SetText(message)

    -- Grow to fit longer (translated) messages; 55 leaves room for the bottom buttons
    frame:SetHeight(max(frame:GetHeight(), 16 + titleText:GetHeight() + 10 + messageText:GetHeight() + 55))

    return frame
end

-- A mode can carry a tier of its own (the two "no target" freeze modes arrived with v39). Filter the
-- list once, so a v38 client never shows a radio that its engine would ignore. Frame names stay
-- Radio1..RadioN over this filtered list, and every loop below uses it, so indices always agree.
local function availableModes(cvarDef)
    if not cvarDef.availableModes then
        local list = {}
        for _, mode in ipairs(cvarDef.modes) do
            if not mode.tier or ACVar.CAP.tierAvailable(mode.tier) then
                list[#list + 1] = mode
            end
        end
        cvarDef.availableModes = list
    end
    return cvarDef.availableModes
end

local function getValueLabel(cvarDef, value)
    if cvarDef.type == "toggle" then
        return value == cvarDef.max and L.MODE_ENABLED or L.MODE_DISABLED
    elseif cvarDef.type == "mode" then
        for _, mode in ipairs(cvarDef.modes) do
            if mode.value == value then return mode.label end
        end
    elseif cvarDef.type == "dropdown" then
        return cvarDef.options[value]
    end
    return tostring(value)
end

-- A small coloured capsule used for "Available" / "Locked" on the feature cards.
local function createBadge(parent, text, color)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(18)
    badge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    badge:SetBackdropColor(color[1], color[2], color[3], 0.18)
    badge:SetBackdropBorderColor(color[1], color[2], color[3], 0.65)
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetText(text)
    badge.text:SetTextColor(color[1], color[2], color[3])
    badge:SetWidth(max(54, badge.text:GetStringWidth() + 18))
    return badge
end

-- Not every widget this addon builds is a Button. A UIDropDownMenu is a plain Frame in 3.3.5a and has
-- no Enable/Disable at all, so asking it to disable itself throws. Everything here goes through one
-- guarded switch instead of calling the method directly.
local function setWidgetEnabled(widget, enabled)
    if not widget then return end

    if widget.isDropDown then
        local fn = enabled and _G.UIDropDownMenu_EnableDropDown or _G.UIDropDownMenu_DisableDropDown
        if type(fn) == "function" then
            fn(widget)
        else
            widget.disabled = not enabled
        end
        return
    end

    if type(widget.Enable) == "function" and type(widget.Disable) == "function" then
        if enabled then widget:Enable() else widget:Disable() end
        return
    end

    -- last resort for a widget kind without the button API: stop it taking the mouse
    if type(widget.EnableMouse) == "function" then widget:EnableMouse(enabled and true or false) end
end

-- Steps by UTF-8 character so multibyte labels are never cut mid-character.
local function setTruncatedText(fontString, text, maxWidth)
    fontString:SetText(text)
    if fontString:GetStringWidth() <= maxWidth then return end
    local chars = {}
    for char in gmatch(text,"[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = char end
    local lo, hi = 0, #chars - 1
    while lo < hi do
        local mid = floor((lo + hi + 1) / 2)
        fontString:SetText(concat(chars, "", 1, mid).."...")
        if fontString:GetStringWidth() <= maxWidth then lo = mid else hi = mid - 1 end
    end
    fontString:SetText((gsub(concat(chars, "", 1, lo), "%s+$", "")).."...")
end

local function fitResetButton(button, maxWidth)
    local fontString = button:GetFontString()
    fontString:ClearAllPoints()
    fontString:SetPoint("CENTER")
    fontString:SetWidth(0)
    local naturalWidth = fontString:GetStringWidth() + 2 * RESET_TEXT_PADDING
    local width = max(RESET_MIN_WIDTH, min(naturalWidth, maxWidth))
    button:SetWidth(width)
    if naturalWidth > width then
        fontString:SetWidth(width - 2 * RESET_TEXT_PADDING)
    end
end

local function createResetButton(control, widgetFrame, cvarDef, x, y)
    local defaultLabel = getValueLabel(cvarDef, cvarDef.default) or tostring(cvarDef.default)
    local button = CreateFrame("Button", getFrameName(cvarDef.name, "ResetButton"), widgetFrame, "UIPanelButtonTemplate")
    button:SetHeight(20)
    button:SetText(format(L.RESET_TO, defaultLabel))
    fitResetButton(button, huge)
    button:SetPoint("TOPRIGHT", control, x, y)
    button:Disable()
    button:SetScript("OnClick", function()
        ACVar:SetCVarValue(cvarDef.name, cvarDef.default)
        ACVar:PrintCVarChange(cvarDef.name, cvarDef.default, cvarDef.type == "mode" and defaultLabel or nil)
        ACVar:UpdateUIForCVar(cvarDef)
        PlaySound("igMainMenuOptionFaerTab")
    end)
    return button
end

function ACVar:UpdateResetButtonState(cvarDef, currentValue)
    local resetButton = _G[getFrameName(cvarDef.name, "ResetButton")]
    if resetButton then
        if self.FormatNumber(currentValue) ~= self.FormatNumber(cvarDef.default) then
            resetButton:Enable()
        else
            resetButton:Disable()
        end
    end
end

function ACVar:UpdateUIForCVar(cvarDef)
    if self.IsReadOnly(cvarDef) then return end
    local cvarName = cvarDef.name
    -- An unpatched client has none of these CVars; show the shipped default rather than a blank row.
    local currentValue = self:GetCVarValue(cvarName)
    if currentValue == nil then currentValue = cvarDef.default end
    if cvarDef.type == "toggle" then
        _G[getFrameName(cvarName, "Checkbox")]:SetChecked(currentValue == cvarDef.max)
    elseif cvarDef.type == "slider" then
        local slider = _G[getFrameName(cvarName, "Slider")]
        slider.isUpdating = true
        slider:SetValue(currentValue or 0)
        slider.isUpdating = nil
        _G[getFrameName(cvarName, "SliderValue")]:SetText(tostring(currentValue))
    elseif cvarDef.type == "mode" then
        for i, mode in ipairs(availableModes(cvarDef)) do
            _G[getFrameName(cvarName, "Radio"..i)]:SetChecked(currentValue == mode.value)
        end
    elseif cvarDef.type == "dropdown" then
        local dropdown = _G[getFrameName(cvarName, "Dropdown")]
        UIDropDownMenu_SetSelectedValue(dropdown, currentValue)
        local label = cvarDef.options[currentValue] or tostring(currentValue)
        UIDropDownMenu_SetText(dropdown, label)
    end
    self:UpdateResetButtonState(cvarDef, currentValue)
end

local function getCVar(cvarName)
    return ACVar:GetCVarValue(cvarName)
end

local function fitContentHeight(content)
    content:SetScript("OnUpdate", nil)
    local lastControl = content.lastControl
    if lastControl and lastControl:GetBottom() then
        content:SetHeight(content:GetTop() - lastControl:GetBottom() + 20)
    end
end

local function layoutCardOnce(control)
    control:SetScript("OnUpdate", nil)
    control:layoutCard()
    control:GetParent():SetScript("OnUpdate", fitContentHeight)
end

local function applyCardHeight(control)
    if control.baseHeight then
        control:SetHeight(control.baseHeight + (control.reasonShown and CONSTANTS.FRAME.REASON_LINE_HEIGHT or 0))
    end
end

-- One place decides how a card looks: locked by the client, inactive because a prerequisite is off,
-- or live. Both dim the card, but only one reason is printed and it says which problem it is.
function ACVar:UpdateControlState(cvarDef)
    local control = _G[getFrameName(cvarDef.name, "Control")]
    if not control or not control.setReason then return end

    local locked = ACVar.CAP.isLocked(cvarDef)
    local inactive = (not locked) and cvarDef.requires and not cvarDef.requires.test(getCVar)

    local reason
    if locked then
        reason = (ACVar.CAP.lockReason(cvarDef))
    elseif inactive then
        reason = format(L.DISABLED_REASON, cvarDef.requires.reason)
    end

    control:setReason(reason, locked)
    control:SetAlpha((locked or inactive) and CONSTANTS.DIMMED_ALPHA or 1)

    for _, widget in ipairs(control.widgets or {}) do
        setWidgetEnabled(widget, not locked)
    end
    if locked and control.resetButton then control.resetButton:Disable() end
end

function ACVar:UpdateDependencies()
    for _, cvarList in pairs(CVARS) do
        for _, cvarDef in ipairs(cvarList) do
            if not ACVar.IsReadOnly(cvarDef) then
                self:UpdateControlState(cvarDef)
            end
        end
    end
    self:UpdateFeatureCards()
end

-- Feature cards have three states, not two: a group can work while a few of its entries are
-- FreakySphere-only (the Events and Macro groups), which must not read as either "fine" or "broken".
function ACVar:UpdateStatusPill()
    local pill = self.StatusPill
    if not pill then return end

    local status = ACVar.CAP.status()
    local style = CONSTANTS.STATUS[status]
    local text = status == "ok" and L.STATUS_PILL_OK or
        (status == "fork" and L.STATUS_PILL_FORK or L.STATUS_PILL_NONE)

    pill.text:SetText(text)
    pill.dot:SetTexture(style.bar[1], style.bar[2], style.bar[3], 1)
    pill:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], style.bg[4])
    pill:SetBackdropBorderColor(style.bar[1], style.bar[2], style.bar[3], 0.55)
    pill:SetWidth(pill.text:GetStringWidth() + 34)
end

function ACVar:UpdateFeatureCards()
    for _, entry in ipairs(self.FeatureCards or {}) do
        local control, feature = entry.control, entry.feature
        local available = ACVar.CAP.featureAvailable(feature)
        local partial = available and ACVar.MIXED_FEATURES[feature.id] and not ACVar.CAP.isFreakySphere

        local label, color, reason, isLock
        if partial then
            label, color = L.STATUS_PARTIAL, CONSTANTS.COLORS.WARN_TEXT
            reason, isLock = L.REASON_PARTIAL, true
        elseif available then
            label, color = L.STATUS_AVAILABLE, CONSTANTS.COLORS.OK_TEXT
        else
            label, color = L.STATUS_LOCKED, CONSTANTS.COLORS.LOCK_TEXT
            reason, isLock = ACVar.CAP.lockReason({ tier = feature.tier, probe = feature.probe }), true
        end

        control.badge.text:SetText(label)
        control.badge.text:SetTextColor(unpack(color))
        control.badge:SetBackdropColor(color[1], color[2], color[3], 0.18)
        control.badge:SetBackdropBorderColor(color[1], color[2], color[3], 0.65)
        control.badge:SetWidth(max(54, control.badge.text:GetStringWidth() + 18))
        control:SetAlpha(available and 1 or CONSTANTS.DIMMED_ALPHA)
        control:setReason(reason, isLock)
    end
end

function ACVar:UpdateAllUI()
    for _, cvarList in pairs(CVARS) do
        for _, cvarDef in ipairs(cvarList) do
            self:UpdateUIForCVar(cvarDef)
        end
    end
    -- One misbehaving widget must not take the whole window down with it: without this a single bad
    -- call aborts selectTab and leaves the frame half-built. The error is reported once, in chat.
    local ok, err = pcall(self.UpdateDependencies, self)
    if not ok and not self.stateErrorReported then
        self.stateErrorReported = true
        self:PrintMessage("%s", CONSTANTS.COLORS.ERROR..tostring(err)..CONSTANTS.COLORS.RESET)
    end
end

function ACVar:ToggleFrame(tabName)
    if self.Frame then
        local category = self.ResolveCategory(tabName)
        if self.Frame:IsShown() and not (category and category ~= self.CurrentCategory) then
            self:HideFrame()
        else
            self:ShowFrame(tabName)
        end
    end
end

-- Public API: AwesomeCVar:ToggleFrame([tabName])
-- tabName: "Rendering", "Nameplates", "TextToSpeech", "Interaction", "Other" or "About" (case and spaces ignored),
-- the localized tab name, or the former "Camera"/"UI" tabs (now part of "Rendering")
_G["AwesomeCVar"].ToggleFrame = function(self, tabName) ACVar:ToggleFrame(tabName) end

function ACVar:ShowFrame(tabName)
    if self.Frame then
        self.Frame:Show()
        self:UpdateAllUI()
        self:UpdateStatusPill()

        if _G["AwesomeCVarMinimapCheck"] then
            _G["AwesomeCVarMinimapCheck"]:SetChecked(not self.DB.minimap.hide)
        end
        if _G["AwesomeCVarGameMenuCheck"] then
            _G["AwesomeCVarGameMenuCheck"]:SetChecked(self.DB.showGameMenuButton)
        end
        if _G["AwesomeCVarChatMessagesCheck"] then
            _G["AwesomeCVarChatMessagesCheck"]:SetChecked(self.DB.showChatMessages)
        end
        if _G["AwesomeCVarVersionAlertsCheck"] then
            _G["AwesomeCVarVersionAlertsCheck"]:SetChecked(self.DB.showVersionAlerts)
        end

        local category = self.ResolveCategory(tabName)
        if self._SelectTab and self.TabsByName and category and self.TabsByName[category] then
            self._SelectTab(self.TabsByName[category])
        end
        PlaySound("igMainMenuContinue")
    end
end

function ACVar:HideFrame()
    if self.Frame then
        self.Frame:Hide()
        PlaySound("igMainMenuOptionFaerTab")
    end
end

function ACVar:ResetFramePosition(silent)
    if self.Frame then
        self.DB.frameWidth, self.DB.frameHeight = nil, nil
        self.Frame:SetWidth(CONSTANTS.FRAME.MAIN_WIDTH)
        self.Frame:SetHeight(CONSTANTS.FRAME.MAIN_HEIGHT)
        self.Frame:ClearAllPoints()
        self.Frame:SetPoint("CENTER")
        if not silent then
            self:PrintMessage(L.MSG_FRAME_RESET)
        end
    end
end

local function setClosesOnEscape(frameName, enabled)
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == frameName then
            tremove(UISpecialFrames, i)
        end
    end
    if enabled then
        tinsert(UISpecialFrames, frameName)
    end
end

function ACVar:CreateDefaultConfirmationPopup()
    if self.DefaultConfirmationPopup then return end

    local frame = createPopupFrame("AwesomeCVarDefaultConfirmationPopup", L.RESET_POPUP_TITLE, L.RESET_POPUP_TEXT)
    self.DefaultConfirmationPopup = frame

    local okayButton = createButton(frame, "AwesomeCVar_ConfirmResetButton", _G.OKAY)
    okayButton:SetPoint("BOTTOM", frame, "BOTTOM", -60, 20)
    okayButton:SetScript("OnClick", function()
        for _, cvarList in pairs(CVARS) do
            for _, cvarDef in ipairs(cvarList) do
                if not ACVar.IsReadOnly(cvarDef) then
                    self:SetCVarValue(cvarDef.name, cvarDef.default)
                end
            end
        end
        self:ResetFramePosition(true)
        if self.DB.showChatMessages then
            self:PrintMessage(L.MSG_DEFAULTS_RESET)
        end
        self:UpdateAllUI()
        frame:Hide()
        PlaySound("igMainMenuClose")
    end)

    local cancelButton = createButton(frame, "AwesomeCVar_CancelResetButton", _G.CANCEL)
    cancelButton:SetPoint("BOTTOM", frame, "BOTTOM", 60, 20)
    cancelButton:SetScript("OnClick", function()
        frame:Hide()
        PlaySound("igMainMenuOptionFaerTab")
    end)

    local escapeRestorer = CreateFrame("Frame")
    escapeRestorer:Hide()
    escapeRestorer:SetScript("OnUpdate", function(restorer)
        restorer:Hide()
        setClosesOnEscape("AwesomeCVarFrame", true)
    end)

    frame:SetScript("OnShow", function(self)
        self:Raise()
        setClosesOnEscape("AwesomeCVarFrame", false)
        PlaySound("igMainMenuOpen")
    end)
    frame:SetScript("OnHide", function()
        escapeRestorer:Show()
    end)

    setClosesOnEscape("AwesomeCVarDefaultConfirmationPopup", true)
end

function ACVar:AddGameMenuButton()
    local button = ACVar.GameMenuButton or CreateFrame("Button", "GameMenuButtonAwesomeCVar", _G.GameMenuFrame, "GameMenuButtonTemplate")
    if not button then return end

    button:SetText(L.ADDON_NAME_SHORT)
    button:ClearAllPoints()
    button:SetPoint("TOP", _G.GameMenuButtonContinue, "BOTTOM", 0, -1)
    button:SetScript("OnClick", function()
        self:ToggleFrame()
        HideUIPanel(_G.GameMenuFrame)
    end)
    button:SetScript("OnShow", function()
        if not self.DB.showGameMenuButton then
            button:Hide()
            return
        end
        button:SetScript("OnUpdate", function()
            local anchor, anchorBottom
            for _, child in ipairs({ _G.GameMenuFrame:GetChildren() }) do
                if child ~= button and child:IsShown() and child:GetObjectType() == "Button" then
                    local bottom = child:GetBottom()
                    if bottom and (not anchorBottom or bottom < anchorBottom) then
                        anchorBottom, anchor = bottom, child
                    end
                end
            end

            button:ClearAllPoints()
            button:SetPoint("TOP", anchor or _G.GameMenuButtonContinue, "BOTTOM", 0, -1)
            if not self.MenuExtended then
                _G.GameMenuFrame:SetHeight(_G.GameMenuFrame:GetHeight() + 24)
                self.MenuExtended = true
            end
            button:SetScript("OnUpdate", nil)
        end)
    end)
    button:SetScript("OnHide", function()
        if self.MenuExtended then
            _G.GameMenuFrame:SetHeight(_G.GameMenuFrame:GetHeight() - 24)
            self.MenuExtended = false
        end
    end)
    ACVar.GameMenuButton = button
end

function ACVar:CreateMainFrame()
    local frame = CreateFrame("Frame", "AwesomeCVarFrame", UIParent, "UIPanelDialogTemplate")
    self.Frame = frame

    frame:SetFrameStrata("DIALOG") -- not above game popups such as invites and ready checks
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetWidth(max(CONSTANTS.FRAME.MAIN_WIDTH, min(self.DB.frameWidth or 0, UIParent:GetWidth())))
    frame:SetHeight(max(CONSTANTS.FRAME.MAIN_HEIGHT, min(self.DB.frameHeight or 0, UIParent:GetHeight())))
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(CONSTANTS.FRAME.MAIN_WIDTH, CONSTANTS.FRAME.MAIN_HEIGHT)
    frame:SetMaxResize(UIParent:GetWidth(), UIParent:GetHeight())
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.numTabs = 0

    setClosesOnEscape("AwesomeCVarFrame", true)

    local titleFontString = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    titleFontString:SetPoint("TOP", 0, -8)
    titleFontString:SetText(L.MAIN_FRAME_TITLE)

    -- Client-state pill on the title row: always visible, one click jumps to the full explanation.
    local pill = CreateFrame("Button", "AwesomeCVarStatusPill", frame)
    pill:SetHeight(18)
    pill:SetPoint("TOPRIGHT", -16, -8)
    pill:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    pill.dot = pill:CreateTexture(nil, "ARTWORK")
    pill.dot:SetSize(7, 7)
    pill.dot:SetPoint("LEFT", 8, 0)
    pill.text = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pill.text:SetPoint("LEFT", pill.dot, "RIGHT", 6, 0)
    pill:SetScript("OnClick", function()
        local tab = ACVar.TabsByName and ACVar.TabsByName.About
        if tab and ACVar._SelectTab then ACVar._SelectTab(tab) end
        PlaySound("igCharacterInfoTab")
    end)
    pill:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        _G.GameTooltip:AddLine(ACVar.CAP.clientLabel(), 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    pill:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    ACVar.StatusPill = pill

    local tabStrip = CreateFrame("Frame", nil, frame)
    tabStrip:SetPoint("TOPLEFT", 20, -30)
    tabStrip:SetPoint("TOPRIGHT", -12, -30)
    tabStrip:SetHeight(CONSTANTS.FRAME.TAB_HEIGHT)
    local tabs, panels = {}, {}
    local currentPanel = nil
    local prevTab = nil

    local function selectTab(tab)
        if currentPanel then currentPanel:Hide() end
        local panel = panels[tab.categoryName]
        panel:Show()
        if abs(panel:GetScrollChild():GetWidth() - panel:GetWidth()) > 0.5 then
            panel:GetScript("OnSizeChanged")(panel, panel:GetWidth())
        end
        currentPanel = panel
        ACVar.CurrentCategory = tab.categoryName
        PanelTemplates_SetTab(frame, tab:GetID())
        ACVar:UpdateAllUI()
    end
    self._SelectTab = selectTab

    for _, categoryName in ipairs(CATEGORY_ORDER) do
        frame.numTabs = frame.numTabs + 1

        local tab = CreateFrame("CheckButton", "AwesomeCVarFrameTab"..frame.numTabs, tabStrip, "OptionsFrameTabButtonTemplate")
        tab.categoryName = categoryName
        tab:SetID(frame.numTabs)

        tab:SetText(ACVar.CATEGORY_NAMES[categoryName])
        tab:SetHeight(CONSTANTS.FRAME.TAB_HEIGHT)
        tab:SetWidth(tab:GetTextWidth() + 30)

        if prevTab then
            tab:SetPoint("LEFT", prevTab, "RIGHT", -16, 0)
        else
            tab:SetPoint("TOPLEFT", 0, 0)
        end
        prevTab = tab

        local panel = CreateFrame("ScrollFrame", "AwesomeCVarScrollFrame_"..categoryName, frame, "UIPanelScrollFrameTemplate")
        panel:SetPoint("TOPLEFT", 16, -61)
        panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -36, 64)
        panel:Hide()

        local subPanel = CreateFrame("Frame", "AwesomeCVarFramePanel_"..categoryName, panel)
        subPanel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 6)
        subPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, -6)
        subPanel:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        subPanel:SetBackdropColor(0.3, 0.3, 0.3, 0.8)
        subPanel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        subPanel:SetFrameLevel(panel:GetFrameLevel())

        local content = CreateFrame("Frame", "AwesomeCVarFrameContent_"..categoryName, subPanel)
        content:SetSize(panel:GetSize())
        content.controls = {}
        panel:SetScrollChild(content)
        panel:SetScript("OnSizeChanged", function(_, width)
            content:SetWidth(width)
            for _, control in ipairs(content.controls) do
                control:SetScript("OnUpdate", layoutCardOnce)
            end
        end)
        panels[categoryName] = panel
        tinsert(tabs, tab)

        tab:SetScript("OnClick", function(self)
            selectTab(self)
            PlaySound("igCharacterInfoTab")
        end)

        local cvarList = CVARS[categoryName]
        local lastControl = nil

        for _, cvarDef in ipairs(cvarList) do
            local isHeader = cvarDef.type == "header"
            local control = CreateFrame("Frame", getFrameName(cvarDef.name, "Control"), content)
            control:SetWidth(content:GetWidth() - 35)
            control.isHeader = isHeader
            control.widgets = {}
            tinsert(content.controls, control)

            if not lastControl then
                control:SetPoint("TOPLEFT", 10, -15)
            elseif isHeader then
                control:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, -25)
            else
                control:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, lastControl.isHeader and -4 or -15)
            end

            local paddingLeft, paddingRight, paddingTop, paddingBottom = 12, -12, -10, 10
            if isHeader then
                paddingLeft, paddingRight, paddingTop, paddingBottom = 2, 0, 0, 0
            else
                control:SetBackdrop({
                    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    tile = true, tileSize = 12, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 }
                })
                control:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
                control:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            end

            local text = control:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            text:SetPoint("TOPLEFT", control, "TOPLEFT", paddingLeft, paddingTop)
            text:SetJustifyH("LEFT")
            text:SetText(cvarDef.label)
            if isHeader then
                local font, size, flags = text:GetFont()
                text:SetFont(font, size + 2, flags)
                local rule = control:CreateTexture(nil, "ARTWORK")
                rule:SetTexture(1, 0.82, 0, 0.25)
                rule:SetHeight(1)
                rule:SetPoint("LEFT", text, "RIGHT", 8, 0)
                rule:SetPoint("RIGHT", control, "RIGHT")
            else
                text:SetWidth(control:GetWidth() + (paddingRight - paddingLeft))
            end

            local descText
            if cvarDef.desc then
                descText = control:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                descText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -8)
                descText:SetWidth(control:GetWidth() + (paddingRight - paddingLeft))
                descText:SetJustifyH("LEFT")
                descText:SetTextColor(unpack(CONSTANTS.COLORS.DESC_TEXT))
                -- a setting that only applies after a restart says so in the description, so it is
                -- impossible to toggle it and wonder why nothing changed
                local desc = cvarDef.desc
                if cvarDef.restart then
                    desc = desc .. "\n|cffff8000" .. L.TAG_RESTART .. "|r"
                end
                descText:SetText(desc)
            end

            local perfText
            if cvarDef.perf then
                perfText = control:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                perfText:SetPoint("TOPLEFT", descText or text, "BOTTOMLEFT", 0, -4)
                perfText:SetWidth(control:GetWidth() + (paddingRight - paddingLeft))
                perfText:SetJustifyH("LEFT")
                perfText:SetTextColor(unpack(CONSTANTS.COLORS.PERF_TEXT))
                perfText:SetText(format(L.PERF_FORMAT, cvarDef.perf))
            end

            -- Widget, anchored below label/desc/perf
            local widgetFrame = CreateFrame("Frame", getFrameName(cvarDef.name, "Widget"), control)
            widgetFrame:SetPoint("TOPLEFT", perfText or descText or text, "BOTTOMLEFT", 0, -8)
            widgetFrame:SetPoint("RIGHT", control, "RIGHT", paddingRight, 0)

            if cvarDef.type == "toggle" then
                widgetFrame:SetHeight(25)
                local checkbox = CreateFrame("CheckButton", getFrameName(cvarDef.name, "Checkbox"), widgetFrame, "UICheckButtonTemplate")
                checkbox:SetPoint("LEFT", widgetFrame, "LEFT", 0, 0)
                checkbox.cvarDef = cvarDef
                tinsert(control.widgets, checkbox)
                checkbox:SetScript("OnClick", function(self)
                    local checked = self:GetChecked()
                    local newVal = checked and self.cvarDef.max or self.cvarDef.min
                    ACVar:SetCVarValue(self.cvarDef.name, newVal)
                    ACVar:UpdateResetButtonState(self.cvarDef, newVal)
                    ACVar:PrintCVarChange(self.cvarDef.name, newVal)
                    PlaySound(checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
                end)

            elseif cvarDef.type == "slider" then
                widgetFrame:SetHeight(40)
                local slider = CreateFrame("Slider", getFrameName(cvarDef.name, "Slider"), widgetFrame, "OptionsSliderTemplate")
                tinsert(control.widgets, slider)
                _G[slider:GetName().."Low"]:SetText(cvarDef.min)
                _G[slider:GetName().."High"]:SetText(cvarDef.max)
                slider:SetMinMaxValues(cvarDef.min, cvarDef.max)
                slider:SetValueStep(cvarDef.step or 1)
                slider:SetPoint("TOPLEFT", widgetFrame, "TOPLEFT", 0, -8)
                slider:SetPoint("RIGHT", widgetFrame)

                local valueText = widgetFrame:CreateFontString(getFrameName(cvarDef.name, "SliderValue"), "ARTWORK", "GameFontNormal")
                valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
                slider.cvarDef = cvarDef
                slider.valueText = valueText

                slider:SetScript("OnValueChanged", function(self, val)
                    if self.isUpdating then return end
                    val = ACVar.FormatNumber(val)
                    self.valueText:SetText(tostring(val))
                    ACVar:SetCVarValue(self.cvarDef.name, val)
                    self.pendingValue = val
                    ACVar:UpdateResetButtonState(self.cvarDef, val)
                end)
                slider:SetScript("OnMouseUp", function(self)
                    if self.pendingValue then
                        ACVar:PrintCVarChange(self.cvarDef.name, self.pendingValue)
                        self.pendingValue = nil
                    end
                end)

            elseif cvarDef.type == "dropdown" then
                widgetFrame:SetHeight(40)
                local dropdown = CreateFrame("Frame", getFrameName(cvarDef.name, "Dropdown"), widgetFrame, "UIDropDownMenuTemplate")
                dropdown:SetPoint("TOPLEFT", widgetFrame, -16, 0)
                dropdown:SetPoint("TOPRIGHT", widgetFrame)
                dropdown.cvarDef = cvarDef
                dropdown.isDropDown = true
                tinsert(control.widgets, dropdown)
                dropdown.relativeTo = dropdown
                dropdown.point = "TOPLEFT"
                dropdown.relativePoint = "BOTTOMLEFT"
                dropdown.xOffset = 18
                dropdown.yOffset = 2

                control.dropdown = dropdown

                local function getCurrentValue()
                    return ACVar:GetCVarValue(cvarDef.name) or cvarDef.default
                end
                local function setClosedLabel(val)
                    UIDropDownMenu_SetText(dropdown, cvarDef.options[val] or tostring(val))
                    UIDropDownMenu_SetSelectedValue(dropdown, val)
                end
                local function getMinMaxIndex(t)
                    local minK, maxK
                    for k in pairs(t) do
                        if type(k) == "number" then
                            if not minK or k < minK then minK = k end
                            if not maxK or k > maxK then maxK = k end
                        end
                    end
                    return minK or 0, maxK or -1
                end
                UIDropDownMenu_Initialize(dropdown, function(self, level)
                    local cur = getCurrentValue()
                    local minK, maxK = getMinMaxIndex(cvarDef.options)
                    for i = minK, maxK do
                        local label = cvarDef.options[i]
                        if label ~= nil then
                            local info = UIDropDownMenu_CreateInfo()
                            info.text = label
                            info.value = i
                            info.checked = (i == cur)
                            info.func = function()
                                UIDropDownMenu_SetSelectedValue(dropdown, i)
                                UIDropDownMenu_SetText(dropdown, label)
                                ACVar:SetCVarValue(cvarDef.name, i)
                                ACVar:UpdateResetButtonState(cvarDef, i)
                                ACVar:PrintCVarChange(cvarDef.name, i)
                                PlaySound("igMainMenuOptionCheckBoxOn")
                                CloseDropDownMenus()
                            end
                            UIDropDownMenu_AddButton(info, level)
                        end
                    end
                    _G["DropDownList"..(level or 1)].maxWidth = _G[dropdown:GetName().."Middle"]:GetWidth() + paddingRight
                end)
                setClosedLabel(getCurrentValue())


            elseif cvarDef.type == "mode" then
                control.radios = {}
                for j, mode in ipairs(availableModes(cvarDef)) do
                    local radio = CreateFrame("CheckButton", getFrameName(cvarDef.name, "Radio"..j), widgetFrame, "UIRadioButtonTemplate")
                    local label = radio:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    label:SetPoint("TOPLEFT", radio, "TOPRIGHT", 5, -2)
                    label:SetJustifyH("LEFT")
                    label:SetJustifyV("TOP")
                    label:SetWordWrap(true)
                    label:SetNonSpaceWrap(false)
                    label:SetText(mode.label)

                    radio.cvarDef = cvarDef
                    radio.modeValue = mode.value
                    radio.modeLabel = mode.label
                    radio.label = label
                    tinsert(control.widgets, radio)
                    radio:SetScript("OnClick", function(self)
                        for k = 1, #availableModes(self.cvarDef) do
                            _G[getFrameName(self.cvarDef.name, "Radio"..k)]:SetChecked(false)
                        end
                        self:SetChecked(true)
                        ACVar:SetCVarValue(self.cvarDef.name, self.modeValue)
                        ACVar:UpdateResetButtonState(self.cvarDef, self.modeValue)
                        ACVar:PrintCVarChange(self.cvarDef.name, self.modeValue, self.modeLabel)
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    end)
                    tinsert(control.radios, radio)
                end

            elseif cvarDef.type == "status" then
                -- Client-state banner: the one place that says, in colour, what this client can do.
                control.isStatus = true
                text:Hide()
                if descText then descText:Hide() end
                widgetFrame:SetHeight(1)

                local status = ACVar.CAP.status()
                local style = CONSTANTS.STATUS[status]
                control:SetBackdropColor(style.bg[1], style.bg[2], style.bg[3], style.bg[4])
                control:SetBackdropBorderColor(style.bar[1], style.bar[2], style.bar[3], 0.45)

                local accent = control:CreateTexture(nil, "ARTWORK")
                accent:SetTexture(style.bar[1], style.bar[2], style.bar[3], 1)
                accent:SetWidth(3)
                accent:SetPoint("TOPLEFT", control, "TOPLEFT", 3, -3)
                accent:SetPoint("BOTTOMLEFT", control, "BOTTOMLEFT", 3, 3)

                local title = control:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
                title:SetPoint("TOPLEFT", control, "TOPLEFT", 16, -12)
                title:SetJustifyH("LEFT")
                title:SetTextColor(style.bar[1], style.bar[2], style.bar[3])
                title:SetText(status == "ok" and L.STATUS_TITLE_OK or
                    (status == "fork" and L.STATUS_TITLE_FORK or L.STATUS_TITLE_NONE))
                control.statusTitle = title

                local detail = control:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                detail:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
                detail:SetJustifyH("LEFT")
                detail:SetTextColor(unpack(CONSTANTS.COLORS.DESC_TEXT))
                detail:SetText(ACVar.CAP.clientLabel())
                control.statusDetail = detail

                if status ~= "ok" then
                    local warn = control:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                    warn:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -6)
                    warn:SetJustifyH("LEFT")
                    warn:SetTextColor(unpack(CONSTANTS.COLORS.LOCK_TEXT))
                    warn:SetText(status == "fork" and L.STATUS_WARN_FORK or L.STATUS_WARN_NONE)
                    control.statusWarn = warn
                end

            elseif cvarDef.type == "feature" then
                local feature = ACVar.FEATURES_BY_ID[cvarDef.group]
                control.feature = feature
                widgetFrame:SetHeight(1)

                local badge = createBadge(control, "", CONSTANTS.COLORS.OK_TEXT)
                badge:SetPoint("TOPRIGHT", control, "TOPRIGHT", paddingRight, paddingTop - 1)
                control.badge = badge

                local names = widgetFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                names:SetPoint("TOPLEFT", 0, 0)
                names:SetJustifyH("LEFT")
                names:SetTextColor(unpack(CONSTANTS.COLORS.DESC_TEXT))
                names:SetText(concat(feature.names, "   ·   "))
                control.nameList = names

                self.FeatureCards = self.FeatureCards or {}
                tinsert(self.FeatureCards, { control = control, feature = feature })

            elseif cvarDef.type == "link" then
                -- read-only URL box: click selects it for Ctrl+C, the button copies through CopyToClipboard
                widgetFrame:SetHeight(24)
                local url = cvarDef.url
                local editBox = CreateFrame("EditBox", getFrameName(cvarDef.name, "EditBox"), widgetFrame, "InputBoxTemplate")
                editBox:SetAutoFocus(false)
                tinsert(control.widgets, editBox)
                editBox:SetHeight(20)
                editBox:SetPoint("LEFT", widgetFrame, "LEFT", 6, 0)
                editBox:SetPoint("RIGHT", widgetFrame, "RIGHT", -96, 0)
                editBox:SetText(url)
                editBox:SetCursorPosition(0)
                editBox:SetScript("OnTextChanged", function(self)
                    if self:GetText() ~= url then
                        self:SetText(url)
                        self:HighlightText()
                    end
                end)
                editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
                editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
                editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

                local copyButton = createButton(widgetFrame, getFrameName(cvarDef.name, "CopyButton"), L.COPY, 86, 22)
                copyButton:SetPoint("RIGHT", widgetFrame, "RIGHT", 0, 0)
                tinsert(control.widgets, copyButton)
                copyButton:SetScript("OnClick", function()
                    if _G.CopyToClipboard then
                        _G.CopyToClipboard(url)
                        ACVar:PrintMessage(L.MSG_COPIED)
                        PlaySound("igMainMenuOptionCheckBoxOn")
                    else
                        editBox:SetFocus()
                    end
                end)

            elseif cvarDef.type ~= "description" and not isHeader then
                widgetFrame:SetHeight(20)
                text:SetText(text:GetText().." (Unsupported type: "..tostring(cvarDef.type)..")")
            else
                widgetFrame:SetHeight(0)
            end

            local resetButton
            if not ACVar.IsReadOnly(cvarDef) then
                resetButton = createResetButton(control, widgetFrame, cvarDef, paddingRight, paddingTop)
                control.resetButton = resetButton
            end

            -- Reason line, shared by "a prerequisite is off" and "the client cannot do this at all".
            -- Created for every card so a lock can appear later without rebuilding the layout.
            local holder = CreateFrame("Frame", nil, content)
            holder:SetAllPoints(control)
            holder:SetFrameLevel(control:GetFrameLevel() + 10)
            holder:Hide()
            local reason = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            reason:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", paddingLeft, paddingBottom)
            reason:SetJustifyH("LEFT")
            reason:SetWordWrap(false)
            reason:SetTextColor(unpack(CONSTANTS.COLORS.INACTIVE_TEXT))
            control.reasonHolder = holder
            control.reasonText = reason
            control.reasonShown = false

            function control:setReason(text, isLock)
                if text then
                    self.reasonText:SetText(text)
                    self.reasonText:SetTextColor(unpack(isLock and CONSTANTS.COLORS.LOCK_TEXT or
                        CONSTANTS.COLORS.INACTIVE_TEXT))
                end
                local shown = text ~= nil
                if self.reasonShown ~= shown then
                    self.reasonShown = shown
                    if shown then self.reasonHolder:Show() else self.reasonHolder:Hide() end
                    applyCardHeight(self)
                    self:GetParent():SetScript("OnUpdate", fitContentHeight)
                end
            end

            function control:layoutCard()
                self:SetWidth(content:GetWidth() - 35)
                if self.isStatus then
                    local w = self:GetWidth() - 34
                    self.statusTitle:SetWidth(w)
                    self.statusDetail:SetWidth(w)
                    if self.statusWarn then self.statusWarn:SetWidth(w) end
                    local h = 12 + self.statusTitle:GetStringHeight() + 4 + self.statusDetail:GetStringHeight()
                    if self.statusWarn then h = h + 6 + self.statusWarn:GetStringHeight() end
                    self.baseHeight = h + 12
                    applyCardHeight(self)
                    return
                end
                local innerWidth = self:GetWidth() + (paddingRight - paddingLeft)
                if not isHeader then
                    if resetButton then
                        fitResetButton(resetButton, innerWidth - min(text:GetStringWidth(), innerWidth / 2) - 8)
                    end
                    local reserved = resetButton and (resetButton:GetWidth() + 8) or 0
                    if self.badge then reserved = max(reserved, self.badge:GetWidth() + 8) end
                    text:SetWidth(innerWidth - reserved)
                end
                if descText then descText:SetWidth(innerWidth) end
                if perfText then perfText:SetWidth(innerWidth) end
                if reason then reason:SetWidth(innerWidth) end
                if self.nameList then
                    self.nameList:SetWidth(innerWidth)
                    widgetFrame:SetHeight(self.nameList:GetStringHeight() + 2)
                end
                if self.dropdown then UIDropDownMenu_SetWidth(self.dropdown, self:GetWidth() - 40) end

                local descH = descText and (descText:GetStringHeight() + 8 + 8) or 0
                local perfH = perfText and (perfText:GetStringHeight() + 4) or 0

                if cvarDef.type == "mode" and self.radios then
                    local totalH = 0
                    local prevRadio
                    for i, radio in ipairs(self.radios) do
                        local radioW = radio:GetWidth()
                        if not radioW or radioW == 0 then radioW = 16 end
                        local radioH = radio:GetHeight()
                        if not radioH or radioH == 0 then radioH = 16 end
                        radio.label:SetWidth(control:GetWidth() - 24 - radioW - 5)
                        local h = max(radioH, radio.label:GetStringHeight() + 2)
                        local labelW = min(radio.label:GetStringWidth(), radio.label:GetWidth())
                        radio:SetHitRectInsets(0, -(5 + labelW), 0, -(h - radioH))

                        radio:ClearAllPoints()
                        if prevRadio then
                            radio:SetPoint("TOPLEFT", prevRadio, "TOPLEFT", 0, -(prevRadio.itemHeight + 4))
                        else
                            radio:SetPoint("TOPLEFT", widgetFrame, "TOPLEFT", 0, 0)
                        end
                        radio.itemHeight = h

                        totalH = totalH + h + (i < #self.radios and 4 or 0)
                        prevRadio = radio
                    end
                    widgetFrame:SetHeight(totalH)
                end

                local widgetH = (cvarDef.type ~= "description" and not isHeader) and (widgetFrame:GetHeight() + 8) or 0
                self.baseHeight = abs(paddingTop) + text:GetStringHeight() + descH + perfH + widgetH + paddingBottom
                applyCardHeight(self)
            end
            control:SetScript("OnUpdate", layoutCardOnce)

            lastControl = control
        end

        content.lastControl = lastControl
        content:SetScript("OnUpdate", fitContentHeight)
    end

    self.TabsByName = {}
    for _, tab in ipairs(tabs) do
        self.TabsByName[tab.categoryName] = tab
    end

    if #tabs > 0 then
        PanelTemplates_SetNumTabs(frame, frame.numTabs)
        selectTab(self.TabsByName[ACVar.DEFAULT_CATEGORY] or tabs[1])
    end

    local okayButton = createButton(frame, "AwesomeCVarOkayButton", _G.OKAY)
    okayButton:SetPoint("BOTTOMRIGHT", -24, 16)
    okayButton:SetScript("OnClick", function()
        ACVar:HideFrame()
    end)

    local resizeGrip = CreateFrame("Button", "AwesomeCVarResizeGrip", frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        ACVar.DB.frameWidth, ACVar.DB.frameHeight = frame:GetWidth(), frame:GetHeight()
    end)

    local defaultsButton = createButton(frame, "AwesomeCVarDefaultsButton", _G.DEFAULTS)
    defaultsButton:SetPoint("BOTTOMLEFT", 16, 16)
    defaultsButton:SetScript("OnClick", function()
        self.DefaultConfirmationPopup:Show()
    end)

    -- Labels share the row between Defaults and Okay evenly and are cut with "..." past their share;
    -- the tooltip always shows the full label.
    local optionChecks = {}
    local function createOptionCheck(name, label, tooltip, checked, onClick)
        local check = CreateFrame("CheckButton", name, frame, "UICheckButtonTemplate")
        local previous = optionChecks[#optionChecks]
        if previous then
            check:SetPoint("LEFT", _G[previous:GetName().."Text"], "RIGHT", 12, 0)
        else
            check:SetPoint("LEFT", defaultsButton, "RIGHT", 12, 0)
        end
        check.label, check.tooltip = label, tooltip
        check:SetChecked(checked)
        check:SetScript("OnClick", function(self)
            onClick(self:GetChecked() and true or false)
            PlaySound("igMainMenuOptionCheckBoxOn")
        end)
        check:SetScript("OnEnter", function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:AddLine(self.label)
            _G.GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            _G.GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        optionChecks[#optionChecks + 1] = check
    end

    createOptionCheck("AwesomeCVarMinimapCheck", L.MINIMAP_ICON, L.MINIMAP_ICON_DESC, not ACVar.DB.minimap.hide,
        function(checked)
            ACVar.DB.minimap.hide = not checked
            ACVar:UpdateMinimapButton()
        end)
    createOptionCheck("AwesomeCVarGameMenuCheck", L.GAME_MENU_BUTTON, L.GAME_MENU_BUTTON_DESC, ACVar.DB.showGameMenuButton,
        function(checked)
            ACVar.DB.showGameMenuButton = checked
            ACVar:UpdateGameMenuButton()
        end)
    createOptionCheck("AwesomeCVarChatMessagesCheck", L.CHAT_MESSAGES, L.CHAT_MESSAGES_DESC, ACVar.DB.showChatMessages,
        function(checked) ACVar.DB.showChatMessages = checked end)
    createOptionCheck("AwesomeCVarVersionAlertsCheck", L.VERSION_ALERTS, L.VERSION_ALERTS_DESC, ACVar.DB.showVersionAlerts,
        function(checked) ACVar.DB.showVersionAlerts = checked end)

    -- Refit on show too: the ElvUI skin resizes the boxes after creation.
    local function fitOptionLabels()
        local available = frame:GetWidth() - (16 + defaultsButton:GetWidth()) - (24 + okayButton:GetWidth()) - 12
        for _, check in ipairs(optionChecks) do
            local _, _, _, textX = _G[check:GetName().."Text"]:GetPoint(1)
            available = available - 12 - check:GetWidth() - (textX or 0)
        end
        local maxWidth = max(0, floor(available / #optionChecks))
        for _, check in ipairs(optionChecks) do
            local text = _G[check:GetName().."Text"]
            local _, _, _, textX = text:GetPoint(1)
            setTruncatedText(text, check.label, maxWidth)
            -- The label hovers and clicks as the checkbox.
            check:SetHitRectInsets(0, -((textX or 0) + text:GetStringWidth()), 0, 0)
        end
    end
    frame:HookScript("OnSizeChanged", fitOptionLabels)
    frame:HookScript("OnShow", fitOptionLabels)
    fitOptionLabels()

    self:UpdateStatusPill()
end