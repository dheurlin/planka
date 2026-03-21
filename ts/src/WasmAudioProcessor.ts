const FRAME_SIZE = 128;
const SIZEOF_FLOAT = 4;

export abstract class WasmAudioProcessor {
  /** We expect subclasses to initialize this themselves */
  protected abstract wasmObjPtr: number;
  protected memory: WebAssembly.Memory;
  private inputChannelsWasmPtr: number | undefined;
  private inputNumChannels: number | undefined;
  private outputChannelsWasmPtr: number | undefined;
  private outputNumChannels: number | undefined;

  protected wasmInitFunc: (...args: any[]) => number;
  protected wasmProcessFunc: (thisPtr: number, inputChannelsPtr: number, inputNumChannels: number, outputChannelsPtr: number, outputNumChannels: number, ...rest: any[]) => boolean;

  protected constructor(
    wasmClassName: string,
    private readonly instance: WebAssembly.Instance,
  ) {
    if (!(this.instance.exports.memory instanceof WebAssembly.Memory)) {
      throw new TypeError(`Expected instance to have an exported memory of type WebAssembly.Memory`);
    }
    this.memory = this.instance.exports.memory;

    const initFnName = `${wasmClassName}_init` as const;
    if (typeof this.instance.exports[initFnName] !== 'function') {
      throw new TypeError(`Expected instance to have an exported function "${initFnName}"`);
    }

    this.wasmInitFunc = this.instance.exports[initFnName] as typeof this.wasmInitFunc;

    const processFnName = `${wasmClassName}_process` as const;
    if (typeof this.instance.exports[processFnName] !== 'function') {
      throw new TypeError(`Expected instance to have an exported function "${processFnName}"`);
    }

    this.wasmProcessFunc = this.instance.exports[processFnName] as typeof this.wasmProcessFunc;
  }

  protected getAudioBuffers(inputNumChannels: number, outputNumChannels: number): {
    inputChannelsWasmPtr: number,
    inputNumChannels: number,
    outputChannelsWasmPtr: number,
    outputNumChannels: number,
  } {
    if (
      this.inputChannelsWasmPtr === undefined &&
      this.inputNumChannels === undefined &&
      this.outputChannelsWasmPtr === undefined &&
      this.outputNumChannels === undefined
    ) {
      this.inputNumChannels = inputNumChannels;
      this.outputNumChannels = outputNumChannels;

      this.inputChannelsWasmPtr = this.malloc(inputNumChannels * FRAME_SIZE * SIZEOF_FLOAT);
      this.outputChannelsWasmPtr = this.malloc(outputNumChannels * FRAME_SIZE * SIZEOF_FLOAT);

      return { 
        inputNumChannels,
        outputNumChannels,
        outputChannelsWasmPtr: this.outputChannelsWasmPtr,
        inputChannelsWasmPtr: this.outputChannelsWasmPtr,
      };
    } else if (inputNumChannels !== this.inputNumChannels || outputNumChannels !== this.outputNumChannels) {
      throw new Error("Channel count unexpectedly changed, we don't handle this!")
    } else if (
      this.inputChannelsWasmPtr !== undefined &&
      this.inputNumChannels !== undefined &&
      this.outputChannelsWasmPtr !== undefined &&
      this.outputNumChannels !== undefined
    ) {
      return { 
        inputNumChannels,
        outputNumChannels,
        outputChannelsWasmPtr: this.outputChannelsWasmPtr,
        inputChannelsWasmPtr: this.outputChannelsWasmPtr,
      };
    }

    throw new Error("IMPOSSIBLE!");
  }

  protected copyInputchannelsToWasm(inputChannels: Array<Float32Array>) {
    if (this.inputChannelsWasmPtr === undefined) {
      throw new Error("outputChannelsWasmPtr was unexpectedly undefined!");
    }

    const target = new Float32Array(this.memory.buffer, this.inputChannelsWasmPtr);

    let currOffset = 0;
    for (const buff of inputChannels) {
      const src = new Float32Array(buff);
      target.set(src, currOffset);
      currOffset += src.length;
    }

  }

  protected copyOutputsChannelsFromWasm(outputChannels: Array<Float32Array>) {
    if (this.outputChannelsWasmPtr === undefined) {
      throw new Error("outputChannelsWasmPtr was unexpectedly undefined!");
    }

    for (const [i, outputChannel] of outputChannels.entries()) {
      const srcPtr = this.outputChannelsWasmPtr + i * FRAME_SIZE * SIZEOF_FLOAT;
      outputChannel.set(new Float32Array(this.memory.buffer, srcPtr, FRAME_SIZE));
    }
  }

  protected malloc(numBytes: number): number {
    const malloc = this.instance.exports.malloc as (sizeInBytes: number) => number;
    const mallocRes = malloc(numBytes);
    if (mallocRes == 0) {
      throw new RangeError("Failed to allocate WASM memory");
    }
    return mallocRes;
  }
}
