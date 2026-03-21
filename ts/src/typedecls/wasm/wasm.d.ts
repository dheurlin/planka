declare module "wasm/processors/*.wasm" {
  const WasmModule: Uint8Array;
  export default WasmModule;
}
