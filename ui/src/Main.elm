module Main exposing ( main )

import Browser

import Html exposing
  ( Html
  , div
  , text
  , p
  , input
  , label
  , footer
  , button
  , br
  )
import Html.Attributes exposing
  ( type_
  , attribute
  , value
  , for
  , id
  , class
  , attribute
  )

import Svg as S
import Svg.Attributes as S

import Html.Events exposing (on, onClick)
import Json.Decode as D
import Bytes exposing ( Endianness(..) )
import Array exposing (Array)

import MessageFromUI as FromUI
import MessageToUI as ToUI

import ResizeObserver
import Gestures
import FileInfo exposing (FileInfo)

import Screens.FileSelect as FileSelect

main : Program (List String) Model Msg
main =
  Browser.element
  { init = init
  , update = update
  , subscriptions = subscriptions
  , view = view
  }

type Model
  = FileSelectModel FileSelect.Model
  | FileLoaded FileLoadedModel

type alias FileLoadedModel =
  { parameters: PlaybackParameters
  , fileInfo: FileInfo
  , soundwaveDimensions: { height: Float, width: Float }
  , playbackStatus:
    { playingStatus: PlayingStatus
    , progressInSamples: Int
    }
  , gestureState: Gestures.PointerState
  , zoomLevel: Float
  , sampleOffset: Int
  }

initialFileLoadedModel : FileInfo -> FileLoadedModel
initialFileLoadedModel i =
  { parameters = { playbackSpeed = 1, pitchShiftFactor = 1 }
  , fileInfo = i
  , soundwaveDimensions = { height = 0, width = 0 }
  , playbackStatus =
      { playingStatus = Paused
      , progressInSamples = 0
      }
  , gestureState = Gestures.None
  , zoomLevel = 1
  , sampleOffset = 0
  }

type PlayingStatus = Playing | Paused

type alias PlaybackParameters =
  { pitchShiftFactor: Float
  , playbackSpeed: Float
  }


type Msg
  = GotFileSelectMsg FileSelect.Msg
  | ChangedPitchShiftFactor Float
  | ChangedPlaybackSpeed Float
  | ClickedPlay
  | ClickedPause
  | GotPlaybackProgress { progressInSamples: Int }
  | GotResizeEvent { elementId: String, newWidth: Float, newHeight: Float }
  | GotGestureEvent Gestures.PointerMsg
  | GotWheelEvent WheelEvent
  | OccuredError String
  | Irrelevant

initWith : (subModel -> Model) -> (subMsg -> Msg) -> (flags -> ( subModel, subMsg )) -> flags -> ( Model, Cmd Msg )
initWith toModel toMsg initFn flags =
  let
    ( model, cmd ) = initFn flags
  in
    update (toMsg cmd) (toModel model) 

init : ( List String ) -> ( Model, Cmd Msg )
init flags = initWith FileSelectModel GotFileSelectMsg FileSelect.init flags

