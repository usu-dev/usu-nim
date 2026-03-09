import std/[sequtils, unittest]
import usu

suite "pretty":
  test "settings":
    check "{\n  .key value\n}" == parseUsu(".key value").pretty(settings = {RootBrackets})
    let long = ".lorem-ipsum Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
    check """
.lorem-ipsum >
  Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
  incididunt ut labore et dolore magna aliqua.""" == parseUsu(long).pretty()
    check long == parseUsu(long).pretty(settings = {NoWrap})


    check ".first `val`\n.second `val`" == parseUsu(".first val .second val").pretty(settings = {QuoteValues})

    check ".nest.nested.nesteded val\n.key.list[0] val\n.key.list[1] val" ==  parseUsu(
    """
    .nest {
      .nested {
        .nesteded val
      }
    }
    .key.list [val val]
    """
    ).pretty(settings = {Flatten})

  test "inliner":
    let data = ".key [1 2 3 4 5 6]"
    check data == (parseUsu(data).pretty do (u: UsuNode) -> bool:
        u.kind == UsuArray and u.elems.allIt(it.kind == UsuValue)
      )
    let maps = """.key {
  .key2 {.key3 map}
}"""
    check maps == (parseUsu(maps).pretty do (u: UsuNode) -> bool:
        u.kind == UsuMap and "key3" in u.fields
      )


