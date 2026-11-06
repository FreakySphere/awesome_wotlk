local _, ACVar = ...

local _G = _G
local type = type
local tonumber = tonumber
local format = string.format

-- ------------------------------------------------------------------------------------------------
-- What is actually installed?
--
-- The DLL publishes two globals: `AwesomeWotlk` (numeric API level) and, since FreakySphere, the
-- `FreakySphere` version string. Everything the addon offers is gated on those *and* on a direct probe
-- of the function itself, so a future fork that ships the same API keeps working without a new check.
--
--   unpatched : AwesomeWotlk is nil            -> nothing works, every control is read-only
--   fork      : AwesomeWotlk < our level       -> the v38 surface works, FreakySphere additions are locked
--   ok        : FreakySphere present, level ok -> everything works
-- ------------------------------------------------------------------------------------------------
local CAP = {}
ACVar.CAP = CAP

CAP.modVersion = tonumber(_G.AwesomeWotlk) or 0
CAP.brandVersion = _G.FreakySphere
CAP.isPatched = CAP.modVersion > 0
CAP.isFreakySphere = (CAP.brandVersion ~= nil) or (CAP.modVersion >= ACVar.MOD_VERSION)
-- v39 brought a second wave of settings (world culling, LuaJIT, clamp views, ...). They exist on
-- upstream v39 as well, so they are not "fs" -- but a v38 fork does not have them and a control that
-- silently does nothing is worse than a locked one.
CAP.hasV39 = CAP.modVersion >= 39
CAP.addonVersion = ACVar.MOD_VERSION

function CAP.hasFunction(name)
    return type(_G[name]) == "function"
end

function CAP.hasTable(name)
    return type(_G[name]) == "table"
end

-- "base" features ship with any awesome_wotlk, "v39" with upstream v39 or newer, "fs" ones only with
-- FreakySphere
function CAP.tierAvailable(tier)
    if tier == "fs" then return CAP.isFreakySphere end
    if tier == "v39" then return CAP.hasV39 end
    return CAP.isPatched
end

function CAP.status()
    if not CAP.isPatched then return "unpatched" end
    if not CAP.isFreakySphere then return "fork" end
    return "ok"
end

-- The client line shown in the status banner and the About tab
function CAP.clientLabel()
    if not CAP.isPatched then return ACVar.L.STATUS_CLIENT_NONE end
    if CAP.brandVersion then
        return format(ACVar.L.STATUS_CLIENT_FS, tostring(CAP.brandVersion), CAP.modVersion)
    end
    return format(ACVar.L.STATUS_CLIENT_FORK, CAP.modVersion)
end

-- ------------------------------------------------------------------------------------------------
-- Per-definition gating. A control is locked when the client cannot honour it; `reason` is what the
-- card prints underneath, so the user always knows which of the two problems they are looking at.
-- ------------------------------------------------------------------------------------------------
function CAP.lockReason(def)
    local tier = def.tier or "base"

    if not CAP.isPatched then
        return ACVar.L.REASON_UNPATCHED, "unpatched"
    end

    if tier == "fs" and not CAP.isFreakySphere then
        return ACVar.L.REASON_FORK, "fork"
    end

    if tier == "v39" and not CAP.hasV39 then
        return ACVar.L.REASON_V39, "v39"
    end

    if def.probe and not def.probe() then
        return ACVar.L.REASON_MISSING_API, "missing"
    end

    return nil, nil
end

function CAP.isLocked(def)
    local _, kind = CAP.lockReason(def)
    return kind ~= nil, kind
end

-- ------------------------------------------------------------------------------------------------
-- Feature groups listed in the Features tab. `probe` is the single source of truth for "does this
-- work here"; the list of names is documentation, and is copied verbatim by the Copy button.
-- ------------------------------------------------------------------------------------------------
local function fsProbe(name)
    return function() return CAP.hasFunction(name) end
end

