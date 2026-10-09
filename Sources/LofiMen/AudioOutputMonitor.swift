import CoreAudio
import IOKit.audio
import LofiMenCore

/// Core Audio notifications cover Bluetooth/USB removal and built-in headphone jacks.
/// No polling, recording permission, or audio engine is needed.
@MainActor
final class AudioOutputMonitor {
    private var route: AudioOutputRoute?
    private var systemListeners: [AudioPropertyListener] = []
    private var deviceListeners: [AudioPropertyListener] = []
    private var streamListeners: [AudioPropertyListener] = []
    private var observedStreams: [AudioStreamID] = []
    private let onHeadphonesDisconnected: () -> Void

    init(onHeadphonesDisconnected: @escaping () -> Void) {
        self.onHeadphonesDisconnected = onHeadphonesDisconnected
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            if let listener = listen(to: AudioObjectID(kAudioObjectSystemObject), selector: selector) {
                systemListeners.append(listener)
            }
        }
        refresh()
    }

    func refresh() {
        // A failed property read is not evidence of a disconnected device.
        guard let device = values(of: AudioObjectID(kAudioObjectSystemObject),
                                  selector: kAudioHardwarePropertyDefaultOutputDevice)?.first else { return }
        let streams = device == kAudioObjectUnknown ? [] :
            values(of: device, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) ?? []
        let next = device == kAudioObjectUnknown ? nil : snapshot(device, streams: streams)
        let shouldPause = route?.shouldPause(afterChangingTo: next) == true
        let previousDevice = route?.deviceID
        route = next
        if previousDevice != next?.deviceID {
            deviceListeners.removeAll()
            if let next {
                for (selector, scope) in [
                    (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
                    (kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput),
                    (kAudioDevicePropertyJackIsConnected, kAudioObjectPropertyScopeOutput),
                    (kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
                ] {
                    if let listener = listen(to: next.deviceID, selector: selector, scope: scope) {
                        deviceListeners.append(listener)
                    }
                }
            }
        }
        if streams != observedStreams {
            observedStreams = streams
            streamListeners = streams.compactMap { listen(to: $0, selector: kAudioStreamPropertyTerminalType) }
        }
        if shouldPause { onHeadphonesDisconnected() }
    }

    private func snapshot(_ device: AudioObjectID, streams: [AudioStreamID]) -> AudioOutputRoute {
        let source = values(of: device, selector: kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)?.first
        let jack = values(of: device, selector: kAudioDevicePropertyJackIsConnected, scope: kAudioObjectPropertyScopeOutput)?.first
        let transport = values(of: device, selector: kAudioDevicePropertyTransportType)?.first
        let alive = values(of: device, selector: kAudioDevicePropertyDeviceIsAlive)?.first
        let headphoneStream = streams.contains {
            values(of: $0, selector: kAudioStreamPropertyTerminalType)?.first == kAudioStreamTerminalTypeHeadphones
        }
        // Some USB and Bluetooth headsets report only a generic output terminal.
        // Losing one of these routes must also pause before fallback to speakers.
        let headsetTransport = [kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE,
                                kAudioDeviceTransportTypeUSB].contains(transport ?? 0)
        let headphones = source == UInt32(kIOAudioSelectorControlSelectionValueHeadphones) || headphoneStream || jack == 1 || headsetTransport
        return AudioOutputRoute(deviceID: device, isHeadphones: headphones, isConnected: alive != 0,
                                dataSource: source, jackConnected: jack.map { $0 != 0 })
    }

    private func listen(to object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioPropertyListener? {
        AudioPropertyListener(object: object, selector: selector, scope: scope) { [weak self] _, _ in
            // Core Audio delivers these listeners on the main queue.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func values(of object: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [UInt32]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0, size.isMultiple(of: UInt32(MemoryLayout<UInt32>.size)) else { return nil }
        var values = [UInt32](repeating: 0, count: Int(size) / MemoryLayout<UInt32>.size)
        let result = values.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
        }
        return result == noErr ? Array(values.prefix(Int(size) / MemoryLayout<UInt32>.size)) : nil
    }
}

private final class AudioPropertyListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let callback: AudioObjectPropertyListenerBlock
    private var registered = false

    init?(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
          callback: @escaping AudioObjectPropertyListenerBlock) {
        self.object = object
        self.address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        self.callback = callback
        guard AudioObjectHasProperty(object, &address),
              AudioObjectAddPropertyListenerBlock(object, &address, .main, callback) == noErr else { return nil }
        registered = true
    }

    deinit {
        if registered { AudioObjectRemovePropertyListenerBlock(object, &address, .main, callback) }
    }
}
