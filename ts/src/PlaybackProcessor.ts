import { wasmImportObject } from './wasm-helpers';
import WasmBinary from 'wasm/processors/PlaybackProcessor.wasm';
import { WasmAudioProcessor } from './WasmAudioProcessor';
import { assertExhausted } from './utils';

class PlaybackProcessor extends AudioWorkletProcessor implements AudioWorkletProcessorImpl {
  private wasmPlaybackProcesor: WasmPlaybackProcessor | null = null;
  private playbackSpeed = 1;
  private isPlaying = false;

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
          break;

        case "Play":
          self.isPlaying = true;
          break;

        case "Pause":
          self.isPlaying = false;
          break;

        default:
          assertExhausted(ev.data);
      }
    };
  }

  process(inputs: Float32Array[][], outputs: Float32Array[][], _parameters: Record<string, Float32Array>): boolean {
    if (this.wasmPlaybackProcesor == null) {
      return true;
    }

    const input = inputs[0]!;
    const output = outputs[0]!;
    return this.wasmPlaybackProcesor.process(input, output, this.playbackSpeed, this.isPlaying);
  }
}

export type PlaybackProcessorMessage =
  | {
    tag: 'DataReady';
    channels: Array<ArrayBuffer>;
  } | {
    tag: 'PlaybackSpeedChanged',
    newSpeed: number,
  } | {
    tag: 'Play',
  } | {
    tag: 'Pause',
  };

registerProcessor('playback-processor', PlaybackProcessor);

const SIZEOF_FLOAT = 4;

class WasmPlaybackProcessor extends WasmAudioProcessor {
  protected override wasmObjPtr: number;

  private constructor(
    instance: WebAssembly.Instance,
    audioData: Array<ArrayBuffer>,
  ) {
    super("PlaybackProcessor", instance);

    const audioDataWasmPtr = this.copyAudioDataToWasmMemory(audioData);
    const channelLen = (audioData[0]?.byteLength ?? 0) / SIZEOF_FLOAT;

    this.wasmObjPtr = this.wasmInitFunc(sampleRate, audioDataWasmPtr, audioData.length, channelLen);
  }

  static async instantiate(wasmBinary: Uint8Array, audioData: Array<ArrayBuffer>): Promise<WasmPlaybackProcessor> {
    const { instance } = await WebAssembly.instantiate(
      wasmBinary,
      wasmImportObject("PlaybackProcessor", () => instance),
    ) as unknown as WebAssembly.WebAssemblyInstantiatedSource; // Type declarations seem to be wrong here?

    return new WasmPlaybackProcessor(instance, audioData);
  }

  public process(
    inputChannels: Array<Float32Array>,
    outputChannels: Array<Float32Array>,
    playbackSpeed: number,
    isPlaying: boolean,
  ): boolean {
    const { inputChannelsWasmPtr, inputNumChannels, outputChannelsWasmPtr, outputNumChannels } = this.getAudioBuffers(inputChannels.length, outputChannels.length);

    const res = this.wasmProcessFunc(
      this.wasmObjPtr,
      inputChannelsWasmPtr,
      inputNumChannels,
      outputChannelsWasmPtr,
      outputNumChannels,
      playbackSpeed,
      isPlaying,
    );

    this.copyOutputsChannelsFromWasm(outputChannels);

    return res;
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
