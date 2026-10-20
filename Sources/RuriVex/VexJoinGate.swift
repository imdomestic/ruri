import Foundation
import RuriCore
import RuriLocalization

public struct VexJoinGate: Sendable {
    public let project: String
    public let roomID: String
    public let generation: Int
    public let buildID: String
    public private(set) var room: VexRoom
    public private(set) var localPrepared = false
    public private(set) var launched = false
    public private(set) var cancelled = false

    public init(room: VexRoom) throws {
        project = room.project; roomID = room.id; generation = room.generation; buildID = room.buildId; self.room = room
        try observe(room)
    }
    public mutating func observe(_ value: VexRoom) throws {
        guard value.project == project, value.id == roomID, !launched else { return }
        guard !cancelled else { throw CancellationError() }
        if value.generation != generation || value.buildId != buildID {
            cancelled = true; throw RuriError.message(Messages.Vex.generationChanged)
        }
        if value.state.cancelsJoin {
            cancelled = true
            if let error = value.lastError { throw error }
            throw RuriError.message(Messages.Vex.roomUnavailable(value.state.rawValue))
        }
        room = value
    }
    public mutating func observe(_ value: VexReady) throws {
        guard value.project == project, value.id == roomID, !launched else { return }
        guard !cancelled else { throw CancellationError() }
        guard value.generation == generation, value.buildId == buildID else {
            cancelled = true; throw RuriError.message(Messages.Vex.generationChanged)
        }
        room.state = .ready; room.host = value.host; room.port = value.port
    }
    public mutating func prepareLocal() { localPrepared = true }
    public mutating func claimLaunch() -> Bool {
        guard !cancelled, !launched, localPrepared, room.state == .ready else { return false }
        launched = true
        return true
    }
}
