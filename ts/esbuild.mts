import * as esbuild from 'esbuild';

const options: esbuild.BuildOptions = {
  entryPoints: [
    'src/main.ts',
    'src/PlaybackProcessor.ts',
    'src/PitchShiftProcessor.ts',
  ],
  loader: { '.wasm': 'binary' },
  alias: {
    'wasm': '../cpp/build/wasm',
  },
  bundle: true,
  outbase: 'src',
  outdir: '../dist',
}

if (process.argv.includes('--watch')) {
  await esbuild.context(options).then((cxt) => cxt.watch());
} else {
  await esbuild.build(options);
}
