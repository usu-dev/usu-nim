import std/[unittest, json, os]

import usu/[json]
import usu

const currDir = currentSourcePath().parentDir
const outJsonFile = currDir / "simple.json"
const inUsuFile = currDir / "simple.usu"
const usuStr = readFile(inUsuFile)

suite "parsing":
  test "simple":
    check (%parseUsu(usuStr)) == parseFile(outJsonFile)

  test "getters":
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

    check u["meta"]["title"].value == "A Simple Usu Document"
    check u["numbers"][2].value == "3"
