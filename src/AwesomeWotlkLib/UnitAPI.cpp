#include "UnitAPI.h"

#include <array>
#include <cmath>
#include <cstring>
#include <format>
#include <string>

#include "Extensions.h"
#include "NamePlates.h"

#include "ObjectManager/CGUnit_C.h"
#include "include/Game/CGGameUI.h"
#include "include/Lib/Lua.h"
#include "include/Math/Math.h"

namespace {
bool checkToken(LuaState* l, const char* token, guid_t guid) {
    if (const guid_t guid_t = object_mgr::guidFromUnitId{}(token); guid_t == guid) {
        lua::pushString(l, token);
        return true;
    }
    return false;
}

bool checkIndexedTokens(LuaState* l, const char* base, int start, int end, guid_t guid) {
    for (int i = start; i <= end; ++i) {
        std::string token = std::format("{}{}", base, i);
        if (checkToken(l, token.c_str(), guid)) { return true; }
    }
    return false;
}

int unitHasFlag(LuaState* l, uint32_t flag) {
    if (!lua::isString(l, 1)) { lua::throwError(l, "Usage: %s(unitID)"); }
    auto* unit = object_mgr::get<CGUnit_C>(object_mgr::guidFromUnitId{}(lua::checkString(l, 1)), eTypemaskUnit);
    if ((unit != nullptr) && ((unit->descriptors_->flags & flag) != 0u)) {
        lua::pushNumber(l, 1);
        return 1;
    }
    return 0;
}
}  // namespace

