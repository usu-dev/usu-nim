## using `usu-nim`

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



