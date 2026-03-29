module Main exposing ( main )

import Browser
import Http

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

import Utils

main : Program () Model Msg
main =
  Browser.element
  { init = init
  , update = update
  , subscriptions = subscriptions
  , view = view
  }

type Model
  = FileNotLoaded
  | FileSelected
  | FileLoading FileInfo -- TODO FileInfo needed here?
  | FileLoaded FileLoadedModel

type alias FileInfo =
  { sampleRate: Float
  , durationInMs: Int
  , reverseSamplesURL: String -- We receive the samples in reverse, so we don't have to reverse a linked list on the elm side
  , numSamples: Int
  }

type alias FileLoadedModel =
  { parameters: PlaybackParameters
  , fileInfo: FileInfo
  , channelData: Array Float
  , soundwaveDimensions: { height: Float, width: Float }
  , displayParams: SoundwaveDisplayParams
  , playbackStatus:
    { playingStatus: PlayingStatus
    , progressInSamples: Int
    }
  }

type PlayingStatus = Playing | Paused

type alias PlaybackParameters =
  { pitchShiftFactor: Float
  , playbackSpeed: Float
  }

type alias SoundwaveDisplayParams =
  { zoomLevel: Float
  , sampleOffset: Int
  }

type Msg
  = SelectedFile (List D.Value)
  | GotFileInfo FileInfo
  | GotFileData (Array Float) -- TODO Just one channel for now
  | ChangedPitchShiftFactor Float
  | ChangedPlaybackSpeed Float
  | ClickedPlay
  | ClickedPause
  | GotPlaybackProgress { progressInSamples: Int }
  | GotResizeEvent { elementId: String, newWidth: Float, newHeight: Float }
  | OccuredError String

init : () -> ( Model, Cmd Msg )
init _ = (FileNotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg, model ) of
    ( SelectedFile (f :: []), _ ) ->
      ( FileSelected , FromUI.send <| FromUI.FileChosen f )

    ( SelectedFile _, _ )-> ( model, Cmd.none )

    ( GotFileInfo i, _ ) -> ( FileLoading i , downloadAudioBytes i.reverseSamplesURL i.numSamples )

    ( GotFileData fs, FileLoading i ) ->
      ( FileLoaded
        { parameters = { playbackSpeed = 1, pitchShiftFactor = 1 }
        , fileInfo = i
        , channelData = fs
        , soundwaveDimensions = { height = 0, width = 0 }
        , displayParams = { sampleOffset = 0, zoomLevel = 1 }
        , playbackStatus = { playingStatus = Paused, progressInSamples = 0 }
        }
      , ResizeObserver.observeElement "sound-wave-container"
      )

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

    ( OccuredError e, _) -> ( Debug.log e model, Cmd.none ) -- TODO Better error handling?

    (c, m) -> ( Debug.log "UNHANDLED MODEL" m, Debug.log "AND MSG" c |> always Cmd.none )

downloadAudioBytes : String -> Int -> Cmd Msg
downloadAudioBytes bytesUrl length =
  let
      makeMsg : Result Http.Error (Array Float) -> Msg
      makeMsg r = case r of
        Ok bytes -> GotFileData bytes
        Err m -> OccuredError <| Utils.httpErrorToString m
  in
    Http.get
      { url = bytesUrl
      , expect = Http.expectBytes makeMsg (Utils.floatArrayReverseDecoder length)
      }

subscriptions : Model -> Sub Msg
subscriptions _ =
  Sub.batch
    [ ToUI.receive <| \m -> case m of
        Ok (ToUI.AudioInfo info) -> GotFileInfo
          { durationInMs = info.durationInMs
          , sampleRate = info.sampleRate
          , reverseSamplesURL = info.reverseSamplesURL
          , numSamples = info.numSamples
          }

        Ok (ToUI.PlaybackProgress p) -> GotPlaybackProgress
          { progressInSamples = p.progressInSamples }

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
    [ ]
    ++ contentView model

contentView : Model -> List (Html Msg)
contentView model = case model of
  FileNotLoaded -> fileSelectView
  FileLoading _  -> [ text "Loading..." ]
  FileSelected   -> [ text "Loading..." ]
  FileLoaded m -> [ loadedView m ]

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
soundWaveView { channelData, soundwaveDimensions, playbackStatus, displayParams } =
  let
    { zoomLevel, sampleOffset } = displayParams
    width = soundwaveDimensions.width
    height = soundwaveDimensions.height
    widthStr = String.fromFloat width
    heightStr = String.fromFloat height
    downSamplingStride = toFloat (Array.length channelData) / toFloat numSamplesToDisplay
    samplesToDisplay = Array.initialize numSamplesToDisplay <| \i ->
      Array.get (sampleOffset + (floor <| toFloat i * downSamplingStride / zoomLevel)) channelData |> Maybe.withDefault 0
    linePoints = samplesToLinePoints (width, height) displayParams samplesToDisplay
  in
    div
      [ id "sound-wave-container" ]
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
      , text <| "Width: " ++ widthStr ++ ", Height: " ++ heightStr
      , br [] []
      , text <| "Progress: " ++ String.fromFloat (100 * toFloat playbackStatus.progressInSamples / toFloat (Array.length channelData)) ++ " %"
      ]

stringifyLinePoints : Array (Float, Float) -> String
stringifyLinePoints = Array.foldl (\(x, y) acc -> acc ++ (String.fromFloat x) ++ "," ++ (String.fromFloat y) ++ " ") ""

samplesToLinePoints : (Float, Float) -> SoundwaveDisplayParams -> Array Float -> Array (Float, Float)
samplesToLinePoints dims p arr = Array.indexedMap (sampleToLinePoint dims p (Array.length arr)) arr

sampleToLinePoint : (Float, Float) -> SoundwaveDisplayParams -> Int -> Int -> Float -> (Float, Float)
sampleToLinePoint (width, height) {zoomLevel, sampleOffset} numSamples sampleIndex sample =
  ( (toFloat (sampleIndex - sampleOffset) / toFloat numSamples) * width * zoomLevel
  , (height / 2) + sample * height -- TODO Should it be minus here? Since 0 is on top
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

fileSelectView : List (Html Msg)
fileSelectView = 
  [ p [] [ text "No file selected" ]
  , input
      [ type_ "file"
      , on "change" (D.map SelectedFile filesDecoder)
      ] [ ] 
  ]

filesDecoder : D.Decoder (List D.Value)
filesDecoder =
  D.at ["target", "files"] (D.list D.value)

