module Screens.FileSelect exposing (Model, Msg(..), init, subscriptions, update, view)

import Array exposing (Array)
import Json.Decode as D
import Html exposing
  ( Html
  , text
  , div
  , p
  , input
  )
import Html.Events exposing ( on )
import Html.Attributes exposing
  ( type_
  )
import Http

import FileInfo exposing (FileInfo, FileInfoToDownload)
import MockData.MockSamples as Mock
import Utils
import MessageToUI as ToUI
import MessageFromUI as FromUI

type Model
  = FileNotLoaded
  | FileSelected
  | FileLoading FileInfoToDownload -- TODO FileInfo needed here?
  | FileLoaded

type Msg
  = SelectedFile (List D.Value)
  | GotFileInfoToDownload FileInfoToDownload
  | GotFileInfo FileInfo
  | GotIrrelevant
  | OccuredError String

init : ( List String ) -> ( Model, Msg )
init flags =
  if List.member "UseMockSamples" flags then
    let
      samplesLen = Mock.b64CodedMockSamplesByteLength // 4
      mockSamplesResult = Utils.decodeSamplesB64 Mock.b64CodedMockSamples samplesLen
    in
      case mockSamplesResult of
        Err e -> ( FileNotLoaded, OccuredError <| "Error decoding mock samples: " ++ e )
        Ok arr ->
          let
              fileInfoFull = { durationInMs = 1000 , numSamples = samplesLen , channelData = arr , sampleRate = 48000 }
          in
            ( FileLoaded
            , GotFileInfo fileInfoFull
            )
  else
    ( FileNotLoaded, GotIrrelevant )

subscriptions : Model -> Sub Msg
subscriptions _ = ToUI.receive <| \m -> case m of
  Ok (ToUI.AudioInfo info) -> GotFileInfoToDownload
    { durationInMs = info.durationInMs
    , sampleRate = info.sampleRate
    , reverseSamplesURL = info.reverseSamplesURL
    , numSamples = info.numSamples
    }
  Ok _ -> GotIrrelevant
  Err e -> OccuredError e

update: Msg -> Model -> (Model, Cmd Msg)
update msg model = case ( msg, model ) of
  ( SelectedFile (f :: []), _ ) ->
    ( FileSelected , FromUI.send <| FromUI.FileChosen f )

  ( SelectedFile _, _ )-> ( model, Cmd.none )

  ( GotFileInfoToDownload i, _ ) -> ( FileLoading i , downloadAudioBytes i )

  ( GotFileInfo fs, FileLoading i ) -> ( FileLoaded , Cmd.none )

  ( OccuredError e, _) -> ( Debug.log e model, Cmd.none ) -- TODO Better error handling?

  ( _, _ ) -> ( model, Cmd.none )

downloadAudioBytes : FileInfoToDownload -> Cmd Msg
downloadAudioBytes ({ reverseSamplesURL,  numSamples } as toDownload) =
  let
      makeMsg : Result Http.Error (Array Float) -> Msg
      makeMsg r = case r of
        Ok bytes -> GotFileInfo <| FileInfo.fromFileInfoToDownload toDownload bytes
        Err m -> OccuredError <| Utils.httpErrorToString m
  in
    Http.get
      { url = reverseSamplesURL
      , expect = Http.expectBytes makeMsg (Utils.floatArrayReverseDecoder numSamples)
      }

view : Model -> Html Msg
view model = case model of
  FileNotLoaded -> fileSelectView
  _ -> text "Loading..." 

fileSelectView : Html Msg
fileSelectView = 
  div [ ]
    [ p [ ]
      [ text "No file selected" ]
    , input
        [ type_ "file"
        , on "change" (D.map SelectedFile filesDecoder)
        ] [ ] 
    ]

filesDecoder : D.Decoder (List D.Value)
filesDecoder =
  D.at ["target", "files"] (D.list D.value)
