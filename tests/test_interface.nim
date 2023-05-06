## TODO: Split these up
## Maybe see if I can store a base state of the process before each tests runs and roll back after
import osproc, streams, os
import unittest

let
  testRcfilePath = getCurrentDir() / "inim.ini"
  testDirName = absolutePath("tests/test_dir")

proc getResponse(inStream, outStream: var Stream, lines: seq[string] = @[]): string =
  ## Write all lines in `lines` to inStream and read the result
  for line in lines:
    inStream.writeLine(line)
  inStream.flush()
  outStream.readLine()

suite "Interface Tests":

  setup:
    # Start our process and create links to our stdin/stdout
    var process = startProcess(
      "bin/inim",
      workingDir = "",
      args = @["--rcFilePath=" & testRcfilePath, "--showHeader=false",
          "--withTools"],
      options = {poDaemon}
    )

    var
      inputStream = process.inputStream
      outputStream = process.outputStream

  test "Test Standard Syntax works":
    let defLines = @[
      """let a = "A"""",
      "a"
    ]
    require getResponse(inputStream, outputStream, defLines) == "A : string"

    let typeLines = @[
      "type B = object",
      "  c: string", # Have to add indents in manually for tests now
      "",
      "B"
    ]
    require getResponse(inputStream, outputStream, typeLines) == "B : B"
    require getResponse(inputStream, outputStream, @["B.c"]) == "string : string"

    let varLines = @[
      """var g = B(c: "C")""",
      "g"
    ]
    require getResponse(inputStream, outputStream, varLines) == """(c: "C") : B"""

    # Make sure we're not creating more errors when we type in code that wouldn't compile normally
    let jankLines = @[
      """proc adderNoReturnNoType(a: float, b: float) = a + b""",
    ]

    # Check for both responses to work with stable vs devel of nim
    require getResponse(inputStream, outputStream, jankLines) in @[
      """Error: expression 'a + b' is of type 'float' and has to be used (or discarded)""",
      """Error: expression 'a + b' is of type 'float' and has to be discarded"""
    ]

    # Check indentation
    let ifLines = @[
      """if true:""",
      """  echo "TRUE"""",
      """else:""",
      """  echo "FALSE"""",
      """""",
    ]
    require getResponse(inputStream, outputStream, ifLines) == """TRUE"""

    inputStream.writeLine("quit")
    inputStream.flush()
    assert outputStream.atEnd()
    process.close()

  test "Test commands":
    # Test cd
    let chdirLines = @[
      """cd "tests/test_dir"""",
    ]
    require getResponse(inputStream, outputStream, chdirLines) == testDirName & " : string"

    # Test ls
    let lsLines = @[
      """ls()""",
    ]
    require getResponse(inputStream, outputStream, lsLines) == """@["a1", "a2"] : seq[string]"""

    # Test pwd
    let pwdLines = @[
      """pwd()""",
    ]
    require getResponse(inputStream, outputStream, pwdLines) == testDirName & " : string"

    let callLines = @[
      """call "echo A"""",
    ]
    require getResponse(inputStream, outputStream, callLines) == "A"
    inputStream.writeLine("quit")
    inputStream.flush()
    process.close()

  # Finally, delete our RCfile path
  if existsFile(testRcfilePath):
    removeFile(testRcfilePath)

suite "Argument Tests":

  test "Test srcFile runtime output echoes to stdout":
    # Start our process and create links to our stdin/stdout
    var process = startProcess(
      "bin/inim",
      workingDir = "",
      args = @["--rcFilePath=" & testRcfilePath, "--showHeader=false",
               "--withTools", "-s=tests/test_error_output.nim"],
      options = {poDaemon}
    )

    var
      inputStream = process.inputStream
      outputStream = process.outputStream

    # Quit straight away, but check that the runtime output of the file is
    # printed to stdout
    let defLines = @[
      "quit"
    ]
    let resp = getResponse(inputStream, outputStream, defLines) == """@["a", "b", "c"]"""
