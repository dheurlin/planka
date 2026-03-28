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
  )
import Html.Attributes exposing
  ( style
  , type_
  , attribute
  , value
  , for
  , id
  )
import Html.Events exposing (on)
import Json.Decode as D
import Bytes exposing ( Endianness(..) )

import MessageFromUI as FromUI
import MessageToUI as ToUI

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
  | FileLoading FileInfo -- TODO FileInfo needed here?
  | FileLoaded FileLoadedModel

type alias FileInfo =
  { sampleRate: Float, durationInMs: Int, dataURL: String, numSamples: Int }

type alias FileLoadedModel =
  { parameters: PlaybackParameters
  , fileInfo: FileInfo
  , channelData: List Float
  }

type alias PlaybackParameters =
  { pitchShiftFactor: Float
  , playbackSpeed: Float
  }

type Msg
  = SelectedFile (List D.Value)
  | GotFileInfo FileInfo
  | GotFileData (List Float) -- TODO Just one channel for now
  | ChangedPitchShiftFactor Float
  | ChangedPlaybackSpeed Float
  | OccuredError String

init : () -> ( Model, Cmd Msg )
init _ = (FileNotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg, model ) of
    ( SelectedFile (f :: []), _ ) ->
      ( model , FromUI.send <| FromUI.FileChosen f )

    ( SelectedFile _, _ )-> ( model, Cmd.none )

    ( GotFileInfo i, _ ) -> ( FileLoading i , downloadAudioBytes i.dataURL i.numSamples )

    ( GotFileData fs, FileLoading i ) ->
      ( FileLoaded
        { parameters = { playbackSpeed = 1, pitchShiftFactor = 1 }
        , fileInfo = i
        , channelData = fs
        }
      , Cmd.none
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

    ( OccuredError e, _) -> ( Debug.log e model, Cmd.none ) -- TODO Better error handling?

    (c, m) -> ( Debug.log "UNHANDLED MODEL" m, Debug.log "AND MSG" c |> always Cmd.none )

downloadAudioBytes : String -> Int -> Cmd Msg
downloadAudioBytes bytesUrl length =
  let
      makeMsg : Result Http.Error (List Float) -> Msg
      makeMsg r = case r of
        Ok bytes -> GotFileData bytes
        Err m -> OccuredError <| Utils.httpErrorToString m
  in
    Http.get
      { url = bytesUrl
      , expect = Http.expectBytes makeMsg (Utils.floatListDecoder length)
      }

subscriptions : Model -> Sub Msg
subscriptions _ = ToUI.receive <| \m -> case m of
  Ok (ToUI.AudioInfo info) -> GotFileInfo
    { durationInMs = info.durationInMs
    , sampleRate = info.sampleRate
    , dataURL = info.dataURL
    , numSamples = info.numSamples
    }
  Err e                 -> OccuredError e

view : Model -> Html Msg
view model =
  div 
    [ id "app-container"
    , style "background-color" "white" 
    , style "width" "100%"
    , style "padding" "20px 8px"] <| 
    [ ]
    ++ contentView model

contentView : Model -> List (Html Msg)
contentView model = case model of
  FileNotLoaded -> fileSelectView
  FileLoading _  -> [ text "Loading..." ]
  FileLoaded m -> [ loadedView m ]

loadedView : FileLoadedModel -> Html Msg
loadedView { parameters } = div []
  [ div [ id "playback-speed-container" ]
    [ label [ for "playback-speed" ]
      [ text "Playback speed" ]
    , sliderView
        { id = "playback-speed"
        , makeMsg = ChangedPlaybackSpeed
        , minValue = 0.3
        , maxValue = 2
        , currentValue = parameters.playbackSpeed
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
        , currentValue = parameters.pitchShiftFactor
        , step = 0.01
        }
    ]
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

