##[
  # Usu stores usu

  A simple configuration language that places type burden on the file consumer.
]##
import std/[sequtils, sets, strutils]

import usu/parser

proc `$`(usu: UsuNode): string =
  case usu.kind
  of UsuNull:
    result.add "null"
  of UsuArray:
    result.add "["
    for v in usu.elems:
      result.add " " & $v & " "
    result.add "]"
  of UsuValue:
    const quotes = toHashSet(['"', '\'', '`'])
    let
      chars = usu.value.toSeq().toHashSet()
      quoteOptions = quotes - chars
    if quoteOptions.len == 3:
      result.add usu.value
    elif '"' in quoteOptions:
      result.add "\"" & usu.value & "\""
    elif '\'' in quoteOptions:
      result.add "'" & usu.value & "'"
    elif '`' in quoteOptions:
      result.add "`" & usu.value & "`"
    else:
      result.add escape(usu.value)
  of UsuMap:
    result.add "{"
    for k, v in usu.fields:
      result.add "." & k & " " & $v & " "
    result.add "}"

export UsuNode, parseUsu, UsuParserError

func toUsu[T: bool | int | float | string](val: T): UsuNode =
  UsuNode(kind: UsuValue, value: $val)

func toUsu(o: object): UsuNode =
  result = UsuNode(kind: UsuMap)
  for k, v in o.fieldPairs:
    result.fields[k] = toUsu(v)

func toUsu[T](a: openArray[T]): UsuNode =
  var items: seq[UsuNode]
  for item in a:
    items.add toUsu(item)
  result = UsuNode(kind: UsuArray, elems: items)

when isMainModule:
  import std/[json, os]
  import usu/json
  if (commandLineParams().len) != 1:
    stderr.writeLine "expected positional argument for usu file"
    quit 1
  let usuFile = commandLineParams()[0]
  let usuStr = readFile(usuFile)
  echo pretty( %* parseUsu(usuStr))

  echo usuFile
