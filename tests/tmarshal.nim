import std/[unittest, json, tables, options]

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

suite "marshal":
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
    )[] == parseUsu(
      ".ceo {.name Linus Torvalds} .employees [ {.name John Doe} ]"
    ).to(Company)[]


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

suite "unmarshal":
  test "quotes":
    let strings = @[
      "a value that kas a .key",
      "`a value` <- see backticks",
      "escaped quote: \", single quote: ', backtick quote: `",
    ]
    check parseUsu($strings.toUsu()).to(seq[string]) == strings
