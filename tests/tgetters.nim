import std/[unittest, json, os]

import usu/[json]
import usu

template checkException(msg: string, body: untyped) =
  try:
    body
  except:
    check getCurrentExceptionMsg() == msg


const currDir = currentSourcePath().parentDir
const inUsuFile = currDir / "simple.usu"
const usuStr = readFile(inUsuFile)

suite "getters":
  test "simple":
    let u = parseUsu(usuStr)
    check u.get("meta.title").value == "A Simple Usu Document"
    check u.get(".meta.title").value == "A Simple Usu Document"
    expect KeyError:
      discard u.get("unknown")

    check u.get("numbers[2]").value == "3"

    expect KeyError:
      discard u.get("numbers[10]")

    check u.get("steps").to(OrderedTable[string, string]) == {
        "one": "First Step",
        "two": "Second Step",
        "three": "Third Step"
      }.toOrderedTable()

    expect KeyError:
      discard u.get("numbers.key")

    check u["numbers"][2].value == "3"

  test  "nested":
    const input = """
  .key.key2.key3 5
  .key.key4 [
    {.key6.key8 7}
  ]
  .key.key5 [
    [1 2 3]
  ]

  ."dotted.key" val
  """
    let u = parseUsu(input)
    check u.get("key.key2") == newUsuMap([("key3", newUsuValue($5))])
    check u.get(".key.key2.key3") == newUsuValue($5)
    check u.get("key.key4[0].key6.key8") == newUsuValue("7")
    check u.get(".key.key5[0][1]") == newUsuValue("2")
    check u.get(r"dotted\.key") == newUsuValue("val")

    checkException("key: key2, expected UsuArray, got: UsuMap"):
      discard u.get("key.key2[0]")

    checkException("index: 1, is out of bounds: 0..0"):
      discard u.get("key.key5[1]")

