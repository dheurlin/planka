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
      _browser_assert: (message: number, file: number, line: number, func: number) => {
        const mem = (getInstance().exports.memory as WebAssembly.Memory).buffer;
        throw new WasmAssert(
          [
            `${charsToString(message, mem)}`,
            `File: ${charsToString(file, mem)}`,
            `Line: ${line}`,
            `Function: ${charsToString(func, mem)}`
          ].join('\n'),
        )
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
      'fd_read',
      'fd_fdstat_get',
      'fd_prestat_get',
      'fd_prestat_dir_name',
      'proc_exit',
    ]),
  });
}

class WasmAssert extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WasmAssert";
  }
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

