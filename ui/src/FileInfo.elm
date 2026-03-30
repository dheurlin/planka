module FileInfo exposing (..)

import Array exposing (Array)

type alias FileInfoToDownload =
  { sampleRate: Float
  , durationInMs: Int
  , reverseSamplesURL: String -- We receive the samples in reverse, so we don't have to reverse a linked list on the elm side
  , numSamples: Int
  }

type alias FileInfo =
  { sampleRate: Float
  , durationInMs: Int
  , numSamples: Int
  , channelData: Array Float
  }

fromFileInfoToDownload : FileInfoToDownload -> Array Float -> FileInfo
fromFileInfoToDownload f samples =
  { sampleRate = f.sampleRate
  , durationInMs = f.durationInMs
  , numSamples = f.numSamples
  , channelData = samples
  }
