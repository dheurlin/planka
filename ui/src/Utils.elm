module Utils exposing (..)

import Http

import Bytes.Decode as BD
import Bytes as B

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


floatListDecoder : Int -> BD.Decoder (List Float)
floatListDecoder len = bdList len (BD.float32 B.LE)

bdList : Int -> BD.Decoder a -> BD.Decoder (List a)
bdList len decoder = BD.loop (len, []) <| bdListStep decoder

bdListStep : BD.Decoder a -> (Int, List a) -> BD.Decoder (BD.Step (Int, List a) (List a))
bdListStep decoder (n, xs) =
  if n <= 0 then
    BD.succeed (BD.Done xs)
  else
    BD.map (\x -> BD.Loop (n - 1, x :: xs)) decoder
