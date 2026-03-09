##[
  # Usu stores usu

  A simple configuration language that places type burden on the file consumer.

  .. include:: ./docs/manual.md
]##

import std/[sequtils, sets, strutils, tables, sugar]
import ./usu/[parser, marshal]

proc escapeKey(s: string): string =
  if "." notin s and " " notin s:
    return s
  else:
    return "\"" & s & "\""

proc escapeValue(s: string, prefix = "`", suffix = "`"): string =
  ## replaces " by \"
  ## adds prefix and suffix
  ## more conservative version of strutils.escape
  result = newStringOfCap(s.len + s.len shr 3)
  result.add(prefix)
  for c in items(s):
    case c
    of '`': add(result, "\\`")
    # of '\"': add(result, "\\\"")
    of '\n': add(result, "\\n")
    else: add(result, c)
  add(result, suffix)

proc hasKeyLikeWord(s: string): bool =
   var prev = '\x00'
   for c in s:
     if c == '.' and prev == ' ':
       return true
     prev = c

#[

# BUG: this proc is insufficient if string has newlines
proc usuValueToStr(usu: UsuNode): string =
  assert usu.kind == UsuValue
  const quotes = toHashSet(['"', '\'', '`'])
  let
    s = usu.value
    chars = s.toSeq().toHashSet()
    quoteSettings = quotes - chars

  if quoteSettings.len == 3 and not s.hasKeyLikeWord:
    return s
  elif '"' in quoteSettings:
    return "\"" & s & "\""
  elif '\'' in quoteSettings:
    return "'" & s & "'"
  elif '`' in quoteSettings:
    return "`" & s & "`"
  else:
    return escapeValue(s)
]#

proc valueToStr(usu: UsuNode): string =
  assert usu.kind == UsuValue
  let chars = usu.value.toSeq().toHashSet()
  if len([' ', '\n'].toHashSet() * chars) > 0 :
    return escapeValue(usu.value)
  else:
    return usu.value


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
    result = valueToStr(usu)
  of UsuMap:
    result.add "{"
    result.add collect(
      for k, v in usu.fields: "." & escapeKey(k) & " " & $v
    ).join(" ")
    result.add "}"

export marshal, parser

import std/wordwrap

proc hasSyntax(s: string): bool =
  for c in s:
    case c
    of '{', '[','}',']': return true
    else: discard

type PathPair* = tuple[path: string, value: UsuNode]

proc toPathPairs(u: UsuNode, parent: string): seq[PathPair] =
  case u.kind
  of UsuValue, UsuNull:
    result.add (parent, u)
  of UsuArray:
    for i, e in u.elems:
      let parent = parent & "[" & $i & "]"
      for (k, v) in e.toPathPairs(parent):
        result.add (k, v)
  of UsuMap:
    for k, v in u.fields:
      let path = parent & "." & k
      for (k, v) in v.toPathPairs(path):
        result.add (k, v)

proc toPathPairs(u: UsuNode): seq[PathPair] =
  checkKind u, UsuMap
  for k, v in u.fields:
    for (k, v) in v.toPathPairs(k):
      result.add (k, v)

iterator flatten*(u: UsuNode): PathPair =
  ## iterate over path (full key path + index, as string) and value nodes
  for (k, v) in toPathPairs(u):
    yield (k, v)

type
  UsuPrettySettings* = enum
    RootBrackets ## place brackets around root map
    NoWrap       ## don't word wrap long strings (>100 char)
    Flatten      ## remove all nesting and produce only key, value pairs
    QuoteValues  ## output escaped strings for any UsuValue

proc prettyValueToStr(usu: UsuNode, count: Natural, settings:set[UsuPrettySettings]): string =
  assert usu.kind == UsuValue
  let v = usu.value
  if v[0] in {'\'', '"', '`'} or hasKeyLikeWord(v) or hasSyntax(v):
    return escapeValue(usu.value)
  if v[^1] == '\n': # last newline will be added back by pretty when used as a key/val pair
    return '\n' & indent(v.strip(), count)
  elif '\n' in v:
    # TODO: keep the newline nature of the string? but enclose with '\`'
    return escapeValue(v)
  elif NoWrap notin settings and v.len > 100:
    return ">" & "\n" & indent(wrapWords(v, splitLongWords = false),count)
  else:
    return v

proc prettyImpl(
  u: UsuNode,
  indent: Natural = 0,
  settings: set[UsuPrettySettings] = {},
  inline: (u: UsuNode) -> bool = (_: UsuNode) => false
): string =
  if inline(u): return $u
  case u.kind:
  of UsuNull:
    result = "null"
  of UsuMap:
    var kvInd: int = indent
    let childSettings = settings + {RootBrackets} # always use brackets for children
    if RootBrackets in settings:
      kvInd += 2
      result.add "{\n"
    if Flatten in settings:
      for k, v in u.flatten:
        result.add ' '.repeat(kvInd)
        result.add '.' & k & ' '
        result.add prettyImpl(v, kvInd, childSettings, inline)
        result.add '\n'
    else:
      for k, v in u.fields:
        result.add ' '.repeat(kvInd)
        result.add '.' & k & ' '
        result.add prettyImpl(v, kvInd, childSettings, inline)
        result.add '\n'
    if RootBrackets in settings:
      result.add ' '.repeat(indent)
      result.add '}'
    else:
      result.setLen(result.len - 1) # workaround to remove last '\n' on maps
  of UsuArray:
    result.add "[\n"
    for v in u.elems:
      result.add ' '.repeat(indent + 2) & prettyImpl(v, indent + 2, settings, inline)
      result.add '\n'
    result.add ' '.repeat(indent)
    result.add ']'
  of UsuValue:
    if QuoteValues in settings:
      result = escapeValue(u.value)
    else:
      result = prettyValueToStr(u, indent + 2, settings)

proc pretty*(
  u: UsuNode,
  inline: proc(u: UsuNode): bool {.closure.},
  settings: set[UsuPrettySettings] = {},
): string =
  ## multiline representation of usu
  ##
  ## `inline` will be called on all children objects and should return true to apply `$` to the node.
  ##
  ## Note: experimental, output may change in future versions
  prettyImpl(u, indent = 0, settings = settings, inline = inline)

proc pretty*(
  u: UsuNode,
  settings: set[UsuPrettySettings] = {},
): string =
  prettyImpl(u, settings = settings)
