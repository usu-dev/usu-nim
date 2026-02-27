import std/[unittest, json, tables, options, times, os, strutils]

import usu/[json]
import usu

type
  Role = enum
    Admin, User
  Person = object
    name: string
    age: int
    weight: float
    emails: Table[string, string]
    roles: set[Role]
    job: Option[string]
  Company = ref object
    ceo: Person
    employees: seq[Person]

const john = Person(
  name: "John Doe",
  age: 15,
  weight: 0.16,
  emails: {"personal":"john@example.com"}.toTable(),
  roles: {Admin, User},
  job: some("code monkey")
)


const fullUsu = """
.name John Doe
.age 15
.weight 0.16
.emails { .personal john@example.com }
.roles [Admin User]
.job code monkey
"""

proc `==`(a, b: ref object): bool =
  ## dereference then compare
  a[] == b[]

type EnvVar = distinct string
proc `$`(v: EnvVar): string {.borrow.}
proc `==`(a, b: EnvVar): bool {.borrow.}
proc fromUsu(e: var EnvVar, node: UsuNode) =
  ## custom parsing hook to populate a value
  ## from environment var with an optional default
  checkKind node, UsuValue
  let val = node.value
  if not val.startsWith("!"):
    e = EnvVar(val)
  else:
    let key = val.split(" ")[0] # [1..^1]
    let rest =
      if val.len == key.len: ""
      else: val[key.len+1..^1]
    e = EnvVar(getEnv(key[1..^1], rest))

proc fromUsu(d: var DateTime, node: UsuNode) =
  checkKind node, UsuValue
  d = parse(node.value, "yyyy.MM.dd")

proc fromUsu(v: var JsonNode, node: UsuNode) =
  checkKind node, UsuValue
  v = parseJson(node.value)

suite "unmarshal":
  test "object":
    check john == parseUsu(fullUsu).to(Person)
    check:
      Person(name: "John Doe") == parseUsu(""".name John Doe""").to(Person)
    check:
      Person(name: "John Doe") == parseUsu(""".name John Doe .unknown ??""").to(Person)
    expect(ValueError):
      discard parseUsu(""".age 15.0""").to(Person)
    check Company(
      ceo: Person(name: "Linus Torvalds"),
      employees: @[Person(name: "John Doe")]
    ) == parseUsu(
      ".ceo {.name Linus Torvalds} .employees [ {.name John Doe} ]"
    ).to(Company)

  test "round-trip":
    check john == parseUsu($john.toUsu()).to(Person)

  test "tuples":
    check ("a", 5) == parseUsu("[a 5]").to((string,int))
    check (letter: "a", num: 5) == parseUsu("[a 5]").to((string, int))
    check ("a", 5) == parseUsu("{.letter a .num 5}").to(tuple[letter: string, num: int])

  test "enums":
    type Color = enum
      Red, Blue, Green
    let list = @[Red, Blue, Green]
    check list == parseUsu("[Red Blue Green]").to(seq[Color])
    expect(ValueError):
      check @[Red, Blue, Green] == parseUsu("[Yellow]").to(seq[Color])
    check $toUsu(list) == $parseUsu("[Red Blue Green]")

  test "optionals":
    type B = object
      str: string
    type A = object
      opt: Option[B]

    check A(opt: some(B(str: "string"))) == parseUsu("""
      .opt {.str string}
    """).to(A)
    check A(opt: none(B)) == parseUsu("""
      .opt null
    """).to(A)
  
  test "usu node":
    type A = object
      usu: UsuNode
    check A(usu: newUsuValue("some usu")) == parseUsu("""
      {.usu some usu}
    """).to(A)

    type B = object
      key: A

    check B(
      key: A(usu: parseUsu(".map {.key val}"))
    ) == parseUsu("""
    .key {.usu {.map {.key val}}}
    """
    ).to(B)

  test "custom parsing":
    type A = object
      date: DateTime
    check A(date: parse("1970.01.01", "yyyy.MM.dd")) == parseUsu(".date 1970.01.01").to(A)
    type B = object
      e: EnvVar

    putEnv("TEST", "VAL")
    check B(e: EnvVar("VAL")) == parseUsu(".e !TEST").to(B)
    check B(e: EnvVar("VAL2")) == parseUsu(".e !TEST2 VAL2").to(B)

    type C = object
      json: JsonNode

    check C(
      json: (%* {"numbers": [1, 2, 3]})
    ) == parseUsu("""
      .json `{"numbers": [1, 2, 3]}`
    """).to(C)

  test "seqs + arrays":
    check @[1, 2, 3] == parseUsu("[1 2 3]").to(seq[int])
    check [1, 2, 3] == parseUsu("[1 2 3]").to(array[3, int])

    expect(UsuParserError):
      discard parseUsu("[1 2 3]").to(array[2, int])


suite "marshal":
  test "quotes":
    let strings = @[
      "a value that kas a .key",
      "`a value` <- see backticks",
      "escaped quote: \", single quote: ', backtick quote: `",
    ]
    check parseUsu($strings.toUsu()).to(seq[string]) == strings
  test "optionals":
    type B = object
      str: string
    type A = object
      opt: Option[B]

    const a = A(opt: some(B(str: "string")))
    check parseUsu($a.toUsu()).to(A) == a


  test "usu node":
    type A = object
      usu: UsuNode
    const a = A(usu: newUsuValue("some usu"))
    check parseUsu($a.toUsu()).to(A) == a


