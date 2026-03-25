
declare module 'esbuild-plugin-elm' {
  import type { Plugin } from 'esbuild';

  export type ElmPluginOpts = {
    /**
     * Enable the time-travelling debugger (default: false)
     */
    debug: boolean,
    /**
    * Optimize the js output (true by default if NODE_ENV is production) (default: NODE_ENV === 'production')
    */
    optimize: boolean,
    /**
    * Specify an explicit path to the elm executable (default: node_modules/.bin/elm || elm):
    */
    pathToElm: string,

    /**
     * Clear the console before re-building on file changes (default: false)
     */
    clearOnWatch: boolean,
    /*
     * The current working directory/elm project root (default: <PWD>)
     */
    cwd: string,

    /**
    * Enable verbose output of node-elm-compiler (default: false)
    */
    verbose: boolean;
  }

  export const ElmPlugin: (opts: Partial<ElmPluginOpts>) => Plugin;
  export default ElmPlugin;
}
