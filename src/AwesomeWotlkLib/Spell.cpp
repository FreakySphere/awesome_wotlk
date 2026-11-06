#include "Spell.h"

#include <hookkit/wildabi.h>

#include <algorithm>
#include <array>
#include <cstdint>

#include "Extensions.h"

#include "include/DB/ClientDB.h"
#include "include/DB/DBRecords.h"
#include "include/Lib/Lua.h"
#include "include/ObjectManager/CGUnit_C.h"
#include "include/ObjectManager/DescriptorsEnums.h"
#include "include/ObjectManager/ObjectManager.h"

namespace {
int luaGetSpellBaseCooldown(LuaState* l) {
    if (!lua::isNumber(l, 1)) { lua::throwError(l, "Usage: %s(spellID)"); }
    auto spell_id = static_cast<uint32_t>(lua::checkNumber(l, 1));

    const auto* spell_data = client_db::getRowById<SpellRec>("spell", spell_id);
    if (spell_data == nullptr) { return 0; }

    uint32_t cd_time = spell_data->recovery_time != 0 ? spell_data->recovery_time : spell_data->category_recovery_time;
    uint32_t gcd_time = spell_data->start_recovery_time;

    if (cd_time == 0) {
        for (uint32_t triggered_id : spell_data->effect_trigger_spell) {
            if (triggered_id == 0 || triggered_id == spell_id) { continue; }
            if (const auto* rec = client_db::getRowById<SpellRec>("spell", triggered_id)) {
                uint32_t trig_cd = rec->recovery_time != 0 ? rec->recovery_time : rec->category_recovery_time;
                cd_time = std::max(cd_time, trig_cd);
                gcd_time = std::max(gcd_time, rec->start_recovery_time);
            }
        }
    }

    lua::pushNumber(l, cd_time);
    lua::pushNumber(l, gcd_time);
    return 2;
}

int luaOpenSpell(LuaState* l) {
    lua::pushCFunction(l, luaGetSpellBaseCooldown);
    lua::setGlobal(l, "GetSpellBaseCooldown");
    return 0;
}

// ---- stance / form cast fix (FreakySphere: ported from Hypopheria2k / CH33T4) -----------------------
// 3.3.5a does not refresh UNIT_FIELD_BYTES_2 byte 3 (the shapeshift form) after a form spell lands, so
// the next line of the same macro is still evaluated against the form you just left:
//
//   /cast Battle Stance
//   /cast Charge          <- "you are in the wrong stance"
//
// Writing the form the cast just switched to fixes the one-click macro. Opt-in: it is a descriptor
// write, and only warriors / druids / shamans / warlocks have anything to gain from it.
struct FormSpell {
    uint32_t spell_id;
    uint8_t form;
};

// FORM_* values from the 3.3.5a ShapeshiftForm enum. The first nine are the set the original fix
// shipped with; the rest are the same mechanic for the other classes that use it.
constexpr std::array<FormSpell, 14> kFormSpells = {{
    {768, 0x01},    // Cat Form             FORM_CAT
    {783, 0x03},    // Travel Form          FORM_TRAVEL
    {1066, 0x04},   // Aquatic Form         FORM_AQUA
    {5487, 0x05},   // Bear Form            FORM_BEAR
    {9634, 0x08},   // Dire Bear Form       FORM_DIREBEAR
    {33891, 0x02},  // Tree of Life Form    FORM_TREE
    {2457, 0x11},   // Battle Stance        FORM_BATTLESTANCE
    {71, 0x12},     // Defensive Stance     FORM_DEFENSIVESTANCE
    {2458, 0x13},   // Berserker Stance     FORM_BERSERKERSTANCE
    {2645, 0x10},   // Ghost Wolf           FORM_GHOSTWOLF
    {24858, 0x1F},  // Moonkin Form         FORM_MOONKIN
    {33943, 0x1D},  // Flight Form          FORM_FLIGHT
    {40120, 0x1B},  // Swift Flight Form    FORM_FLIGHT_EPIC
    {47241, 0x16},  // Metamorphosis        FORM_METAMORPHOSIS
}};

uint8_t formForSpell(uint32_t spell_id) {
    for (const FormSpell& entry : kFormSpells) {
        if (entry.spell_id == spell_id) { return entry.form; }
    }
    return 0;
}

HOOKKIT_BIND(spell::castFormSpell, [](int spell_id, int a2, int a3, int a4, int a5) -> int {
    const int result = spell::castFormSpell{}(spell_id, a2, a3, a4, a5);
    if (result == 0) { return result; }
    if (extensions::console::kCvarRegistry->get<"enableStancePatch", int>() == 0) { return result; }

    const uint8_t form = formForSpell(static_cast<uint32_t>(spell_id));
    if (form == 0) { return result; }

    if (auto* player = object_mgr::get<CGUnit_C>(object_mgr::getPlayerGuid(), eTypemaskUnit)) {
        player->setValueBytes(eUnitFieldBytes2, spell::kOffsetShapeshiftForm, form);
    }
    return result;
});
}  // namespace

void spell::initialize(hookkit::HookTransaction& tx) {
    auto& cvars = *extensions::console::kCvarRegistry;
    cvars.add<int>({.name = "enableStancePatch", .init = 1, .min{0}, .max{1}});

    extensions::console::kLuaLibRegistry->add(luaOpenSpell);
    tx.attach(spell::castFormSpell{});
}
