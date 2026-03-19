export function assertMemory<K extends string>(exports: WebAssembly.Exports, key: K): asserts exports is Record<K, WebAssembly.Memory> {
  if (!(exports[key] instanceof WebAssembly.Memory)) {
    throw new TypeError(`Expected export "${key}" to be WebAssembly.Memory, but it was ${JSON.stringify(exports[key])}`);
  }
}

export function assertFunction<K extends string>(exports: WebAssembly.Exports, key: K): asserts exports is Record<K, Function> {
  if (typeof exports[key] !== 'function') {
    throw new TypeError(`Expected export "${key}" to be function, but it was ${JSON.stringify(exports[key])}`);
  }
}

export function notImplementedFuncs(names: Array<string>): Record<string, Function> {
  return Object.fromEntries(names.map((name) => [
    name, function () { throw new Error(`Function ${name} not implemented!`) }
  ]))
}