initLoaded : FileLoadedModel -> ( Model, Cmd Msg )
initLoaded m =
  ( FileLoaded m
  , ResizeObserver.observeElement "sound-wave-container"
  )

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg, model ) of
    ( GotFileSelectMsg (FileSelect.GotFileInfo i) , FileSelectModel _) ->
      initLoaded (initialFileLoadedModel i)

    ( GotFileSelectMsg subMsg, FileSelectModel subModel ) ->
      FileSelect.update subMsg subModel |> updateWith FileSelectModel GotFileSelectMsg model

    ( ChangedPitchShiftFactor p, FileLoaded data ) -> 
      ( FileLoaded
        { data
        | parameters = { pitchShiftFactor = p, playbackSpeed = data.parameters.playbackSpeed }
        }
      , FromUI.send <| FromUI.PitchShiftFactorChanged p
      )

    ( ChangedPlaybackSpeed p, FileLoaded data) ->
      ( FileLoaded
        { data
        | parameters = { playbackSpeed = p, pitchShiftFactor = data.parameters.pitchShiftFactor }
        }
      , FromUI.send <| FromUI.PlaybackSpeedChanged p
      )

    ( ClickedPause, FileLoaded data) ->
      ( FileLoaded
        { data
        | playbackStatus =
            { playingStatus = Paused
            , progressInSamples = data.playbackStatus.progressInSamples
            }
        }
      , FromUI.send <| FromUI.PauseRequested
      )

    ( ClickedPlay, FileLoaded data) ->
      ( FileLoaded
        { data
        | playbackStatus =
            { playingStatus = Playing
            , progressInSamples = data.playbackStatus.progressInSamples
            }
        }
      , FromUI.send <| FromUI.PlayRequested
      )

    ( GotPlaybackProgress { progressInSamples }, FileLoaded data ) ->
      ( FileLoaded
        { data
        | playbackStatus =
            { playingStatus = data.playbackStatus.playingStatus
            , progressInSamples = progressInSamples
            }
        }
      , Cmd.none
      )

    ( GotResizeEvent ev, FileLoaded data ) -> case ev.elementId of
      "sound-wave-container" ->
        ( FileLoaded
          { data
          | soundwaveDimensions = { width = ev.newWidth, height = ev.newHeight }
          }
        , Cmd.none
        )

      _ -> ( model, Cmd.none )

    ( GotGestureEvent e, FileLoaded data ) -> ( FileLoaded <| updateOnGesture e data, Cmd.none )

    ( GotWheelEvent e, FileLoaded data ) -> ( FileLoaded <| updateOnWheel e data, Cmd.none )

    ( OccuredError e, _) -> ( Debug.log e model, Cmd.none ) -- TODO Better error handling?

    (c, m) -> ( Debug.log "UNHANDLED MODEL" m, Debug.log "AND MSG" c |> always Cmd.none )

updateWith : (subModel -> Model) -> (subMsg -> Msg) -> Model -> ( subModel, Cmd subMsg ) -> ( Model, Cmd Msg )
updateWith toModel toMsg model ( subModel, subCmd ) =
    ( toModel subModel
    , Cmd.map toMsg subCmd
    )

subscriptions : Model -> Sub Msg
subscriptions model =
  case model of
    FileSelectModel f -> Sub.map GotFileSelectMsg (FileSelect.subscriptions f)
    _ -> 
      Sub.batch
        [ ToUI.receive <| \m -> case m of
            Ok (ToUI.PlaybackProgress p) -> GotPlaybackProgress
              { progressInSamples = p.progressInSamples }

            Ok _ -> Irrelevant

            Err e                 -> OccuredError e

        , ResizeObserver.resize <| \res -> case res of
            Ok ev -> GotResizeEvent
              { elementId = ev.elementId
              , newWidth = ev.newWidth
              , newHeight = ev.newHeight
              }

            Err e -> OccuredError e
        ]

view : Model -> Html Msg
view model =
  div 
    [ id "app-container"] <| 
    [ contentView model ]
    

contentView : Model -> Html Msg
contentView model = case model of
  FileSelectModel f -> Html.map GotFileSelectMsg <| FileSelect.view f
  FileLoaded m ->  loadedView m 

loadedView : FileLoadedModel -> Html Msg
loadedView m = div []
  [ div [ id "playback-speed-container" ]
    [ label [ for "playback-speed" ]
      [ text "Playback speed" ]
    , sliderView
        { id = "playback-speed"
        , makeMsg = ChangedPlaybackSpeed
        , minValue = 0.3
        , maxValue = 2
        , currentValue = m.parameters.playbackSpeed
        , step = 0.01
        }
    ]
  , div [ id "pitch-shift-factor-container" ]
    [ label [ for "pitch-shift-factor" ]
      [ text "Pitch shift factor" ]
    , sliderView
        { id = "pitch-shift-factor"
        , makeMsg = ChangedPitchShiftFactor
        , minValue = 0.3
        , maxValue = 2
        , currentValue = m.parameters.pitchShiftFactor
        , step = 0.01
        }
    ]
  , soundWaveView m
  , playbackControlsView m
  ]

