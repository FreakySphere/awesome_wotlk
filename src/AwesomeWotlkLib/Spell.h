#pragma once

#include <cstdint>

#include <hookkit/hook.h>
#include <hookkit/transaction.h>

#include "include/BaseTypes.h"

namespace spell {
// byte 3 of UNIT_FIELD_BYTES_2 holds the active shapeshift form
inline constexpr uint8_t kOffsetShapeshiftForm = 3;

// 0x0080DA40 is the inner cast entry the older forks (CH33T4, Crumdidlyumshis, somewirdhuman,
// Hypopheria2k) have used for the stance fix; it returns non-zero when the cast was accepted.
HOOKKIT_HOOK_HANDLE(castFormSpell, 0x0080DA40, hookkit::Conv::eCdecl, int, int, int, int, int, int);

void initialize(hookkit::HookTransaction& tx);
}  // namespace spell
