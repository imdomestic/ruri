import Foundation
import RuriLocalization

public struct ChorusJoinGate: Sendable {
    public let roomID: String
    public let generation: Int
    public let buildID: String
    public private(set) var room: ChorusRoom
    public private(set) var localPrepared = false
    public private(set) var launched = false
    public private(set) var cancelled = false

    public init(room: ChorusRoom) throws {
        roomID = room.id; generation = room.generation; buildID = room.buildId; self.room = room
        try observe(room)
    }
    public mutating func observe(_ value: ChorusRoom) throws {
        guard value.id == roomID, !launched else { return }
        guard !cancelled else { throw CancellationError() }
        if value.generation != generation || value.buildId != buildID {
            cancelled = true; throw RuriError.message(Messages.Chorus.generationChanged)
        }
        if value.state.cancelsJoin {
            cancelled = true
            if let error = value.lastError { throw error }
            throw RuriError.message(Messages.Chorus.roomUnavailable(value.state.rawValue))
        }
        room = value
    }
    public mutating func observe(_ value: ChorusReady) throws {
        guard value.id == roomID, !launched else { return }
        guard !cancelled else { throw CancellationError() }
        guard value.generation == generation, value.buildId == buildID else {
            cancelled = true; throw RuriError.message(Messages.Chorus.generationChanged)
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
