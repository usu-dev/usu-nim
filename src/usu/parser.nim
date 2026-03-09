import std/[tables, deques, strutils, strformat, sequtils, strscans]

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

proc newUsuMap*(fields: openArray[(string, UsuNode)]): UsuNode =
   UsuNode(kind: UsuMap, fields: fields.toOrderedTable())

proc newUsuArray(elems: varargs[UsuNode]): UsuNode =
  UsuNode(kind: UsuArray, elems: @elems)

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

proc newUsuNull(t: Token): UsuNode =
  case t.kind
  of tokNull:
    result = UsuNode(kind: UsuNull)
  else: error(t, "expected tokNull")

type
  Key = object
    indexed: bool
    idx: int
    name: string


proc parseIndex(name: string): (string, int) =
  var key: string
  var idx: int
  if scanf(name, "$w[$i]", key, idx):
    if idx < 0:
      raise newException(UsuParserError, fmt("failed to extract index from key \"{key}\", index can't be negative"))
    return (key, idx)
  else:
    raise newException(UsuParserError, fmt("failed to extract index from key \"{name}\""))

proc init(_: typedesc[Key], name: string): Key =
  if '[' in name:
    result.indexed = true
    let (key, idx) = parseIndex(name)
    result.idx = idx
    result.name = key
  else:
    result.name = name

proc contains(
  node: UsuNode,
  key: Key,
): bool =
  assert node.kind == UsuMap
  key.name in node.fields

proc `[]`(node: var UsuNode, key: Key): var UsuNode =
  node.fields[key.name]

proc `[]=`(node: var UsuNode, key: Key, val: UsuNode) =
  node.fields[key.name] = val

proc pop(d: var Deque[Token]): Token {.inline.} = popFirst d

proc parse(tokens: var Deque[Token], root: bool = false): UsuNode

# TODO: toUsuArray(idx: int, val: UsuNode)

# TODO: use Key + index to inform creation
# proc toUsuMap(path: seq[Key], value: UsuNode): UsuNode {.deprecated.}=
#   # TODO: index means newUsuArray then toUsuMap...
#   if path.len > 1:
#     result = newUsuMap({path[0].name: toUsuMap(path[1..^1], value)})
#   else:
#     result = newUsuMap({path[0].name: value})

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



proc toUsuArray(val: UsuNode, idx: int): UsuNode =
  if idx != 0:
    result = newUsuArray(newUsuNull().repeat(idx+1))
    result.elems[idx] = val
  else:
    result = newUsuArray(val)

proc toUsuNode(path: seq[Key], value: UsuNode): UsuNode

proc toUsuNode(
  key: Key,
  path: seq[Key],
  value: UsuNode,
): UsuNode =
  ## generate a value to be set for key if a key has an index then the return type will be array
  if key.indexed:
    result = toUsuArray(toUsuNode(path[1..^1], value), key.idx)
  else:
    result = toUsuNode(path[1..^1], value)

proc toUsuNode(
  path: seq[Key],
  value: UsuNode
): UsuNode =
  let curr = path[0]
  if path.len > 1:
    result = newUsuMap({curr.name: toUsuNode(curr, path, value)})
  else:
    if curr.indexed:
      result = newUsuMap({path[0].name: toUsuArray(value, curr.idx)})
    else:
      result = newUsuMap({path[0].name: value})

proc nestedUpdate(node: var UsuNode, path: seq[Key], value: UsuNode, token: Token)

proc updateArray(node: var UsuNode, key: Key, path: seq[Key], value: UsuNode, token: Token) =
  assert node[key].kind == UsuArray
  assert path.len >= 1
  if node[key].elems.len < key.idx:
    while node[key].elems.len < key.idx:
      node[key].elems.add newUsuNull()
    node[key].elems.add toUsuNode(path, value)
  else:
    nestedUpdate(node[key].elems[key.idx], path, value, token)

proc nestedUpdate(node: var UsuNode, path: seq[Key], value: UsuNode, token: Token) =
  assert node.kind == UsuMap

  let key = path[0]

  if path.len == 1: # final update
    if key in node:
      if node[key].kind != value.kind:
        error(token,
          fmt"""failed to merge values for repeated key: "{key.name}", kinds must match expected: "{node[key].kind}", but got: "{value.kind}""""
        )
      case node[key].kind:
      of UsuMap:
        node[key].fields.deepMerge(value.fields)
      of UsuArray:
        node[key].elems.add value.elems
      of UsuValue, UsuNull:
        node[key] = value
    else:
      if key.indexed:
        node[key] = toUsuArray(value, key.idx)
      else:
        node[key] = value
  else:
    if key in node:
      if node[key].kind == UsuArray:
        if not key.indexed:
          error token, "failed to merge map with array"
        echo key, path
        node.updateArray(key, path[1..^1], value, token) # should updateArray be a special case of 'nestedUpdate?'
      else:
        node[key].nestedUpdate(path[1..^1], value, token)
    else:
      node[key] = toUsuNode(key, path, value)


func splitEscapedPath(token: Token): seq[string] =
  let key = token.keyVal
  var i = 0
  while i < len(key):
    var path = ""
    var start = i
    while i < len(key):
      case key[i]
      of '\\':
        path.add key[start..i-1] & "."
        inc i, 2
        start = i
      of '.':
        path.add key[start..i-1]
        inc i; break
      else: inc i
    if i == len(key):
      path.add key[start..i-1]

    if path == "":
      error(token, msg = "key value can't be empty")
    else:
      result.add path

func splitPath(token: Token): seq[string] =
  if token.kind != tokKey:
    error(token, "expected tokKey")
  let key = token.keyVal
  if "." notin key:
    return @[key]
  elif "\\." notin key:
    return key.split('.')
  else:
    return splitEscapedPath(token)

func getPath(token: Token): seq[Key] =
  if token.kind != tokKey:
    error(token, "expected tokKey")
  for key in token.splitPath:
    result.add Key.init(key)

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
      let path = getPath(currTok)
      let value =
        case nextToken.kind
        of tokString: newUsuValue(pop(tokens))
        of tokLBracket, tokLCurly: parse(tokens)
        of tokNull:
          pop(tokens).newUsuNull()
        else:
          error(nextToken, suffix = "expected value")
      if currTok.append:
        nestedUpdate(result, path, newUsuArray(value), nextToken)
      else:
        nestedUpdate(result, path, value, nextToken)

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
  const input = ".`level1.level2.level3` value"
  echo lex(input)
  var tokens = toDeque(lex(input))
  echo parse(tokens, root = true)

