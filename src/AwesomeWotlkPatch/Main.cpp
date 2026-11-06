#include <windows.h>

#include <commdlg.h>
#include <hookkit/accessor.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <format>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "Patch.h"
#include "Utils.h"
#include "resource.h"

namespace {
inline constexpr utils::Accessor<std::string, struct AppNameTag> kAppName;
inline constexpr utils::Accessor<std::string, struct AppPathTag> kAppPath;
inline constexpr utils::Accessor<bool, struct QuietModeTag> kQuietMode;

// shown in the title bar and on every message box; the exe file name stays AwesomeWotlkPatch.exe
inline constexpr const char* kTitle = "AwesomeWotLK Patcher";

// What the file on disk currently is. ePartial means some other tool (or an older build of this one)
// left the bytes in a state this patcher does not recognise -- refuse rather than guess.
enum class ClientState { eMissing, eNotClient, eClean, ePatched, ePartial };

enum class Action {
    ePatched,
    eAlreadyPatched,
    eAlreadyPatchedUpdated,
    eRuntimeFailed,
    eRemoved,
    eNoBackup,
    eBackupOtherBuild,
    eBackupImported,
    eNotClient,
    eFailed,
    eNothingToDo,
};

std::string backupPath(const std::string& path) { return path + ".bak"; }

ClientState inspect(const std::vector<char>& image) {
    if (!isPE32(image)) { return ClientState::eNotClient; }

    bool all_patched = true;
    bool all_clean = true;
    for (const auto& [virtual_address, hex_bytes, expected] : kPatches) {
        const unsigned offset = virtualAddress2RawOffset(image, virtual_address);
        if (offset == 0u) { return ClientState::eNotClient; }

        std::vector<char> data;
        std::vector<char> guard;
        if (!convHexString2ByteArray(hex_bytes, data) || data.empty() || !convHexString2ByteArray(expected, guard) ||
            guard.empty()) {
            return ClientState::eNotClient;
        }
        if (offset + data.size() > image.size() || offset + guard.size() > image.size()) {
            return ClientState::eNotClient;
        }
        all_patched = all_patched && std::equal(data.begin(), data.end(), image.begin() + offset);
        all_clean = all_clean && std::equal(guard.begin(), guard.end(), image.begin() + offset);
    }

    if (all_patched) { return ClientState::ePatched; }
    if (all_clean) { return ClientState::eClean; }
    return ClientState::ePartial;
}

// A backup is usable only when it is a clean 3.3.5a client. A patched backup is worthless: the patch
// overwrites 32 bytes at ScanDllStart, so the original code cannot be reconstructed from it.
bool backupUsable(const std::string& path, DWORD* timestamp = nullptr) {
    std::vector<char> image;
    if (!readFile(backupPath(path).c_str(), image)) { return false; }
    if (inspect(image) != ClientState::eClean) { return false; }
    if (timestamp != nullptr) { *timestamp = peTimestamp(image); }
    return true;
}

// Called only with a verified-clean image. Keeps an existing backup when it is clean and belongs to the
// same client build; refreshes it when the game was updated in the meantime.
bool ensureBackup(const std::string& path, const std::vector<char>& image) {
    DWORD existing = 0;
    if (backupUsable(path, &existing) && existing == peTimestamp(image)) { return true; }
    return writeFile(backupPath(path).c_str(), image);
}

bool patchImage(std::vector<char>& image) {
    bool changed = false;
    if (!applyLAA(image, &changed)) { return false; }

    for (const auto& [virtual_address, hex_bytes, expected] : kPatches) {
        const unsigned offset = virtualAddress2RawOffset(image, virtual_address);
        if (offset == 0u) { return false; }

        std::vector<char> data;
        if (!convHexString2ByteArray(hex_bytes, data) || data.empty()) { return false; }
        if (offset + data.size() > image.size()) { return false; }
        if (std::equal(data.begin(), data.end(), image.begin() + offset)) { continue; }

        std::vector<char> guard;
        if (!convHexString2ByteArray(expected, guard) || guard.empty()) { return false; }
        if (offset + guard.size() > image.size() ||
            !std::equal(guard.begin(), guard.end(), image.begin() + offset)) {
            return false;
        }
        std::ranges::copy(data, image.begin() + static_cast<int>(offset));
    }
    return true;
}

// The patcher ships the runtime next to itself: the mod and the sidecar DLL it imports. Both have to be
// refreshed, not merely dropped in once.
//
//  * Copying only when the file is absent leaves a client patched by an older release with the old DLL
//    forever, and the patcher then reports "already patched" and changes nothing.
//  * skia.dll is a hard import of AwesomeWotlkLib.dll. Without it LoadLibrary fails, the patched Wow.exe
//    boots straight past the mod, and the game looks completely normal while nothing works.
struct RuntimeRefresh {
    bool updated = false;  // at least one file was written
    bool failed = false;   // a file could not be provided or written
};

bool sameFileContents(const std::filesystem::path& a, const std::filesystem::path& b) {
    std::error_code ec;
    if (std::filesystem::file_size(a, ec) != std::filesystem::file_size(b, ec) || ec) { return false; }
    std::vector<char> left;
    std::vector<char> right;
    if (!readFile(a.string().c_str(), left) || !readFile(b.string().c_str(), right)) { return false; }
    return left == right;
}

RuntimeRefresh refreshRuntimeFiles(const std::string& exe_path) {
    static constexpr std::array<const char*, 2> kFiles = {"AwesomeWotlkLib.dll", "skia.dll"};

    RuntimeRefresh result;
    const auto game_dir = std::filesystem::path(exe_path).parent_path();
    const auto app_dir = std::filesystem::path(*kAppPath).parent_path();

    for (const char* name : kFiles) {
        const auto src = app_dir / name;
        const auto dst = game_dir / name;

        std::error_code ec;
        if (!std::filesystem::is_regular_file(src, ec)) {
            // Running from a folder without the runtime is fine as long as the game already has it.
            if (!std::filesystem::is_regular_file(dst, ec)) { result.failed = true; }
            continue;
        }
        if (std::filesystem::equivalent(src, dst, ec)) { continue; }  // patcher run from the game folder
        if (std::filesystem::is_regular_file(dst, ec) && sameFileContents(src, dst)) { continue; }

        if (std::filesystem::copy_file(src, dst, std::filesystem::copy_options::overwrite_existing, ec)) {
            result.updated = true;
        } else {
            result.failed = true;
        }
    }
    return result;
}

Action patchClient(const std::string& path) {
    std::vector<char> image;
    if (!readFile(path.c_str(), image)) { return Action::eFailed; }

    const ClientState state = inspect(image);
    if (state == ClientState::eNotClient || state == ClientState::ePartial) { return Action::eNotClient; }
    if (state == ClientState::ePatched) {
        // The exe is fine, but the runtime beside it may still be an older build.
        const RuntimeRefresh refresh = refreshRuntimeFiles(path);
        if (refresh.failed) { return Action::eRuntimeFailed; }
        return refresh.updated ? Action::eAlreadyPatchedUpdated : Action::eAlreadyPatched;
    }

    if (!ensureBackup(path, image)) { return Action::eFailed; }
    if (!patchImage(image)) { return Action::eFailed; }
    if (!writeFile(path.c_str(), image)) { return Action::eFailed; }

    if (refreshRuntimeFiles(path).failed) { return Action::eRuntimeFailed; }
    return Action::ePatched;
}

// Restores Wow.exe.bak over Wow.exe. The backup is consumed, exactly as a manual restore would.
Action removePatch(const std::string& path, bool force) {
    DWORD backup_timestamp = 0;
    if (!backupUsable(path, &backup_timestamp)) { return Action::eNoBackup; }

    std::vector<char> current;
    if (!force && readFile(path.c_str(), current) && peTimestamp(current) != backup_timestamp) {
        return Action::eBackupOtherBuild;
    }

    if (!MoveFileExA(backupPath(path).c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        return Action::eFailed;
    }
    return Action::eRemoved;
}

// For clients patched by an older version, which have no backup: let the user point at an untouched
// 3.3.5a client, validate it, and use it as Wow.exe.bak. The patched file itself is never touched.
Action importBackup(const std::string& path) {
    char selected[MAX_PATH] = {};
    OPENFILENAMEA ofn{};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = GetActiveWindow();
    ofn.lpstrFilter = "Wow.exe\0Wow.exe\0Executables (*.exe)\0*.exe\0";
    ofn.lpstrFile = selected;
    ofn.nMaxFile = MAX_PATH;
    ofn.lpstrTitle = "Select a clean World of Warcraft 3.3.5a client";
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR;
    if (GetOpenFileNameA(&ofn) == FALSE) { return Action::eNothingToDo; }

    std::vector<char> image;
    if (!readFile(selected, image) || inspect(image) != ClientState::eClean) { return Action::eNotClient; }
    if (!writeFile(backupPath(path).c_str(), image)) { return Action::eFailed; }
    return Action::eBackupImported;
}

std::string actionMessage(Action action, const std::string& path) {
    switch (action) {
        case Action::ePatched:
            return std::format(
                "Successfully patched {}.\nA clean backup was saved as Wow.exe.bak.\nYou can now start the game.",
                path);
        case Action::eAlreadyPatched:
            return std::format("{} is already patched.\nNothing was changed.", path);
        case Action::eAlreadyPatchedUpdated:
            return std::format(
                "{} is already patched.\nThe runtime files next to it were updated to this version.\n"
                "You can now start the game.",
                path);
        case Action::eRuntimeFailed:
            return "Wow.exe is patched, but AwesomeWotlkLib.dll / skia.dll could not be placed next to it.\n\n"
                   "Without both files the client starts without the mod. Copy them into the game folder\n"
                   "yourself, or close the game and run the patcher again.";
        case Action::eRemoved:
            return std::format("The patch was removed.\n{} was restored from Wow.exe.bak.", path);
        case Action::eNoBackup:
            return "There is no usable Wow.exe.bak, so the patch cannot be removed automatically.\n\n"
                   "Replace Wow.exe with a clean 3.3.5a copy instead.";
        case Action::eBackupOtherBuild:
            return "Wow.exe.bak comes from a different client build than the current Wow.exe.";
        case Action::eBackupImported:
            return "A clean client was saved as Wow.exe.bak.\nThe patch can now be removed.";
        case Action::eNotClient:
            return std::format(
                "{} is not a World of Warcraft 3.3.5a (build 12340) client, or another tool has\n"
                "already modified the bytes this patcher changes.\n\nNothing was changed.",
                path);
        case Action::eFailed:
        default:
            return "The file could not be written.\nClose the game (and any launcher) and try again.";
    }
}

UINT actionIcon(Action action) {
    switch (action) {
        case Action::ePatched:
        case Action::eAlreadyPatched:
        case Action::eAlreadyPatchedUpdated:
        case Action::eRemoved:
        case Action::eBackupImported:
            return MB_ICONINFORMATION;
        case Action::eNoBackup:
        case Action::eBackupOtherBuild:
        case Action::eRuntimeFailed:
            return MB_ICONWARNING;
        default:
            return MB_ICONERROR;
    }
}

bool actionSucceeded(Action action) {
    return action == Action::ePatched || action == Action::eAlreadyPatched ||
        action == Action::eAlreadyPatchedUpdated || action == Action::eRemoved ||
        action == Action::eBackupImported;
}

template <typename... Args>
void message(DWORD icon, const char* fmt, const Args&... args) {
    if (!*kQuietMode) {
        MessageBoxA(nullptr, std::vformat(fmt, std::make_format_args(args...)).c_str(), kTitle, icon | MB_OK);
    }
}

// The client is looked for next to the patcher first, then in the working directory. Double-clicking
// from a shortcut can leave the working directory somewhere else entirely.
const char* findGameClientExecutable() {
    static constexpr std::array<const char*, 2> kPossibleNames = {"Project-Epoch.exe", "Wow.exe"};
    static std::string found;

    const auto app_dir = std::filesystem::path(*kAppPath).parent_path();
    for (const char* name : kPossibleNames) {
        const auto candidate = app_dir / name;
        if (std::filesystem::is_regular_file(candidate)) {
            found = candidate.string();
            return found.c_str();
        }
    }
    for (const char* name : kPossibleNames) {
        if (std::filesystem::is_regular_file(name)) {
            found = name;
            return found.c_str();
        }
    }
    return nullptr;
}

// ------------------------------------------------------------------------------------------------
// The window shown when the patcher is started without arguments.
// ------------------------------------------------------------------------------------------------
struct DialogContext {
    std::string path;
};

void layoutDialog(HWND hwnd);
void centerOnScreen(HWND hwnd);

void refreshDialog(HWND hwnd, DialogContext& ctx) {
    bool can_patch = false;
    bool can_remove = false;
    bool can_locate = false;
    std::string status = "Wow.exe was not found next to this program.\n\n"
                         "Put the patcher in your game folder, or drag Wow.exe onto it.";

    if (const char* found = findGameClientExecutable()) {
        ctx.path = found;
        std::vector<char> image;
        const ClientState state = readFile(found, image) ? inspect(image) : ClientState::eMissing;

        switch (state) {
            case ClientState::eClean:
                status = "World of Warcraft 3.3.5a detected.\n\n"
                         "This client is not patched. Patching saves a clean copy as Wow.exe.bak first, "
                         "so the change can be undone at any time.";
                can_patch = true;
                break;
            case ClientState::ePatched:
                if (backupUsable(found)) {
                    status = "World of Warcraft 3.3.5a detected.\n\n"
                             "The client is patched. A clean Wow.exe.bak is available, so the patch can be removed.";
                    can_remove = true;
                } else {
                    status = "World of Warcraft 3.3.5a detected.\n\n"
                             "The client is patched, but there is no clean Wow.exe.bak. Click \"Use a clean "
                             "Wow.exe...\" and pick an unmodified 3.3.5a client, and the patch can be removed.";
                    can_locate = true;
                }
                break;
            case ClientState::ePartial:
                status = "This Wow.exe was already modified by another tool.\n\nNothing will be changed.";
                break;
            case ClientState::eNotClient:
                status = "This Wow.exe is not a World of Warcraft 3.3.5a (build 12340) client.\n\n"
                         "Nothing will be changed.";
                break;
            default:
                status = "Wow.exe could not be read.";
                break;
        }
    }

    SetDlgItemTextA(hwnd, IDC_STATUS, status.c_str());
    EnableWindow(GetDlgItem(hwnd, IDC_PATCH), can_patch);
    EnableWindow(GetDlgItem(hwnd, IDC_REMOVE), can_remove);
    EnableWindow(GetDlgItem(hwnd, IDC_LOCATE), can_locate);

    layoutDialog(hwnd);
    centerOnScreen(hwnd);
}

// ------------------------------------------------------------------------------------------------
// Owner-draw buttons. A standard Win32 button cannot be coloured, so Patch and Remove paint
// themselves: filled, rounded, white label, darker while pressed, grey while disabled.
// ------------------------------------------------------------------------------------------------
COLORREF shiftColor(COLORREF color, int delta) {
    const auto clamp = [](int value) { return value < 0 ? 0 : (value > 255 ? 255 : value); };
    return RGB(clamp(GetRValue(color) + delta), clamp(GetGValue(color) + delta), clamp(GetBValue(color) + delta));
}

COLORREF blendColor(COLORREF from, COLORREF to, float amount) {
    const auto mix = [amount](int a, int b) { return static_cast<int>(a + (b - a) * amount + 0.5f); };
    return RGB(mix(GetRValue(from), GetRValue(to)), mix(GetGValue(from), GetGValue(to)),
        mix(GetBValue(from), GetBValue(to)));
}

void drawColoredButton(const DRAWITEMSTRUCT& item, COLORREF base) {
    const bool disabled = (item.itemState & ODS_DISABLED) != 0;
    const bool pressed = (item.itemState & ODS_SELECTED) != 0;

    // A disabled button keeps its colour, just faded: only one of the two is ever available, and the
    // green/red language should still read at a glance.
    const COLORREF fill = disabled ? blendColor(base, RGB(0xFF, 0xFF, 0xFF), 0.62f)
                                  : (pressed ? shiftColor(base, -30) : base);
    const COLORREF border = disabled ? blendColor(base, RGB(0xFF, 0xFF, 0xFF), 0.40f) : shiftColor(base, -45);
    const COLORREF label_color = disabled ? blendColor(base, RGB(0x00, 0x00, 0x00), 0.25f) : RGB(0xFF, 0xFF, 0xFF);

    HDC dc = item.hDC;
    RECT box = item.rcItem;

    // the dialog's own face colour behind the rounded corners
    HBRUSH face = CreateSolidBrush(GetSysColor(COLOR_BTNFACE));
    FillRect(dc, &box, face);
    DeleteObject(face);

    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, border);
    HGDIOBJ old_brush = SelectObject(dc, brush);
    HGDIOBJ old_pen = SelectObject(dc, pen);
    RoundRect(dc, box.left, box.top, box.right, box.bottom, 6, 6);
    SelectObject(dc, old_brush);
    SelectObject(dc, old_pen);
    DeleteObject(brush);
    DeleteObject(pen);

    char label[64] = {};
    GetWindowTextA(item.hwndItem, label, static_cast<int>(std::size(label)));

    const int old_mode = SetBkMode(dc, TRANSPARENT);
    const COLORREF old_color = SetTextColor(dc, label_color);
    HFONT font = reinterpret_cast<HFONT>(SendMessage(GetParent(item.hwndItem), WM_GETFONT, 0, 0));
    HGDIOBJ old_font = font != nullptr ? SelectObject(dc, font) : nullptr;

    RECT text_box = box;
    DrawTextA(dc, label, -1, &text_box, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

    if (old_font != nullptr) { SelectObject(dc, old_font); }
    SetTextColor(dc, old_color);
    SetBkMode(dc, old_mode);

    if ((item.itemState & ODS_FOCUS) != 0 && !disabled) {
        HPEN ring = CreatePen(PS_SOLID, 1, shiftColor(base, 60));
        HGDIOBJ ring_old_pen = SelectObject(dc, ring);
        HGDIOBJ ring_old_brush = SelectObject(dc, GetStockObject(NULL_BRUSH));
        RECT focus = box;
        InflateRect(&focus, -3, -3);
        RoundRect(dc, focus.left, focus.top, focus.right, focus.bottom, 5, 5);
        SelectObject(dc, ring_old_brush);
        SelectObject(dc, ring_old_pen);
        DeleteObject(ring);
    }
}

// The status text changes length with the client state, so the dialog is sized to its content instead
// of reserving the height of the longest message in the template. That keeps the window tight in every
// state and leaves no dead band between the text and the buttons.
void layoutDialog(HWND hwnd) {
    HWND status = GetDlgItem(hwnd, IDC_STATUS);
    if (status == nullptr) { return; }

    RECT status_rect{};
    GetWindowRect(status, &status_rect);
    MapWindowPoints(nullptr, hwnd, reinterpret_cast<LPPOINT>(&status_rect), 2);
    const int width = status_rect.right - status_rect.left;

    char text[1024] = {};
    GetWindowTextA(status, text, static_cast<int>(std::size(text)));

    int text_height = 16;
    if (HDC dc = GetDC(hwnd)) {
        HFONT font = reinterpret_cast<HFONT>(SendMessage(hwnd, WM_GETFONT, 0, 0));
        HGDIOBJ old = font != nullptr ? SelectObject(dc, font) : nullptr;
        RECT calc{0, 0, width, 0};
        DrawTextA(dc, text, -1, &calc, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
        text_height = std::max<int>(calc.bottom - calc.top, 16);
        if (old != nullptr) { SelectObject(dc, old); }
        ReleaseDC(hwnd, dc);
    }
    SetWindowPos(status, nullptr, 0, 0, width, text_height, SWP_NOMOVE | SWP_NOZORDER);

    const auto rect_of = [hwnd](int id) {
        RECT r{};
        GetWindowRect(GetDlgItem(hwnd, id), &r);
        MapWindowPoints(nullptr, hwnd, reinterpret_cast<LPPOINT>(&r), 2);
        return r;
    };

    const RECT patch = rect_of(IDC_PATCH);
    const RECT locate = rect_of(IDC_LOCATE);
    const RECT close = rect_of(IDCANCEL);
    const int row1_height = patch.bottom - patch.top;
    const int row2_height = locate.bottom - locate.top;
    const int close_width = close.right - close.left;
    const int gap = 8;

    const int row1 = status_rect.top + text_height + 16;
    const int row2 = row1 + row1_height + 8;

    // Both rows span the full text width. Leaving the right half of the button row empty was the
    // "dead band" -- the two actions now fill it evenly.
    const int left = status_rect.left;
    const int content = status_rect.right - status_rect.left;
    const int half = (content - gap) / 2;

    SetWindowPos(GetDlgItem(hwnd, IDC_PATCH), nullptr, left, row1, half, row1_height, SWP_NOZORDER);
    SetWindowPos(
        GetDlgItem(hwnd, IDC_REMOVE), nullptr, left + half + gap, row1, content - half - gap, row1_height, SWP_NOZORDER);
    SetWindowPos(GetDlgItem(hwnd, IDC_LOCATE), nullptr, left, row2, content - close_width - gap, row2_height, SWP_NOZORDER);
    SetWindowPos(GetDlgItem(hwnd, IDCANCEL), nullptr, left + content - close_width, row2, close_width, row2_height,
        SWP_NOZORDER);

    RECT client{};
    RECT window{};
    GetClientRect(hwnd, &client);
    GetWindowRect(hwnd, &window);
    const int border_x = (window.right - window.left) - client.right;
    const int border_y = (window.bottom - window.top) - client.bottom;
    SetWindowPos(hwnd, nullptr, 0, 0, client.right + border_x, row2 + row2_height + 16 + border_y,
        SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);

    // Moving a child leaves the pixels it vacated behind until something repaints that area. When the
    // status text changes length the buttons shift, and without this the old button edge stayed visible
    // as a coloured strip under the new one. ALLCHILDREN also repaints the buttons themselves.
    RedrawWindow(hwnd, nullptr, nullptr,
        RDW_INVALIDATE | RDW_ERASE | RDW_ALLCHILDREN | RDW_UPDATENOW);
}

// Middle of the work area, not of the whole screen: a centred window should not sit under the taskbar.
void centerOnScreen(HWND hwnd) {
    RECT window{};
    RECT work{};
    if (GetWindowRect(hwnd, &window) == FALSE || SystemParametersInfoA(SPI_GETWORKAREA, 0, &work, 0) == FALSE) { return; }
    const int width = window.right - window.left;
    const int height = window.bottom - window.top;
    const int x = work.left + ((work.right - work.left) - width) / 2;
    const int y = work.top + ((work.bottom - work.top) - height) / 2;
    SetWindowPos(hwnd, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}

INT_PTR CALLBACK dialogProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    static DialogContext* ctx = nullptr;

    switch (msg) {
        case WM_INITDIALOG:
            ctx = reinterpret_cast<DialogContext*>(lparam);
            refreshDialog(hwnd, *ctx);
            return TRUE;

        case WM_DRAWITEM: {
            const auto* item = reinterpret_cast<const DRAWITEMSTRUCT*>(lparam);
            if (item->CtlID == IDC_PATCH) {
                drawColoredButton(*item, RGB(0x2E, 0x7D, 0x32));  // green
                return TRUE;
            }
            if (item->CtlID == IDC_REMOVE) {
                drawColoredButton(*item, RGB(0xC6, 0x28, 0x28));  // red
                return TRUE;
            }
            return FALSE;
        }

        case WM_COMMAND:
            switch (LOWORD(wparam)) {
                case IDC_PATCH: {
                    const Action result = patchClient(ctx->path);
                    MessageBoxA(hwnd, actionMessage(result, ctx->path).c_str(), kTitle,
                        actionIcon(result) | MB_OK);
                    refreshDialog(hwnd, *ctx);
                    return TRUE;
                }
                case IDC_REMOVE: {
                    if (MessageBoxA(hwnd,
                            "Remove the patch and restore Wow.exe from Wow.exe.bak?\n\nClose the game first.",
                            kTitle, MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
                        return TRUE;
                    }
                    Action result = removePatch(ctx->path, false);
                    if (result == Action::eBackupOtherBuild) {
                        if (MessageBoxA(hwnd,
                                "Wow.exe.bak comes from a different client build than the current Wow.exe.\n"
                                "Restoring it may downgrade your game.\n\nContinue anyway?",
                                kTitle, MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
                            return TRUE;
                        }
                        result = removePatch(ctx->path, true);
                    }
                    MessageBoxA(hwnd, actionMessage(result, ctx->path).c_str(), kTitle,
                        actionIcon(result) | MB_OK);
                    refreshDialog(hwnd, *ctx);
                    return TRUE;
                }
                case IDC_LOCATE: {
                    const Action result = importBackup(ctx->path);
                    if (result == Action::eNothingToDo) { return TRUE; }
                    MessageBoxA(hwnd, actionMessage(result, ctx->path).c_str(), kTitle,
                        actionIcon(result) | MB_OK);
                    refreshDialog(hwnd, *ctx);
                    return TRUE;
                }
                case IDCANCEL:
                    EndDialog(hwnd, 0);
                    return TRUE;
                default:
                    break;
            }
            break;

        case WM_CLOSE:
            EndDialog(hwnd, 0);
            return TRUE;

        default:
            break;
    }
    return FALSE;
}

int run(std::span<char*> args) {
    *kAppPath = args.front();
    *kAppName = std::filesystem::path(args.front()).filename().string();

    bool remove = false;
    const char* exe_path = nullptr;
    for (const char* arg : args.subspan(1)) {
        const std::string_view value(arg);
        if (value == "--quiet" || value == "-q") {
            *kQuietMode = true;
        } else if (value == "--remove" || value == "--unpatch" || value == "-r") {
            remove = true;
        } else if (exe_path == nullptr) {
            exe_path = arg;
        }
    }

    // Started without arguments: the two-button window.
    if (args.size() <= 1) {
        DialogContext ctx;
        DialogBoxParamA(
            GetModuleHandleA(nullptr), MAKEINTRESOURCEA(IDD_PATCHER), nullptr, dialogProc, reinterpret_cast<LPARAM>(&ctx));
        return 0;
    }

    if (exe_path == nullptr) { exe_path = findGameClientExecutable(); }
    if (exe_path == nullptr) {
        message(MB_ICONERROR,
            "World of Warcraft executable (Wow.exe) not found.\n"
            "Do one of the following:\n"
            "- Move the patcher into the folder that contains Wow.exe\n"
            "- Drag and drop Wow.exe onto {}\n"
            "- Run `{} <path>` from the command line",
            *kAppName, *kAppName);
        return 1;
    }

    Action result = remove ? removePatch(exe_path, false) : patchClient(exe_path);
    if (result == Action::eBackupOtherBuild) {
        if (*kQuietMode ||
            MessageBoxA(nullptr,
                "Wow.exe.bak comes from a different client build than the current Wow.exe.\n"
                "Restoring it may downgrade your game.\n\nContinue anyway?",
                kTitle, MB_ICONWARNING | MB_YESNO | MB_DEFBUTTON2) != IDYES) {
            return 1;
        }
        result = removePatch(exe_path, true);
    }

    message(actionIcon(result), "%s", actionMessage(result, exe_path));
    return actionSucceeded(result) ? 0 : 1;
}
}  // namespace

int main(int argc, char** argv) {
    try {
        return run(std::span(argv, static_cast<size_t>(argc)));
    } catch (...) {
        return 1;
    }
}
