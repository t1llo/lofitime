import AppKit

/// Quiet, locally synthesized forest sounds. No downloads or audio permissions.
enum ForestAmbience {
    static func makeSound() -> NSSound? {
        let rate = 22_050
        let seconds = 12
        let count = rate * seconds
        var samples = Data(capacity: count * 2)
        var random: UInt32 = 42
        var breeze = 0.0
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            random = random &* 1_664_525 &+ 1_013_904_223
            let noise = Double(random) / Double(UInt32.max) * 2 - 1
            breeze = breeze * 0.97 + noise * 0.03
            var value = breeze * (0.35 + 0.12 * sin(time * .pi / 3))
            // Short, varied bird calls separated by stretches of soft wind.
            for (start, pitch) in [(1.0, 2_400.0), (1.55, 2_800.0), (4.2, 2_100.0), (7.3, 3_100.0), (8.0, 2_650.0)] {
                let local = time - start
                if local >= 0 && local < 0.24 {
                    let envelope = pow(sin(local / 0.24 * .pi), 2)
                    value += sin(2 * .pi * (pitch * local + 600 * local * local)) * envelope * 0.22
                }
            }
            // A very faint insect hum; fade loop edges to avoid clicks.
            value += sin(time * 2 * .pi * 145) * 0.006 * (1 + sin(time * 2))
            let fade = min(1, time / 0.3, (Double(seconds) - time) / 0.3)
            var sample = Int16(max(-1, min(1, value * fade)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var wav = Data()
        func text(_ string: String) { wav.append(contentsOf: string.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(36 + samples.count)); text("WAVEfmt ")
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1))
        integer(UInt32(rate)); integer(UInt32(rate * 2)); integer(UInt16(2)); integer(UInt16(16))
        text("data"); integer(UInt32(samples.count)); wav.append(samples)
        return NSSound(data: wav)
    }
}
