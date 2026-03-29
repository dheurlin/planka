import ElmPlugin from 'esbuild-plugin-elm';
import * as esbuild from 'esbuild';

const options = (useMockSamples: boolean) => ({
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
  define: { USE_MOCK_SAMPLES: useMockSamples ? 'true' : 'false' },
  plugins: [
    ElmPlugin({
      cwd: '../ui',
    }),
  ],
} satisfies esbuild.BuildOptions);

const useMockSamples = process.argv.includes('--use-mock-samples');

if (process.argv.includes('--watch')) {
  await esbuild.context(options(useMockSamples)).then((cxt) => cxt.watch());
} else {
  await esbuild.build(options(useMockSamples));
}
