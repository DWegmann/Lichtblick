import XCTest
import Security
@testable import CredentialSupport

final class CredentialSupportTests: XCTestCase {
    func testMissingEntitlementWhenRememberingIsANoticeInsteadOfConnectionFailure() {
        let warning = CredentialStore.update(password: "test-secret", remember: true) { password in
            XCTAssertEqual(password, "test-secret")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecMissingEntitlement))
        }
        XCTAssertTrue(warning?.contains("Verbindung wurde hergestellt") == true)
        XCTAssertTrue(warning?.contains("Apple-Development-Team") == true)
        XCTAssertFalse(warning?.contains("test-secret") == true)
    }

    func testMissingEntitlementWhileDeletingDoesNotClaimThatOldPasswordWasRemoved() {
        let warning = CredentialStore.update(password: "session-secret", remember: false) { password in
            XCTAssertNil(password)
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecMissingEntitlement))
        }
        XCTAssertTrue(warning?.contains("nicht gelöscht") == true)
        XCTAssertTrue(warning?.contains("nicht neu gespeichert") == true)
        XCTAssertFalse(warning?.contains("session-secret") == true)
    }

    func testOtherKeychainErrorsAlsoAllowSessionWithoutIncorrectSigningAdvice() {
        let warning = CredentialStore.update(password: "test", remember: true) { _ in
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
        }
        XCTAssertNotNil(warning)
        XCTAssertFalse(warning?.contains("Apple-Development-Team") == true)
    }

    func testSuccessfulSaveAndDeletionDoNotShowWarning() {
        XCTAssertNil(CredentialStore.update(password: "test", remember: true) { XCTAssertEqual($0, "test") })
        XCTAssertNil(CredentialStore.update(password: "test", remember: false) { XCTAssertNil($0) })
    }
}
