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
  = SayHello
  | FileSelected (List File)
  | FileURLReady (String)
  -- Maybe add Model as first arg here?
  | PitchShiftFactorChanged Float
  | PlaybackSpeedChanged Float
  | FileFinishedLoading
  | ErrorOccured String

init : () -> ( Model, Cmd Msg )
init _ = (FileNotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SayHello -> ( model, FromUI.send <| FromUI.SayHello "Hello from Elm!" )

    FileSelected (f :: []) ->
      ( model
      , Task.perform FileURLReady <| File.toUrl f
      )

    FileSelected _ -> (model, Cmd.none)

    FileURLReady url -> ( model, FromUI.send <| FromUI.FileURLReady url )

    -- TODO How to avoid N x M issue here with Msg and Model??
    PitchShiftFactorChanged p -> 
      case model of
        FileLoaded { parameters } ->
          ( FileLoaded { parameters = { parameters | pitchShiftFactor = p  } }
          , FromUI.send <| FromUI.PitchShiftFactorChanged p
          )
        _ -> (model, Cmd.none)

    PlaybackSpeedChanged p ->
      case model of
        FileLoaded { parameters } -> 
          ( FileLoaded { parameters = { parameters | playbackSpeed = p } }
          , FromUI.send <| FromUI.PlaybackSpeedChanged p
          )
        _ -> (model, Cmd.none)

    FileFinishedLoading ->
      ( FileLoaded { parameters = { pitchShiftFactor = 1, playbackSpeed = 1 } }
      , Cmd.none
      )
    ErrorOccured _ -> ( model, Cmd.none ) -- TODO Better error handling?

subscriptions : Model -> Sub Msg
subscriptions _ = receiveMessage <| \str -> case str of
  "FileLoaded" -> FileFinishedLoading
  _ -> ErrorOccured <| "Invalid message received: " ++ str

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
    [ sliderView "playback-speed" PlaybackSpeedChanged 0.3 2 parameters.playbackSpeed 0.01
    , sliderView "pitch-shift" PitchShiftFactorChanged 0.3 2 parameters.pitchShiftFactor 0.01
    ]

-- TODO named params
sliderView: String -> (Float -> Msg) -> Float -> Float -> Float -> Float -> Html Msg
sliderView theId msg minVal maxVal startVal step = input
  [ type_ "range"
  , id theId
  , attribute "min" (String.fromFloat minVal)
  , attribute "max" (String.fromFloat maxVal)
  , value (String.fromFloat startVal)
  , attribute "step" (String.fromFloat step)
  , on "change" (D.map msg (D.at ["target", "value"] stringFloatDecoder))
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
      , on "change" (D.map FileSelected filesDecoder)
      ] [ ] 
  ]

filesDecoder : D.Decoder (List File)
filesDecoder =
  D.at ["target","files"] (D.list File.decoder)

