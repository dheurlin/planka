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
  , zoomingState: ZoomingState
  , panningState: PanningState
  }

type ZoomingState
  = NotZooming { zoomLevel: Float }
  | Zooming { originalZoomLevel: Float, currentZoomLevel: Float }

getZoomLevel : FileLoadedModel -> Float
getZoomLevel { zoomingState } = case zoomingState of
  NotZooming { zoomLevel } -> zoomLevel
  Zooming { currentZoomLevel } -> currentZoomLevel

type PanningState
  = NotPanning { sampleOffset: Int }
  | Panning { originalSampleOffset: Int, currentSampleOffset: Int }

getSampleOffset : FileLoadedModel -> Int
getSampleOffset { panningState } = case panningState of
  NotPanning { sampleOffset } -> sampleOffset
  Panning { currentSampleOffset } -> currentSampleOffset

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
  , zoomingState = NotZooming { zoomLevel = 1 }
  , panningState = NotPanning { sampleOffset = 0 }
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

soundWaveView : FileLoadedModel -> Html Msg
soundWaveView ({ fileInfo, soundwaveDimensions, playbackStatus } as model) =
  let
    channelData = fileInfo.channelData
    sampleOffset = getSampleOffset model
    zoomLevel = getZoomLevel model
    width = soundwaveDimensions.width
    height = soundwaveDimensions.height
    widthStr = String.fromFloat width
    heightStr = String.fromFloat height
    downSamplingStride = toFloat (Array.length channelData) / toFloat numSamplesToDisplay
    samplesToDisplay = Array.initialize numSamplesToDisplay <| \i ->
      Array.get (sampleOffset + (floor <| toFloat i * downSamplingStride / zoomLevel)) channelData |> Maybe.withDefault 0
    linePoints = samplesToLinePoints (width, height) zoomLevel sampleOffset samplesToDisplay
  in
    div
      [ id "sound-wave-container"
      , Gestures.onPointerDown GotGestureEvent
      , Gestures.onPointerUp GotGestureEvent
      , Gestures.onPointerMove GotGestureEvent
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
          ( sampleIndexToXCoord (width, height) zoomLevel sampleOffset (Array.length channelData) playbackStatus.progressInSamples
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

samplesToLinePoints : (Float, Float) -> Float -> Int -> Array Float -> Array (Float, Float)
samplesToLinePoints dims zoomLevel sampleOffset arr = Array.indexedMap (sampleToLinePoint dims zoomLevel sampleOffset (Array.length arr)) arr

sampleToLinePoint : (Float, Float) -> Float -> Int -> Int -> Int -> Float -> (Float, Float)
sampleToLinePoint dims zoomLevel sampleOffset numSamples sampleIndex sample =
  ( sampleIndexToXCoord dims zoomLevel sampleOffset numSamples sampleIndex
  , (Tuple.second dims / 2) + sample * Tuple.second dims -- TODO Should it be minus here? Since 0 is on top
  )

sampleIndexToXCoord : (Float, Float) -> Float -> Int -> Int -> Int -> Float
sampleIndexToXCoord (width, height) zoomLevel sampleOffset numSamples sampleIndex =
  (toFloat (sampleIndex - sampleOffset) / toFloat numSamples) * width * zoomLevel

updateOnGesture : Gestures.PointerMsg -> FileLoadedModel -> FileLoadedModel
updateOnGesture e ({ zoomingState, gestureState, panningState, soundwaveDimensions } as data) =
  let
    newGestureState = Gestures.updateState e gestureState
    width = soundwaveDimensions.width
  in
    case (zoomingState, panningState, newGestureState) of
      ( NotZooming { zoomLevel }, _, Gestures.PointingDouble _ ) ->
        { data
        | zoomingState = Zooming { originalZoomLevel = zoomLevel, currentZoomLevel = zoomLevel }
        , gestureState = newGestureState
        }
      ( Zooming { originalZoomLevel }, _ ,Gestures.PointingDouble p ) ->
        let
            newWidth = width + (p.distanceZoomed)
            newZoomLevel = max 1 <| originalZoomLevel * newWidth / width
        in
          { data
          | zoomingState = Zooming { originalZoomLevel = originalZoomLevel, currentZoomLevel = newZoomLevel }
          , gestureState = newGestureState
          }
      ( Zooming { currentZoomLevel }, _ , _) ->
        { data
        | zoomingState = NotZooming { zoomLevel = currentZoomLevel }
        , gestureState = newGestureState
        }

      ( _, NotPanning { sampleOffset }, Gestures.PointingSingle _) ->
        { data
        | panningState = Panning { originalSampleOffset = sampleOffset, currentSampleOffset = sampleOffset }
        , gestureState = newGestureState
        }

      ( _, Panning { originalSampleOffset }, Gestures.PointingSingle p) ->
        let
          panningSpeed = 1 / 15 -- found experimentally, no idea why this works ¯\_(ツ)_/¯
          samplesMoved = round <| (toFloat data.fileInfo.numSamples / (width * getZoomLevel data)) * p.distanceMoved.x * panningSpeed
        in
          { data
          | panningState = Panning { originalSampleOffset = originalSampleOffset, currentSampleOffset = originalSampleOffset + samplesMoved }
          , gestureState = newGestureState
          }

      ( _, Panning { currentSampleOffset }, Gestures.None) ->
        { data
        | panningState = NotPanning { sampleOffset = currentSampleOffset }
        , gestureState = newGestureState
        }

      _ -> { data | gestureState = newGestureState }

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
