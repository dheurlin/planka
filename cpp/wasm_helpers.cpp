#include "wasm_helpers.h"

namespace console {
  void log(const std::string& str) {
    _console_log(str.c_str());
  }
}
