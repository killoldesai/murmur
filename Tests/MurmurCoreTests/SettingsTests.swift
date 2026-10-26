import XCTest
@testable import MurmurCore

@MainActor
final class AppSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "murmur-settings-\(UUID().uuidString)")!
    }

    func testDefaults() {
        let settings = AppSettings(defaults: defaults())
        XCTAssertFalse(settings.deleteAudioAfterTranscribing)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertNil(settings.language)
        XCTAssertFalse(settings.hasCompletedOnboarding)
    }

    func testValuesPersist() {
        let store = defaults()
        let first = AppSettings(defaults: store)
        first.setDeleteAudioAfterTranscribing(true)
        first.setHapticsEnabled(false)
        first.setLanguage("fr")
        first.completeOnboarding()
        let second = AppSettings(defaults: store)
        XCTAssertTrue(second.deleteAudioAfterTranscribing)
        XCTAssertFalse(second.hapticsEnabled)
        XCTAssertEqual(second.language, "fr")
        XCTAssertTrue(second.hasCompletedOnboarding)
    }

    func testLanguageCanReturnToAutoDetect() {
        let store = defaults()
        let settings = AppSettings(defaults: store)
        settings.setLanguage("de")
        settings.setLanguage(nil)
        XCTAssertNil(AppSettings(defaults: store).language)
    }

    func testLanguageNames() {
        XCTAssertEqual(TranscriptionLanguage.name(for: nil), "Auto-detect")
        XCTAssertEqual(TranscriptionLanguage.name(for: "en"), "English")
        XCTAssertEqual(TranscriptionLanguage.name(for: "xx"), "Auto-detect")
        XCTAssertEqual(Set(TranscriptionLanguage.all.map(\.id)).count, TranscriptionLanguage.all.count)
    }
}

@MainActor
final class OnboardingControllerTests: XCTestCase {
    func testSelectJumpsToPageAndIgnoresOutOfRange() {
        let controller = OnboardingController()
        controller.select(2)
        XCTAssertEqual(controller.index, 2)
        controller.select(9)
        controller.select(-1)
        XCTAssertEqual(controller.index, 2)
    }

    func testPageCanBeWordedForIPad() {
        let page = OnboardingController.pages[0].worded(forDevice: "iPad")
        XCTAssertEqual(page.title, "Your words stay on your iPad")
        XCTAssertFalse(page.title.contains("\n"))
        XCTAssertEqual(page.symbol, OnboardingController.pages[0].symbol)
    }

    func testWalksThroughPagesThenMicrophone() {
        let controller = OnboardingController()
        XCTAssertEqual(controller.index, 0)
        XCTAssertNotNil(controller.page)
        controller.next(); controller.next()
        XCTAssertFalse(controller.isMicrophoneStep)
        controller.next()
        XCTAssertTrue(controller.isMicrophoneStep)
        XCTAssertNil(controller.page)
        controller.next()
        XCTAssertEqual(controller.index, OnboardingController.pages.count)
    }

    func testSkipStillShowsMicrophoneStep() {
        let controller = OnboardingController()
        controller.skip()
        XCTAssertTrue(controller.isMicrophoneStep)
    }

    func testStartIndexIsClamped() {
        XCTAssertEqual(OnboardingController(startAt: 99).index, OnboardingController.pages.count)
        XCTAssertEqual(OnboardingController(startAt: -3).index, 0)
    }

    func testPagesHaveCopy() {
        XCTAssertEqual(OnboardingController.pages.count, 3)
        for page in OnboardingController.pages {
            XCTAssertFalse(page.title.isEmpty)
            XCTAssertFalse(page.body.isEmpty)
        }
    }
}

final class LegalLinksTests: XCTestCase {
    func testLinksAreSecureAndDistinct() {
        let urls = [LegalLinks.home, LegalLinks.privacy, LegalLinks.terms]
        XCTAssertTrue(urls.allSatisfy { $0.scheme == "https" })
        XCTAssertEqual(Set(urls.map(\.absoluteString)).count, 3)
        XCTAssertTrue(LegalLinks.privacy.absoluteString.hasSuffix("/privacy/"))
        XCTAssertTrue(LegalLinks.terms.absoluteString.hasSuffix("/terms/"))
    }

    func testSubscriptionNoticeMentionsRenewalAndCancellation() {
        XCTAssertTrue(LegalLinks.subscriptionNotice.contains("renew automatically"))
        XCTAssertTrue(LegalLinks.subscriptionNotice.contains("cancel"))
    }
}
