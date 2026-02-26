import std/[algorithm, json, os, sugar, unittest, strutils]

import usu
import usu/json

let officialPath = currentSourcePath().parentDir / "official/cases"

proc collectCases(p: string): seq[string] =
  result = collect:
    for kind, path in walkDir(p):
      if kind == pcDir: path
  sort result


let passing = collectCases(officialPath / "pass")
let failing = collectCases(officialPath / "fail")

suite "official passing":
  for path in passing:
    test path.splitPath().tail:
        check ( % parseUsu(readFile(path / "in.usu"))) == parseFile(path / "out.json")

template checkError(path: string) =
  try:
    discard parseUsu(readFile(path / "in.usu"))
    check false
  except UsuParserError as e:
    var message = readFile(path / "out.msg")
    message.stripLineEnd()
    # \r\n handling makes the pos unstable so ignore it on windows
    when defined(windows):
      check e.msg.split("pos")[0] == message.split("pos")[0]
    else:
      check e.msg == message

suite "official failing":
  for path in failing:
    test path.splitPath().tail:
        checkError(path)


