import Foundation

/// Privacy-preserving, 100% on-device shooting & sharing analytics store.
/// Tracks real capture volume, aesthetic score progression, magic enhancements, and shares.
@MainActor
@Observable
final class ShootingMetricsStore {
    static let shared = ShootingMetricsStore()

    private let defaults: UserDefaults
    private let keyPrefix = "superpose.metrics."

    private(set) var totalShotsCaptured: Int
    private(set) var magicEnhancedShots: Int
    private(set) var totalShares: Int
    private(set) var poseMatchesAchieved: Int
    private(set) var bestAestheticScore: Double
    private var aestheticScoreSum: Double
    private var aestheticScoreCount: Int

    var averageAestheticScore: Double {
        guard aestheticScoreCount > 0 else { return 0 }
        return aestheticScoreSum / Double(aestheticScoreCount)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.totalShotsCaptured = defaults.integer(forKey: keyPrefix + "totalShots")
        self.magicEnhancedShots = defaults.integer(forKey: keyPrefix + "magicShots")
        self.totalShares = defaults.integer(forKey: keyPrefix + "totalShares")
        self.poseMatchesAchieved = defaults.integer(forKey: keyPrefix + "poseMatches")
        self.bestAestheticScore = defaults.double(forKey: keyPrefix + "bestAesthetic")
        self.aestheticScoreSum = defaults.double(forKey: keyPrefix + "aestheticSum")
        self.aestheticScoreCount = defaults.integer(forKey: keyPrefix + "aestheticCount")
    }

    func recordShot(aestheticScore: Double?, usedMagic: Bool, poseMatchScore: Int?) {
        totalShotsCaptured += 1
        if usedMagic {
            magicEnhancedShots += 1
        }
        if let poseMatchScore, poseMatchScore >= 85 {
            poseMatchesAchieved += 1
        }
        if let aestheticScore {
            aestheticScoreSum += aestheticScore
            aestheticScoreCount += 1
            if aestheticScore > bestAestheticScore {
                bestAestheticScore = aestheticScore
            }
        }
        persist()
    }

    func recordShare() {
        totalShares += 1
        persist()
    }

    func reset() {
        totalShotsCaptured = 0
        magicEnhancedShots = 0
        totalShares = 0
        poseMatchesAchieved = 0
        bestAestheticScore = 0
        aestheticScoreSum = 0
        aestheticScoreCount = 0
        persist()
    }

    private func persist() {
        defaults.set(totalShotsCaptured, forKey: keyPrefix + "totalShots")
        defaults.set(magicEnhancedShots, forKey: keyPrefix + "magicShots")
        defaults.set(totalShares, forKey: keyPrefix + "totalShares")
        defaults.set(poseMatchesAchieved, forKey: keyPrefix + "poseMatches")
        defaults.set(bestAestheticScore, forKey: keyPrefix + "bestAesthetic")
        defaults.set(aestheticScoreSum, forKey: keyPrefix + "aestheticSum")
        defaults.set(aestheticScoreCount, forKey: keyPrefix + "aestheticCount")
    }
}
