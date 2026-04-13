## Overview

`usu-nim` is a library for parsing and writing the usu configuration language.
usu is a minimal-quoting, human-friendly format where type interpretation is always
left to the consumer — every value is a string until your code says otherwise.

The library's public surface has three concerns: parsing usu text into an AST,
marshaling Nim values into that AST, and unmarshaling the AST back into Nim values.


## usu language

Understanding the parser's behavior requires understanding the language. This section
covers the syntax rules that affect how `parseUsu` constructs its output.

### Keys and values

Every entry is a key followed by a value. Keys begin with `.`:

```usu
.name Alice
.age  30
```

Keys may be nested by chaining segments with `.`:

```usu
.server.host localhost
.server.port 8080
```

This is exactly equivalent to writing the nested map explicitly:

```usu
.server {
  .host localhost
  .port 8080
}
```

The parser performs a **deep merge** when it encounters a key path whose parent
map already exists, so you can spread nested keys across multiple lines freely.

### Maps and arrays

A map is delimited by `{` and `}`. An array is delimited by `[` and `]`:

```usu
.address { .city Oslo .country Norway }
.scores [42 97 13]
```

Values inside an array are whitespace-separated. Nested structures are allowed:

```usu
.users [
  { .name Alice .age 30 }
  { .name Bob   .age 25 }
]
```

### The implicit root map

When input begins with a `.` key at the top level (not inside any brackets), the
parser treats the entire input as a map — you do not need to write surrounding `{}`.
The two forms below are identical:

```usu
.key value           # implicit root map
{ .key value }       # explicit root map
```

A bare `[...]` at the root level produces a `UsuArray`, not a `UsuMap`.

### Null

The bare word `null` produces a `UsuNull` node:

```usu
.optional null
```

To store the literal string `"null"` as a value, quote it:

```usu
.word "null"
.word 'null'
.word `null`
```

This distinction matters during unmarshaling: `UsuNull` maps to `none(T)` for
`Option[T]` fields, while a quoted `"null"` unmarshal as the string `"null"`.

### Quoted strings

Three quote styles are available: single quotes (`'`), double quotes (`"`), and backtick quotes (`\``).
All three support the same escape sequences inside them:

| Sequence   | Meaning              |
|------------|----------------------|
| `\n`       | newline              |
| `\t`       | tab                  |
| `\\`       | literal backslash    |
| `\'`       | literal single quote |
| `\"`       | literal double quote |
| ``\```       | literal backtick     |

A quoted string that begins with a newline immediately after the opening quote is
dedented — leading whitespace common to all lines is removed. This is useful for
embedding indented blocks without fighting the indentation of the surrounding file.

### Raw strings

Prefix any quote character with `r` to suppress all escape processing. Only the
matching close quote ends the string:

```usu
.pattern r"\d+\.\d+"
.path    r'C:\Users\alice'
.tmpl    r`no \n escapes here`
```

### Comments

Line comments start with `#` and run to the end of the line.
Block comments are delimited by `#(` and `)#` and may span multiple lines:

```usu
# this is a line comment

#(
  this is a block comment
  it can span multiple lines
)#
```

Comments are stripped during lexing and never appear in the AST.

### Unquoted multi-line values

An unquoted value may continue on the next line when the key and value are
separated by a newline. Leading whitespace is stripped via dedent:

```usu
.description
  A long description that lives
  on its own line.
```

The newline at the end of the last line is preserved in the value when the
source has a trailing newline. If you want to fold the lines into a single
space-separated string (as if they were one line), use the `>` folder syntax:

```usu
.summary >
  This whole paragraph becomes
  one space-separated line.
```

The parser also applies `>` folding when `pretty` outputs long strings
(over 100 characters), unless `NoWrap` is set.

### Quoted keys

Key segments that contain spaces, dots, or other special characters must be quoted.
All three quote styles work:

```usu
."key with spaces" value
.'another spaced key' value
.`yet another` value
```

It's possible to include a literal `.` in a key by using a quoted key:

```usu
."host.name" value   # key segment is literally "host.name"
```

### Duplicate keys and merge behavior

When the same key appears more than once the parser merges, never replaces wholesale:

- **Map + map** → fields are merged recursively (deep merge).
- **Array + array** → elements from the second array are appended to the first.
- **Scalar + scalar** → the second value overwrites the first.
- **Type mismatch** → raises `UsuParserError`.

```usu
# Both entries contribute to the same map:
.server.host localhost
.server.port 8080
# result: {.server { host: "localhost", port: "8080" }}

# Arrays with the same key are concatenated:
.numbers [1 2 3]
.numbers [4 5 6]
# result: [1 2 3 4 5 6]
```

