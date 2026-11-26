import Foundation

@MainActor
@Observable
final class ShotPackStore {
    let isUnlimited = true

    func consumeOnePack() -> Bool {
        true
    }
}
