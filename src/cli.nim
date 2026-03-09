import std/[json, os]
import ./usu
import ./usu/json

if (commandLineParams().len) != 1:
  stderr.writeLine "expected positional argument for usu file"
  quit 1
let usuFile = commandLineParams()[0]
let usuStr = readFile(usuFile)
let u = parseUsu(usuStr)
# echo pretty(u)
echo pretty(%* u)

