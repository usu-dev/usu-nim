##[
  # Usu stores usu

  A simple configuration language that places type burden on the file consumer.

  .. include:: ./docs/manual.md
]##

import std/[sequtils, sets, strutils, tables, sugar]
import ./usu/[parser, marshal]

proc hasKeyLikeWord(s: string): bool =
  var prev = '\x00'
  for c in s:
    if c == '.' and prev == ' ':
      return true
    prev = c

proc escapeKey(s: string): string =
  if "." notin s and " " notin s:
    return s
  else:
    return "\"" & s & "\""

proc escapeValue(s: string, prefix = "\"", suffix = "\""): string =
  ## replaces " by \"
  ## adds prefix and suffix
  ## more conservative version of strutils.escape
  result = newStringOfCap(s.len + s.len shr 3)
  result.add(prefix)
  for c in items(s):
    case c
    of '\"': add(result, "\\\"")
    else: add(result, c)
  add(result, suffix)


proc usuValueToStr(usu: UsuNode): string =
  assert usu.kind == UsuValue
  const quotes = toHashSet(['"', '\'', '`'])
  let
    s = usu.value
    chars = s.toSeq().toHashSet()
    quoteOptions = quotes - chars

  if quoteOptions.len == 3 and not s.hasKeyLikeWord:
    return s
  elif '"' in quoteOptions:
    return "\"" & s & "\""
  elif '\'' in quoteOptions:
    return "'" & s & "'"
  elif '`' in quoteOptions:
    return "`" & s & "`"
  else:
    return escapeValue(s)

proc `$`*(usu: UsuNode): string =
  case usu.kind
  of UsuNull:
    result.add "null"
  of UsuArray:
    result.add "["
    result.add collect(
      for v in usu.elems: $v
    ).join(" ")
    result.add "]"
  of UsuValue:
    result = usuValueToStr(usu)
  of UsuMap:
    result.add "{"
    result.add collect(
      for k, v in usu.fields: "." & escapeKey(k) & " " & $v
    ).join(" ")
    result.add "}"

export marshal, parser
