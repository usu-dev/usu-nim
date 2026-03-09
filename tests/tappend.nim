import usu

let s =  """
.list[0] value
.map[0].key val
.map+ {.key.key val}
.map+ {.appended map}
}
"""
echo parseUsu(s).pretty do (u: UsuNode) -> bool:
  u.kind == UsuMap and ("key" in u.fields or "appended" in u.fields)

assert parseUsu(s) == parseUsu(
"""
.list [value]
.map [
  {.key val}
  null
  {.key {.key val}}
  {.appended map}
]
"""
)

