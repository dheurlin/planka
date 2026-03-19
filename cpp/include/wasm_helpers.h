#define WASM_EXPORT(name) extern "C" __attribute__((export_name(#name)))
#define WASM_IMPORT extern "C" // TODO Does it have to be done like this?
