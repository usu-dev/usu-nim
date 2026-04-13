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

template checkKind*(node: UsuNode, k: UsuNodeKind) =
  if node.kind != k:
    raise newException(UsuParserError, "Expected node kind: $1, got: $2, node: $3" % [$k, $node.kind, $node])

template checkKind*(node: UsuNode, k: set[UsuNodeKind]) =
  if node.kind notin k:
    raise newException(UsuParserError, "Expected node kind: $1, got: $2, node: $3" % [$k, $node.kind, $node])


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

proc `$`(u: UsuNode): string =
  # minimal stringify for debugging purposes
  case u.kind
  of UsuMap:
    result.add "{"
    result.add u.fields.pairs.toSeq().mapIt($it[0] & ":" & $it[1]).join(",")
    result.add "}"
  of UsuArray:
    result.add "["
    result.add u.elems.toSeq().mapIt($it).join(",")
    result.add "]"
  of UsuValue:
    result = escape(u.value)
  of UsuNull: result = "null"


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
  KeyKind = enum
    Plain, Index, Append, IndexOnly
  Key = object
    name: string
    case kind: KeyKind:
    of Index, IndexOnly:
      idx: int
    of Append, Plain:
      nil

proc parseKeyWithIndices(input: string): (string, seq[int]) =
  var
    key: string
    idx: int
    pos: int
    indices: seq[int]

  # First grab the key
  pos = input.find('[')
  key = input[0..pos-1]

  # Then grab each [N] block
  while pos < input.len:
    if scanf(input[pos..^1], "[$i]", idx):
      inc pos, ($idx).len + 2
      indices.add(idx)
    else:
      break

  if indices.anyIt(it < 0):
      raise newException(UsuParserError, fmt("failed to extract index from key \"{key}\", index can't be negative"))
  if indices.len == 0:
    raise newException(UsuParserError, fmt("failed to extract index from key \"{input}\""))

  return (key, indices)


proc initKeys(name: string): seq[Key] =
  if '[' in name:
    let (key, idxs) = parseKeyWithIndices(name)
    result.add Key(kind: Index, idx: idxs[0], name: key)
    if idxs.len > 1:
      for i in idxs[1..^1]:
        result.add Key(kind: IndexOnly, idx: i)
  elif name.endsWith("+"):
    result.add Key(kind: Append, name: name[0..^2])
  else:
    result.add Key(kind: Plain, name: name)

proc contains(
  node: UsuNode,
  key: Key,
): bool =
  assert node.kind == UsuMap
  assert key.name != "" # empty keys are not allowed
  key.name in node.fields

proc `[]`(node: var UsuNode, key: Key): var UsuNode =
  node.fields[key.name]

proc `[]=`(node: var UsuNode, key: Key, val: UsuNode) =
  node.fields[key.name] = val

proc pop(d: var Deque[Token]): Token {.inline.} = popFirst d

proc parse(tokens: var Deque[Token], root: bool = false): UsuNode

proc deepMerge(target: var OrderedTable[string, UsuNode], source: OrderedTable[string, UsuNode]) =
  for key, value in source:
    if target.hasKey(key):
      case target[key].kind
      of UsuMap:
        deepMerge(target[key].fields, value.fields)
      of UsuValue, UsuNull:
        target[key] = value
      of UsuArray:
        case value.kind
        of UsuArray:
          target[key].elems.add value.elems
        else:
          target[key].elems.add value
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
  case key.kind
  of Index, IndexOnly:
    result = toUsuArray(toUsuNode(path[1..^1], value), key.idx)
  of Plain:
    result = toUsuNode(path[1..^1], value)
  of Append: assert false

proc toUsuNode(
  path: seq[Key],
  value: UsuNode
): UsuNode =
  let curr = path[0]
  if path.len > 1:
    case curr.kind
    of IndexOnly:
      result = toUsuArray(toUsuNode(path[1..^1], value), curr.idx)
    else:
      result = newUsuMap({curr.name: toUsuNode(curr, path, value)})
  else:
    case curr.kind
    of Index:
      result = newUsuMap({path[0].name: toUsuArray(value, curr.idx)})
    of IndexOnly:
      result = toUsuArray(value, curr.idx)
    of Append:
      result = newUsuMap({path[0].name: toUsuArray(value, 0)})
    else:
      result = newUsuMap({path[0].name: value})

proc nestedUpdate(node: var UsuNode, path: seq[Key], value: UsuNode, token: Token)

proc merge(a: var UsuNode, b: UsuNode) =
  if a.kind == UsuNull:
    a = b
    return
  if a.kind != b.kind:
    raise newException(UsuParserError, "can't merge nodes with mismatched kinds " & $a.kind & " != " & $b.kind)
  case a.kind
  of UsuMap:
    a.fields.deepMerge(b.fields) # deep merge breaks expecations
  of UsuArray:
    a.elems.add b.elems
  of UsuValue, UsuNull:
    a = b

proc expand(node: var UsuNode, idx: Natural) =
  assert node.kind == UsuArray
  while node.elems.len <= idx:
    node.elems.add newUsuNull()

template tryMerge(a: var UsuNode, b: UsuNode) =
  try:
    merge(a, b)
  except:
    case key.kind
    of Index:
      error(token, fmt"""failed to set value for key: "{key.name}" at index: {key.idx}, """ & getCurrentExceptionMsg())
    of IndexOnly:
      error(token, fmt"""failed to set value at index: {key.idx}, """ & getCurrentExceptionMsg())
    else:
      error(token, fmt"""failed to set value for key: "{key.name}", """ & getCurrentExceptionMsg())