type alias SliderViewParams msg =
  { id: String
  , makeMsg: (Float -> msg)
  , minValue: Float
  , maxValue: Float
  , currentValue: Float
  , step: Float
  }

sliderView: SliderViewParams Msg -> Html Msg
sliderView params = input
  [ type_ "range"
  , id params.id
  , attribute "min" (String.fromFloat params.minValue)
  , attribute "max" (String.fromFloat params.maxValue)
  , value (String.fromFloat params.currentValue)
  , attribute "step" (String.fromFloat params.step)
  , on "change" (D.map params.makeMsg targetValueFloatDecoder)
  ]
  [ ]

targetValueFloatDecoder : D.Decoder Float
targetValueFloatDecoder =
  let
    decodeFloat fs =
      case String.toFloat fs of
        Just f -> D.succeed f
        Nothing -> D.fail <| ""
  in
    D.at ["target", "value"] D.string |> D.andThen decodeFloat

numSamplesToDisplay : Int
numSamplesToDisplay = 10000 -- Seems to render fast enough, and look OK

type alias DownSampledSamples = Array { originalIndex: Int, value: Float }

downSample : Int -> Array Float -> DownSampledSamples
downSample targetLength arr = Array.initialize targetLength <| \i ->
  let
    stride = floor <| toFloat (Array.length arr) / toFloat targetLength
  in
    { originalIndex = i
    , value = Array.get (i * stride) arr |> Maybe.withDefault 1
    }

type alias SoundWaveParams =
  { dims : (Float, Float)
  , zoomLevel : Float
  , sampleOffset : Int
  , numSamples : Int
  }

soundWaveView : FileLoadedModel -> Html Msg
soundWaveView ({ fileInfo, soundwaveDimensions, playbackStatus } as model) =
  let
    channelData = fileInfo.channelData
    sampleOffset = model.sampleOffset
    zoomLevel = model.zoomLevel
    width = soundwaveDimensions.width
    height = soundwaveDimensions.height
    widthStr = String.fromFloat width
    heightStr = String.fromFloat height
    params : SoundWaveParams
    params =
      { dims = (width, height)
      , zoomLevel = zoomLevel
      , sampleOffset = sampleOffset
      , numSamples = Array.length fileInfo.channelData
      -- , numSamples = numSamplesToDisplay
      }
    stride = round <| (toFloat <| Array.length channelData) / toFloat numSamplesToDisplay
    downSampled = downSample numSamplesToDisplay fileInfo.channelData
    linePoints = samplesToLinePoints params stride downSampled
  in
    div
      [ id "sound-wave-container"
      , Gestures.onPointerDown GotGestureEvent
      , Gestures.onPointerUp GotGestureEvent
      , Gestures.onPointerMove GotGestureEvent
      , on "wheel" (D.map GotWheelEvent wheelDecoder)
      ]
      [ S.svg
        [ S.class "sound-wave-svg"
        , S.width widthStr
        , S.height heightStr
        , S.viewBox <| "0 0 " ++ widthStr ++ " " ++ heightStr
        ]
        [ S.polyline 
          [ S.points <| stringifyLinePoints linePoints
          , S.class "sound-line"
          ]
          [  ]
        ]
      , div
        [ class "progress-indicator"
        , attribute "style" <| "--x-position: " ++
          ( sampleIndexToXCoord params 1 playbackStatus.progressInSamples
          |> String.fromFloat
          |> \s -> s ++ "px;"
          )
        ]
        [ ]
      , text <| "Width: " ++ widthStr ++ ", Height: " ++ heightStr
      , br [] []
      , text <| "Progress: " ++ String.fromFloat (100 * toFloat playbackStatus.progressInSamples / toFloat (Array.length channelData)) ++ " %"
      ]

stringifyLinePoints : Array (Float, Float) -> String
stringifyLinePoints = Array.foldl (\(x, y) acc -> acc ++ (String.fromFloat x) ++ "," ++ (String.fromFloat y) ++ " ") ""

samplesToLinePoints : SoundWaveParams -> Int -> DownSampledSamples -> Array (Float, Float)
samplesToLinePoints params stride arr = Array.map (sampleToLinePoint params stride) arr

