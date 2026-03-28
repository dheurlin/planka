import { Elm } from './Main.elm';

import type { PlaybackProcessorMessage } from './PlaybackProcessor';
import type { PitchShiftProcessorMessage } from './PitchShiftProcessor';
import { ResizeObserverElmIntegration } from './ResizeObserverElmIntegration';

declare const elmApp: HTMLDivElement;

let cxt = new AudioContext();
let player: AudioWorkletNode | undefined;
let pitchShifter: AudioWorkletNode | undefined;

const ui = Elm.Main!.init({
  node: elmApp,
});

const _resizer = new ResizeObserverElmIntegration(ui);

ui.ports.sendMessage?.subscribe(async (message: any) => {
  switch (message.tag) {
    case "FileChosen": {
      const buff = await fileToArrayBuffer(message.fileRef);
      console.log("Decoding audio...");
      const decoded = await cxt.decodeAudioData(buff);
      // Ensure we use a sample rate that corresponds to the chosen file
      cxt = new AudioContext({ sampleRate: decoded.sampleRate });

      const channelData = Array.from({ length: decoded.numberOfChannels }, (_, i) => decoded.getChannelData(i).buffer)

      startPlayingAudio(channelData, decoded);
      break;
    }

    case "PlaybackSpeedChanged":
      player?.port.postMessage({
        tag: "PlaybackSpeedChanged",
        newSpeed: message.playbackSpeed,
      } satisfies PlaybackProcessorMessage);

      pitchShifter?.port.postMessage({
        tag: "PlaybackSpeedChanged",
        newSpeed: message.playbackSpeed,
      } satisfies PitchShiftProcessorMessage);

      break;

    case "PitchShiftFactorChanged":
      pitchShifter?.port.postMessage({
        tag: "PitchShiftFactorChanged",
        newPitchShiftFactor: message.pitchShiftFactor,
      } satisfies PitchShiftProcessorMessage);

      break;

    default:
      throw new TypeError(`Unknown message from Elm: ${JSON.stringify(message)}`);
  }
})

async function startPlayingAudio(
  channelData: Array<ArrayBuffer>,
  audioBuffer: AudioBuffer,
) {
  console.log("Reversing samples...");
  // Have to do it before we send it to PlaybackProcessor, cause we
  // transfer it and it gets invalidated
  const reverseSamplesURL = URL.createObjectURL(new Blob([
    reverseSamples(new Float32Array(channelData[0]!)).buffer
  ]));
  const numSamples = channelData[0]!.byteLength / 4;

  await Promise.all(['PlaybackProcessor', 'PitchShiftProcessor'].map((name) => {
    return cxt.audioWorklet.addModule(`dist/${name}.js`);
  }));

  player = new AudioWorkletNode(cxt, 'playback-processor', {
    channelCount: channelData.length,
    outputChannelCount: [ channelData.length ]
  });
  pitchShifter = new AudioWorkletNode(cxt, 'pitch-shift-processor');

  player.connect(pitchShifter).connect(cxt.destination);

  console.log("Ready to play");
  player.port.postMessage(
    {
      tag: 'DataReady',
      channels: channelData,
    } satisfies PlaybackProcessorMessage,
    channelData,
  );

  cxt.resume();

  console.log("dataURL from JS side: ", reverseSamplesURL);
  ui.ports.receiveMessage?.send({
    tag: 'AudioInfo',
    sampleRate: audioBuffer.sampleRate,
    durationInMs: Math.round(audioBuffer.duration * 1000),
    reverseSamplesURL: reverseSamplesURL,
    numSamples,
  });
}

function reverseSamples(orig: Float32Array<ArrayBuffer>): Float32Array<ArrayBuffer> {
  const copy = new Float32Array(orig.length);
  copy.set(orig);
  copy.reverse();
  return copy;
}

function fileToArrayBuffer(file: File): Promise<ArrayBuffer> {
  const reader = new FileReader();
  return new Promise((resolve) => {
    reader.readAsArrayBuffer(file);
    reader.onload = () => {
      resolve(reader.result as ArrayBuffer);
    }
  });
}

export default {}
