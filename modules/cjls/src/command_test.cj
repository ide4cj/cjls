package cjls

import std.argopt.ArgumentParseException
import std.env.getWorkingDirectory
import std.fs.Path

@Test
class CommandTest {
    @TestCase
    func noArgumentsServesAsAnEditorStartsTheServer() {
        // act, assert
        @Expect(match (parseCommand([])) {
            case Serve => true
            case _ => false
        })
    }

    @TestCase
    func projectIsOfTheWorkingDirectoryUnlessDirSaysOtherwise() {
        // act
        let none = parseCommand(["project"])
        let separate = parseCommand(["project", "--dir", "sub"])
        let joined = parseCommand(["project", "--dir=sub"])
        let short = parseCommand(["project", "-d", "sub"])

        // assert
        let sub = getWorkingDirectory().join("sub")
        @Expect(dirOf(none), Some(getWorkingDirectory()))
        @Expect(dirOf(separate), Some(sub))
        @Expect(dirOf(joined), Some(sub))
        @Expect(dirOf(short), Some(sub))
    }

    @TestCase
    func dirGivenTwiceIsTheLast() {
        // act
        let command = parseCommand(["project", "--dir", "a", "-d", "b"])

        // assert
        @Expect(dirOf(command), Some(getWorkingDirectory().join("b")))
    }

    @TestCase
    func anUnknownCommandOrOptionIsAUsageError() {
        // act, assert
        @AssertThrows[ArgumentParseException](parseCommand(["frob"]))
        @AssertThrows[ArgumentParseException](parseCommand(["project", "sub"]))
        @AssertThrows[ArgumentParseException](parseCommand(["project", "--frob"]))
        @AssertThrows[ArgumentParseException](parseCommand(["project", "--dir"]))
        @AssertThrows[ArgumentParseException](parseCommand(["project", "--dir="]))
    }
}

func dirOf(command: Command): ?Path {
    match (command) {
        case PrintProject(dir) => dir
        case _ => Option<Path>.None
    }
}
