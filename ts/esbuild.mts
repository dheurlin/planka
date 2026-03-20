import * as esbuild from 'esbuild';

const options: esbuild.BuildOptions = {
  entryPoints: ['src/main.ts', 'src/PlaybackProcessor.ts'],
  bundle: true,
  // outbase: '../dist'
  outdir: '../dist',
}

if (process.argv.includes('--watch')) {
  await esbuild.context(options).then((cxt) => cxt.watch());
} else {
  await esbuild.build(options);
}
