import Foundation

@MainActor
@Observable
final class ShotPackStore: ShotPackStoring {
    let isUnlimited = true

    func consumeOnePack() -> Bool {
        true
    }
}
