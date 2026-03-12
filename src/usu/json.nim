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

proc toUsu*(node: JsonNode): UsuNode =
  case node.kind
  of JString:
    result = newUsuValue(node.str)
  of JInt:
    result = newUsuValue($node.num)
  of JFloat:
    result = newUsuValue($node.fnum)
  of Jbool:
    result = newUsuValue($node.bval)
  of JNull:
    result = newUsuNull()
  of JObject:
    result = UsuNode(kind: UsuMap)
    for k, v in node.fields.pairs:
      result.fields[k] = v.toUsu()
  of JArray:
    result = UsuNode(kind: UsuArray)
    for v in node.elems:
      result.elems.add v.toUsu()

export json
