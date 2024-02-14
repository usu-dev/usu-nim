import std/[os, strformat]

task test, "run tests":
  selfExec "c -r tests/tusu.nim"
  selfExec "c -r tests/tofficial.nim"


task docs, "Deploy doc html + search index to public/ directory":
  let
    name = "usu"
    version = gorgeEx("git describe --tags --match 'v*'").output
    srcFile = "src" / (name & ".nim")
    gitUrl = fmt"https://github.com/usu-dev/{name}-nim"
  selfExec fmt"doc --project --index:on --git.url:{gitUrl} --git.commit:{version} --outdir:public {srcFile}"
  withDir "public":
    mvFile(name & ".html", "index.html")
    for file in walkDirRec(".", {pcFile}):
      # As we renamed the file, we need to rename that in hyperlinks
      exec(fmt"sed -i -r 's|{name}\.html|index.html|g' {file}")
      # drop 'src/' from titles
      exec(fmt"sed -i -r 's/<(.*)>src\//<\1>/' {file}")
