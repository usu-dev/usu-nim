import std/[os, strformat]

task tests, "run tests":
  selfExec "c -r tests/tester.nim"

proc getCommit(): string =
  let (output, code) = gorgeEx("git rev-parse HEAD")
  if code != 0:
    quit output
  return output

const version {.define.} = ""

task docs, "Deploy doc html + search index to public/ directory":
  let
    name = "usu"
    tag =
      when defined(version): version
      else: getCommit()
    srcFile = "src" / (name & ".nim")
    gitUrl = fmt"https://github.com/usu-dev/{name}-nim"
  selfExec fmt"""doc --project --index:on --git.url:{gitUrl} --git.commit:"{tag}" --outdir:public {srcFile}"""
  withDir "public":
    mvFile(name & ".html", "index.html")
    for file in walkDirRec(".", {pcFile}):
      # As we renamed the file, we need to rename that in hyperlinks
      exec(fmt"sed -i -r 's|{name}\.html|index.html|g' {file}")
      # drop 'src/' from titles
      exec(fmt"sed -i -r 's/<(.*)>src\//<\1>/' {file}")
