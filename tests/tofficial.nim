import std/[algorithm, json, os, sugar, unittest]

import usu
import usu/json

let officialPath = currentSourcePath().parentDir / "official/cases"
var cases = collect:
  for kind, path in walkDir(officialPath):
    if kind == pcDir:
      path
sort cases

suite "official":
  for path in cases:
    test path.tailDir():
        check ( % parseUsu(readFile(path / "in.usu"))) == parseFile(path / "out.json")
