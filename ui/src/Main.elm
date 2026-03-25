port module Main exposing ( main )

import Browser
import Html exposing (Html)
import Html exposing (div, text, p, button, input)
import Html.Attributes exposing (style, type_)
import Html.Events exposing (onClick, on)
import File exposing (File)
import Json.Decode as D
import Json.Encode as E
import Task

import MessageFromUI as MUI

port sendMessage : E.Value -> Cmd msg
sendFromUI = MUI.send sendMessage

main : Program () Model Msg
main =
  Browser.element
  { init = init
  , update = update
  , subscriptions = subscriptions
  , view = view
  }

type Model = NotLoaded
type Msg
  = SayHello
  | FileSelected (List File)
  | FileURLReady (String)

init : () -> ( Model, Cmd Msg )
init _ = (NotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    SayHello -> ( model, sendFromUI <| MUI.SayHello "Hello from Elm!" )
    FileSelected (f :: []) ->
      ( model
      , Task.perform FileURLReady <| File.toUrl f
      )
    FileSelected _ -> (model, Cmd.none)
    FileURLReady url -> ( model, sendFromUI <| MUI.FileURLReady url )

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none

view : Model -> Html Msg
view model =
  div
    [ style "background-color" "red" 
    , style "width" "100%"
    , style "padding" "20px 0"]
    [ p []
      [ text "Hello from Elm!" ]
    , button [ onClick SayHello ] [ text "Say hello from Elm" ] 
    , input
        [ type_ "file"
        , on "change" (D.map FileSelected filesDecoder)
        ] [ ] 
    ]

filesDecoder : D.Decoder (List File)
filesDecoder =
  D.at ["target","files"] (D.list File.decoder)

