#pragma once

#include <string>

#define WASM_EXPORT(name) extern "C" __attribute__((export_name(#name)))
#define WASM_IMPORT extern "C" // TODO Does it have to be done like this?

WASM_IMPORT void _console_log(const char *str);
WASM_IMPORT void _console_error(const char *str);

WASM_IMPORT void _browser_assert(const char *, const char *, int, const char *);
#define browser_assert(x) ((void)((x) || (_browser_assert(#x, __FILE__, __LINE__, __func__),0)))

namespace console {
  void log(const std::string& str);
  void error(const std::string& str);
};

// Helpers for printing, in the absense of proper formatting
#define s(n) (std::to_string((n)))
#define p(n) (std::to_string(reinterpret_cast<uintptr_t>((n))))

