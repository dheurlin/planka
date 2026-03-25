module MessageFromUI exposing (..)

import Json.Encode as E

send: (E.Value -> Cmd msg) -> MessageFromUI -> Cmd msg
send sendValue m = encode m |> sendValue

type MessageFromUI
  = SayHello String
  | FileURLReady String
  | PlaybackSpeedChanged Float
  | PitchShiftFactorChanged Float

encode: MessageFromUI -> E.Value
encode msg = case msg of
  SayHello str -> E.object
    [ ( "tag", E.string "SayHello" )
    , ( "message", E.string str )
    ]
  FileURLReady url-> E.object
    [ ( "tag", E.string "FileURLReady" )
    , ( "url", E.string url )
    ]
  PitchShiftFactorChanged p -> E.object 
    [ ( "tag", E.string "PitchShiftFactorChanged" )
    , ( "pitchShiftFactor", E.float p )
    ]
  PlaybackSpeedChanged p -> E.object
    [ ( "tag", E.string "PlaybackSpeedChanged" )
    , ( "playbackSpeed", E.float p )
    ]
