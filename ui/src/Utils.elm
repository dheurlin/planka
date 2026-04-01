module Utils exposing (..)

import Http

import Bytes.Decode as BD
import Bytes as B
import Base64.Decode as B64

import Array exposing (Array)
import Array

httpErrorToString : Http.Error -> String
httpErrorToString error =
  case error of
    Http.BadUrl url ->
      "The URL " ++ url ++ " was invalid"
    Http.Timeout ->
      "Unable to reach the server, try again"
    Http.NetworkError ->
      "Unable to reach the server, check your network connection"
    Http.BadStatus 500 ->
      "The server had a problem, try again later"
    Http.BadStatus 400 ->
      "Verify your information and try again"
    Http.BadStatus _ ->
      "Unknown error"
    Http.BadBody errorMessage ->
      "Bad HTTP body: " ++ errorMessage


floatListReverseDecoder : Int -> BD.Decoder (List Float)
floatListReverseDecoder len = bdListReverse len (BD.float32 B.LE)

floatArrayReverseDecoder : Int -> BD.Decoder (Array Float)
floatArrayReverseDecoder len = BD.map (Array.fromList) <| floatListReverseDecoder len

bdListReverse : Int -> BD.Decoder a -> BD.Decoder (List a)
bdListReverse len decoder = BD.loop (len, []) <| bdListReverseStep decoder

bdListReverseStep : BD.Decoder a -> (Int, List a) -> BD.Decoder (BD.Step (Int, List a) (List a))
bdListReverseStep decoder (n, xs) =
  if n <= 0 then
    BD.succeed (BD.Done xs)
  else
    BD.map (\x -> BD.Loop (n - 1, x :: xs)) decoder

decodeSamplesB64 : String -> Int -> Result String (Array Float)
decodeSamplesB64 b64 numSamples =
  B64.decode B64.bytes b64
    |> Result.mapError (\err ->
      case err of
        B64.ValidationError -> "B64 decoding failed: Validation error"
        B64.InvalidByteSequence -> "B64 decoding failed: Invalid bytes sequence"
    )
    |> Result.andThen (\bytes ->
      Result.fromMaybe "Error decoding bytes" <|
        BD.decode (floatListReverseDecoder numSamples) bytes
    )
    |> Result.map (Array.fromList << List.reverse)
