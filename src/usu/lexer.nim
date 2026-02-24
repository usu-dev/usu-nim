import std/strutils

const whitespaces = {' ', '\t', '\v', '\f', '\r'}
const quotes = {'"', '\'', '`'}
const syntax = {'{', '}','[',']','.', '>', '#'} # change

# should i have an UsuParser object?
type
  TokenKind* = enum
    tokLCurly, tokRCurly,
    tokLBracket, tokRBracket
    tokKey, tokString,
    tokEnd
  Token* = object
    pos*: int ## start position of the token
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
  result = multiReplace(
    s, {
        "\\n": "\n",
        "\\t": "\t",
        "\\\\": "\\"
      }
  )

proc lexUnquoted(
  pos: var int,
  input: string,
  tokens: var seq[Token],
  modes: var set[LexerMode]
) =
  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'
  template prev: char =
    if pos - 1 > 0: input[pos - 1]
    else: '\x00'
  template next: char =
    if pos + 1 < input.len: input[pos + 1]
    else: '\x00'
  template keystart: bool =
    current == '.' and prev in {' ', '\n', '\r'}
  template eof: bool = current == '\x00'

  var str = ""

  let strEnd = {'}',']', '[', '{'} + (
    if InlineString in modes and tokens[^1].kind != tokKey: {' ', '\n'}
    elif tokens.len > 0 and tokens[^1].kind == tokKey: {'\x00'}
    else: {'\n'}
  )
  let start = pos
  while true:
    if current == '#':
      # remove any trailing whitespace before comment
      str = strip(str, leading = false)
      skipComment(pos, input)
      if current == '.': break
    else:
      str.add(current)
    inc pos
    if keystart or (current in strEnd) or eof: break
 
  str =
    if InlineString in modes: strip(str)
    else: dedent(str)
  str = strip(str, chars = whitespaces + (if RespectNewlines notin modes: {'\n', '\r'} else: {}))
  str = subEscapeSeqs(str)
  if ChompNewLines in modes: str = str.splitLines().join(" ")
  tokens.add Token(pos: start, kind: tokString, stringVal: str)
  modes.excl {RespectNewlines, ChompNewlines}

when defined(debugUsu):
  proc debugUsu(pos: int, input: string, modes: set[LexerMode]) =
    for i, c in input:
      if pos == i:
        stdout.write("!>>>>")
        stdout.write(c)
        stdout.write("<<<<!")
      else:
        stdout.write(c)
    stdout.write("\n^^^^" & $modes & "^^^^^\n")

func fromChar(c: char, pos: int): Token =
  # parseEnum?
  let kind = case c
    of '[': tokLBracket
    of ']': tokRBracket
    of '{': tokLCurly
    of '}': tokRCurly
    else: raise newException(ValueError, "failed to lex token, unexpected char: " & $c)
  result = Token(pos: pos, kind: kind)


proc lex*(input: string): seq[Token] =
  var pos = 0
  var modes: set[LexerMode]

  template current: char =
    if pos < input.len: input[pos]
    else: '\x00'

  template next: char =
    if pos+1 < input.len: input[pos+1]
    else: '\x00'

  while pos < input.len:
    pos = skip(pos, input, modes)
    when defined(debugUsu):
      debugUsu(pos, input, modes)
    case current
    of '#':
      skipComment(pos, input)
    of '{', '[':
      result.add fromChar(current, pos)
      inc pos
      if current notin {'\n', '\r'}:
        modes.incl InlineString
    of '}', ']':
      result.add fromChar(current, pos)
      inc pos
      modes.excl InlineString
    of '\n', '\r': inc pos
    of '.': #TODO: lexKey proc
      var key = ""
      let start = pos
      inc pos
      if current in quotes:
        let q = current
        inc pos
        while current != q:
          # we need to escape periods to prevent path splitting in parser
          if current == '.':
            key.add '\\'
          key.add(current)
          inc pos
        inc pos
      else:
        while current notin {'\r', '\n', ' ', '}'}:
          key.add(current)
          inc pos
      result.add(
        Token(pos: start, kind: tokKey, keyVal: key)
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
      let start = pos
      inc(pos)
      while current != quote:
        str.add(current)
        inc(pos)
      inc(pos)
      result.add(Token(pos: start, kind: tokString, stringVal: subEscapeSeqs(str)))
    else:
      lexUnquoted(pos, input, result, modes)

  if result[0].kind == tokKey:
    result = @[Token(kind: tokLCurly, pos: -1)] & result & @[Token(kind: tokRCurly, pos: pos + 1)]

  result.add(Token(kind: tokEnd))

when isMainModule:
  const input = """
{."key with space"
   {.`key with period.` value with a period.}}
"""

  echo lex(input)

