import { Elm } from './Main.elm';

import type { PlaybackProcessorMessage } from './PlaybackProcessor';
import type { PitchShiftProcessorMessage } from './PitchShiftProcessor';

declare const playbackSpeedSlider: HTMLInputElement;
declare const pitchShiftFactorSlider: HTMLInputElement;
declare const elmApp: HTMLDivElement;

let cxt = new AudioContext();
let player: AudioWorkletNode | undefined;
let pitchShifter: AudioWorkletNode | undefined;

const ui = Elm.Main!.init({
  node: elmApp,
});

ui.ports.sendMessage?.subscribe(async (message: any) => {
  switch (message.tag) {
    case "FileChosen": {
      const buff = await fileToArrayBuffer(message.fileRef);
      const decoded = await cxt.decodeAudioData(buff);
      // Ensure we use a sample rate that corresponds to the chosen file
      cxt = new AudioContext({ sampleRate: decoded.sampleRate });

      const channelData = Array.from({ length: decoded.numberOfChannels }, (_, i) => decoded.getChannelData(i).buffer)

      startPlayingAudio(channelData);
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

  player.port.postMessage(
    {
      tag: 'DataReady',
      channels: channelData,
    } satisfies PlaybackProcessorMessage,
    channelData,
  );

  cxt.resume();
  ui.ports.receiveMessage?.send("FileLoaded");
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
