import std/[unittest, json, os]

import usu/[json]
import usu

const currDir = currentSourcePath().parentDir
const outJsonFile = currDir / "simple.json"
const inUsuFile = currDir / "simple.usu"

suite "parsing":
  test "simple":
    let usuStr = readFile(inUsuFile)
    check (%parseUsu(usuStr)) == parseFile(outJsonFile)