proc nestedUpdate(node: var UsuNode, key: Key, value: UsuNode, token: Token) =
  if key.kind == IndexOnly:
    if node.kind == UsuNull:
      node = toUsuArray(value, key.idx)
    else:
      node.expand(key.idx)
      node.elems[key.idx] = value
    return
  if node.kind == UsuNull:
    node = UsuNode(kind: UsuMap)

  if key in node:
    case key.kind
    of Append:
      if node[key].kind != UsuArray:
        error(token,
          fmt"""failed to append values to key: "{key.name}", expected UsuArray, got "{node[key].kind}""""
        )
      node[key].elems.add value
    of Index:
      while node[key].elems.len <= key.idx:
        node[key].elems.add newUsuNull()
      trymerge(node[key].elems[key.idx], value)
    of Plain:
      trymerge(node[key], value)
    of IndexOnly: assert false
  else:
    case key.kind
    of IndexOnly:
      assert node.kind == UsuArray
      tryMerge(node.elems[key.idx], value)
    of Append:
      node[key] = toUsuArray(value, 0)
    of Index:
      node[key] = toUsuArray(value, key.idx)
    of Plain:
      node[key] = value

proc nestedUpdate(node: var UsuNode, path: seq[Key], value: UsuNode, token: Token) =
  let key = path[0]


  if path.len == 1:
    nestedUpdate(node, key, value, token)
    return

  if node.kind == UsuNull:
    node = UsuNode(kind: UsuMap)
  if key notin node:
    node[key] = toUsuNode(key, path, value)
    return

  case key.kind
  of Index: # consume key and update at index
    if node[key].kind != UsuArray:
      # TODO: better error
      error token, "failed to merge map with array"
    node[key].expand(key.idx)
    nestedUpdate(node[key].elems[key.idx], path[1..^1], value, token)
  of Append: assert false
  else:
    nestedUpdate(node[key], path[1..^1], value, token)

func splitEscapedPath(path: string): seq[string] =
  var i = 0
  while i < len(path):
    var key = ""
    var start = i
    while i < len(path):
      case path[i]
      of '\\':
        key.add path[start..i-1] & "."
        inc i, 2
        start = i
      of '.':
        key.add path[start..i-1]
        inc i; break
      else: inc i
    if i == len(path):
      key.add path[start..i-1]
    result.add key

func splitPath(path: string): seq[string] =
  if "." notin path:
    return @[path]
  elif "\\." notin path:
    return path.split('.')
  else:
    return splitEscapedPath(path)

func getPath(token: Token): seq[Key] =
  if token.kind != tokKey:
    error(token, "expected tokKey")
  let path = token.keyVal.splitPath
  for i, p in path:
    if p == "": error(token,"key value can't be empty")
    for key in initKeys(p):
      if key.kind == Append and i != path.len - 1:
        error token,
          "error in nested key path: " & $path & ", '+' is only supported on last key"
      result.add key

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

proc pathToKeys(path: string): seq[Key] =
  ## this proc is for use by getters
  let path =
    if path.startsWith("."): path[1..^1]
    else: path

  for i, p in path.splitPath:
    if p == "":
      raise newException(KeyError, "key value can't be empty")
    for key in initKeys(p):
      if key.kind == Append:
        raise newException(KeyError, "append keys not supported in this context")
      result.add key

proc getNode(u: UsuNode, key: Key): UsuNode =
  template checkMap() =
    if u.kind != UsuMap:
      raise newException(KeyError, "key: $#, expected UsuMap, got: $#" % [key.name, $u.kind])
    if key.name notin u.fields:
      raise newException(KeyError, "key: $#, does not exist in map" % key.name)
  template checkBounds() =
    if u.kind != UsuArray:
      raise newException(KeyError, "key: $#, expected UsuArray, got: $#" % [key.name, $u.kind])
    if u.elems.len - 1 < key.idx:
      raise newException(KeyError, "index: $#, is out of bounds: $#..$#" % [$key.idx, $u.elems.low, $u.elems.high])

  case key.kind
  of Plain:
    checkMap()
    return u.fields[key.name]
  of Index:
    checkMap()
    let u = u.fields[key.name]
    checkBounds()
    return u.elems[key.idx]
  of IndexOnly:
    checkBounds()
    return u.elems[key.idx]
  of Append: assert false


proc getNode(u: UsuNode, path: seq[Key]): UsuNode =
  if path.len == 1:
    return getNode(u, path[0])
  let key = path[0]
  result = u.getNode(key).getNode(path[1..^1])

proc getNode(u: UsuNode, path: string): UsuNode =
  let keys = pathToKeys(path)
  result = getNode(u, keys)

proc get*(u: UsuNode, path: string): UsuNode =
  ## retrieve a nested UsuNode using a path string
  ##
  ## Paths use `.` as a separator for map keys and `[N]` for array indices.
  ## If a key contains a literal `.`, it must be escaped with `\.`.
  ##
  ## Examples:
  ## ```nim
  ## u.get("meta.title")
  ## u.get("numbers[0]")
  ## u.get("key\.with\.dots")
  ## ```
  ## Raises KeyError if the path does not exist.
  u.getNode(path)

proc `[]`*(u: UsuNode, key: string): UsuNode =
  assert u.kind == UsuMap
  u.fields[key]

proc `[]`*(u: UsuNode, idx: Natural): UsuNode =
  assert u.kind == UsuArray
  u.elems[idx]

