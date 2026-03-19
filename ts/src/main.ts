import type { PlaybackProcessorMessage } from './PlaybackProcessor.js';
import { assertFunction, assertMemory, notImplementedFuncs } from './wasm-helpers.js';

declare const fileSelect: HTMLInputElement;
let cxt = new AudioContext();

fileSelect.addEventListener('change', async () => {
  if (fileSelect.files == null || fileSelect.files[0] == null) {
    console.warn("No files selected...");
    return;
  }

  const buff = await fileToArrayBuffer(fileSelect.files[0]);
  const decoded = await cxt.decodeAudioData(buff);
  // Ensure we use a sample rate that corresponds to the chosen file
  cxt = new AudioContext({ sampleRate: decoded.sampleRate });
  console.log(cxt);
  
  // const channelData = channelsToSharedArrayBuffers(decoded);
  const channelData = Array.from({ length: decoded.numberOfChannels }, (_, i) => decoded.getChannelData(i).buffer)
  startPlayingAudio(channelData);
});

async function startPlayingAudio(channelData: Array<ArrayBuffer>) {
  await cxt.audioWorklet.addModule('dist/PlaybackProcessor.js');

  const player = new AudioWorkletNode(cxt, 'playback-processor', {
    channelCount: channelData.length,
    outputChannelCount: [ channelData.length ]
  });
  player.connect(cxt.destination);

  player.port.postMessage(
    {
      tag: 'DataReady',
      channels: channelData,
      wasmModule: await WebAssembly.compileStreaming(fetch('dist/wasm/processors/PlaybackProcessor.wasm')) ,
    } satisfies PlaybackProcessorMessage,
    channelData,
  );

  cxt.resume();
}

function fileToArrayBuffer(file: File): Promise<ArrayBuffer> {
  const reader = new FileReader();
  return new Promise((resolve) => {
    reader.readAsArrayBuffer(file);
    reader.onload = () => {
      if (!(reader.result instanceof ArrayBuffer)) {
        throw new TypeError(`Reader unexpectedly returned ${typeof reader.result}`);
      }
      resolve(reader.result);
    }
  });
}

export default {}
