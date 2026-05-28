type
  FatalUserError* = object of CatchableError
    exitCode*: int

proc fatal*(message: string; exitCode = 2) {.noreturn.} =
  var error = newException(FatalUserError, message)
  error.exitCode = exitCode
  raise error