ACVar.FEATURES = {
    {
        id = "NameplateAPI",
        tier = "base",
        probe = function() return CAP.hasTable("C_NamePlate") end,
        names = {
            "C_NamePlate.GetNamePlates",
            "C_NamePlate.GetNamePlateForUnit",
            "C_NamePlate.GetNamePlateForGUID",
            "C_NamePlate.GetNamePlateByGUID",
            "C_NamePlate.GetNamePlateTokenByGUID",
            "C_NamePlate.GetGUIDForNamePlate",
            "nameplate:GetStackingEnabled",
            "nameplate:SetStackingEnabled",
            "nameplate:GetOcclusionEnabled",
            "nameplate:SetOcclusionEnabled",
        },
    },
    {
        id = "DistanceAPI",
        tier = "fs",
        probe = fsProbe("GetDistanceForUnit"),
        names = {
            "GetDistanceForUnit",
            "GetDistanceForGUID",
            "GetDistanceForNamePlate",
            "GetNamePlateForGUID",
            "GetGUIDForNamePlate",
            "C_NamePlate.GetNamePlatesDistance",
            "C_NamePlate.GetNamePlatesDistanceList",
        },
    },
    {
        id = "WorldQueries",
        tier = "fs",
        probe = fsProbe("UnitInLOS"),
        names = {
            "UnitInLOS",
            "UnitPosition",
            "UnitFacing",
            "AmBehind",
            "UnitExistsGUID",
            "TargetUnitByGUID",
            "UnitGUIDByName",
        },
    },
    {
        id = "UnitAPI",
        tier = "base",
        probe = fsProbe("UnitTokenFromGUID"),
        names = {
            "UnitIsControlled",
            "UnitIsDisarmed",
            "UnitIsFlagSilenced",
            "UnitOccupations",
            "UnitOwner",
            "UnitTokenFromGUID",
        },
    },
    {
        id = "ItemSpellAPI",
        tier = "base",
        probe = fsProbe("GetItemInfoInstant"),
        names = {
            "GetItemInfoInstant",
            "GetInventoryItemTransmog",
            "GetSpellBaseCooldown",
        },
    },
    {
        id = "TTSAPI",
        tier = "base",
        probe = function() return CAP.hasTable("C_VoiceChat") end,
        names = {
            "C_VoiceChat.GetTtsVoices",
            "C_VoiceChat.GetRemoteTtsVoices",
            "C_VoiceChat.SpeakText",
            "C_VoiceChat.StopSpeakingText",
            "C_TTSSettings.GetSpeechRate",
            "C_TTSSettings.GetSpeechVolume",
            "C_TTSSettings.GetSpeechVoiceID",
            "C_TTSSettings.GetVoiceOptionName",
            "C_TTSSettings.SetDefaultSettings",
            "C_TTSSettings.SetSpeechRate",
            "C_TTSSettings.SetSpeechVolume",
            "C_TTSSettings.SetVoiceOption",
            "C_TTSSettings.SetVoiceOptionByName",
            "C_TTSSettings.RefreshVoices",
        },
    },
    {
        id = "WindowAPI",
        tier = "base",
        probe = fsProbe("FlashWindow"),
        names = {
            "FlashWindow",
            "IsWindowFocused",
            "FocusWindow",
            "CopyToClipboard",
            "CaptureFrame",
            "QueueInteract",
        },
    },
    {
        id = "EventsAPI",
        tier = "base",
        probe = function() return CAP.hasTable("C_NamePlate") end,
        names = {
            "NAME_PLATE_CREATED",
            "NAME_PLATE_UNIT_ADDED",
            "NAME_PLATE_UNIT_REMOVED",
            "NAME_PLATE_OWNER_CHANGED",
            "VOICE_CHAT_TTS_PLAYBACK_STARTED",
            "VOICE_CHAT_TTS_PLAYBACK_FINISHED",
            "VOICE_CHAT_TTS_PLAYBACK_FAILED",
            "VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE",
            "VOICE_CHAT_TTS_VOICES_UPDATE",
        },
    },
    {
        id = "MacroAPI",
        tier = "base",
        probe = function() return CAP.hasTable("C_NamePlate") end,
        names = {
            "@cursor",
            "@playerlocation",
            "@focuslocation",
            "@targetlocation",
        },
    },
}

-- NAME_PLATE_OWNER_CHANGED and the two extra macro conditionals came with FreakySphere, so the
-- Events and Macro groups report themselves as mixed rather than claiming the whole group is fine.
ACVar.MIXED_FEATURES = {
    EventsAPI = { "NAME_PLATE_OWNER_CHANGED" },
    MacroAPI = { "@focuslocation", "@targetlocation" },
}

function CAP.featureAvailable(feature)
    if not CAP.tierAvailable(feature.tier) then return false end
    return feature.probe ~= nil and feature.probe() or false
end

ACVar.FEATURES_BY_ID = {}
for _, feature in ipairs(ACVar.FEATURES) do
    ACVar.FEATURES_BY_ID[feature.id] = feature
end

-- ------------------------------------------------------------------------------------------------
-- One-line summary for chat on login.
-- ------------------------------------------------------------------------------------------------
function CAP.summary()
    local locked, total = 0, 0
    for _, feature in ipairs(ACVar.FEATURES) do
        total = total + 1
        if not CAP.featureAvailable(feature) then locked = locked + 1 end
    end
    return locked, total
end
