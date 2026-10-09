/// The parts of an audio route that can change when headphones are unplugged.
public struct AudioOutputRoute: Equatable, Sendable {
    public let deviceID: UInt32
    public let isHeadphones: Bool
    public let isConnected: Bool
    public let dataSource: UInt32?
    public let jackConnected: Bool?

    public init(deviceID: UInt32, isHeadphones: Bool, isConnected: Bool = true,
                dataSource: UInt32? = nil, jackConnected: Bool? = nil) {
        self.deviceID = deviceID
        self.isHeadphones = isHeadphones
        self.isConnected = isConnected
        self.dataSource = dataSource
        self.jackConnected = jackConnected
    }

    public func shouldPause(afterChangingTo next: AudioOutputRoute?) -> Bool {
        guard isHeadphones, isConnected else { return false }
        guard let next, next.isConnected else { return true }
        if deviceID != next.deviceID || !next.isHeadphones { return true }
        if jackConnected == true && next.jackConnected == false { return true }
        if let dataSource, let nextSource = next.dataSource, dataSource != nextSource { return true }
        return false
    }
}
