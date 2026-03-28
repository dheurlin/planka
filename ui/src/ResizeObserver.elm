port module ResizeObserver exposing (..)

import Json.Decode as D

port observeElement : String -> Cmd msg

port resizeEventOccured : (D.Value -> msg) -> Sub msg

resize : (Result String ResizeEvent -> msg) -> Sub msg
resize toMsg = resizeEventOccured <| D.decodeValue decode >>
  ( \res ->
    case res of
    Ok v -> toMsg <| Ok <| v
    Err e -> toMsg <| Err <| D.errorToString e
  )

type alias ResizeEvent =
  { elementId: String
  , newWidth: Int
  , newHeight: Int
  }

decode : D.Decoder ResizeEvent
decode = D.map3 ResizeEvent
  ( D.field "elementId" D.string )
  ( D.field "newWidth" D.int )
  ( D.field "newHeight" D.int )
