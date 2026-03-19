class PlaybackProcessor extends AudioWorkletProcessor implements AudioWorkletProcessorImpl {
  private wasmPlaybackProcesor: WasmPlaybackProcessor | null = null;

  constructor() {
    super();

    const self = this;
    this.port.onmessage = async function (this, ev: MessageEvent<PlaybackProcessorMessage>) {
      switch (ev.data.tag) {
        case 'DataReady':
          console.log(ev.data);
          self.wasmPlaybackProcesor = await WasmPlaybackProcessor.instantiate(ev.data.wasmModule, ev.data.channels);
        break;
      }
    };

  }

  process(_inputs: Float32Array[][], outputs: Float32Array[][], _parameters: Record<string, Float32Array>): boolean {
    if (this.wasmPlaybackProcesor == null) {
      return true;
    }

    // Assuming a single output
    const output = outputs[0]!;
    return this.wasmPlaybackProcesor.process(output);
  }
}

export type PlaybackProcessorMessage =
  ({
    tag: 'DataReady';
    channels: Array<ArrayBuffer>;
    wasmModule: WebAssembly.Module;
  })

registerProcessor('playback-processor', PlaybackProcessor);

const wasmImportObject = (getInstance: () => WebAssembly.Instance): WebAssembly.Imports => ({
  env: {
    _console_log: (ptr: number) => {
      console.log(
        "[PlaybackProcessor.wasm] " +
        charsToString(ptr, (getInstance().exports.memory as WebAssembly.Memory).buffer));
    }
  },
  wasi_snapshot_preview1: notImplementedFuncs(['fd_close', 'fd_seek', 'fd_write']),
});

const SIZEOF_FLOAT = 4;
const FRAME_SIZE = 128;

class WasmPlaybackProcessor {
  private wasmObjPtr: number;
  private outputChannelsWasmPtr: number;
  private memory: WebAssembly.Memory;

  private constructor(
    private readonly instance: WebAssembly.Instance,
    private readonly audioData: Array<ArrayBuffer>,
  ) {
    this.memory = this.instance.exports.memory as WebAssembly.Memory;
    const audioDataWasmPtr = this.copyAudioDataToWasmMemory(audioData);
    const channelLen = (audioData[0]?.byteLength ?? 0) / SIZEOF_FLOAT;

    const PlaybackProcessor_Init = instance.exports.PlaybackProcessor_init as Function;
    this.wasmObjPtr = PlaybackProcessor_Init(sampleRate, audioDataWasmPtr, audioData.length, channelLen);

    this.outputChannelsWasmPtr = this.malloc(audioData.length * FRAME_SIZE * SIZEOF_FLOAT);
  }

  static async instantiate(module: WebAssembly.Module, audioData: Array<ArrayBuffer>): Promise<WasmPlaybackProcessor> {
    const instance: WebAssembly.Instance = await WebAssembly.instantiate(module, wasmImportObject(() => instance) );
    return new WasmPlaybackProcessor(instance, audioData);
  }

  public process(outputChannels: Array<Float32Array>): boolean {
    const PlaybackProcessor_process = this.instance.exports.PlaybackProcessor_process as Function;

    const res = PlaybackProcessor_process(this.wasmObjPtr, this.outputChannelsWasmPtr, this.audioData.length, FRAME_SIZE);
    
    // Copy out...
    for (const [i, outputChannel] of outputChannels.entries()) {
      const srcPtr = this.outputChannelsWasmPtr + i * FRAME_SIZE * SIZEOF_FLOAT;
      outputChannel.set(new Float32Array(this.memory.buffer, srcPtr, FRAME_SIZE));
    }

    return res;
  }

  private malloc(numBytes: number): number {
    const malloc = this.instance.exports.malloc as (sizeInBytes: number) => number;
    const mallocRes = malloc(numBytes);
    if (mallocRes == 0) {
      throw new RangeError("Failed to allocate WASM memory");
    }
    return mallocRes;
  }

  private copyAudioDataToWasmMemory(audioData: Array<ArrayBuffer>): number {
    const audioDataWasmPtr = this.malloc(audioData.reduce((sum, buff) => sum + buff.byteLength, 0));
    const target = new Float32Array(this.memory.buffer, audioDataWasmPtr);

    let currOffset = 0;
    for (const buff of audioData) {
      const src = new Float32Array(buff);
      target.set(src, currOffset);
      currOffset += src.length;
    }

    return audioDataWasmPtr;
  }
}


// WASM stuff. TODO: Configure build so we can import this shit

function notImplementedFuncs(names: Array<string>): Record<string, Function> {
  return Object.fromEntries(names.map((name) => [
    name, function () { throw new Error(`Function ${name} not implemented!`) }
  ]))
}

function charsToString(basePtr: number, mem: ArrayBuffer): string {
  let str = "";
  let memAsArr = new Uint8Array(mem);
  for (let i = basePtr; memAsArr[i] !== 0; i++) {
    str += String.fromCharCode(memAsArr[i]!);
  }

  return str;
}


