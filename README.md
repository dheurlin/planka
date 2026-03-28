Planka
======

Music transcription helper written in Elm and C++

# Features

* Change pitch and speed of audio playback
* (FUTURE) Loop sections of a song to transcribe one piece at a time
* (FUTURE) Equalizer which lets you hone in on specific tracks/instrument (e.g. "bass select" when transcribing a bass line)
* (FUTURE) Mobile-first UI, which can be operated with one hand with the other on the keyboard

# How to build and run

First, build WASM modules:

```
cd cpp 
make
```

> Note that you will need to install the necessary WASI components (runtime, std-libs for C & C++, ...) and possibly modify the `Makefile` according to where your distribution places those files.

Next, ensure the Elm compiler is installed. Use your search engine of choice for instructions on how to do this on your OS/distro

Now we can build the UI:

```
# Starting from repo root:
cd ts
npm ci
npm run build
```

And start a dev server as such:

```
npm run serve
```

The two steps above can be combined by running

```
npm run dev
```
