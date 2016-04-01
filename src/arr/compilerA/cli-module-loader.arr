provide *
import namespace-lib as N
import runtime-lib as R
import load-lib as L
import either as E
import ast as A
import pathlib as P
import render-error-display as RED
import file("js-ast.arr") as J
import file("concat-lists.arr") as C
import file("compile-lib.arr") as CL
import file("compile-structs.arr") as CS
import file("locators/file.arr") as FL
import file("locators/legacy-path.arr") as LP
import file("locators/builtin.arr") as BL

j-fun = J.j-fun
j-var = J.j-var
j-id = J.j-id
j-method = J.j-method
j-block = J.j-block
j-true = J.j-true
j-false = J.j-false
j-num = J.j-num
j-str = J.j-str
j-return = J.j-return
j-assign = J.j-assign
j-if = J.j-if
j-if1 = J.j-if1
j-new = J.j-new
j-app = J.j-app
j-list = J.j-list
j-obj = J.j-obj
j-dot = J.j-dot
j-bracket = J.j-bracket
j-field = J.j-field
j-dot-assign = J.j-dot-assign
j-bracket-assign = J.j-bracket-assign
j-try-catch = J.j-try-catch
j-throw = J.j-throw
j-expr = J.j-expr
j-binop = J.j-binop
j-and = J.j-and
j-lt = J.j-lt
j-eq = J.j-eq
j-neq = J.j-neq
j-geq = J.j-geq
j-unop = J.j-unop
j-decr = J.j-decr
j-incr = J.j-incr
j-not = J.j-not
j-instanceof = J.j-instanceof
j-ternary = J.j-ternary
j-null = J.j-null
j-parens = J.j-parens
j-switch = J.j-switch
j-case = J.j-case
j-default = J.j-default
j-label = J.j-label
j-break = J.j-break
j-while = J.j-while
j-for = J.j-for

clist = C.clist


type Either = E.Either

type CLIContext = {
  current-load-path :: String
}

fun module-finder(ctxt :: CLIContext, dep :: CS.Dependency):
  cases(CS.Dependency) dep:
    | dependency(protocol, args) =>
      if protocol == "file":
        clp = ctxt.current-load-path
        this-path = dep.arguments.get(0)
        real-path = P.join(clp, this-path)
        new-context = ctxt.{current-load-path: P.dirname(real-path)}
        locator = FL.file-locator(real-path, CS.standard-globals)
        CL.located(locator, new-context)
      else if protocol == "legacy-path":
        CL.located(LP.legacy-path-locator(dep.arguments.get(0)), ctxt)
      else:
        raise("Unknown import type: " + protocol)
      end
    | builtin(modname) =>
      CL.located(BL.make-builtin-locator(modname), ctxt)
  end
end

fun compile(path, options):
  base-module = CS.dependency("file", [list: path])
  base = module-finder({current-load-path: P.resolve("./")}, base-module)
  wl = CL.compile-worklist(module-finder, base.locator, base.context)
  compiled = CL.compile-program(wl, options)
  compiled
end

fun run(path, options):
  base-module = CS.dependency("file", [list: path])
  base = module-finder({current-load-path: P.resolve("./")}, base-module)
  wl = CL.compile-worklist(module-finder, base.locator, base.context)
  r = R.make-runtime()
  result = CL.compile-and-run-worklist(wl, r, options)
  cases(Either) result:
    | right(answer) =>
      if L.is-success-result(answer):
        print(L.render-check-results(answer))
      else:
        print(L.render-error-message(answer))
        raise("There were execution errors")
      end
      result
    | left(errors) =>
      print-error("Compilation errors:")
      for lists.each(e from errors):
        print-error(RED.display-to-string(e.render-reason(), torepr, empty))
      end
      raise("There were compilation errors")
  end
end

fun build-standalone(path, options):
  shadow options = options.{ compile-module: true }

  base-module = CS.dependency("file", [list: path])
  base = module-finder({current-load-path: P.resolve("./")}, base-module)
  wl = CL.compile-worklist(module-finder, base.locator, base.context)
  compiled = CL.compile-program(wl, options)

  define-name = j-id(A.s-name(A.dummy-loc, "define"))

  static-modules = j-obj(for C.map_list(w from wl):
    loadable = compiled.modules.get-value-now(w.locator.uri())
    cases(CL.Loadable) loadable:
      | module-as-string(_, _, rp) =>
        cases(CS.CompileResult) rp:
          | ok(code) =>
            j-field(w.locator.uri(), J.j-raw-code(code.pyret-to-js-runnable()))
          | err(problems) =>
            for lists.each(e from problems):
              print-error(RED.display-to-string(e.render-reason(), torepr, empty))
            end
            raise("There were compilation errors")
        end
      | pre-loaded(provides, _, _) =>
        raise("Cannot serialize pre-loaded: " + torepr(provides.from-uri))
    end
  end)

  depmap = j-obj(for C.map_list(w from wl):
    deps = w.dependency-map
    j-field(w.locator.uri(),
      j-obj(for C.map_list(k from deps.keys-now().to-list()):
        j-field(k, j-str(deps.get-value-now(k).uri()))
      end))
  end)

  natives = j-list(true, for fold(natives from [clist:], w from wl):
    C.map_list(lam(r): j-str(r.path) end, w.locator.get-native-modules()) + natives
  end)

  to-load = j-list(false, for C.map_list(w from wl):
    j-str(w.locator.uri())
  end)

  prog = j-block([clist:
      j-app(define-name, [clist: natives, j-fun([clist:],
        j-block([clist:
          j-return(j-obj([clist:
            j-field("staticModules", static-modules),
            j-field("depMap", depmap),
            j-field("toLoad", to-load)
          ]))
        ]))
      ])
    ])

  print(prog.tosource().pretty(80).join-str("\n"))
end
