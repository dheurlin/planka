import { Elm } from './Main.elm';

import type { PlaybackProcessorMessage } from './PlaybackProcessor';
import type { PitchShiftProcessorMessage } from './PitchShiftProcessor';

declare const fileSelect: HTMLInputElement;
declare const playbackSpeedSlider: HTMLInputElement;
declare const pitchShiftFactorSlider: HTMLInputElement;
declare const elmApp: HTMLDivElement;

let cxt = new AudioContext();
let player: AudioWorkletNode | undefined;
let pitchShifter: AudioWorkletNode | undefined;

const ui = Elm.Main!.init({
  node: elmApp,
});

fileSelect.addEventListener('change', async () => {
  if (fileSelect.files == null || fileSelect.files[0] == null) {
    console.warn("No files selected...");
    return;
  }

  const buff = await fileToArrayBuffer(fileSelect.files[0]);
  const decoded = await cxt.decodeAudioData(buff);
  // Ensure we use a sample rate that corresponds to the chosen file
  cxt = new AudioContext({ sampleRate: decoded.sampleRate });

  const channelData = Array.from({ length: decoded.numberOfChannels }, (_, i) => decoded.getChannelData(i).buffer)
  const initialPlaybackSpeed = playbackSpeedSlider.value;
  const initialPitchShiftFactor = pitchShiftFactorSlider.value;

  startPlayingAudio(
    channelData,
    parseFloatWithFallback(initialPlaybackSpeed, 1),
    parseFloatWithFallback(initialPitchShiftFactor, 1),
  );
});

playbackSpeedSlider.addEventListener('change', () => {
  if (player === undefined) {
    return;
  }
  const hopefullyFloat = Number.parseFloat(playbackSpeedSlider.value);
  if (Number.isNaN(hopefullyFloat)) {
    console.error("Invalid data in input slider: ", playbackSpeedSlider.value);
    return;
  }

  player.port.postMessage({
    tag: 'PlaybackSpeedChanged', newSpeed: hopefullyFloat,
  } satisfies PlaybackProcessorMessage);

  if (pitchShifter === undefined) {
    console.error("pitchShifter was undefined!");
    return;
  }
  pitchShifter.port.postMessage({
    tag: 'PlaybackSpeedChanged',
    newSpeed: hopefullyFloat,
  } satisfies PitchShiftProcessorMessage);
});

pitchShiftFactorSlider.addEventListener('change', () => {
  console.log("LKJDFLKJDF");
  if (pitchShifter === undefined) {
    console.error("pitchShifter was undefined!");
    return;
  }
  const hopefullyFloat = Number.parseFloat(pitchShiftFactorSlider.value);
  if (Number.isNaN(hopefullyFloat)) {
    console.error("Invalid data in input slider: ", playbackSpeedSlider.value);
    return;
  }

  pitchShifter.port.postMessage({
    tag: 'PitchShiftFactorChanged',
    newPitchShiftFactor: hopefullyFloat,
  } satisfies PitchShiftProcessorMessage);
});

async function startPlayingAudio(
  channelData: Array<ArrayBuffer>,
  initialPlaybackSpeed: number,
  initialPitchShiftFactor: number,
) {
  await Promise.all(['PlaybackProcessor', 'PitchShiftProcessor'].map((name) => {
    return cxt.audioWorklet.addModule(`dist/${name}.js`);
  }));

  player = new AudioWorkletNode(cxt, 'playback-processor', {
    channelCount: channelData.length,
    outputChannelCount: [ channelData.length ]
  });
  pitchShifter = new AudioWorkletNode(cxt, 'pitch-shift-processor');

  player.connect(pitchShifter).connect(cxt.destination);

  player.port.postMessage({
    tag: 'PlaybackSpeedChanged', newSpeed: initialPlaybackSpeed,
  } satisfies PlaybackProcessorMessage);

  player.port.postMessage(
    {
      tag: 'DataReady',
      channels: channelData,
    } satisfies PlaybackProcessorMessage,
    channelData,
  );

  pitchShifter.port.postMessage({
    tag: 'PlaybackSpeedChanged', newSpeed: initialPlaybackSpeed,
  } satisfies PitchShiftProcessorMessage);

  pitchShifter.port.postMessage({
    tag: 'PitchShiftFactorChanged', newPitchShiftFactor: initialPitchShiftFactor,
  } satisfies PitchShiftProcessorMessage);

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

function parseFloatWithFallback(input: string, fallback: number): number {
  const hopefullyFloat = Number.parseFloat(input);

  if (Number.isNaN(hopefullyFloat)) {
    return fallback;
  }

  return hopefullyFloat;
}

export default {}
