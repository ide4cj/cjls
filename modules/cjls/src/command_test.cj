package cjls

import std.env.getWorkingDirectory

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
    func projectTakesADirectoryRelativeToTheWorkingOne() {
        // act
        let given = parseCommand(["project", "sub"])
        let none = parseCommand(["project"])

        // assert
        @Expect(match (given) {
            case PrintProject(dir) => dir == getWorkingDirectory().join("sub")
            case _ => false
        })
        @Expect(match (none) {
            case PrintProject(dir) => dir == getWorkingDirectory()
            case _ => false
        })
    }

    @TestCase
    func anUnknownCommandIsAUsageError() {
        // act, assert
        @AssertThrows[UsageException](parseCommand(["frob"]))
        @AssertThrows[UsageException](parseCommand(["project", "a", "b"]))
    }
}