### Array append operator

The `+` suffix on a key explicitly appends a single value to an existing array.
If the key has already been set it must hold an array:

```usu
.tags [nim]
.tags+ config
.tags+ parsing
# result: .tags ["nim" "config" "parsing"]
```

Attempting to append to a non-array value raises `UsuParserError`.
If the first use of the key includes the append operator it will set the type as an array and set the value to the first element:

```usu
.tags+ nim
# result: .tags [nim]
```

### Indexed array assignment

Use `[N]` on a key to assign to a specific index. If the array is shorter than
the index, it is padded with `UsuNull` entries:

```
.items[0] first
.items[2] third
# result: .items ["first" null "third"]
```

Negative indices are rejected with `UsuParserError`.


## Parsing

```nim
import usu

let node = parseUsu("""
  .name Alice
  .age  30
""")
```

`parseUsu` returns an `UsuNode`.
For top-level key/value input it returns a `UsuMap`; for a bare array literal it returns a `UsuArray`.
All syntax errors raise `UsuParserError` with a message that includes the byte position in the input string.


## The AST — `UsuNode`

```nim
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
```

Accessing the wrong case field at runtime raises a Nim `FieldDefect`, so always
check `kind` before accessing `fields`, `elems`, or `value`.

You can construct nodes directly for programmatic use:

```nim
let m = newUsuMap({
  "host": newUsuValue("localhost"),
  "port": newUsuValue("8080"),
})
let a = UsuNode(kind: UsuArray, elems: @[newUsuValue("a"), newUsuValue("b")])
let n = newUsuNull()
```

Structural equality is defined on `UsuNode`:

```nim
assert newUsuValue("x") == newUsuValue("x")
assert newUsuValue("x") != newUsuNull()
```

## Accessing Usu

`usu-nim` provides a path-based getter to retrieve nested nodes. Paths use `.` to separate segments and `[N]` for array indices.

```nim
import usu

let node = parseUsu("""
.meta {
  .title "A Simple Usu Document"
}
.numbers [10 20 30]
""")

# Get a nested value
let title = node.get("meta.title").value
assert title == "A Simple Usu Document"

# Get an array element
let second = node.get("numbers[1]").value
assert second == "20"

# Paths can start with an optional '.'
assert node.get(".meta.title").value == "A Simple Usu Document"
```

If a path does not exist, a `KeyError` is raised.

You can combine with `.to(T)` to unmarshal a specific sub-tree:

```nim
type Meta = object
  title: string

let meta = node.get("meta").to(Meta)
assert meta.title == "A Simple Usu Document"
```

### Path Syntax

- `.segment`: Map lookup.
- `segment[N]`: Map lookup followed by array index.
- `[N]`: Array index (if the current node is an array).

If a key segment contains a literal `.` in the map, it must be escaped with `\.` in the path string:

```nim
let val = node.get(r"key\.with\.dots")
```

## Serialization

### Compact output — `$`

The `$` operator produces a single-line, round-trippable representation:

```nim
let node = parseUsu(".name Alice .age 30")
echo $node   # {.name Alice .age 30}
```

Values that contain spaces, newlines, tabs, a leading `.`, or equal the bare
word `null` are automatically backtick-escaped. Map keys that contain spaces
or dots are double-quoted. The output is always valid usu that round-trips
through `parseUsu`.

### Human-readable output — `pretty`

`pretty` produces indented, multi-line output:

```nim
proc pretty*(u: UsuNode, settings: set[UsuPrettySettings] = {}): string
proc pretty*(u: UsuNode, inline: proc(u: UsuNode): bool {.closure.},
             settings: set[UsuPrettySettings] = {}): string
```

By default maps are printed as flat key/value lines and arrays expand vertically:

```nim
echo parseUsu(".key [1 2 3]").pretty
# .key [
#   1
#   2
#   3
# ]
```

**Note:** `pretty` output is considered experimental; the exact formatting may
change between versions, but output always round-trips through `parseUsu`.

#### `UsuPrettySettings`

| Flag            | Effect |
|-----------------|--------|
| `RootBrackets`  | Wrap the root map in `{` `}` |
| `NoWrap`        | Suppress word-wrapping of strings longer than 100 characters |
| `Flatten`       | Collapse all nesting; emit only fully-qualified `key[idx]` leaf paths |
| `QuoteValues`   | Backtick-escape every `UsuValue` regardless of content |

