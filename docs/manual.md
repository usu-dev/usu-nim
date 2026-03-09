## using `usu-nim` with `nim` types

```nim
import usu

type
  Project = object
    name, description, license: string
    features: seq[string]

echo parseUsu("""
.name usu
.description usu stores usu
.license MIT
.features [
  minimal quoting
  nested key merging
  config first design
]
""").to(Project)
```

## customized unmarshaling

You can extend support for any nim type using a custom `fromUsu` proc

```nim
import std/[times]

type
  Note = object
    date: DateTime

proc fromUsu(v: var DateTime, node: UsuNode) =
  checkKind node, UsuValue
  v = parse(node.value, "yyyy-MM-dd")

echo parseUsu(".date 2026.02.26").to(Note)
```


## pretty printing

By default, converting an `UsuNode` to a string (with `proc $`_) will result in a single line, minimal character output.
To get a human-readable result, there is pretty_.

This procedure is customizable via a closure to determine whether to inline a given a `UsuNode`
For instance to ad-hoc inline all simple arrays (i.e. arrays with only `UsuValue`):

```nim
echo parseUsu(u).pretty do (u: UsuNode) -> bool:
  u.kind == UsuArray and u.elems.allIt(it.kind == UsuValue)
```

See UsuPrettySettings_ for additional modifications to `pretty` output.
