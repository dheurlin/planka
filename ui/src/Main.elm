module Main exposing ( main )

import Browser
import Html exposing (Html)
import Html exposing (div)
import Html.Attributes exposing (style)
import Html exposing (text)
import Html exposing (p)

main : Program () Model Msg
main =
  Browser.element
  { init = init
  , update = update
  , subscriptions = subscriptions
  , view = view
  }


type Model = NotLoaded
type alias Msg = ()

init : () -> ( Model, Cmd Msg )
init _ = (NotLoaded, Cmd.none)

update: Msg -> Model -> (Model, Cmd Msg)
update _ model = (model, Cmd.none)

subscriptions : Model -> Sub ()
subscriptions _ = Sub.none

view : Model -> Html Msg
view model =
  div
    [ style "background-color" "pink" 
    , style "width" "100%"
    , style "padding" "20px 0"]
    [ p []
      [ text "Hello from Elm!" ]
    ]