namespace {
int luaUnitIsControlled(LuaState* l) {
    return unitHasFlag(l, eUnitFlagFleeing | eUnitFlagConfused | eUnitFlagStunned | eUnitFlagPacified);
}

int luaUnitIsDisarmed(LuaState* l) { return unitHasFlag(l, eUnitFlagDisarmed); }

// FreakySphere: this used to be registered as `UnitIsSilenced`, which already exists in 3.3.5a as a
// voice-chat query, UnitIsSilenced("name", "channel"). Overwriting it broke every caller of the native
// function -- Grid2's unit popup mute menu among them. The flag check keeps a name of its own now and
// the client's own UnitIsSilenced stays untouched.
int luaUnitIsFlagSilenced(LuaState* l) { return unitHasFlag(l, eUnitFlagSilenced); }

// ------------------------------------------------------------------------------------------------
// UnitIsSilenced: two contracts behind one name.
//
// Every fork in this family registered its one-argument silence check as `UnitIsSilenced`, shadowing
// the client's voice-chat query. Renaming ours fixed Grid2 but left addons written against those forks
// calling UnitIsSilenced(unit) and getting nil. One function can honour both, decided by argument
// count:
//
//   UnitIsSilenced(unit)            -> the flag check the forks shipped
//   UnitIsSilenced(name, channel)   -> forwarded verbatim to the client's own function
//
// The original is captured into the registry the first time a real function is found, and an install
// flag stops us ever capturing our own dispatcher on a later reload.
constexpr const char* kOriginalSilencedKey = "FreakySphere.UnitIsSilenced.original";
constexpr const char* kSilencedInstalledKey = "FreakySphere.UnitIsSilenced.installed";
constexpr int kMultiRet = -1;

int luaUnitIsSilenced(LuaState* l) {
    const int argc = lua::getTop(l);

    if (argc >= 2) {
        lua::getField(l, lua::kRegistryindex, kOriginalSilencedKey);
        if (lua::isFunction(l, -1)) {
            lua::pushValue(l, 1);
            lua::pushValue(l, 2);
            if (lua::pcall(l, 2, kMultiRet, 0) == 0) { return lua::getTop(l) - argc; }
            lua::pop(l, 1);
            return 0;
        }
        lua::pop(l, 1);
        return 0;
    }

    return unitHasFlag(l, eUnitFlagSilenced);
}

// Safe to call repeatedly: it only acts once, and only when the client's own function is really there.
void installUnitIsSilenced(LuaState* l) {
    lua::getField(l, lua::kRegistryindex, kSilencedInstalledKey);
    const bool installed = lua::toBoolean(l, -1);
    lua::pop(l, 1);
    if (installed) { return; }

    lua::getGlobal(l, "UnitIsSilenced");
    if (!lua::isFunction(l, -1)) {
        lua::pop(l, 1);  // FrameXML has not defined it yet; try again on the next entry
        return;
    }
    lua::setField(l, lua::kRegistryindex, kOriginalSilencedKey);

    lua::pushBoolean(l, true);
    lua::setField(l, lua::kRegistryindex, kSilencedInstalledKey);

    lua::pushCFunction(l, luaUnitIsSilenced);
    lua::setGlobal(l, "UnitIsSilenced");
}

int luaUnitOccupations(LuaState* l) {
    if (!lua::isString(l, 1)) { lua::throwError(l, "Usage: %s(unitID)"); }
    auto* unit = object_mgr::get<CGUnit_C>(object_mgr::guidFromUnitId{}(lua::checkString(l, 1)), eTypemaskUnit);
    if (unit == nullptr) { return 0; }
    lua::pushNumber(l, unit->descriptors_->npc_flags);
    return 1;
}

int luaUnitOwner(LuaState* l) {
    if (!lua::isString(l, 1)) { lua::throwError(l, "Usage: %s(unitID)"); }
    auto* unit = object_mgr::get<CGUnit_C>(object_mgr::guidFromUnitId{}(lua::checkString(l, 1)), eTypemaskUnit);
    if (unit == nullptr) { return 0; }

    UnitEntry* desc = unit->descriptors_;
    guid_t owner_guid = (desc->summoned_by != 0u) ? desc->summoned_by : desc->created_by;
    if (owner_guid == 0u) { return 0; }

    auto* owner = object_mgr::get<CGUnit_C>(owner_guid, eTypemaskUnit);
    if (owner == nullptr) { return 0; }

    const char* name = owner->getObjectName();
    lua::pushString(l, (name != nullptr) ? name : "UNKNOWN");

    std::string guid_str = std::format("0x{:016X}", owner_guid);
    lua::pushString(l, guid_str.c_str());
    return 2;
}

int luaUnitTokenFromGuid(LuaState* l) {
    if (!lua::isString(l, 1)) { lua::throwError(l, "Usage: %s(GUID)"); }

    guid_t guid = object_mgr::str2Guid{}(lua::checkString(l, 1));
    if ((guid == 0u) || ((object_mgr::get<CGUnit_C>(guid, eTypemaskUnit)) == nullptr)) { return 0; }

    for (const char* token : {"player", "vehicle", "pet", "target", "focus", "mouseover"}) {
        if (checkToken(l, token, guid)) { return 1; }
    }

    if (checkIndexedTokens(l, "party", 1, 4, guid)) { return 1; }
    if (checkIndexedTokens(l, "partypet", 1, 4, guid)) { return 1; }
    if (checkIndexedTokens(l, "raid", 1, 40, guid)) { return 1; }
    if (checkIndexedTokens(l, "raidpet", 1, 40, guid)) { return 1; }
    if (checkIndexedTokens(l, "arena", 1, 5, guid)) { return 1; }
    if (checkIndexedTokens(l, "arenapet", 1, 5, guid)) { return 1; }
    if (checkIndexedTokens(l, "boss", 1, 5, guid)) { return 1; }

    int token_id = name_plates::getTokenId(guid);
    if (token_id >= 0) {
        std::string token = std::format("nameplate{}", token_id + 1);
        lua::pushString(l, token.c_str());
        return 1;
    }
    return 0;
}

// ---- world queries (FreakySphere: ported from srazdokunebil) --------------------------------------
// These read the object manager directly. Only TargetUnitByGUID writes anything, and it is the same
// engine call TargetUnit() already makes.
constexpr uint32_t kLosTraceFlags = 0x00100110;  // world geometry + doodads, not the units themselves

CGUnit_C* unitArg(LuaState* l) {
    if (!lua::isString(l, 1)) { return nullptr; }
    return object_mgr::get<CGUnit_C>(object_mgr::guidFromUnitId{}(lua::checkString(l, 1)), eTypemaskUnit);
}

// true when nothing solid stands between you and the unit, measured eye to eye
int luaUnitInLos(LuaState* l) {
    CGUnit_C* unit = unitArg(l);
    auto* player = object_mgr::get<CGUnit_C>(object_mgr::getPlayerGuid(), eTypemaskUnit);
    if (unit == nullptr || player == nullptr || unit == player) { return 0; }

    Vec3f from;
    Vec3f to;
    player->getPosition(from);
    unit->getPosition(to);
    // roughly eye height, so a plate behind a low wall does not read as visible through the floor
    from.z += player->movement_.bounding_height_ * 0.5f;
    to.z += unit->movement_.bounding_height_ * 0.5f;

    Vec3f hit;
    float pct = 1.0f;
    if (math::trace(from, to, kLosTraceFlags, hit, pct)) { return 0; }
    lua::pushNumber(l, 1);
    return 1;
}

int luaUnitPosition(LuaState* l) {
    CGUnit_C* unit = unitArg(l);
    if (unit == nullptr) { return 0; }
    Vec3f pos;
    unit->getPosition(pos);
    lua::pushNumber(l, pos.x);
    lua::pushNumber(l, pos.y);
    lua::pushNumber(l, pos.z);
    return 3;
}

// counter-clockwise radians, normalised to [0, 2*pi) — same contract as the retail function
int luaUnitFacing(LuaState* l) {
    CGUnit_C* unit = unitArg(l);
    if (unit == nullptr) { return 0; }
    constexpr float kTwoPi = 6.28318530717958647692f;
    float facing = unit->getFacing();
    if (!std::isfinite(facing)) { return 0; }
    facing = std::fmod(facing, kTwoPi);
    if (facing < 0.0f) { facing += kTwoPi; }
    lua::pushNumber(l, facing);
    return 1;
}

// true when you stand in the rear hemisphere of the unit. Deliberately limited to your current target,
// which is the contract the original shipped with.
int luaAmBehind(LuaState* l) {
    const guid_t guid = (lua::isString(l, 1)) ? object_mgr::guidFromUnitId{}(lua::checkString(l, 1)) : 0;
    const guid_t target = object_mgr::getTargetGuid();
    if (guid == 0 || target == 0 || guid != target) {
        lua::pushBoolean(l, false);
        return 1;
    }

    auto* player = object_mgr::get<CGUnit_C>(object_mgr::getPlayerGuid(), eTypemaskUnit);
    auto* unit = object_mgr::get<CGUnit_C>(guid, eTypemaskUnit);
    if (player == nullptr || unit == nullptr) {
        lua::pushBoolean(l, false);
        return 1;
    }

    Vec3f player_pos;
    Vec3f unit_pos;
    player->getPosition(player_pos);
    unit->getPosition(unit_pos);

    const float dx = player_pos.x - unit_pos.x;
    const float dy = player_pos.y - unit_pos.y;
    const float distance_sq = (dx * dx) + (dy * dy);

    // at the same horizontal spot the rear arc is undefined; do not let float noise pick a side
    constexpr float kMinDistanceSq = 0.000001f;
    if (distance_sq <= kMinDistanceSq) {
        lua::pushBoolean(l, false);
        return 1;
    }

    const float facing = unit->getFacing();
    if (!std::isfinite(facing)) {
        lua::pushBoolean(l, false);
        return 1;
    }

    const float inv_distance = 1.0f / std::sqrt(distance_sq);
    const float facing_dot = (dx * inv_distance) * std::cos(facing) + (dy * inv_distance) * std::sin(facing);

    // keep the exact side boundary out of the rear arc
    constexpr float kRearArcEpsilon = 0.0001f;
    lua::pushBoolean(l, facing_dot < -kRearArcEpsilon);
    return 1;
}

// accepts a "0x…" GUID or any unit token, since object_mgr::string2Guid handles both
int luaUnitExistsGuid(LuaState* l) {
    if (!lua::isString(l, 1)) { return 0; }
    const guid_t guid = object_mgr::string2Guid(lua::checkString(l, 1));
    if (guid == 0 || object_mgr::get<CGUnit_C>(guid, eTypemaskUnit) == nullptr) { return 0; }
    lua::pushNumber(l, 1);
    return 1;
}

int luaTargetUnitByGuid(LuaState* l) {
    if (!lua::isString(l, 1)) { return 0; }
    const guid_t guid = object_mgr::string2Guid(lua::checkString(l, 1));
    if (guid == 0 || object_mgr::get<CGUnit_C>(guid, eTypemaskUnit) == nullptr) { return 0; }
    game_ui::target{}(guid);
    return 0;
}

int luaUnitGuidByName(LuaState* l) {
    if (!lua::isString(l, 1)) { return 0; }
    const char* name = lua::checkString(l, 1);
    if (name == nullptr || name[0] == '\0') { return 0; }

    guid_t found = 0;
    object_mgr::enumObjects([&](guid_t guid) {
        auto* unit = object_mgr::get<CGUnit_C>(guid, eTypemaskUnit);
        if (unit == nullptr) { return true; }
        const char* unit_name = unit->getObjectName();
        if (unit_name != nullptr && std::strcmp(unit_name, name) == 0) {
            found = guid;
            return false;
        }
        return true;
    });

    if (found == 0) { return 0; }
    lua::pushGuid(l, found);
    return 1;
}

int luaOpenUnit(LuaState* l) {
    static constexpr std::array<lua::LuaLReg, 13> kFuncs = {{
        {.name = "UnitIsControlled", .func = luaUnitIsControlled},
        {.name = "UnitIsDisarmed", .func = luaUnitIsDisarmed},
        {.name = "UnitIsFlagSilenced", .func = luaUnitIsFlagSilenced},
        {.name = "UnitOccupations", .func = luaUnitOccupations},
        {.name = "UnitOwner", .func = luaUnitOwner},
        {.name = "UnitTokenFromGUID", .func = luaUnitTokenFromGuid},
        {.name = "UnitInLOS", .func = luaUnitInLos},
        {.name = "UnitPosition", .func = luaUnitPosition},
        {.name = "UnitFacing", .func = luaUnitFacing},
        {.name = "AmBehind", .func = luaAmBehind},
        {.name = "UnitExistsGUID", .func = luaUnitExistsGuid},
        {.name = "TargetUnitByGUID", .func = luaTargetUnitByGuid},
        {.name = "UnitGUIDByName", .func = luaUnitGuidByName},
    }};
    for (const auto& [name, func] : kFuncs) {
        lua::pushCFunction(l, func);
        lua::setGlobal(l, name);
    }

    // FrameXML may not have defined its own UnitIsSilenced yet; installUnitIsSilenced is a no-op then
    // and the enter-world hook retries once the UI is fully up.
    installUnitIsSilenced(l);
    return 0;
}
}  // namespace

void unit_api::initialize(hookkit::HookTransaction&) {
    extensions::console::kLuaLibRegistry->add(luaOpenUnit);
    extensions::framescript::kOnEnter->add([] {
        if (LuaState* l = lua::getLuaState()) { installUnitIsSilenced(l); }
    });
}
