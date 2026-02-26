import std/strutils

const whitespaces = {' ', '\t', '\v', '\f', '\r'}

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
    ChompNewlines, InlineString, RespectNewlines
  Lexer = ref object
    input: string
    pos: int
    tokens: seq[Token]
    modes: set[LexerMode]

  UsuParserError* = object of CatchableError

const Quotes = {'"', '\'', '`'}
const OpenBrackets = {'[', '{'}
const CloseBrackets = {'}', ']'}
const Brackets = OpenBrackets + CloseBrackets
const Syntax = Brackets + {'.', '>', '#'}

proc newTokKey(pos: int, val: string): Token =
  Token(kind: tokKey, pos: pos, keyVal: val)

proc newTokString(pos: int, val: string): Token =
  Token(kind: tokString, pos: pos, stringVal: val)

# TODO: support more escape sequences?
proc subEscapeSeqs(s: string): string =
  result = multiReplace(
    s, {
        "\\n": "\n",
        "\\t": "\t",
        "\\\\": "\\",
        "\\\"": "\""
      }
  )

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

proc new(T: typedesc[Lexer], input: string): Lexer =
  new(result)
  result.input = input

proc lastWasKey(l: Lexer): bool =
  if l.tokens.len > 0:
    result = l.tokens[^1].kind == tokKey

proc curr(l: Lexer): char {.inline.} =
  if l.pos < l.input.len: l.input[l.pos]
  else: '\x00'

proc next(l: Lexer): char {.inline.} =
  if l.pos+1 < l.input.len: l.input[l.pos+1]
  else: '\x00'

proc prev(l: Lexer): char {.inline.} =
  if l.pos - 1 >= 0: l.input[l.pos-1]
  else: '\x00'

proc inc(l: var Lexer, n: Natural = 1) =
  inc l.pos, n

proc add(l: var Lexer, t: Token) =
  l.tokens.add t

proc set(l: var Lexer, mode: LexerMode) =
  l.modes.incl mode

proc drop(l: var Lexer, mode: LexerMode) =
  l.modes.excl mode

proc drop(l: var Lexer, modes: varargs[LexerMode]) =
  for m in modes:
    l.modes.excl m

proc isSet(l: var Lexer, mode: LexerMode): bool =
  mode in l.modes

proc skip(
  l: var Lexer,
  chars = whitespaces + {'\n', '\r'}
) =
  let startPos = l.pos
  while l.curr in chars:
    l.inc
  # why do I iterate then check the modes?
  if (l.curr notin Syntax + Quotes) and not l.isSet(InlineString):
    l.pos = startPos

proc skipComment(l: var Lexer) =
  inc l
  if l.curr == '(':
    inc l
    while (l.curr & l.next) != ")#": inc l
    inc l
  else:
    while l.curr notin NewLines:
      inc l
    inc l

func addBracket(l: var Lexer) =
  let kind = case l.curr
    of '[': tokLBracket
    of ']': tokRBracket
    of '{': tokLCurly
    of '}': tokRCurly
    else: raise newException(UsuParserError, "failed to lex token, unexpected char: " & $l.curr)
  l.add Token(pos: l.pos, kind: kind)

func lexBracket(l: var Lexer) =
  l.addBracket
  l.inc
  case l.prev:
  of OpenBrackets:
    if l.curr notin NewLines:
      l.set(InlineString)
  of CloseBrackets:
    l.drop(InlineString)
  of '\x00': discard
  else: assert false

proc lexKey(l: var Lexer) =
  var key = ""
  let start = l.pos
  l.inc
  if l.curr in Quotes:
    let q = l.curr
    l.inc
    while l.curr != q:
      # we need to escape periods to prevent path splitting in parser
      if l.curr == '.':
        key.add '\\'
      key.add(l.curr)
      l.inc
    l.inc
  else:
    while l.curr notin Newlines + {' ', '}'} and l.curr != '\x00':
      key.add(l.curr)
      l.inc
  l.add newTokKey(start, key)

  if l.curr == '\n':
    l.set RespectNewlines
  elif l.curr & l.next == " >":
    l.set ChompNewLines
    inc(l, 2)


# BUG: properly handle values missing final quote
proc lexQuotedVal(l: var Lexer) =

  let quote = l.curr
  var str = ""
  let start = l.pos
  l.inc
  while true:
    str.add(l.curr)
    if (l.next == quote and l.curr != '\\') or (l.next == quote and l.curr & l.prev == "\\\\"):
      inc l, 2; break
    if l.curr == '\x00':
      raise newException(UsuParserError, "reached EOF before end quote char: $1, for value starting at pos $2" % [$quote, $start])
    l.inc
  l.add newTokString(start, subEscapeSeqs(str))

{.push inline.}
proc atEof(l: Lexer): bool =
  # quirk of l.curr that null byte is returned
  l.curr == '\x00'
proc atKeyStart(l: Lexer): bool =
  l.curr == '.' and l.prev in {' '} + NewLines
proc atBracket(l: Lexer): bool =
  l.curr in Brackets
# is this portable when used?
proc atEol(l: Lexer): bool =
  l.curr == '\n'
{.pop.}

# TODO: reduce allocations and string processing/stripping
proc lexUnquotedVal(l: var Lexer) =
  var str = ""
  var hadNewLine = false

  template stop: bool =
    l.atKeystart or l.atEof or l.atBracket

  let start = l.pos
  while true:
    if l.curr == '#':
      # remove any trailing whitespace before comment
      str = strip(str, leading = false)
      l.skipComment
      if stop: break
    else:
      str.add(l.curr)
    l.inc
    if stop: break
    if not l.lastWasKey:
      if l.isSet(InlineString):
        if l.curr in whitespaces: break
      elif l.atEol: hadNewLine = true; break

  if l.isSet(InlineString):
    str = strip(str)
  else:
    str = dedent(str)
    hadNewLine = str.endsWith('\n')

  str = strip(str, chars = whitespaces + NewLines)
  if str == "": return
  str = subEscapeSeqs(str)
  if l.isSet(ChompNewLines):
    str = str.splitLines().join(" ")
  elif l.isSet(RespectNewlines) and hadNewLine:
    str.add "\n"
  l.add newTokString(start, str)

  # reset modes that effect unquoted parsing
  l.drop RespectNewlines, ChompNewlines


proc lex*(l: var Lexer) =
  while l.pos < l.input.len:
    skip l
    when defined(debugUsu):
      debugUsu(l.pos, l.input, l.modes)
    case l.curr
    of '#': skipComment l
    of Brackets: l.lexBracket
    of Newlines: l.inc
    of '.': l.lexKey
    of '>': l.inc # skipping this newline will in effect activate InlineString
    of Quotes: l.lexQuotedVal
    else: l.lexUnquotedVal

  # BUG: unhandled exception when tokens are empty
  if l.tokens[0].kind == tokKey:
    l.tokens = @[Token(kind: tokLCurly, pos: -1)] & l.tokens & @[Token(kind: tokRCurly, pos: l.pos + 1)]

  l.add Token(kind: tokEnd)

proc lex*(s: string): seq[Token] =
  var lexer = Lexer.new(s)
  lexer.lex()
  result = lexer.tokens

