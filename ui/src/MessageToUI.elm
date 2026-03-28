port module MessageToUI exposing (..)

import Json.Decode as D

port receiveMessage : (D.Value -> msg) -> Sub msg

receive : (Result String MessageToUI -> msg) -> Sub msg
receive f = receiveMessage <| D.decodeValue decode >>
  ( \res ->
    case res of
    Ok v -> f <| Ok <| v
    Err e -> f <| Err <| D.errorToString e
  )

type MessageToUI
  = AudioInfo AudioInfoPayload
  | PlaybackProgress PlaybackProgressPayload

type alias AudioInfoPayload =
  { sampleRate: Float
  , durationInMs: Int
  , reverseSamplesURL: String
  , numSamples: Int
  }

type alias PlaybackProgressPayload =
  { progressInSamples: Int }

decode : D.Decoder MessageToUI
decode = D.field "tag" D.string |> D.andThen
  ( \tag ->
      case tag of
        "AudioInfo" -> D.map AudioInfo decodeAudioInfoPayload
        "PlaybackProgress" -> D.map PlaybackProgress decodePlaybackProgressPayload
        _ -> D.fail <| "Unknown message tag " ++ quote tag
  )


decodeAudioInfoPayload : D.Decoder AudioInfoPayload
decodeAudioInfoPayload =
  D.map4 AudioInfoPayload
    ( D.field "sampleRate" D.float )
    ( D.field "durationInMs" D.int )
    ( D.field "reverseSamplesURL" D.string )
    ( D.field "numSamples" D.int )

decodePlaybackProgressPayload : D.Decoder PlaybackProgressPayload
decodePlaybackProgressPayload =
    D.map PlaybackProgressPayload ( D.field "currentProgressInSamples" D.int )

quote : String -> String
quote s = "\"" ++ s ++ "\""
