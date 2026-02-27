import std/[tables, deques, strutils, strformat]

import lexer
export tables, UsuParserError

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

func `==`*(a, b: UsuNode): bool =
  ## check two nodes for equality
  if a.kind != b.kind: return false
  case a.kind:
  of UsuNull: result = true
  of UsuValue:
    result = a.value == b.value
  of UsuArray:
    result = a.elems == b.elems
  of UsuMap:
    result = a.fields == b.fields

proc newUsuValue*(s: string): UsuNode =
  UsuNode(kind: UsuValue, value: s)

proc newUsuNull*(): UsuNode =
  UsuNode(kind: UsuNull)
template error(token: Token, msg = "", suffix = "") =
  ## Shortcut to raise an exception.
  var message = msg
  if message == "":
    message = "unexpected " & (
      case token.kind
      of tokLBracket: "opening array bracket"
      of tokRBracket: "closing array bracket"
      of tokLCurly: "opening map bracket"
      of tokRCurly: "closing map bracket"
      of tokString: "value: \"" & token.stringVal & "\""
      of tokKey: "key: \"" & token.keyVal & "\""
      of tokEnd: "EOF"
      of tokNull: "null"
    )
  if suffix != "":
    message.add ", "
    message.add suffix

  raise newException(UsuParserError, message & " at pos: " & $token.pos)

proc newUsuValue(t: Token): UsuNode = 
  case t.kind
  of tokString:
    result = newUsuValue(t.stringVal)
  else: error(t, "expected tokString")

proc newUsuNull*(t: Token): UsuNode =
  case t.kind
  of tokNull:
    result = UsuNode(kind: UsuNull)
  else: error(t, "expected tokNull")

proc pop(d: var Deque[Token]): Token {.inline.} = popFirst d

proc parse(tokens: var Deque[Token], root: bool = false): UsuNode

proc toUsuMap(fields: openArray[(string, UsuNode)]): UsuNode =
   UsuNode(kind: UsuMap, fields: fields.toOrderedTable())

proc toUsuMap(path: seq[string], value: UsuNode): UsuNode =
  if path.len > 1:
    result = toUsuMap({path[0]: toUsuMap(path[1..^1], value)})
  else:
    result = toUsuMap({path[0]: value})

proc deepMerge[K, V](target: var OrderedTable[K, V], source: OrderedTable[K, V]) =
  for key, value in source:
    if target.hasKey(key):
      # Check if both values are tables to recurse
      # If they are, merge the nested tables
      when compiles(deepMerge(target[key], value)):
        deepMerge(target[key], value)
      else:
        target[key] = value # shallow merge (overrides target)
    else:
      target[key] = value

proc nestedUpdate(node: var UsuNode, path: seq[string], value: UsuNode, token: Token) =
  let curr = path[0]
  if path.len == 1:
    if curr in node.fields:
      # TODO: better error
      if node.fields[curr].kind != value.kind:
        error(token,
          fmt"""failed to merge values for repeated key: "{curr}", kinds must match expected: "{node.fields[curr].kind}", but got: "{value.kind}""""
        )
      case node.fields[curr].kind:
      of UsuMap:
        node.fields[curr].fields.deepMerge(value.fields)
      of UsuArray:
        node.fields[curr].elems.add value.elems
      of UsuValue, UsuNull:
        node.fields[curr] = value
    else:
      node.fields[curr] = value
  else:
    if curr in node.fields:
      node.fields[curr].nestedUpdate(path[1..^1], value, token)
    else:
      node.fields[curr] = toUsuMap(path[1..^1], value)


proc splitPath(token: Token): seq[string] =
  let key = token.keyVal
  let paths = key.split('.')
  var i = 0
  template next: string =
    if i+1 < paths.len: paths[i+1] else: ""
  while i < paths.len:
    var current = paths[i]
    if current.endsWith('\\'): # escaped period
      current = current.replace('\\', '.') & next
      inc i
    if current == "":
      error(token, msg = "key value can't be empty")
    result.add current
    inc i

proc parseMap(tokens: var Deque[Token]): UsuNode =
  var currTok: Token
  result = UsuNode(kind: UsuMap)
  while true:
    currTok = pop tokens
    case currTok.kind
    of tokRCurly: break # end of map
    of tokLBracket, tokString, tokLCurly, tokRBracket, tokNull, tokEnd:
      error(currTok, suffix = "while parsing map")
    of tokKey:
      let nextToken = peekFirst tokens
      let paths = currTok.splitPath
      let value =
        case nextToken.kind
        of tokString: newUsuValue(pop(tokens))
        of tokLBracket, tokLCurly: parse(tokens)
        of tokNull:
          discard pop(tokens)
          newUsuNull()
        else:
          error(nextToken, suffix = "expected value")

      nestedUpdate(result, paths, value, nextToken)

proc parseArray(tokens: var Deque[Token]): UsuNode =
  var currTok: Token
  result = UsuNode(kind: UsuArray)
  while true:
    # parse node including opening brackets
    if tokens.peekFirst.kind in {tokLBracket, tokLCurly}:
      result.elems.add parse(tokens)
    else:
      currTok = pop tokens
      case currTok.kind
      of tokString:
        result.elems.add newUsuValue(currTok)
      of tokNull:
        result.elems.add newUsuNull()
      of tokRBracket:
        break
      of tokEnd, tokLCurly, tokRCurly, tokLBracket, tokKey:
        error(currTok, suffix = "while parsing array")

proc parse(tokens: var Deque[Token], root = false): UsuNode =
  let token = pop tokens
  case token.kind:
    of tokLCurly:
      result = parseMap(tokens)
    of tokLBracket:
      result = parseArray(tokens)
    of tokRCurly, tokRBracket, tokString, tokNull:
      error(token, suffix = "expected opening bracket or key")
    of tokKey:
      error(token)
    of tokEnd: discard
  if root:
    let last = pop tokens
    if last.kind != tokEnd:
      error(last, msg = "expected EOF, got: " & $last.kind)

proc parseUsu*(input: string): UsuNode =
  var tokens = toDeque lex(input)
  result = parse(tokens, root = true)

when isMainModule:

  const input = "  value  "
  echo lex(input)
  var tokens = toDeque(lex(input))
  echo parse(tokens, root = true)

