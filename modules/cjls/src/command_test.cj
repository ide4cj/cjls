package cjls

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
    func anUnknownCommandOrOptionIsAUsageError() {
        // act, assert
        @AssertThrows[UsageException](parseCommand(["frob"]))
        @AssertThrows[UsageException](parseCommand(["project", "sub"]))
        @AssertThrows[UsageException](parseCommand(["project", "--dir"]))
        @AssertThrows[UsageException](parseCommand(["project", "--dir="]))
        @AssertThrows[UsageException](parseCommand(["project", "--dir", "a", "--dir", "b"]))
    }
}

func dirOf(command: Command): ?Path {
    match (command) {
        case PrintProject(dir) => dir
        case _ => Option<Path>.None
    }
}
