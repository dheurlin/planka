export function wasmImportObject(moduleName: string, getInstance: () => WebAssembly.Instance): WebAssembly.Imports {
  return ({
    env: {
      _console_log: (ptr: number) => {
        console.log(
          `[${moduleName}.wasm] ` +
          charsToString(ptr, (getInstance().exports.memory as WebAssembly.Memory).buffer));
      },
      _console_error: (ptr: number) => {
        console.error(
          `[${moduleName}.wasm] ` +
          charsToString(ptr, (getInstance().exports.memory as WebAssembly.Memory).buffer));
      },
      ...notImplementedFuncs([
        // Inshallah this will not be called
        '__mulsc3',
      ]),
    },
    wasi_snapshot_preview1: notImplementedFuncs([
      'fd_close',
      'fd_seek',
      'fd_write',
    ]),
  });
}

export function notImplementedFuncs(names: Array<string>): Record<string, Function> {
  return Object.fromEntries(names.map((name) => [
    name, function () { throw new Error(`Function ${name} not implemented!`) }
  ]))
}

export function charsToString(basePtr: number, mem: ArrayBuffer): string {
  let str = "";
  let memAsArr = new Uint8Array(mem);
  for (let i = basePtr; memAsArr[i] !== 0; i++) {
    str += String.fromCharCode(memAsArr[i]!);
  }

  return str;
}

