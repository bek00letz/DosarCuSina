import Foundation
import SwiftUI
import Testing
@testable import DosarCuSina

/// When the app is covered: `LockCover.decide` over every combination it reads, and the
/// moments a person goes through (a Face ID prompt, the app switcher, the home screen).
@MainActor
@Suite("When the app is covered")
struct LockCoverDecisionTests {
    /// The moments of one lock setting, in this order: active, active with a Face ID prompt,
    /// inactive, inactive with a prompt, background, background with a prompt.
    private static let moments: [(phase: LockCover.Phase, isAuthenticating: Bool)] = [
        (.active, false), (.active, true),
        (.inactive, false), (.inactive, true),
        (.background, false), (.background, true),
    ]

    private static let lockOnly: [LockCover?] = [.lock, .lock, .lock, .lock, .lock, .lock]
    private static let whenLeaving: [LockCover?] = [nil, nil, .privacy, nil, .privacy, .privacy]
    private static let never: [LockCover?] = [nil, nil, nil, nil, nil, nil]

    /// One row per lock setting: the app lock, any section lock, the session open.
    private static let table: [(appLock: Bool, sectionLock: Bool, sessionOpen: Bool, covers: [LockCover?])] = [
        // The app lock with the session closed: the lock, whatever the moment.
        (true, false, false, lockOnly),
        (true, true, false, lockOnly),
        // The app lock, open: covered whenever it leaves the screen, but not by its own prompt.
        (true, false, true, whenLeaving),
        (true, true, true, whenLeaving),
        // A section lock with the session open: a locked section could be on screen.
        (false, true, true, whenLeaving),
        // A section lock, closed: nothing locked can be on screen.
        (false, true, false, never),
        // No lock at all.
        (false, false, true, never),
        (false, false, false, never),
    ]

    @Test("The table lists every lock setting once")
    func theTableIsComplete() {
        let settings = Set(Self.table.map { [$0.appLock, $0.sectionLock, $0.sessionOpen] })
        #expect(settings.count == 8)
        #expect(Self.table.count == 8)
        #expect(Self.table.allSatisfy { $0.covers.count == Self.moments.count })
        #expect(Set(Self.moments.map { $0.phase }) == Set(LockCover.Phase.allCases))
    }

    @Test("Every combination gives the cover in the table", arguments: 0..<8)
    func everyCombination(row: Int) {
        let setting = Self.table[row]
        for (moment, expected) in zip(Self.moments, setting.covers) {
            let cover = LockCover.decide(
                appLockEnabled: setting.appLock,
                anySectionLocked: setting.sectionLock,
                isSessionUnlocked: setting.sessionOpen,
                phase: moment.phase,
                isAuthenticating: moment.isAuthenticating
            )
            #expect(
                cover == expected,
                "app lock \(setting.appLock), section lock \(setting.sectionLock), open \(setting.sessionOpen), \(moment.phase), prompt \(moment.isAuthenticating)"
            )
        }
    }

    @Test("The scene's phase reads as the cover's")
    func scenePhases() {
        #expect(LockCover.Phase(ScenePhase.active) == .active)
        #expect(LockCover.Phase(ScenePhase.inactive) == .inactive)
        #expect(LockCover.Phase(ScenePhase.background) == .background)
    }

    /// The covers a section-locked app with the session open shows through `steps`.
    private func covers(_ steps: [(LockCover.Phase, Bool)]) -> [LockCover?] {
        steps.map { phase, isAuthenticating in
            LockCover.decide(appLockEnabled: false, anySectionLocked: true, isSessionUnlocked: true, phase: phase, isAuthenticating: isAuthenticating)
        }
    }

    @Test("A Face ID prompt only makes the app inactive, and isn't covered")
    func aFaceIDPromptIsNotCovered() {
        // "Arată" on a code: the prompt is asked for, its sheet makes the app inactive,
        // the sheet goes, the answer comes.
        #expect(covers([(.active, false), (.active, true), (.inactive, true), (.active, true), (.active, false)]) == [nil, nil, nil, nil, nil])
    }

    @Test("Leaving for the app switcher during a Face ID prompt covers the app by the background")
    func theSwitcherDuringAPromptIsCovered() {
        // The prompt is up, the person swipes to the app switcher and on to another app: the
        // background comes before the prompt's answer, and the picture is taken then.
        #expect(covers([(.inactive, true), (.background, true), (.background, false), (.inactive, false), (.active, false)]) == [nil, .privacy, .privacy, .privacy, nil])
    }

    @Test("The app switcher and the home screen are covered from the first inactive moment")
    func leavingIsCovered() {
        // To the app switcher and back.
        #expect(covers([(.active, false), (.inactive, false), (.active, false)]) == [nil, .privacy, nil])
        // Home.
        #expect(covers([(.active, false), (.inactive, false), (.background, false)]) == [nil, .privacy, .privacy])
    }
}
