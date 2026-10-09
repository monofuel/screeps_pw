import
  std/json,
  policies, rules

proc inputPath(): cstring {.importjs: "(() => process.argv[2])()".} =
  ## Read the diagnostic input argument.

proc print(value: cstring) {.importjs: "process.stdout.write(#)".} =
  ## Emit the normalized module table for native tests.

proc reject(value: cstring) {.importjs: "(process.stderr.write(#), process.exitCode = 2)".} =
  ## Distinguish participant rejection from infrastructure failure.

try:
  print(cstring($loadPolicy(inputPath()) & "\n"))
except PolicyError as error:
  reject(cstring(error.msg & "\n"))
