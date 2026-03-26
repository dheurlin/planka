port module Main exposing ( main )

import Browser
import Html exposing (Html)
import Html exposing (div, text, p, input)
import Html.Attributes exposing (style, type_, attribute)
import Html.Events exposing (on)
import File exposing (File)
import Json.Decode as D
import Task

import MessageFromUI as FromUI
import Html.Attributes exposing (value)
import Html.Attributes exposing (id)

port receiveMessage : (String -> msg) -> Sub msg

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
  | FileLoaded {
      parameters: {
        pitchShiftFactor: Float,
        playbackSpeed: Float
      }
    }

type Msg
  = SelectedFile (List File)
  | GotFileURL (String)
  | LoadedFile
  | ChangedPitchShiftFactor Float
  | ChangedPlaybackSpeed Float
  | OccuredError String

init : () -> ( Model, Cmd Msg )
init _ = (FileNotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg, model ) of
    ( SelectedFile (f :: []), _ ) ->
      ( model
      , Task.perform GotFileURL <| File.toUrl f
      )

    ( SelectedFile _, _ )-> (model, Cmd.none)

    ( GotFileURL url, _ ) -> ( model, FromUI.send <| FromUI.FileURLReady url )

    ( LoadedFile, _ ) ->
      ( FileLoaded { parameters = { pitchShiftFactor = 1, playbackSpeed = 1 } }
      , Cmd.none
      )

    ( ChangedPitchShiftFactor p, FileLoaded { parameters } ) -> 
      ( FileLoaded { parameters = { parameters | pitchShiftFactor = p  } }
      , FromUI.send <| FromUI.PitchShiftFactorChanged p
      )

    ( ChangedPlaybackSpeed p, FileLoaded { parameters } ) ->
      ( FileLoaded { parameters = { parameters | playbackSpeed = p } }
      , FromUI.send <| FromUI.PlaybackSpeedChanged p
      )

    ( OccuredError _, _) -> ( model, Cmd.none ) -- TODO Better error handling?

    _ -> ( model, Cmd.none )

subscriptions : Model -> Sub Msg
subscriptions _ = receiveMessage <| \str -> case str of
  "FileLoaded" -> LoadedFile
  _ -> OccuredError <| "Invalid message received: " ++ str

view : Model -> Html Msg
view model =
  div 
    [ style "background-color" "red" 
    , style "width" "100%"
    , style "padding" "20px 0"] <| 
    [ ]
    ++ contentView model

contentView: Model -> List (Html Msg)
contentView model = case model of
  FileNotLoaded -> fileSelectView
  FileLoaded { parameters }->
    [ sliderView
        { id = "playback-speed"
        , makeMsg = ChangedPlaybackSpeed
        , minValue = 0.3
        , maxValue = 2
        , currentValue = parameters.playbackSpeed
        , step = 0.01
        }
    , sliderView
        { id = "pitch-shift-factor"
        , makeMsg = ChangedPitchShiftFactor
        , minValue = 0.3
        , maxValue = 2
        , currentValue = parameters.pitchShiftFactor
        , step = 0.01
        }
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
  , on "change" (D.map params.makeMsg (D.at ["target", "value"] stringFloatDecoder))
  ]
  [ ]

stringFloatDecoder : D.Decoder Float
stringFloatDecoder = D.string |> D.andThen
  ( \val -> case String.toFloat val of
      Just f -> D.succeed f
      Nothing -> D.fail ""
  )

fileSelectView : List (Html Msg)
fileSelectView = 
  [ p [] [ text "No file selected" ]
  , input
      [ type_ "file"
      , on "change" (D.map SelectedFile filesDecoder)
      ] [ ] 
  ]

filesDecoder : D.Decoder (List File)
filesDecoder =
  D.at ["target","files"] (D.list File.decoder)

