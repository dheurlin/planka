module Main exposing ( main )

import Browser

import Html exposing
  ( Html
  , div
  , text
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

import Html.Events exposing (on, preventDefaultOn, onClick)
import Json.Decode as D
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
  , soundwaveDimensions: { height: Float, width: Float, xOffset: Float }
  , playbackStatus:
    { playingStatus: PlayingStatus
    , progressInSamples: Int
    }
  , gestureState: Gestures.PointerState
  , zoomLevel: Float
  , sampleOffset: Int
  , sampleSelection: { lower: Int, upper: Int }
  , mouseState: MouseState
  }

type MouseState
  = JustMovingMouse { pointerX: Float, pointerY: Float }

initialFileLoadedModel : FileInfo -> FileLoadedModel
initialFileLoadedModel i =
  { parameters = { playbackSpeed = 1, pitchShiftFactor = 1 }
  , fileInfo = i
  , soundwaveDimensions = { height = 0, width = 0, xOffset = 0 }
  , playbackStatus =
      { playingStatus = Paused
      , progressInSamples = 0
      }
  , gestureState = Gestures.None
  , zoomLevel = 1
  , sampleOffset = 0
  , sampleSelection = { lower = 40000, upper = i.numSamples - 70000 }
  , mouseState = JustMovingMouse { pointerX = 0, pointerY = 0 }
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
  | GotResizeEvent { elementId: String, newWidth: Float, newHeight: Float, newXOffset: Float }
  | GotGestureEvent Gestures.PointerMsg
  | GotWheelEvent WheelEvent
  | GotMouseEvent MouseMsg
  | OccuredError String
  | Irrelevant

type MouseMsg
  = MouseMove MouseEvent

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
  , ResizeObserver.observeElement "sound-wave-svg-wrapper"
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
      "sound-wave-svg-wrapper" ->
        ( FileLoaded
          { data
          | soundwaveDimensions = { width = ev.newWidth, height = ev.newHeight, xOffset = ev.newXOffset }
          }
        , Cmd.none
        )

      _ -> ( model, Cmd.none )

    ( GotGestureEvent e, FileLoaded data ) -> ( FileLoaded <| updateOnGesture e data, Cmd.none )

    ( GotWheelEvent e, FileLoaded data ) -> ( FileLoaded <| updateOnWheel e data, Cmd.none )

    ( GotMouseEvent e, FileLoaded data ) -> updateOnMouse e data |> updateWith FileLoaded identity model

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
              , newXOffset = ev.newXOffset
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

downSample : Int -> Float -> Int -> Array Float -> Array Float
downSample sampleOffset zoomLevel targetLength arr =
  let
    lower = sampleOffset
    numSamplesFromSrc = (toFloat (Array.length arr) / zoomLevel)
    stride = numSamplesFromSrc / toFloat targetLength
    indicesToPick = List.range 0 (targetLength - 1) |> List.map (\i -> round <| toFloat i * stride + toFloat lower)
    values = List.map (\i -> Array.get i arr |> Maybe.withDefault 1) indicesToPick
  in
    Array.fromList values

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
    ( pointerX, pointerY ) = case model.mouseState of
      JustMovingMouse m -> ( m.pointerX, m.pointerY )
    params : SoundWaveParams
    params =
      { dims = (width, height)
      , zoomLevel = zoomLevel
      , sampleOffset = sampleOffset
      , numSamples = Array.length fileInfo.channelData
      }
    downSampled = downSample sampleOffset zoomLevel numSamplesToDisplay fileInfo.channelData
    linePoints = samplesToLinePoints params downSampled
  in
    div
      [ id "sound-wave-container"
      , Gestures.onPointerDown GotGestureEvent
      , Gestures.onPointerUp GotGestureEvent
      , Gestures.onPointerMove GotGestureEvent
      , preventDefaultOn "wheel" (D.map (alwaysPrevent << GotWheelEvent) wheelDecoder)
      , on "mousemove" <| D.map (GotMouseEvent << MouseMove) mouseEventDecoder
      ]
      [ div [ id "sound-wave-svg-wrapper" ]
        [ S.svg
          [ S.class "sound-wave-svg"
          , S.class <| if zoomLevel > 1 then "scrollable" else ""
          , S.width widthStr
          , S.height heightStr
          , S.viewBox <| "0 0 " ++ widthStr ++ " " ++ heightStr
          ]
          [ S.rect
            [ S.class "svg-background"
            , S.x "0"
            , S.y "0"
            , S.width widthStr
            , S.height heightStr
            ]
            [ ]
          , S.rect
            [ S.class "selection-background"
            , S.height heightStr
            , S.width
                ( absoluteSampleIntervalToXInterval params (model.sampleSelection.lower, model.sampleSelection.upper)
                |> String.fromFloat
                ) 
            , S.y "0"
            , S.x
                ( absoluteSampleIndexToXCoord params (model.sampleSelection.lower)
                |> String.fromFloat
                )
            ]
            [ ]
          , S.polyline 
            [ S.points <| stringifyLinePoints linePoints
            , S.class "sound-line"
            ]
            [  ]
          ]
        ]
      , divAtSamplePosition
          params
          "progress-indicator"
          playbackStatus.progressInSamples
          (playbackStatus.progressInSamples - 1)
          [ ]
      , divAtSamplePosition
          params
          "selection-foreground"
          model.sampleSelection.lower
          model.sampleSelection.upper
          [ div [ class "fill" ] []
          , div [ class "marker left" ] [ ]
          , div [ class "marker right" ] [ ]
          ]
      , div
        [ class "debug-stuff" ]
        [ text <| "Width: " ++ widthStr ++ ", Height: " ++ heightStr
        , br [] []
        , text <| "Progress: " ++ String.fromFloat (100 * toFloat playbackStatus.progressInSamples / toFloat (Array.length channelData)) ++ " %"
        , br [] []
        , text <| "Pointer: (" ++ String.fromFloat pointerX ++ ", " ++ String.fromFloat pointerY ++ ")"
        ]
      ]

divAtSamplePosition : SoundWaveParams -> String -> Int -> Int -> List (Html msg) -> Html msg
divAtSamplePosition params className start end =
  let
      startX = absoluteSampleIndexToXCoord params start 
      endX = absoluteSampleIndexToXCoord params end 
  in
    div
      [ class className
      , attribute "style" <| String.concat
        [ "--x-position:"
        , startX |> String.fromFloat
        , "px;"
        , "--width:"
        , endX - startX |> String.fromFloat
        , "px;"
        ]
      ]

stringifyLinePoints : Array (Float, Float) -> String
stringifyLinePoints = Array.foldl (\(x, y) acc -> acc ++ (String.fromFloat x) ++ "," ++ (String.fromFloat y) ++ " ") ""

samplesToLinePoints : SoundWaveParams -> Array Float -> Array (Float, Float)
samplesToLinePoints params arr = Array.indexedMap (sampleToLinePoint params (Array.length arr)) arr

sampleToLinePoint : SoundWaveParams -> Int -> Int -> Float -> (Float, Float)
sampleToLinePoint { dims } sampleLength index value =
  ( toFloat index * (Tuple.first dims / toFloat sampleLength)
  , (Tuple.second dims / 2) - value * Tuple.second dims
  )

absoluteSampleIndexToXCoord : SoundWaveParams -> Int -> Float
absoluteSampleIndexToXCoord { numSamples, dims, zoomLevel, sampleOffset } sampleIndex =
  (toFloat (sampleIndex - ceiling (toFloat sampleOffset)) / toFloat numSamples) * Tuple.first dims * zoomLevel

absoluteSampleIntervalToXInterval : SoundWaveParams -> (Int, Int) -> Float
absoluteSampleIntervalToXInterval params (start, end) =
  let
    startX = absoluteSampleIndexToXCoord params start
    endX = absoluteSampleIndexToXCoord params end
  in endX - startX

screenOffsetToSampleOffset : FileLoadedModel -> Float -> Float -> Int
screenOffsetToSampleOffset model zoomLevel screenOffset =
  round <| ( toFloat model.fileInfo.numSamples  / (model.soundwaveDimensions.width * zoomLevel)  * screenOffset)

calculateNewDisplayParams : FileLoadedModel -> Float -> Float -> { newZoomLevel: Float, newSampleOffset: Int }
calculateNewDisplayParams model deltaX deltaY =
  let
    width = model.soundwaveDimensions.width
    newZoomLevel = max 1 <| model.zoomLevel * ((deltaY - width) / -width)
    xToSamples = screenOffsetToSampleOffset model newZoomLevel
    deltaSampleOffset = xToSamples (deltaX)
    maxSampleOffset = model.fileInfo.numSamples - screenOffsetToSampleOffset model newZoomLevel width
    newSampleOffset = clamp 0 maxSampleOffset <|
      model.sampleOffset + deltaSampleOffset - round (toFloat (xToSamples (deltaY)) / 2)
  in
    { newZoomLevel = newZoomLevel
    , newSampleOffset = newSampleOffset
    }

updateOnGesture : Gestures.PointerMsg -> FileLoadedModel -> FileLoadedModel
updateOnGesture e ({ gestureState } as model) =
  let
    newGestureState = Gestures.updateState e gestureState
    (deltaX, deltaY) = case newGestureState of
      Gestures.None -> (0, 0)
      Gestures.PointingSingle p -> (p.distanceMoved.x, 0)
      Gestures.PointingDouble p -> (p.distanceMoved.x, p.distanceZoomed)

    { newZoomLevel, newSampleOffset } = calculateNewDisplayParams model deltaX deltaY
  in
    { model
    | zoomLevel = newZoomLevel
    , sampleOffset = newSampleOffset
    , gestureState = newGestureState
    }

updateOnWheel : WheelEvent -> FileLoadedModel -> FileLoadedModel
updateOnWheel e model = 
  let
    { newZoomLevel, newSampleOffset } = calculateNewDisplayParams model e.deltaX e.deltaY
  in
    { model
    | zoomLevel = newZoomLevel
    , sampleOffset = newSampleOffset
    }

updateOnMouse : MouseMsg -> FileLoadedModel -> ( FileLoadedModel, Cmd Msg )
updateOnMouse e model =
  let
    elemXOffset = model.soundwaveDimensions.xOffset
  in case (e, model.mouseState) of
    (MouseMove m, JustMovingMouse _) ->
      ( { model
        | mouseState = JustMovingMouse
          { pointerX = m.screenX - elemXOffset
          , pointerY = m.offsetY }
        }
      , Cmd.none
      )

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

type alias MouseEvent =
  { offsetX : Float
  , offsetY : Float
  , screenX : Float
  , screenY : Float
  }

mouseEventDecoder : D.Decoder MouseEvent
mouseEventDecoder = D.map4 (\x y sx sy -> { offsetX = x, offsetY = y, screenX = sx, screenY = sy })
  ( D.field "offsetX" D.float )
  ( D.field "offsetY" D.float )
  ( D.field "screenX" D.float )
  ( D.field "screenY" D.float )

alwaysPrevent : msg -> ( msg, Bool )
alwaysPrevent msg = ( msg, True )