```nim
# wrap root in braces
echo parseUsu(".key value").pretty(settings = {RootBrackets})
# {
#   .key value
# }

# flatten nested structure to dotted paths
echo parseUsu("""
  .a { .b { .c 1 } }
  .items [x y]
""").pretty(settings = {Flatten})
# .a.b.c 1
# .items[0] x
# .items[1] y

# suppress long-string wrapping
echo parseUsu(longLine).pretty(settings = {NoWrap})
```

#### Inline closure

The two-argument `pretty` takes an `inline` closure. When the closure returns
`true` for a node, that node is serialized with `$` (single line) instead of
being expanded. This lets you keep simple arrays or small maps on one line:

```nim
# keep all-value arrays on one line
echo parseUsu(data).pretty do (u: UsuNode) -> bool:
  u.kind == UsuArray and u.elems.allIt(it.kind == UsuValue)
# .key [1 2 3 4 5 6]

# keep specific maps inline
echo parseUsu(data).pretty do (u: UsuNode) -> bool:
  u.kind == UsuMap and "leaf" in u.fields
```


## Marshaling — `toUsu`

`toUsu` converts Nim values to `UsuNode`. All overloads are in `usu/marshal`
and re-exported by `usu`.

| Nim type | `UsuNode` produced |
|----------|-------------------|
| `bool`, `int`, `float`, `string` | `UsuValue` via `$` |
| `enum` | `UsuValue` via `$` |
| `object` | `UsuMap` (field name → child node) |
| `ref object` | `UsuMap` (same as object) |
| `seq[T]`, `openArray[T]` | `UsuArray` |
| `array[N, T]` | `UsuArray` |
| `Table`, `OrderedTable`, etc. | `UsuMap` (key stringified with `$`) |
| `StringTableRef` | `UsuMap` |
| `HashSet`, `OrderedSet`, `set` | `UsuArray` |
| `Option[T]` | `UsuNull` if `none`; otherwise `toUsu(value)` |
| named tuple | `UsuMap` |
| unnamed tuple | `UsuArray` |
| `UsuNode` | identity (returned as-is) |

```nim
type Person = object
  name: string
  age:  int

let p = Person(name: "Alice", age: 30)
echo $p.toUsu()          # {.name Alice .age 30}
echo p.toUsu().pretty()  # .name Alice
                         # .age 30
```

Tuples follow the same key-presence rule as objects. Named tuples become maps;
unnamed tuples become arrays:

```nim
echo $(name: "x", value: 1).toUsu()  # {.name x .value 1}
echo $("x", 1).toUsu()               # [x 1]
```


## Unmarshaling — `fromUsu` and `to`

### The `to` convenience proc

```nim
proc to*[T](node: UsuNode, t: typedesc[T]): T
```

This is the primary entry point. It calls the appropriate `fromUsu` overload
and returns the populated value:

```nim
type Person = object
  name: string
  age:  int

let p = parseUsu(".name Alice .age 30").to(Person)
```

### Built-in `fromUsu` overloads

| Target type | Required `UsuNodeKind` | Conversion |
|-------------|------------------------|------------|
| `string` | `UsuValue` | direct copy of `value` |
| `int` | `UsuValue` | `parseInt` |
| `float` | `UsuValue` | `parseFloat` |
| `bool` | `UsuValue` | `parseBool` (`"true"`/`"false"`/`"1"`/`"0"`) |
| `enum` | `UsuValue` | `parseEnum` (case-sensitive name match) |
| `seq[T]` | `UsuArray` | each element unmarshaled recursively |
| `array[N, T]` | `UsuArray` | length must match exactly |
| `Table[string, T]` etc. | `UsuMap` | each field unmarshaled recursively |
| `StringTableRef` | `UsuMap` | all values as strings |
| `HashSet[T]` etc. | `UsuArray` | elements unmarshaled then included |
| `Option[T]` | any | `UsuNull` → `none`; otherwise `some(fromUsu(node))` |
| named tuple | `UsuMap` or `UsuArray` | by field name or position |
| unnamed tuple | `UsuArray` | by position; length must match |
| `object` / `ref object` | `UsuMap` | see below |
| `UsuNode` | any | identity assignment |

### Object unmarshaling

When unmarshaling into an `object` or `ref object` the parser looks up each
field of the Nim type by name in the `UsuMap`:

- **Missing fields** keep their Nim default values. There is no error for absent keys.
- **Unknown keys** in the usu input are silently ignored.
- **Type mismatches** (wrong `UsuNodeKind` for a field) raise `UsuParserError`.

