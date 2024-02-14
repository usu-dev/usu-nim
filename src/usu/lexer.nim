import std/strutils

const whitespaces = {' ', '\t', '\v', '\r', '\l', '\f'}
const quotes = {'"', '\'', '`'}
const syntax = {'(', ')', ':', '>', '#'}

type
  TokenKind* = enum
    tokLPar, tokRPar,
    tokKey, tokString,
    tokEnd
  Token* = object
    case kind*: TokenKind
    of tokString: stringVal*: string
    of tokKey: keyVal*: string
    else: discard
  LexerMode = enum
    Chomp, ChompNewlines, InlineString, RespectNewlines

proc skip(startPos: int, input: string, modes: set[LexerMode],
    chars = whitespaces + {'\n', '\r'}): int =
  var pos = startPos
  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'
  while current in chars:
    inc pos
  result =
    if (current notin syntax + quotes) and (InlineString notin modes):
      startPos
    else:
      pos

proc skipComment(pos: var int, input: string) =
  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'
  template next: char =
    if pos+1 < input.len: input[pos+1]
    else: '\x00'
  inc(pos)
  if current == '(':
    inc pos
    while current & next != ")#": inc pos
    inc pos
  else:
    while current notin {'\r', '\n'}:
      inc pos
    inc pos

# TODO: support more escape sequences
proc subEscapeSeqs(s: string): string = 
  result = replace(s, "\\n", "\n")


proc lexUnquoted(pos: var int, input: string, tokens: var seq[Token],
    modes: var set[LexerMode]) =
  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'

  var str = ""
  let strEnd = {':', ')'} + (
    if InlineString in modes: {' ', '\n'}
    elif tokens[^1].kind == tokKey: {'\x00'}
    else: {'\n'}
  )
  while current notin strEnd:
    if current == '#':
      # remove any trailing whitespace before comment
      str = strip(str, leading = false)
      skipComment(pos, input)
    else:
      str.add(current)
    inc pos
  str =
    if InlineString in modes: strip(str)
    else: dedent(str)
  str = strip(str, chars = whitespaces + {'\n', '\r'})
  str = subEscapeSeqs(str)
  if RespectNewlines in modes: str.add '\n'
  if ChompNewLines in modes: str = str.splitLines().join(" ")
  tokens.add Token(kind: tokString, stringVal: str)
  modes.excl {RespectNewlines, ChompNewlines}

proc debugUsu(pos: int, input: string, modes: set[LexerMode]) =
  for i, c in input:
    if pos == i:
      stdout.write("!>>>>")
      stdout.write(c)
      stdout.write("<<<<!")
    else:
      stdout.write(c)
  stdout.write("\n^^^^" & $modes & "^^^^^\n")

proc lex*(input: string): seq[Token] =
  var pos = 0
  var level = 0
  var modes: set[LexerMode]

  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'

  template next: char =
    if pos+1 < input.len: input[pos+1]
    else: '\x00'

  while pos < input.len:
    pos = skip(pos, input, modes)
    when defined(debug):
      debugUsu(pos,input, modes)
    case current
    of '#':
      skipComment(pos, input)
    of '(':
      inc pos
      if current notin {'\n', '\r'}:
        modes.incl InlineString
      result.add(Token(kind: tokLPar))
      inc level
    of ')':
      inc pos
      result.add(Token(kind: tokRPar))
      dec level
      modes.excl InlineString
    of '\n', '\r': inc pos
    of ':':
      var key = ""
      inc pos
      while current notin {'\r', '\n', ' ', ')'}:
        key.add(current)
        inc pos
      result.add(
        Token(kind: tokKey, keyVal: key)
      )
      if current == '\n':
        modes.incl RespectNewlines
      elif current & next == " >":
        modes.incl ChompNewLines
        inc pos, 2
    of '>':
      # modes.incl Chomp
      # BUG: is the fact that I skip a newline enough to initiate this somehow?
      # it would then be turning on the "InlineString" lexing
      inc pos
    of '"', '\'', '`':
      let quote = current
      var str = ""
      inc(pos)
      while current != quote:
        str.add(current)
        inc(pos)
      inc(pos)
      result.add(Token(kind: tokString, stringVal: subEscapeSeqs(str)))
    else:
      lexUnquoted(pos, input, result, modes)

  if result[0].kind == tokKey:
    result = @[Token(kind: tokLPar)] & result & @[Token(kind: tokRPar)]
  result.add(Token(kind: tokEnd))

when isMainModule:
  const input = """
(:key >
  "A folded list"
  newlines `don't` matter
  all items are "one item"
)
"""
  echo lex(input)

