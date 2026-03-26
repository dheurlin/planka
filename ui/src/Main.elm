port module Main exposing ( main )

import Browser
import Html exposing (Html)
import Html exposing (div, text, p, input)
import Html.Attributes exposing (style, type_, attribute)
import Html.Events exposing (on)
import Json.Decode as D

import MessageFromUI as FromUI
import Html.Attributes exposing (value)
import Html.Attributes exposing (id)
import Html exposing (label)
import Html.Attributes exposing (for)

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
  | FileLoaded FileLoadedModel

type alias FileLoadedModel =
  { parameters: 
    { pitchShiftFactor: Float
    , playbackSpeed: Float
    }
  }

type Msg
  = SelectedFile (List D.Value)
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
      ( model , FromUI.send <| FromUI.FileChosen f )

    ( SelectedFile _, _ )-> ( model, Cmd.none )

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
    [ id "app-container"
    , style "background-color" "white" 
    , style "width" "100%"
    , style "padding" "20px 8px"] <| 
    [ ]
    ++ contentView model

contentView : Model -> List (Html Msg)
contentView model = case model of
  FileNotLoaded -> fileSelectView
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