sampleToLinePoint : SoundWaveParams -> Int ->  { originalIndex: Int, value: Float } -> (Float, Float)
sampleToLinePoint params stride { originalIndex, value } =
  ( sampleIndexToXCoord params stride originalIndex
  , (Tuple.second params.dims / 2) - value * Tuple.second params.dims
  )

sampleIndexToXCoord : SoundWaveParams -> Int -> Int -> Float
sampleIndexToXCoord { numSamples, dims, zoomLevel, sampleOffset } stride sampleIndex =
  (toFloat (sampleIndex - ceiling (toFloat sampleOffset / toFloat stride)) / toFloat numSamples) * Tuple.first dims * zoomLevel * toFloat stride

-- sampleOffsetToScreenOffset : FileLoadedModel -> Float -> Int -> Float
-- sampleOffsetToScreenOffset model zoomLevel =


screenOffsetToSampleOffset : FileLoadedModel -> Float -> Float -> Int
screenOffsetToSampleOffset model zoomLevel screenOffset =
  round <| ( toFloat model.fileInfo.numSamples  / (model.soundwaveDimensions.width * zoomLevel)  * screenOffset)

updateOnGesture : Gestures.PointerMsg -> FileLoadedModel -> FileLoadedModel
updateOnGesture e ({ zoomLevel, gestureState, sampleOffset, soundwaveDimensions } as model) =
  let
    newGestureState = Gestures.updateState e gestureState
    width = soundwaveDimensions.width
    (deltaX, deltaY) = case newGestureState of
      Gestures.None -> (0, 0)
      Gestures.PointingSingle p -> (p.distanceMoved.x, 0)
      Gestures.PointingDouble p -> (p.distanceMoved.x, p.distanceZoomed)

    newZoomLevel = zoomLevel * ((deltaY - width) / -width)
    xToSamples = screenOffsetToSampleOffset model newZoomLevel 
    deltaSampleOffset = xToSamples (deltaX)
    newSampleOffset = sampleOffset + deltaSampleOffset - round (toFloat (xToSamples (deltaY)) / 2)
    _ = Debug.log "DeltaX" deltaX
  in
    { model
    | zoomLevel = newZoomLevel
    , sampleOffset = newSampleOffset
    , gestureState = newGestureState
    }

updateOnWheel : WheelEvent -> FileLoadedModel -> FileLoadedModel
updateOnWheel e ({zoomLevel, sampleOffset} as model) = 
  let
    width = model.soundwaveDimensions.width
    panSpeed = 2
    newZoomLevel = zoomLevel * ((e.deltaY - width) / -width)
    xToSamples = screenOffsetToSampleOffset model newZoomLevel 
    deltaSampleOffset = xToSamples (e.deltaX * panSpeed)
    newSampleOffset = sampleOffset + deltaSampleOffset - round (toFloat (xToSamples (e.deltaY)) / 2)
  in
    { model
    | zoomLevel = newZoomLevel
    , sampleOffset = newSampleOffset
    }

playbackControlsView : FileLoadedModel -> Html Msg
playbackControlsView { playbackStatus } =
  let
    buttonClickHandler = case playbackStatus.playingStatus of
      Playing -> ClickedPause
      Paused -> ClickedPlay

    -- TODO icons?
    buttonContents = text <| case playbackStatus.playingStatus of
      Playing -> "Pause"
      Paused -> "Play"

  in
    footer
      [ id "playback-controls"
      , class "playback-controls"
      ]
      [ button
        [ onClick buttonClickHandler ]
        [ buttonContents ]
      ]

type alias WheelEvent =
  { deltaX: Float
  , deltaY: Float
  , deltaZ: Float
  }

wheelDecoder : D.Decoder WheelEvent
wheelDecoder = D.map3 (\x y z -> { deltaX = x, deltaY = y, deltaZ = z })
  ( D.field "deltaX" D.float )
  ( D.field "deltaY" D.float )
  ( D.field "deltaZ" D.float )
