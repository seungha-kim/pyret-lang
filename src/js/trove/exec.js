define(["requirejs", "../js/ffi-helpers", "../js/runtime-anf", "trove/checker"], function(rjs, ffi, runtimeLib, checkerLib) {

  return function(RUNTIME, NAMESPACE) {
    var F = ffi(RUNTIME, NAMESPACE);

    function exec(jsStr, modnameP, params) {
      RUNTIME.checkIf(jsStr, RUNTIME.isString);
      RUNTIME.checkIf(modnameP, RUNTIME.isString);
      var str = RUNTIME.unwrap(jsStr);
      var modname = RUNTIME.unwrap(modnameP);
      var oldDefine = rjs.define;
      var name = RUNTIME.unwrap(NAMESPACE.get("gensym").app(RUNTIME.makeString("module")));

      var newRuntime = runtimeLib.makeRuntime({ 
        stdout: function(str) { process.stdout.write(str); },
        stderr: function(str) { process.stderr.write(str); }
      });
      newRuntime.setParam("command-line-arguments", F.toArray(params).map(RUNTIME.unwrap));

      var checker = newRuntime.getField(checkerLib(newRuntime, newRuntime.namespace), "provide");
      var currentChecker = newRuntime.getField(checker, "make-check-context").app(newRuntime.makeString(modname));
      newRuntime.setParam("current-checker", currentChecker);

      function makeResult(execRt, callingRt, r) {
        if(execRt.isSuccessResult(r)) {
          var pyretResult = r.result;
          return callingRt.makeObject({
              "render-check-results": callingRt.makeFunction(function() {
                var toCall = execRt.getField(checker, "render-check-results");
                var checks = execRt.getField(pyretResult, "checks");
                callingRt.pauseStack(function(restarter) {
                    execRt.run(function(rt, ns) {
                        return toCall.app(checks);
                      }, execRt.namespace, {sync: true},
                      function(printedCheckResult) {
                        if(execRt.isSuccessResult(printedCheckResult)) {
                          if(execRt.isString(printedCheckResult.result)) {
                            restarter(callingRt.makeString(execRt.unwrap(printedCheckResult.result)));
                          }
                        }
                        else if(execRt.isFailureResult(printedCheckResult)) {
                          console.error(printedCheckResult);
                          console.error(printedCheckResult.exn);
                          restarter(callingRt.makeString("There was an exception while formatting the check results"));
                        }
                      });
                  });
              })
            });
        }
        else if(execRt.isFailureResult(r)) {
          console.error("Failed: ", r, r.exn);
          return callingRt.makeObject({
              "failure": r.exn
            });
        }
      }

      function OMGBADIDEA(name, src) {
        var define = function(libs, fun) {
          oldDefine(name, libs, fun);
        }
        eval(src);
      }
      OMGBADIDEA(name, str);
      RUNTIME.pauseStack(function(restarter) {
          require([name], function(a) {
              newRuntime.run(a, newRuntime.namespace, {sync: true}, function(r) {
                  var wrappedResult = makeResult(newRuntime, RUNTIME, r);
                  restarter(wrappedResult);
                });
            });
        });
    }

    return RUNTIME.makeObject({
      provide: RUNTIME.makeObject({
        exec: RUNTIME.makeFunction(exec)
      }),
      answer: NAMESPACE.get("nothing")
    });
  };
});
