import { wasmImportObject } from './wasm-helpers';
import WasmBinary from 'wasm/processors/PlaybackProcessor.wasm';

class PlaybackProcessor extends AudioWorkletProcessor implements AudioWorkletProcessorImpl {
  private wasmPlaybackProcesor: WasmPlaybackProcessor | null = null;
  private playbackSpeed = 1;

  constructor() {
    super();

    const self = this;
    this.port.onmessage = async function (this, ev: MessageEvent<PlaybackProcessorMessage>) {
      switch (ev.data.tag) {
        case 'DataReady':
          self.wasmPlaybackProcesor = await WasmPlaybackProcessor.instantiate(WasmBinary, ev.data.channels);
          break;

        case "PlaybackSpeedChanged":
          self.playbackSpeed = ev.data.newSpeed;
      }
    };
  }

  process(_inputs: Float32Array[][], outputs: Float32Array[][], _parameters: Record<string, Float32Array>): boolean {
    if (this.wasmPlaybackProcesor == null) {
      return true;
    }

    // Assuming a single input and output
    const output = outputs[0]!;
    return this.wasmPlaybackProcesor.process(output, this.playbackSpeed);
  }
}

export type PlaybackProcessorMessage =
  | {
    tag: 'DataReady';
    channels: Array<ArrayBuffer>;
  } | {
    tag: 'PlaybackSpeedChanged',
    newSpeed: number,
  };

registerProcessor('playback-processor', PlaybackProcessor);

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

  static async instantiate(wasmBinary: Uint8Array, audioData: Array<ArrayBuffer>): Promise<WasmPlaybackProcessor> {
    const { instance } = await WebAssembly.instantiate(
      wasmBinary,
      wasmImportObject("PlaybackProcessor", () => instance),
    ) as unknown as WebAssembly.WebAssemblyInstantiatedSource; // Type declarations seem to be wrong here?

    return new WasmPlaybackProcessor(instance, audioData);
  }

  public process(outputChannels: Array<Float32Array>, playbackSpeed: number): boolean {
    const PlaybackProcessor_process = this.instance.exports.PlaybackProcessor_process as Function;

    const res = PlaybackProcessor_process(
      this.wasmObjPtr,
      this.outputChannelsWasmPtr,
      this.audioData.length,
      playbackSpeed,
    );
    
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
