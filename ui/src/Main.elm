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

import Canvas as C
import Canvas.Settings as CS
import Canvas.Settings.Line as CL
import Color

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
  , pointerPosition:  { pointerX: Float, pointerY: Float }
  , draggingAction: DraggingAction
  }

type DraggingAction
   = DraggingLimit LimitMarker
   | DraggingNone

type LimitMarker
  = LeftMarker
  | RightMarker

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
  , sampleSelection = { lower = 0, upper = i.numSamples - 1 }
  , pointerPosition = { pointerX = 0, pointerY = 0 }
  , draggingAction = DraggingNone
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
  | GotGestureEvent PointerTarget Gestures.PointerMsg
  | GotWheelEvent WheelEvent
  | GotMouseEvent MouseMsg
  | OccuredError String
  | Irrelevant

type PointerTarget
  = SoundWaveTarget
  | LimitTarget LimitMarker
  | GutterTarget

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
  , ResizeObserver.observeElement "sound-wave-canvas-wrapper"
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
      "sound-wave-canvas-wrapper" ->
        ( FileLoaded
          { data
          | soundwaveDimensions = { width = ev.newWidth, height = ev.newHeight, xOffset = ev.newXOffset }
          }
        , Cmd.none
        )

      _ -> ( model, Cmd.none )

    ( GotGestureEvent t e, FileLoaded data ) -> updateOnGesture t e data |> updateWith FileLoaded identity model

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
  , on "input" (D.map params.makeMsg targetValueFloatDecoder)
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
    ( pointerX, pointerY ) = ( model.pointerPosition.pointerX, model.pointerPosition.pointerY )
    lowerLimitX = absoluteSampleIndexToXCoord model model.sampleSelection.lower
    upperLimitX = absoluteSampleIndexToXCoord model model.sampleSelection.upper
    gutterPointerClass =
      if (abs (pointerX - lowerLimitX) < (abs (pointerX - upperLimitX)))
        then "lower"
        else "upper"
    downSampled = downSample sampleOffset zoomLevel numSamplesToDisplay fileInfo.channelData
    linePoints = samplesToLinePoints model downSampled
  in
    div
      [ id "sound-wave-container"
      , Gestures.onPointerDown <| GotGestureEvent SoundWaveTarget
      , Gestures.onPointerUp <| GotGestureEvent SoundWaveTarget
      , Gestures.onPointerMove <| GotGestureEvent SoundWaveTarget
      , preventDefaultOn "wheel" (D.map (alwaysPrevent << GotWheelEvent) wheelDecoder)
      , on "mousemove" <| D.map (GotMouseEvent << MouseMove) mouseEventDecoder
      ]
      [ div
        [ class <| "gutter top " ++ gutterPointerClass
        , Gestures.onPointerDown <| GotGestureEvent GutterTarget
        ] [ ]
      , div
        [ class <| "gutter bottom " ++ gutterPointerClass
        , Gestures.onPointerDown <| GotGestureEvent GutterTarget
        ] [ ]
      , div [ id "sound-wave-canvas-wrapper" ]
        [ C.toHtml ( round width, round height )
          [ class "sound-wave-canvas"
          , class (if zoomLevel > 1 then "scrollable" else "")
          ]
          [ C.shapes [ CS.fill Color.orange ] [ C.rect ( 0, 0 ) width height ]
          , C.shapes [ CS.fill Color.blue ]
            [ C.rect
              ( absoluteSampleIndexToXCoord model (model.sampleSelection.lower)
              , 0
              )
              ( absoluteSampleIntervalToXInterval model (model.sampleSelection.lower, model.sampleSelection.upper) )
              height
            ]
          , C.shapes
            [ CL.lineWidth 1
            , CS.stroke Color.black
            ]
            [ C.path ( 0, 0 ) 
               ( Array.toList linePoints |> List.map C.lineTo )
            ]
          ]
        ]
      , divAtSamplePosition
          model
          "progress-indicator"
          playbackStatus.progressInSamples
          (playbackStatus.progressInSamples - 1)
          [ ]
      , divAtSamplePosition
          model
          "selection-foreground"
          model.sampleSelection.lower
          model.sampleSelection.upper
          [ div [ class "fill" ] []
          , div
            [ class "marker top left"
            , Gestures.onPointerDown <| GotGestureEvent <| LimitTarget LeftMarker
            ] [ ]
          , div
            [ class "marker bottom left"
            , Gestures.onPointerDown <| GotGestureEvent <| LimitTarget LeftMarker
            ] [ ]
          , div
            [ class "marker top right"
            , Gestures.onPointerDown <| GotGestureEvent <| LimitTarget RightMarker
            ] [ ]
          , div
            [ class "marker bottom right"
            , Gestures.onPointerDown <| GotGestureEvent <| LimitTarget RightMarker
            ] [ ]
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

divAtSamplePosition : FileLoadedModel -> String -> Int -> Int -> List (Html msg) -> Html msg
divAtSamplePosition model className start end =
  let
      startX = absoluteSampleIndexToXCoord model start 
      endX = absoluteSampleIndexToXCoord model end 
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

samplesToLinePoints : FileLoadedModel -> Array Float -> Array (Float, Float)
samplesToLinePoints params arr = Array.indexedMap (sampleToLinePoint params (Array.length arr)) arr

sampleToLinePoint : FileLoadedModel -> Int -> Int -> Float -> (Float, Float)
sampleToLinePoint model sampleLength index value =
  let
    width = model.soundwaveDimensions.width
    height = model.soundwaveDimensions.height
  in
    ( toFloat index * (width / toFloat sampleLength)
    , (height / 2) - value * height
    )

absoluteSampleIndexToXCoord : FileLoadedModel -> Int -> Float
absoluteSampleIndexToXCoord model sampleIndex =
  let
    width = model.soundwaveDimensions.width
    numSamples = model.fileInfo.numSamples
    sampleOffset = model.sampleOffset
    zoomLevel = model.zoomLevel
  in
    (toFloat (sampleIndex - ceiling (toFloat sampleOffset)) / toFloat numSamples) * width * zoomLevel

absoluteSampleIntervalToXInterval : FileLoadedModel -> (Int, Int) -> Float
absoluteSampleIntervalToXInterval model (start, end) =
  let
    startX = absoluteSampleIndexToXCoord model start
    endX = absoluteSampleIndexToXCoord model end
  in endX - startX

screenOffsetToSampleOffset : FileLoadedModel -> Float -> Float -> Int
screenOffsetToSampleOffset model zoomLevel screenOffset =
  round <| ( toFloat model.fileInfo.numSamples  / (model.soundwaveDimensions.width * zoomLevel)  * screenOffset)

calculateNewDisplayParams : FileLoadedModel -> Float -> Float -> Float -> { newZoomLevel: Float, newSampleOffset: Int }
calculateNewDisplayParams model centerPoint deltaX deltaY =
  let
    width = model.soundwaveDimensions.width
    newZoomLevel = max 1 <| model.zoomLevel * ((deltaY - width) / -width)
    xToSamples = screenOffsetToSampleOffset model newZoomLevel
    deltaSampleOffset = xToSamples (deltaX)
    maxSampleOffset = model.fileInfo.numSamples - screenOffsetToSampleOffset model newZoomLevel width
    newSampleOffset = clamp 0 maxSampleOffset <|
      model.sampleOffset + deltaSampleOffset - round (toFloat (xToSamples (deltaY)) * centerPoint)
  in
    { newZoomLevel = newZoomLevel
    , newSampleOffset = newSampleOffset
    }

updateOnGesture : PointerTarget -> Gestures.PointerMsg -> FileLoadedModel -> ( FileLoadedModel, Cmd Msg )
updateOnGesture target e ({ gestureState, draggingAction } as model) =
  let
    newGestureState = Gestures.updateState e gestureState
  in case ( target, draggingAction, newGestureState ) of
    ( _, _, Gestures.None ) ->
      ( { model
        | draggingAction = DraggingNone
        , gestureState = newGestureState
        }
      , Cmd.none
      )
    ( SoundWaveTarget, DraggingNone, _ ) -> 
      let
        width = model.soundwaveDimensions.width
        (deltaX, deltaY, centerPoint) = case newGestureState of
          Gestures.None -> (0, 0, 0.5)
          Gestures.PointingSingle p -> (p.distanceMoved.x, 0, 0.5)
          Gestures.PointingDouble p -> (p.distanceMoved.x, p.distanceZoomed, p.pointerMidPoint.x / width)

        { newZoomLevel, newSampleOffset } = calculateNewDisplayParams model centerPoint deltaX deltaY
      in
        ( { model
          | zoomLevel = newZoomLevel
          , sampleOffset = newSampleOffset
          , gestureState = newGestureState
          }
        , Cmd.none
        )

    ( SoundWaveTarget, DraggingLimit marker, Gestures.PointingSingle p ) ->
      let
        ({ newUpper, newLower } as newLimits) = updateSampleSelectionRelative model marker p.distanceMoved.x
      in
        ( { model
          | draggingAction = DraggingLimit marker
          , sampleSelection = { lower = newLower , upper = newUpper }
          , gestureState = newGestureState
          }
        , FromUI.send <| FromUI.PlaybackLimitsChanged newLimits
        )

    ( LimitTarget marker, DraggingNone, _ ) ->
      ( { model
        | draggingAction = DraggingLimit marker
        , gestureState = newGestureState
        }
      , Cmd.none
      )

    ( GutterTarget, DraggingNone, Gestures.PointingSingle p ) ->
      let
        ( oldLower, oldUpper ) = (model.sampleSelection.lower, model.sampleSelection.upper)
        clickedX = p.pointer.position.x
        clickedSample = screenOffsetToSampleOffset model model.zoomLevel clickedX
        oldLowerPos = absoluteSampleIndexToXCoord model oldLower
        oldUpperPos = absoluteSampleIndexToXCoord model oldUpper
        marker = if (abs (clickedX - oldLowerPos) < abs (clickedX - oldUpperPos))
          then LeftMarker
          else RightMarker

        ({ newUpper, newLower } as newLimits) = updateSampleSelectionAbsolute model marker p.pointer.position.x
      in
        ( { model
          | draggingAction = DraggingLimit marker
          , sampleSelection = { lower = newLower , upper = newUpper }
          , gestureState = newGestureState
          }
        , FromUI.send <| FromUI.PlaybackLimitsChanged newLimits
        )

    ( _, _ , _) -> ( model, Cmd.none )

updateSampleSelectionRelative : FileLoadedModel -> LimitMarker -> Float -> { newLower: Int, newUpper: Int }
updateSampleSelectionRelative model marker distanceMoved =
  let
    samplesMoved = screenOffsetToSampleOffset model model.zoomLevel distanceMoved
    ( oldLower, oldUpper ) = ( model.sampleSelection.lower, model.sampleSelection.upper )
    ( newLower, newUpper ) = case marker of
      LeftMarker -> ( oldLower - samplesMoved, oldUpper )
      RightMarker -> ( oldLower, oldUpper - samplesMoved )
  in
    { newLower = clamp 0 (newUpper - 128) newLower
    , newUpper = clamp (newLower + 128) (model.fileInfo.numSamples - 128) newUpper
    }

updateSampleSelectionAbsolute : FileLoadedModel -> LimitMarker -> Float -> { newLower: Int, newUpper: Int }
updateSampleSelectionAbsolute model marker pos =
  let
    samplePos = screenOffsetToSampleOffset model model.zoomLevel pos
    ( oldLower, oldUpper ) = ( model.sampleSelection.lower, model.sampleSelection.upper )
    ( newLower, newUpper ) = case marker of
      LeftMarker -> ( samplePos + model.sampleOffset, oldUpper )
      RightMarker -> ( oldLower, samplePos + model.sampleOffset )
  in
    { newLower = clamp 0 (newUpper - 128) newLower
    , newUpper = clamp (newLower + 128) (model.fileInfo.numSamples - 128) newUpper
    }

updateOnWheel : WheelEvent -> FileLoadedModel -> FileLoadedModel
updateOnWheel e model = 
  let
    centerPoint = model.pointerPosition.pointerX / model.soundwaveDimensions.width
    { newZoomLevel, newSampleOffset } = calculateNewDisplayParams model centerPoint e.deltaX e.deltaY
  in
    { model
    | zoomLevel = newZoomLevel
    , sampleOffset = newSampleOffset
    }

updateOnMouse : MouseMsg -> FileLoadedModel -> ( FileLoadedModel, Cmd Msg )
updateOnMouse msg model =
  let
    elemXOffset = model.soundwaveDimensions.xOffset
  in case msg of
    MouseMove m ->
      ( { model
        | pointerPosition =
           { pointerX = m.pageX - elemXOffset
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
  , pageX : Float
  , pageY : Float
  }

mouseEventDecoder : D.Decoder MouseEvent
mouseEventDecoder = D.map4 (\x y sx sy -> { offsetX = x, offsetY = y, pageX = sx, pageY = sy })
  ( D.field "offsetX" D.float )
  ( D.field "offsetY" D.float )
  ( D.field "pageX" D.float )
  ( D.field "pageY" D.float )

alwaysPrevent : msg -> ( msg, Bool )
alwaysPrevent msg = ( msg, True )
