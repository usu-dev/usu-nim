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

