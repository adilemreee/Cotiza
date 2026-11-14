import Foundation

/// When to ask for an App Store rating: after the contractor has had a few good moments (an estimate
/// sent, approved or paid), never in the first days, and at most once per app version. iOS shows the
/// prompt at most three times a year on its own and may skip it, so asking is cheap but never certain.
nonisolated struct ReviewPrompt {
    static let goodMomentsNeeded = 3
    static let minimumDaysInstalled = 3
    static let minimumDaysBetweenAsks = 120

    private enum Key {
        static let moments = "review.goodMoments"
        static let firstSeen = "review.firstSeen"
        static let askedVersion = "review.askedVersion"
        static let askedAt = "review.askedAt"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.firstSeen) == nil { defaults.set(Date.now, forKey: Key.firstSeen) }
    }

    var goodMoments: Int { defaults.integer(forKey: Key.moments) }

    func recordGoodMoment() {
        defaults.set(goodMoments + 1, forKey: Key.moments)
    }

    func shouldAsk(now: Date = .now, version: String = ReviewPrompt.appVersion) -> Bool {
        let day: TimeInterval = 86_400
        guard goodMoments >= Self.goodMomentsNeeded,
              let firstSeen = defaults.object(forKey: Key.firstSeen) as? Date,
              now.timeIntervalSince(firstSeen) >= Double(Self.minimumDaysInstalled) * day,
              defaults.string(forKey: Key.askedVersion) != version else { return false }
        if let asked = defaults.object(forKey: Key.askedAt) as? Date,
           now.timeIntervalSince(asked) < Double(Self.minimumDaysBetweenAsks) * day { return false }
        return true
    }

    func markAsked(now: Date = .now, version: String = ReviewPrompt.appVersion) {
        defaults.set(version, forKey: Key.askedVersion)
        defaults.set(now, forKey: Key.askedAt)
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

extension ReviewPrompt {
    /// Counts a good moment and lets the home screen decide whether to ask.
    @MainActor
    static func goodMoment() {
        #if DEBUG
        // UI tests and screenshots must never be interrupted by the rating sheet.
        if UserDefaults.standard.bool(forKey: "CotizaResetState") || ScreenshotScene.current != nil { return }
        #endif
        ReviewPrompt().recordGoodMoment()
        AppRouter.shared.reviewCheck += 1
    }
}
