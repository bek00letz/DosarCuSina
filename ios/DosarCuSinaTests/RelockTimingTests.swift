import Foundation
import Testing
@testable import DosarCuSina

/// A clock the test moves itself.
final class ManualLockClock: @unchecked Sendable {
    var elapsed: Duration = .seconds(1_000)
    var clock: LockClock { LockClock { [unowned self] in self.elapsed } }
}

/// A phone with the two clocks it has: the one its settings set (date and time), and the
/// one that only counts. The vault is given only the second.
@MainActor
private final class Phone {
    let lockClock = ManualLockClock()
    private(set) var clockReads = noon("2026-11-02")

    /// Time passes: both clocks count it.
    func wait(_ duration: Duration) {
        lockClock.elapsed += duration
        clockReads = clockReads.addingTimeInterval(TimeInterval(duration.components.seconds))
    }

    /// The person sets the phone's date or time: only that clock moves.
    func setClock(by interval: TimeInterval) {
        clockReads = clockReads.addingTimeInterval(interval)
    }
}

@MainActor
@Suite("Time away closes the session")
struct RelockTimingTests {
    private func openVault(_ phone: Phone, appLock: Bool = true) async -> BiometricVaultManager {
        let vault = BiometricVaultManager(authenticator: FakeAuthenticator(.succeed), clock: phone.lockClock.clock, appLockEnabled: { appLock }, observesAppLifecycle: false)
        await vault.unlock(reason: "test")
        return vault
    }

    @Test("A minute away keeps it open; longer closes it")
    func timePassing() async {
        let phone = Phone()
        let vault = await openVault(phone)

        vault.appDidEnterBackground()
        phone.wait(.seconds(5))
        vault.appWillEnterForeground()
        #expect(vault.isSessionUnlocked, "A quick switch to another app keeps it open")

        vault.appDidEnterBackground()
        phone.wait(BiometricVaultManager.relockAfterBackground)
        vault.appWillEnterForeground()
        #expect(vault.isSessionUnlocked, "Exactly a minute is still within it")

        vault.appDidEnterBackground()
        phone.wait(BiometricVaultManager.relockAfterBackground + .milliseconds(1))
        vault.appWillEnterForeground()
        #expect(!vault.isSessionUnlocked)
        #expect(vault.isAppLocked)
    }

    @Test("A night with the screen off counts as time away")
    func sleepCounts() async {
        let phone = Phone()
        let vault = await openVault(phone, appLock: false)
        vault.appDidEnterBackground()
        phone.wait(.seconds(8 * 3_600))
        vault.appWillEnterForeground()
        #expect(vault.isLocked(sectionIsSensitive: true), "The section lock closes too")
    }

    @Test("Setting the phone's clock back while away doesn't keep the session open")
    func clockSetBack() async {
        let phone = Phone()
        let vault = await openVault(phone)
        vault.appDidEnterBackground()
        phone.wait(.seconds(120))
        phone.setClock(by: -86_400)
        vault.appWillEnterForeground()
        #expect(!vault.isSessionUnlocked, "Two minutes away, whatever the phone's clock reads")
    }

    @Test("Setting the phone's clock forward while away doesn't close the session early")
    func clockSetForward() async {
        let phone = Phone()
        let vault = await openVault(phone)
        vault.appDidEnterBackground()
        phone.wait(.seconds(10))
        phone.setClock(by: 86_400)
        vault.appWillEnterForeground()
        #expect(vault.isSessionUnlocked, "Ten seconds away, whatever the phone's clock reads")
    }

    @Test("Time away counts from the first time the app left")
    func fromTheFirstTimeAway() async {
        let phone = Phone()
        let vault = await openVault(phone)
        vault.appDidEnterBackground()
        phone.wait(.seconds(50))
        vault.appDidEnterBackground()
        phone.wait(.seconds(50))
        vault.appWillEnterForeground()
        #expect(!vault.isSessionUnlocked)
    }

    @Test("Coming back without having left changes nothing")
    func noTimeAway() async {
        let phone = Phone()
        let vault = await openVault(phone)
        phone.wait(.seconds(3_600))
        vault.appWillEnterForeground()
        #expect(vault.isSessionUnlocked)
    }

    @Test("The phone's own lock clock only counts forward")
    func theContinuousClockCounts() {
        let first = LockClock.continuous.elapsed
        let second = LockClock.continuous.elapsed
        #expect(first >= .zero)
        #expect(second >= first)
    }
}
