package loupe

import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.*

@Test
class MultiplatformCallHierarchyTest {
    @TestCase
    func commonSpecificAndCallPositionsHaveOneFunctionWithTheSpecificBody() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat
            public common func target(): Unit
            //- /plat/linux/plat.cj module=plat package=plat
            features { os.linux }
            package plat
            func leaf(): Unit {}
            public specific func target(): Unit { leaf() }
            //- /app/main.cj module=app package=app deps=plat
            package app
            import plat.target
            func caller(): Unit { target(); target() }
            "#
                )
        let db = fixture.database()
        let common = fixture.files[0]
        let specific = fixture.files[1]
        let app = fixture.files[2]

        // act
        let fromCommon = prepareCallHierarchy(db, common.fileId, offsetIn(common.text, "target"))
        let fromSpecific =
            prepareCallHierarchy(db, specific.fileId, offsetIn(specific.text, "target"))
        let fromCall = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "target();"))
        let caller = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "caller"))[0]
        let calls = outgoingCalls(db, caller)

        // assert
        @Expect(fromCommon, fromSpecific)
        @Expect(fromCall, fromSpecific)
        @Expect(fromSpecific.size, 1)
        @Expect(fromSpecific[0].target.fileId, specific.fileId)
        @Expect(calls.map { it => it.item }, fromSpecific)
        @Expect(calls[0].ranges.size, 2)
        @Expect(incomingCalls(db, fromCommon[0])[0].item, caller)
        @Expect(incomingCalls(db, fromCommon[0])[0].ranges, calls[0].ranges)
        @Expect(outgoingCalls(db, fromCommon[0]).map { it => it.item.name }, ["leaf"])
    }

    @TestCase
    func commonMethodsAndInitializersUseTheirSpecificDeclarations() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat
            public common class Host {
                public common init()
                public common func run(): Unit
            }
            //- /plat/linux/plat.cj module=plat package=plat
            features { os.linux }
            package plat
            func leaf(): Unit {}
            public specific class Host {
                public specific init() { leaf() }
                public specific func run(): Unit { leaf() }
            }
            //- /app/main.cj module=app package=app deps=plat
            package app
            import plat.Host
            func caller(): Unit { Host().run() }
            "#
                )
        let db = fixture.database()
        let common = fixture.files[0]
        let specific = fixture.files[1]
        let app = fixture.files[2]
        let caller = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "caller"))[0]

        // act
        let calls = outgoingCalls(db, caller)

        // assert
        @Expect(calls.map { it => it.item.name }, ["run", "init"])
        for (name in ["run", "init"]) {
            let fromCommon = prepareCallHierarchy(db, common.fileId, offsetIn(common.text, name))
            let fromSpecific =
                prepareCallHierarchy(db, specific.fileId, offsetIn(specific.text, name))
            @Expect(fromCommon, fromSpecific)
            @Expect(fromSpecific.size, 1)
            @Expect(fromSpecific[0].target.fileId, specific.fileId)
            @Expect(incomingCalls(db, fromCommon[0]).map { it => it.item }, [caller])
            @Expect(outgoingCalls(db, fromCommon[0]).map { it => it.item.name }, ["leaf"])
        }
    }

    @TestCase
    func bodiesOnlyDeclaredInCommonRemainCallersAndCallees() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /plat/common/plat.cj module=plat package=plat
            @NonProduct
            features {}
            package plat
            public common func fallback(): Unit { leaf() }
            public common class Host {
                public common init()
                public common func run(): Unit
                public func describe(): Unit { run(); fallback() }
            }
            //- /plat/linux/plat.cj module=plat package=plat
            features { os.linux }
            package plat
            func leaf(): Unit {}
            public specific class Host {
                public specific init() {}
                public specific func run(): Unit {}
            }
            //- /app/main.cj module=app package=app deps=plat
            package app
            import plat.Host
            func caller(): Unit { Host().describe() }
            "#
                )
        let db = fixture.database()
        let common = fixture.files[0]
        let app = fixture.files[2]
        let describe = prepareCallHierarchy(db, common.fileId, offsetIn(common.text, "describe"))[0]
        let caller = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "caller"))[0]

        // act
        let calls = outgoingCalls(db, describe)
        let callerCalls = outgoingCalls(db, caller)

        // assert
        @Expect(calls.map { it => it.item.name }, ["run", "fallback"])
        @Expect(calls[0].item.target.fileId, fixture.files[1].fileId)
        @Expect(calls[1].item.target.fileId, common.fileId)
        @Expect(outgoingCalls(db, calls[1].item).map { it => it.item.name }, ["leaf"])
        @Expect(incomingCalls(db, calls[0].item).map { it => it.item }, [describe])
        @Expect(callerCalls[0].item, describe)
        @Expect(incomingCalls(db, describe).map { it => it.item }, [caller])
    }

    @TestCase
    func callsKeepTheSelectedSpecificOverload() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /plat/common/plat.cj module=plat package=plat
            package plat
            public common func target(x: Int64): Unit
            public common func target(x: Bool): Unit
            //- /plat/linux/plat.cj module=plat package=plat
            package plat
            public specific func target(x: Int64): Unit {}
            public specific func target(x: Bool): Unit {}
            //- /app/main.cj module=app package=app deps=plat
            package app
            import plat.target
            func caller(): Unit { target(true) }
            "#
                )
        let db = fixture.database()
        let specific = fixture.files[1]
        let app = fixture.files[2]
        let caller = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "caller"))[0]
        let selected =
            prepareCallHierarchy(db, specific.fileId, offsetIn(specific.text, "target(x: Bool)"))

        // act
        let fromCall = prepareCallHierarchy(db, app.fileId, offsetIn(app.text, "target(true)"))
        let calls = outgoingCalls(db, caller)

        // assert
        @Expect(fromCall, selected)
        @Expect(calls.map { it => it.item }, selected)
        @Expect(calls[0].ranges.size, 1)
        @Expect(incomingCalls(db, selected[0]).map { it => it.item }, [caller])
        let other =
            prepareCallHierarchy(db, specific.fileId, offsetIn(specific.text, "target(x: Int64)"))[
                0
            ]
        @Expect(incomingCalls(db, other).isEmpty())
    }

    @TestCase
    func anExcludedSourceSetHasNoHierarchyOrCallEdges() {
        // arrange
        let fixture =
            Fixture
                .parse(
                    #"
            //- /plat/common/plat.cj module=plat package=plat
            package plat
            public common func target(): Unit
            //- /plat/linux/plat.cj module=plat package=plat
            package plat
            public specific func target(): Unit {}
            func caller(): Unit { target() }
            //- /plat/windows/plat.cj module=plat package=plat inactive=windows
            package plat
            public specific func target(): Unit { ignored() }
            func ignored(): Unit { target() }
            "#
                )
        let db = fixture.database()
        let specific = fixture.files[1]
        let inactive = fixture.files[2]
        let target = prepareCallHierarchy(db, specific.fileId, offsetIn(specific.text, "target"))[0]

        // act
        let fromInactive =
            prepareCallHierarchy(db, inactive.fileId, offsetIn(inactive.text, "target"))
        let incoming = incomingCalls(db, target)

        // assert
        @Expect(fromInactive.isEmpty())
        @Expect(incoming.map { it => it.item.name }, ["caller"])
        @Expect(incoming[0].item.target.fileId, specific.fileId)
        @Expect(outgoingCalls(db, target).isEmpty())
    }
}
