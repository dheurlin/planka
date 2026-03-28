import WasmBinary from 'wasm/processors/PitchShiftProcessor.wasm';
import { wasmImportObject } from "./wasm-helpers";
import { WasmAudioProcessor } from "./WasmAudioProcessor";

class PitchShiftProcessor extends AudioWorkletProcessor implements AudioWorkletProcessorImpl {
  private wasmPitchShiftProcessor: WasmPitchShiftProcessor | null = null;
  private playbackSpeed = 1;
  private pitchShiftFactor = 1;
  private mixToMono = true; // This improves performance on weaker devices

  constructor() {
    super();
    WasmPitchShiftProcessor.instantiate(WasmBinary).then((p) => this.wasmPitchShiftProcessor = p);

    const self = this;
    this.port.onmessage = function (this, ev: MessageEvent<PitchShiftProcessorMessage>) {
      switch (ev.data.tag) {
        case 'PlaybackSpeedChanged':
          self.playbackSpeed = ev.data.newSpeed;
          break;

        case 'PitchShiftFactorChanged':
          self.pitchShiftFactor = ev.data.newPitchShiftFactor;
          break;

        default:
          throw new TypeError('IMPOSSIBLE');
      }
    };
  }

  process(inputs: Float32Array[][], outputs: Float32Array[][]): boolean {
    if (this.wasmPitchShiftProcessor == null) {
      return true;
    }

    return this.wasmPitchShiftProcessor.process(inputs[0]!, outputs[0]!, this.pitchShiftFactor, this.playbackSpeed, this.mixToMono);
  }
}

export type PitchShiftProcessorMessage = 
  | {
    tag: 'PlaybackSpeedChanged',
    newSpeed: number,
  } | {
    tag: 'PitchShiftFactorChanged',
    newPitchShiftFactor: number,
  }

registerProcessor('pitch-shift-processor', PitchShiftProcessor);

class WasmPitchShiftProcessor extends WasmAudioProcessor {
  protected override wasmObjPtr: number;

  private constructor(instance: WebAssembly.Instance) {
    super("PitchShiftProcessor", instance);
    this.wasmObjPtr = this.wasmInitFunc(sampleRate);
  }

  static async instantiate(wasmBinary: Uint8Array): Promise<WasmPitchShiftProcessor> {
    const { instance } = await WebAssembly.instantiate(
      wasmBinary,
      wasmImportObject("PitchShiftProcessor", () => instance),
    ) as unknown as WebAssembly.WebAssemblyInstantiatedSource; // Type declarations seem to be wrong here?

    return new WasmPitchShiftProcessor(instance);
  }

  public process(
    inputChannels: Array<Float32Array>,
    outputChannels: Array<Float32Array>,
    targetPitchShiftFactor: number,
    playbackSpeed: number,
    mixToMono: boolean,
  ): boolean {
    const { inputChannelsWasmPtr, inputNumChannels, outputChannelsWasmPtr, outputNumChannels } = this.getAudioBuffers(inputChannels.length, outputChannels.length);

    this.copyInputChannelsToWasm(inputChannels);

    const res = this.wasmProcessFunc(
      this.wasmObjPtr,
      inputChannelsWasmPtr,
      inputNumChannels,
      outputChannelsWasmPtr,
      outputNumChannels,
      targetPitchShiftFactor,
      playbackSpeed,
      mixToMono,
    );

    this.copyOutputsChannelsFromWasm(outputChannels);

    return res;
  }

}
