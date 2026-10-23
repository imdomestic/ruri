import Foundation
import RuriCore

final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    func write(_ data: Data, _ error: Bool) { lock.withLock { if error { stderr.append(data) } else { stdout.append(data) } } }
    var output: Data { lock.withLock { stdout } }
    var errors: Data { lock.withLock { stderr } }
    var value: OperationValue { get throws { try JSONDecoder().decode(OperationValue.self, from: output) } }
}
