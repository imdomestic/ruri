import Foundation

public enum ChorusCommitGraph {
    public struct Node: Equatable, Sendable {
        public let sha: String
        public let parents: [String]
        public init(sha: String, parents: [String]) { self.sha = sha; self.parents = parents }
    }
    public struct Lane: Equatable, Sendable {
        public let sha: String
        public let color: Int
    }
    public struct Edge: Equatable, Sendable {
        public let from: Int
        public let to: Int
        public let color: Int
        public let startsAtNode: Bool
    }
    public struct Row: Equatable, Identifiable, Sendable {
        public var id: String { sha }
        public let sha: String
        public let column: Int
        public let color: Int
        public let incoming: Bool
        public let top: [Lane]
        public let bottom: [Lane]
        public let edges: [Edge]
        public var width: Int { max(column + 1, top.count, bottom.count) }
    }
    public enum InvalidHistory: Error, Equatable { case duplicateCommit, invalidTopologicalOrder, duplicateParent }

    public static func layout(_ nodes: [Node]) throws -> [Row] {
        var lanes: [Lane] = [], seen = Set<String>(), rows: [Row] = [], nextColor = 0
        for node in nodes {
            guard seen.insert(node.sha).inserted else { throw InvalidHistory.duplicateCommit }
            guard Set(node.parents).count == node.parents.count else { throw InvalidHistory.duplicateParent }
            guard node.parents.allSatisfy({ !seen.contains($0) }) else { throw InvalidHistory.invalidTopologicalOrder }
            let top = lanes
            let incoming = lanes.contains { $0.sha == node.sha }
            if !incoming { lanes.append(.init(sha: node.sha, color: nextColor)); nextColor += 1 }
            let column = lanes.firstIndex { $0.sha == node.sha }!
            let color = lanes[column].color
            lanes.remove(at: column)
            if let parent = node.parents.first, !lanes.contains(where: { $0.sha == parent }) {
                lanes.insert(.init(sha: parent, color: color), at: column)
            }
            for parent in node.parents.dropFirst() where !lanes.contains(where: { $0.sha == parent }) {
                lanes.append(.init(sha: parent, color: nextColor)); nextColor += 1
            }
            var edges: [Edge] = []
            for (index, lane) in top.enumerated() where lane.sha != node.sha {
                let destination = lanes.firstIndex { $0.sha == lane.sha }!
                edges.append(.init(from: index, to: destination, color: lane.color, startsAtNode: false))
            }
            for parent in node.parents {
                let destination = lanes.firstIndex { $0.sha == parent }!
                edges.append(.init(from: column, to: destination, color: lanes[destination].color, startsAtNode: true))
            }
            rows.append(.init(sha: node.sha, column: column, color: color, incoming: incoming, top: top, bottom: lanes, edges: edges))
        }
        return rows
    }
}
