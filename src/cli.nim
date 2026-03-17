import std/[json, parseopt, strutils]
import
  ./usu,
  ./usu/json

var
  usuFile: string
  showJson: bool
  showUsu: bool
  settings: set[UsuPrettySettings]

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    usuFile = key
  of cmdLongOption:
    case key
    of "usu": showUsu = true
    of "json": showJson = true
    of "settings":
      let setting = parseEnum[UsuPrettySettings](val)
      settings.incl setting
  of cmdShortOption:
    quit "no short options"
  of cmdEnd: assert false

if usuFile == "":
  quit "expected a file path"

let u = parseUsu(readFile(usuFile))

if showJson:
  echo pretty(%* u)

if showUsu:
  echo pretty(u, settings = settings)
