import Testing
@testable import RuriCore

struct ChorusCommitGraphTests {
    typealias Node = ChorusCommitGraph.Node

    @Test func mergeKeepsFirstParentAndJoinsSharedAncestor() throws {
        let rows = try ChorusCommitGraph.layout([
            Node(sha: "merge", parents: ["left", "right"]),
            Node(sha: "left", parents: ["base"]),
            Node(sha: "right", parents: ["base"]),
            Node(sha: "base", parents: [])
        ])
        #expect(rows.map(\.column) == [0, 0, 1, 0])
        #expect(rows[0].bottom.map(\.sha) == ["left", "right"])
        #expect(rows[0].bottom[0].color == rows[0].color)
        #expect(rows[1].bottom.map(\.sha) == ["base", "right"])
        #expect(rows[2].bottom.map(\.sha) == ["base"])
        #expect(rows[2].edges.filter(\.startsAtNode).map(\.to) == [0])
        #expect(rows[3].bottom.isEmpty)
    }

    @Test func paginationKeepsEarlierRowsAndUnresolvedParents() throws {
        let nodes = [Node(sha: "merge", parents: ["left", "right"]), Node(sha: "left", parents: ["base"]), Node(sha: "right", parents: ["base"]), Node(sha: "base", parents: [])]
        let page = try ChorusCommitGraph.layout(Array(nodes.prefix(2)))
        let complete = try ChorusCommitGraph.layout(nodes)
        #expect(page == Array(complete.prefix(2)))
        #expect(page.last?.bottom.map(\.sha) == ["base", "right"])
        for index in 1..<complete.count { #expect(complete[index - 1].bottom == complete[index].top) }
    }

    @Test func octopusAndIndependentRootsKeepAllParents() throws {
        let rows = try ChorusCommitGraph.layout([
            Node(sha: "merge", parents: ["a", "b", "c"]), Node(sha: "other", parents: []),
            Node(sha: "b", parents: []), Node(sha: "a", parents: []), Node(sha: "c", parents: [])
        ])
        #expect(rows[0].edges.count == 3)
        #expect(rows[1].column == 3)
        #expect(!rows[1].incoming)
        #expect(rows[1].bottom.map(\.sha) == ["a", "b", "c"])
        #expect(rows[2].bottom.map(\.sha) == ["a", "c"])
        #expect(rows.last?.bottom.isEmpty == true)
    }

    @Test func rejectsInvalidHistory() {
        #expect(throws: ChorusCommitGraph.InvalidHistory.duplicateCommit) {
            try ChorusCommitGraph.layout([Node(sha: "a", parents: []), Node(sha: "a", parents: [])])
        }
        #expect(throws: ChorusCommitGraph.InvalidHistory.invalidTopologicalOrder) {
            try ChorusCommitGraph.layout([Node(sha: "a", parents: []), Node(sha: "b", parents: ["a"])])
        }
        #expect(throws: ChorusCommitGraph.InvalidHistory.duplicateParent) {
            try ChorusCommitGraph.layout([Node(sha: "a", parents: ["b", "b"])])
        }
    }
}
