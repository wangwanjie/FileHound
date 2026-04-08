import Testing
@testable import FileHound

struct QueryCompilerTests {
    @Test
    func compilesNestedGroupsAndExclusions() throws {
        let query = SearchQuery(
            scope: .roots(["/Users/VanJay"]),
            rootGroup: .all([
                .rule(.nameContains("report")),
                .any([
                    .rule(.extensionIs("txt")),
                    .rule(.extensionIs("md"))
                ]),
                .exclude(.pathContains("/Library/"))
            ])
        )

        let compiled = try QueryCompiler().compile(query)

        #expect(compiled.requiresContentScan == false)
        #expect(compiled.rootPaths == ["/Users/VanJay"])
        #expect(compiled.excludedPathFragments.contains("/Library/"))
    }

    @Test
    func detectsContentRulesInNestedGroups() throws {
        let query = SearchQuery(
            scope: .roots(["/Users/VanJay/Documents"]),
            rootGroup: .all([
                .any([
                    .rule(.nameContains("notes")),
                    .rule(.contentContains("needle"))
                ])
            ])
        )

        let compiled = try QueryCompiler().compile(query)

        #expect(compiled.requiresContentScan == true)
    }
}
