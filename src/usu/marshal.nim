##[
  # Usu stores usu

  A simple configuration language that places type burden on the file consumer.

  .. include:: ./docs/manual.md
]##

import std/[sets, strutils, tables, options, typetraits]
import ./parser

type
  SomeTable*[K, V] =
    Table[K, V] |
     OrderedTable[K, V] |
     TableRef[K, V] |
     OrderedTableRef[K, V]

  SomeSet*[T] = HashSet[T] | OrderedSet[T] | set[T]

func toUsu*[T: bool | int | float | string](val: T): UsuNode =
  UsuNode(kind: UsuValue, value: $val)

func toUsu*(o: object): UsuNode =
  result = UsuNode(kind: UsuMap)
  for k, v in o.fieldPairs:
    result.fields[k] = toUsu(v)

func toUsu*[T](a: openArray[T]): UsuNode =
  var items: seq[UsuNode]
  for item in a:
    items.add toUsu(item)
  result = UsuNode(kind: UsuArray, elems: items)

func toUsu*[K,V](t: SomeTable[K,V]): UsuNode =
  result = UsuNode(kind: UsuMap)
  for k, v in t.pairs:
    result.fields[$k] = toUsu(v)

func toUsu*[E: enum](e: E): UsuNode =
  result = UsuNode(kind: UsuValue, value: $e)

func toUsu*[T](s: SomeSet[T]): UsuNode =
  result = UsuNode(kind: UsuArray)
  for item in s:
    result.elems.add toUsu(item)

func toUsu*[T](o: Option[T]): UsuNode =
  result = UsuNode(kind: UsuValue)
  result.value = if o.isSome(): $o.get() else: "null"

func toUsu*(t: tuple): UsuNode =
  let named = type(t).isNamedTuple
  result = UsuNode(kind: if named: UsuMap else: UsuArray)
  for k, v in t.fieldPairs:
    if named:
      if k in result.fields:
        result.fields[k] = toUsu(v)
    else:
      result.elems.add toUsu(v)

template checkKind*(node: UsuNode, k: UsuNodeKind) =
  if node.kind != k:
    raise newException(UsuParserError, "Expected node kind: $1, got: $2, node: $3" % [$k, $node.kind, $node])

template checkKind*(node: UsuNode, k: set[UsuNodeKind]) =
  if node.kind notin k:
    raise newException(UsuParserError, "Expected node kind: $1, got: $2, node: $3" % [$k, $node.kind, $node])

proc fromUsu*(v: var int, node: UsuNode) =
  checkKind node, UsuValue
  v = parseInt(node.value)

proc fromUsu*(v: var float, node: UsuNode) =
  checkKind node, UsuValue
  v = parseFloat(node.value)

proc fromUsu*(v: var string, node: UsuNode) =
  checkKind node, UsuValue
  v = node.value

proc fromUsu*(v: var bool, node: UsuNode) =
  checkKind node, UsuValue
  v = parseBool(node.value)

proc fromUsu*[T](v: var seq[T], node: UsuNode) =
  checkKind node, UsuArray
  for n in node.elems:
    var e: T
    fromUsu(e, n)
    v.add e

proc fromUsu*[T](v: var SomeSet[T], node: UsuNode) =
  checkKind node, UsuArray
  for n in node.elems:
    var e: T
    fromUsu(e, n)
    v.incl e

proc fromUsu*[E: enum](v: var E, node: UsuNode) =
  checkKind node, UsuValue
  v = parseEnum[E](node.value)

proc fromUsu*[T](v: var SomeTable[string, T], node: UsuNode) =
  checkKind node, UsuMap
  for name, nodeValue in node.fields:
    var value: T
    fromUsu(value, nodeValue)
    v[name] = value

proc fromUsu*[T](o: var Option[T], node: UsuNode) =
  checkKind node, {UsuValue, UsuNull}
  if node.kind == UsuNull:
    o = none(T)
  else:
    var v: T
    fromUsu(v, node)
    o = some(v)

proc fromUsu*(t: var tuple, node: UsuNode) =
  template len(n: UsuNode): int =
    case node.kind
    of UsuMap: node.fields.len
    of UsuArray: node.elems.len
    else: 0
  let named = type(t).isNamedTuple()
  if named:
    checkKind node, {UsuArray, UsuMap}
  else:
    checkKind node, UsuArray
  if t.tupleLen != node.len:
    raise newException(UsuParserError, "array has incorrect number of items for tuple")
  var i = 0
  for k, v in t.fieldPairs:
    var v2: type(v)
    if node.kind == UsuArray:
      fromUsu(v2, node.elems[i])
    else:
      fromusu(v2, node.fields[k])
    v = v2
    inc i

template fieldPairs*[T: ref object](x: T): untyped =
  x[].fieldPairs

proc fromUsu*[T: object | ref object](v: var T, node: UsuNode) =
  checkKind node, UsuMap
  when compiles(new(v)):
    new(v)
  for name, value in v.fieldPairs:
    if name in node.fields:
      when compiles(new(value)):
        new(value)
      fromUsu(value, node.fields[name])

proc to*[T](node: UsuNode, t: typedesc[T]): T =
  fromUsu(result, node)
