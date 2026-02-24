import std/[json, tables]

import parser

proc `%`*(u: UsuNode): JsonNode =
  case u.kind
  of UsuMap:
    result = newJObject()
    for k, v in u.fields.pairs: result[k] = %v
  of UsuArray:
    result = newJArray()
    for elem in u.elems: result.add %elem
  of UsuValue:
    result = JsonNode(kind: JString, str: u.value)
  of UsuNull:
    result = newJNull()

export json