```nim
type Person = object
  name: string
  age:  int = 35   # default

# Missing "age" → default value is used
let p = parseUsu(".name Alice").to(Person)
assert p.age == 35

# Unknown key "nickname" → silently ignored
let q = parseUsu(".name Alice .nickname Al").to(Person)
assert q.name == "Alice"
```

### Array length requirements

Fixed-size Nim `array` types require an exact element count. A mismatch raises `UsuParserError`:

```nim
let ok  = parseUsu("[1 2 3]").to(array[3, int])   # fine
let bad = parseUsu("[1 2 3]").to(array[2, int])   # UsuParserError
```

`seq` has no such restriction.

### Tuple unmarshaling

Named tuples accept either an `UsuMap` (matched by field name) or an `UsuArray` (matched by position).
Unnamed tuples require an `UsuArray`.
In both cases the element count must match the tuple length:

```nim
("a", 5) == parseUsu("[a 5]").to((string, int))
(letter: "a", num: 5) == parseUsu("[a 5]").to((string, int))
(letter: "a", num: 5) == parseUsu("{.letter a .num 5}").to(tuple[letter: string, num: int])
```

### Numbers

Integer and float values in usu are stored as strings. Nim's `parseInt` and
`parseFloat` are used during unmarshaling.

```nim
type A = object
  i: int
  f: float

let a = parseUsu(".i -2 .f 100_000.0").to(A)
# a.i == -2, a.f == 100000.0
```

A float string like `"15.0"` will fail to unmarshal into an `int` field —
the types in the usu source and the Nim type must be compatible.

### Full example

```nim
import usu

type
  Role = enum Admin, User

  Person = object
    name:   string
    age:    int
    weight: float
    roles:  set[Role]
    job:    Option[string]

const src = """
  .name  John Doe
  .age   15
  .weight 0.16
  .roles [Admin User]
  .job   code monkey
"""

let person = parseUsu(src).to(Person)
echo person.name    # John Doe
echo person.roles   # {Admin, User}
echo person.job     # Some("code monkey")

# round-trip
assert person == parseUsu($person.toUsu()).to(Person)
```


## Extending the Marshaler

### Custom `fromUsu`

Define a `proc fromUsu(v: var YourType, node: UsuNode)` to unmarshal any additional type.
Use `checkKind` to validate the node kind before reading:

```nim
import std/times

proc fromUsu(v: var DateTime, node: UsuNode) =
  checkKind node, UsuValue
  v = parse(node.value, "yyyy-MM-dd")

type Note = object
  date: DateTime

let note = parseUsu(".date 2026-03-19").to(Note)
```

`checkKind` raises `UsuParserError` with a descriptive message if the node kind
does not match. It accepts either a single kind or a set of kinds:

```nim
checkKind node, UsuValue               # exactly UsuValue
checkKind node, {UsuValue, UsuNull}    # either
```

A more involved example: read a value from an environment variable, falling back
to a default written inline:

```nim
type EnvVar = distinct string

proc fromUsu(e: var EnvVar, node: UsuNode) =
  checkKind node, UsuValue
  let val = node.value
  if val.startsWith("!"):
    # "!VAR_NAME optional_default"
    let parts = val.split(" ", maxsplit = 1)
    let key   = parts[0][1..^1]
    let def   = if parts.len > 1: parts[1] else: ""
    e = EnvVar(getEnv(key, def))
  else:
    e = EnvVar(val)
```

### The `postFromUsu` hook

After all fields of an object are populated, the unmarshaler checks whether `postFromUsu` is defined for that type and calls it if so.
This is the right place for derived-field computation or post-load validation:

```nim
type Config = object
  host: string
  port: int
  address: string   # derived

proc postFromUsu(c: var Config) =
  c.address = c.host & ":" & $c.port

let cfg = parseUsu(".host localhost .port 8080").to(Config)
assert cfg.address == "localhost:8080"
```

`postFromUsu` is only called when unmarshaling (not after `toUsu`).


## JSON Interop

Import `usu/json` for bidirectional conversion with `std/json`:

```nim
import usu/json

# UsuNode → JsonNode
let node = parseUsu(".name Alice .age 30")
let j    = %node     # j is a JsonNode JObject

# JsonNode → UsuNode
let j2   = %* { "name": "Alice", "scores": [1, 2, 3] }
let node2 = j2.toUsu()
```

All `UsuValue` nodes become `JString` — numeric and boolean JSON types do not
survive the round-trip back through usu without custom unmarshaling, since the
usu format carries no type information.
