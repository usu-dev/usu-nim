import std/[os, strutils, sequtils]

task tests, "run tests":
  selfExec "c -r tests/tester.nim"

const version {.define.} = ""

proc getCommit(): string =
  when defined(version): return version
  let (output, code) = gorgeEx("git rev-parse HEAD")
  if code != 0: quit output
  return output

proc fixUpDocs(name = "usu") =
  withDir "public":
    mvFile(name & ".html", "index.html")
    for file in walkDirRec(".", {pcFile}):
      writeFile(file):
        readFile(file).multiReplace({
          name &  ".html": "index.html", # fix renamed file links
          ">src/": ">"                   # drop 'src/' from titles
        })

when defined(docs):
  --project
  --index:on
  --warning:"LanguageXNotSupported:off"
  --git.url:"https://github.com/usu-dev/usu-nim"
  --outdir:public
  switch("git.commit", getCommit())

task docs, "build docs with fixup":
  let cmd = "doc -d:docs $1 src/usu.nim" % [
      (when defined(version): " -d:version:" & version else: "")
    ]
  selfExec cmd
  fixUpDocs()
