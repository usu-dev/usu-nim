import std/[tables, deques]

import lexer
export tables

type
  UsuNodeKind* = enum
    UsuMap, UsuArray, UsuValue, UsuNull
  UsuNode* = object
    case kind*: UsuNodeKind
    of UsuMap:
      fields*: OrderedTable[string, UsuNode]
    of UsuArray:
      elems*: seq[UsuNode]
    of UsuValue:
      value*: string
    of UsuNull:
      nil
  UsuParserError* = object of CatchableError

proc peekSecond(deq: Deque[Token]): Token {.inline.} =
  if deq.len > 1: deq[1]
  else: Token(kind: tokEnd)

proc keyCheck(u: UsuNode, t: Token) =
  if t.keyVal in u.fields:
    raise newException(UsuParserError, "keys must be unique, but got duplicate for: " & t.keyVal)

proc pop(d: var Deque[Token]): Token {.inline.} = popFirst d

proc parseString(token: Token): UsuNode =
  result = (
    if token.stringVal == "null": UsuNode(kind: UsuNull)
    else: UsuNode(kind: UsuValue, value: token.stringVal)
  )

proc parse(tokens: var Deque[Token]): UsuNode

proc parseMap(tokens: var Deque[Token]): UsuNode =
  var currTok: Token
  result = UsuNode(kind: UsuMap)

  while true:
    currTok = pop tokens
    case currTok.kind
    of tokLPar:
      raise newException(UsuParserError, "Unexpected left paranthesis when parsing map")
    of tokString:
      raise newException(UsuParserError, "Unexpected value: " & $currTok.stringVal & ", while parsing map")
    of tokKey:
      let nextToken = peekFirst tokens

      # bail for empty map
      if currTok.keyVal == "" and nextToken.kind == tokRPar:
        discard pop tokens
        break
      keyCheck result, currTok
      case nextToken.kind
      of tokString:
        result.fields[currTok.keyVal] = parseString(pop tokens)
      of tokLPar:
        let value = parse(tokens)
        result.fields[currTok.keyVal] = value
      else:
        raise newException(UsuParserError, "Unexpected token in map: " & $nextToken)
    of tokRPar: break
    of tokEnd:
      raise newException(UsuParserError, "reached EOF: expected closing paren")


proc parseArray(tokens: var Deque[Token]): UsuNode =
  var currTok: Token
  result = UsuNode(kind: UsuArray)
  while true:
    currTok = pop tokens
    case currTok.kind
    of tokString:
      result.elems.add parseString(currTok)
    of tokLPar:
      result.elems.add parse(tokens)
    of tokRPar: break
    of tokKey:
      raise newException(UsuParserError, "Unexpected key:" & $currTok.keyVal & ", while parsing array")
    of tokEnd:
      raise newException(UsuParserError, "reached EOF: expected closing paren")


proc parse(tokens: var Deque[Token]): UsuNode =
  let token = pop tokens
  case token.kind:
    of tokLPar:
      case tokens.peekFirst.kind
      of tokKey:
        return parseMap(tokens)
      of tokString:
        return parseArray(tokens)
      of tokRPar:
        return UsuNode(kind: UsuArray)
      of tokLPar:
        return parse(tokens)
      else: raise newException(UsuParserError, "else error" & $token)
    of tokRpar:
      raise newException(UsuParserError, "Unexpected closing paren")
    of tokKey:
      raise newException(UsuParserError, "Unexpected key: " & token.keyVal)
    of tokEnd: discard
    else:
      raise newException(UsuParserError, "else error")

proc parseUsu*(input: string): UsuNode =
  var tokens = toDeque lex(input)
  return parse tokens

when isMainModule:
  const input = """
:dirs (
  /home/daylin/dev/github/daylinmorgan/
  /home/daylin/dev/github/usu-dev/
  /home/daylin/dev/github/forks/
)

:sessions (
  (:name protocol :dir /home/daylin/stuff/writing/clonmapper-protocol)
)
"""
  echo lex(input)
  echo parseUsu(input)

