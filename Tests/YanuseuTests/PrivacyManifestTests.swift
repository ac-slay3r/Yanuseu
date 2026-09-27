import XCTest

final class PrivacyManifestTests: XCTestCase {
    func testBundledPrivacyManifestDeclaresAppOnlyUserDefaultsAccess() throws {
        guard let url = Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") else {
            let appBundle = Bundle(identifier: "cool.n0thing.yanus")
            let mainPath = Bundle.main.bundleURL.path
            let appPath = appBundle?.bundleURL.path ?? "missing"
            let appHasManifest = appBundle.map { FileManager.default.fileExists(atPath: $0.bundleURL.appendingPathComponent("PrivacyInfo.xcprivacy").path) } ?? false
            XCTFail("PrivacyInfo.xcprivacy missing; main=\(Bundle.main.bundleIdentifier ?? "nil") at \(mainPath); app=\(appPath); appHasManifest=\(appHasManifest)")
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
