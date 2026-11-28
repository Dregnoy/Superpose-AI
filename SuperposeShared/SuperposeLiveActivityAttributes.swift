import ActivityKit
import Foundation

struct SuperposeShootAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var modeTitle: String
        var detailText: String
        var shotCount: Int
        var countdownSeconds: Int?
        var matchScore: Int?
    }

    var sessionName: String
}
