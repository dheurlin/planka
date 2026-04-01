module Gestures exposing (..)

import Html.Events exposing (on)
import Html
import Json.Decode as D

type alias Coord = { x: Float, y: Float }

coordDiff : Coord -> Coord -> Coord
coordDiff c1 c2 = { x = c1.x - c2.x, y = c1.y - c2.y }

midPoint : Coord -> Coord -> Coord
midPoint c1 c2 =
  { x = c1.x + ( c2.x - c1.x ) / 2
  , y = c1.y + ( c2.y - c1.y ) / 2
  }

distance : Coord -> Coord -> Float
distance c1 c2 = sqrt <| (c2.x - c1.x)^2 + (c2.y - c1.y)^2

type PointerState
  = None
  | PointingSingle
    { distanceMoved : Coord
    , pointer: Pointer
    }
  | PointingDouble
    { distanceMoved : Coord
    , distanceZoomed : Float
    , pointer1: Pointer
    , pointer2: Pointer
    }

type alias Pointer =
  { pointerId: Int
  , position: Coord
  , startPosition: Coord
  }

updatePointerPosition : Coord -> Pointer -> Pointer
updatePointerPosition c p = { p | position = c }

updateState : PointerMsg -> PointerState -> PointerState
updateState ev state = case (ev, state) of
  ( GotPointerDown { pointerId, clientCoords }, None ) -> PointingSingle
      { pointer = { pointerId = pointerId, position = clientCoords, startPosition = clientCoords }
      , distanceMoved = { x = 0, y = 0 }
      }

  ( GotPointerDown { pointerId, clientCoords }, PointingSingle p ) ->
     PointingDouble
          { pointer1 = p.pointer
          , pointer2 = { pointerId = pointerId, position = clientCoords, startPosition = clientCoords }
          , distanceMoved = p.distanceMoved
          , distanceZoomed = 0
          }

  ( GotPointerMove { clientCoords }, PointingSingle p ) ->
    let
      newPointer = updatePointerPosition clientCoords p.pointer
    in
       PointingSingle
            { p
            | pointer = newPointer
            , distanceMoved = coordDiff p.pointer.startPosition clientCoords 
            }

  ( GotPointerMove { pointerId, clientCoords }, PointingDouble p ) ->
    let
      newPointer1 = if pointerId == p.pointer1.pointerId
        then updatePointerPosition clientCoords p.pointer1
        else p.pointer1

      newPointer2 = if pointerId == p.pointer2.pointerId
        then updatePointerPosition clientCoords p.pointer2
        else p.pointer2
    in
       PointingDouble
            { p
            | pointer1 = newPointer1
            , pointer2 = newPointer2
            , distanceZoomed =
              (distance p.pointer1.position p.pointer2.position) -
              (distance newPointer1.startPosition newPointer2.startPosition)
            , distanceMoved = coordDiff
                (midPoint newPointer1.position newPointer2.position)
                (midPoint newPointer1.startPosition newPointer2.startPosition)
            }

  ( GotPointerUp _, PointingSingle p ) -> None

  ( GotPointerUp { pointerId }, PointingDouble p ) ->
    let
        pointerToUse = if pointerId == p.pointer1.pointerId then p.pointer2 else p.pointer1
    in
      PointingSingle
        { pointer = pointerToUse
        , distanceMoved = p.distanceMoved
        }

  _ -> state

type PointerMsg
  = GotPointerDown { pointerId: Int, clientCoords: Coord }
  | GotPointerUp { pointerId: Int }
  | GotPointerMove { pointerId: Int, clientCoords: Coord }

onPointerDown : (PointerMsg -> msg) -> Html.Attribute msg
onPointerDown toMsg = on "pointerdown" (D.map toMsg decodePointerDown)

onPointerUp : (PointerMsg -> msg) -> Html.Attribute msg
onPointerUp toMsg = on "pointerup" (D.map toMsg decodePointerUp)

onPointerMove : (PointerMsg -> msg) -> Html.Attribute msg
onPointerMove toMsg = on "pointermove" (D.map toMsg decodePointerMove)

decodePointerDown : D.Decoder PointerMsg
decodePointerDown =
    D.map GotPointerDown decodePointerFields

decodePointerUp : D.Decoder PointerMsg
decodePointerUp =
  D.map (GotPointerUp << \i -> { pointerId = i }) ( D.field "pointerId" D.int )

decodePointerMove : D.Decoder PointerMsg
decodePointerMove =
    D.map GotPointerMove decodePointerFields

decodeCoord : D.Decoder { x : Float, y : Float }
decodeCoord = D.map2 (\x y -> { x = x, y = y })
  ( D.field "clientX" D.float )
  ( D.field "clientY" D.float )

decodePointerFields : D.Decoder { pointerId : Int, clientCoords : { x : Float, y : Float } }
decodePointerFields = D.map2 (\coord id -> { pointerId = id, clientCoords = coord })
  decodeCoord
  ( D.field "pointerId" D.int )
