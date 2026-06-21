import XCTest
@testable import MousePortal

final class ConfigProfileTests: XCTestCase {

    func testLegacyConfigProfileDecodingDefaultsTriggerKeyToOption() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "hotkeyConfigs": [],
          "portals": [],
          "triggerMode": "withKey",
          "hotkeyGlobalEnabled": true,
          "portalGlobalEnabled": true,
          "showMenuBarIcon": true,
          "createdAt": 0,
          "modifiedAt": 0
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(ConfigProfile.self, from: json)

        XCTAssertEqual(profile.triggerMode, .withKey)
        XCTAssertEqual(profile.triggerKey, .option)
    }

    func testConfigProfileCodableRoundTripPreservesTriggerKey() throws {
        var profile = ConfigProfile(name: "Test")
        profile.triggerMode = .withKey
        profile.triggerKey = .command

        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConfigProfile.self, from: encoded)

        XCTAssertEqual(decoded.triggerMode, .withKey)
        XCTAssertEqual(decoded.triggerKey, .command)
    }
}
