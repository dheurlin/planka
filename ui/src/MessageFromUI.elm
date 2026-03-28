port module MessageFromUI exposing (..)

import Json.Encode as E

port sendMessage : E.Value -> Cmd msg

send: MessageFromUI -> Cmd msg
send = encode >> sendMessage

type MessageFromUI
  = FileChosen E.Value
  | PlaybackSpeedChanged Float
  | PitchShiftFactorChanged Float
  | PauseRequested
  | PlayRequested

encode: MessageFromUI -> E.Value
encode msg = case msg of
  FileChosen f -> E.object
    [ ( "tag", E.string "FileChosen" )
    , ( "fileRef", f )
    ]

  PitchShiftFactorChanged p -> E.object 
    [ ( "tag", E.string "PitchShiftFactorChanged" )
    , ( "pitchShiftFactor", E.float p )
    ]

  PlaybackSpeedChanged p -> E.object
    [ ( "tag", E.string "PlaybackSpeedChanged" )
    , ( "playbackSpeed", E.float p )
    ]

  PauseRequested -> E.object
    [ ( "tag", E.string "PauseRequested" ) ]

  PlayRequested -> E.object
    [ ( "tag", E.string "PlayRequested" ) ]
