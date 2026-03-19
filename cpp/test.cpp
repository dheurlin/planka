#include <cstdint>
#include <string>

#define WASM_EXPORT(name) extern "C" __attribute__((export_name(#name)))
#define WASM_IMPORT extern "C" // TODO Does it have to be done like this?

WASM_IMPORT void hejhej(const char *str);

WASM_EXPORT(add)
std::int32_t add(std::int32_t a, std::int32_t b) {
  return a + b;
}

WASM_EXPORT(hello)
void hello() {
  std::string c = "sdf";
  hejhej(c.c_str());
  // std::print("Hello from c++!");
}
