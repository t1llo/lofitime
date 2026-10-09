import Foundation

public enum GardenHabitat: String, CaseIterable, Sendable {
    case meadow, birchGrove, pineForest, fernGlade

    public var title: String {
        switch self {
        case .meadow: "Wildflower meadow"
        case .birchGrove: "Birch grove"
        case .pineForest: "Pine woodland"
        case .fernGlade: "Fern glade"
        }
    }
}

public struct GardenPlant: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable {
        case grass, flower, bush, oak, pine, birch, mushroom, rock
    }

    public let id: Int
    public let kind: Kind
    public let x: Double
    public let z: Double
    public let height: Double
    public let rotation: Double
    public let variation: Double
}

extension ActivityDay {
    /// Independent, stable random streams keep existing plants rooted as more focus is added.
    public func plantingRandom(_ index: Int, lane: Int = 0) -> Double {
        var value = UInt64(plantingSeed) &+ UInt64(index) &* 0x9E3779B97F4A7C15 &+ UInt64(lane) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Double((value ^ (value >> 31)) >> 11) / 9_007_199_254_740_992
    }

    public var planting: [GardenPlant] {
        guard isInRange, duration > 0 else { return [] }
        var plants: [GardenPlant] = []
        func add(_ kind: GardenPlant.Kind, id: Int, height: Double, x: Double? = nil, z: Double? = nil) {
            plants.append(GardenPlant(id: id, kind: kind,
                                      x: x ?? (plantingRandom(id, lane: 1) - 0.5) * 0.88,
                                      z: z ?? (plantingRandom(id, lane: 2) - 0.5) * 0.84,
                                      height: height, rotation: plantingRandom(id, lane: 3) * .pi * 2,
                                      variation: plantingRandom(id, lane: 4)))
        }

        // Rejection sampling separates trunks without repeating a fixed row of tree slots.
        var trunks: [(x: Double, z: Double)] = []
        for candidate in 0..<200 where trunks.count < trees {
            let x = (plantingRandom(candidate + 500, lane: 1) - 0.5) * 0.82
            let z = plantingRandom(candidate + 500, lane: 2) * 0.68 - 0.44
            guard trunks.allSatisfy({ hypot($0.x - x, $0.z - z) > 0.29 }) else { continue }
            let index = trunks.count
            trunks.append((x, z))
            let kind: GardenPlant.Kind
            switch habitat {
            case .meadow: kind = .oak
            case .birchGrove: kind = .birch
            case .pineForest: kind = .pine
            case .fernGlade: kind = index.isMultiple(of: 3) ? .oak : .birch
            }
            let maturity = min(1, max(0, (duration - 1_500 - Double(index) * 1_800) / 7_200))
            let height = 0.48 + plantingRandom(index + 500, lane: 5) * 0.30 + maturity * 0.42
            add(kind, id: index + 500, height: height, x: x, z: z)
        }
        for index in 0..<flowers {
            add(.flower, id: index + 100, height: 0.10 + plantingRandom(index + 100) * 0.10)
        }
        for index in 0..<bushes {
            add(.bush, id: index + 200, height: 0.16 + plantingRandom(index + 200) * 0.14)
        }
        for index in 0..<min(12, 2 + Int(min(duration, 10_800) / 600)) {
            add(.grass, id: index + 300, height: 0.06 + plantingRandom(index + 300) * 0.08)
        }
        if habitat == .fernGlade || habitat == .pineForest, duration >= 1_800 {
            for index in 0..<min(4, Int(min(duration, 7_200) / 1_800)) {
                add(.mushroom, id: index + 400, height: 0.08 + plantingRandom(index + 400) * 0.05)
            }
        }
        if duration >= 900, habitat != .meadow {
            add(.rock, id: 600, height: 0.09 + plantingRandom(600) * 0.08)
        }
        return plants
    }
}
