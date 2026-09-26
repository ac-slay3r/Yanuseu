import XCTest

final class PrivacyManifestTests: XCTestCase {
    func testBundledPrivacyManifestDeclaresAppOnlyUserDefaultsAccess() throws {
        guard let url = Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") else {
            XCTFail("PrivacyInfo.xcprivacy is missing from the application bundle")
            return
        }
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let manifest = try XCTUnwrap(propertyList as? [String: Any])
        let apiTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try XCTUnwrap(apiTypes.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        XCTAssertEqual(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }
}
