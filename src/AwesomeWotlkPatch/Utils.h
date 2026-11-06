#pragma once

#include <windows.h>

#include <cstddef>
#include <filesystem>
#include <fstream>
#include <span>
#include <streambuf>
#include <string>
#include <string_view>
#include <vector>

inline bool readFile(const char* path, std::vector<char>& content) {
    std::ifstream file(path, std::ios::binary);
    if (!file) { return false; }
    content.assign(std::istreambuf_iterator(file), std::istreambuf_iterator<char>());
    return true;
}

// Written to a sibling file first and then renamed over the target, so an interrupted write can never
// leave a half-patched Wow.exe behind. The temp file is on the same volume, so the rename is atomic.
inline bool writeFile(const char* path, const std::vector<char>& content) {
    const std::string temp = std::string(path) + ".new";
    {
        std::ofstream file(temp, std::ios::binary | std::ios::trunc);
        if (!file) { return false; }
        file.write(content.data(), static_cast<std::streamsize>(content.size()));
        file.flush();
        if (!file) {
            std::error_code ignored;
            std::filesystem::remove(temp, ignored);
            return false;
        }
    }
    if (!MoveFileExA(temp.c_str(), path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        std::error_code ignored;
        std::filesystem::remove(temp, ignored);
        return false;
    }
    return true;
}

inline unsigned virtualAddress2RawOffset(const std::vector<char>& image, unsigned address) {
    const auto* dos_header = reinterpret_cast<const IMAGE_DOS_HEADER*>(image.data());
    const auto* nt_headers = reinterpret_cast<const IMAGE_NT_HEADERS*>(&image[dos_header->e_lfanew]);
    size_t sections_offset =
        dos_header->e_lfanew + offsetof(IMAGE_NT_HEADERS, OptionalHeader) + nt_headers->FileHeader.SizeOfOptionalHeader;
    size_t section_count = nt_headers->FileHeader.NumberOfSections;
    if (sections_offset + section_count * sizeof(IMAGE_SECTION_HEADER) > image.size()) { return 0; }
    const std::span sections(reinterpret_cast<const IMAGE_SECTION_HEADER*>(&image[sections_offset]), section_count);
    for (const auto& section : sections) {
        DWORD begin = nt_headers->OptionalHeader.ImageBase + section.VirtualAddress;
        DWORD end = begin + section.Misc.VirtualSize;
        if (address >= begin && address < end) { return address - begin + section.PointerToRawData; }
    }
    return 0;
}

// A 3.3.5a client is a 32-bit PE. Everything below (the address translation, the patch layout) assumes
// IMAGE_NT_HEADERS32, so this is checked before anything is written.
inline bool isPE32(const std::vector<char>& image) {
    if (image.size() < sizeof(IMAGE_DOS_HEADER)) { return false; }
    const auto* dos_header = reinterpret_cast<const IMAGE_DOS_HEADER*>(image.data());
    if (dos_header->e_magic != IMAGE_DOS_SIGNATURE || dos_header->e_lfanew < 0 ||
        static_cast<size_t>(dos_header->e_lfanew) + sizeof(IMAGE_NT_HEADERS) > image.size()) {
        return false;
    }
    const auto* nt_headers = reinterpret_cast<const IMAGE_NT_HEADERS*>(&image[dos_header->e_lfanew]);
    return nt_headers->Signature == IMAGE_NT_SIGNATURE && nt_headers->FileHeader.Machine == IMAGE_FILE_MACHINE_I386;
}

// The PE timestamp is the build identifier of the client. Patching never touches it, so it can be used
// to tell whether Wow.exe.bak still belongs to the Wow.exe sitting next to it.
inline DWORD peTimestamp(const std::vector<char>& image) {
    if (!isPE32(image)) { return 0; }
    const auto* dos_header = reinterpret_cast<const IMAGE_DOS_HEADER*>(image.data());
    const auto* nt_headers = reinterpret_cast<const IMAGE_NT_HEADERS*>(&image[dos_header->e_lfanew]);
    return nt_headers->FileHeader.TimeDateStamp;
}

inline int hexDigitValue(char c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

inline bool convHexString2ByteArray(std::string_view hex, std::vector<char>& result) {
    result.clear();
    if (hex.size() % 2 != 0) { return false; }
    result.reserve(hex.size() / 2);
    for (size_t i = 0; i < hex.size(); i += 2) {
        const int high = hexDigitValue(hex[i]);
        const int low = hexDigitValue(hex[i + 1]);
        if (high < 0 || low < 0) { return false; }
        result.push_back(static_cast<char>((high << 4) | low));
    }
    return true;
}

inline bool applyLAA(std::vector<char>& image, bool* changed = nullptr) {
    if (image.size() < sizeof(IMAGE_DOS_HEADER)) { return false; }
    auto* dos_header = reinterpret_cast<PIMAGE_DOS_HEADER>(image.data());
    if (dos_header->e_magic != IMAGE_DOS_SIGNATURE || dos_header->e_lfanew < 0 ||
        static_cast<size_t>(dos_header->e_lfanew) + sizeof(IMAGE_NT_HEADERS) > image.size()) {
        return false;
    }
    auto* nt_headers = reinterpret_cast<PIMAGE_NT_HEADERS>(&image[dos_header->e_lfanew]);
    if (nt_headers->Signature != IMAGE_NT_SIGNATURE) { return false; }
    const bool had_flag = (nt_headers->FileHeader.Characteristics & IMAGE_FILE_LARGE_ADDRESS_AWARE) != 0;
    nt_headers->FileHeader.Characteristics |= IMAGE_FILE_LARGE_ADDRESS_AWARE;
    if (changed != nullptr) { *changed = !had_flag; }
    return true;
}
