import XCTest
@testable import StarlinkKit

final class CapabilityTests: XCTestCase {
    func testCapabilitiesWithSameMethodOnDifferentDevicesHaveDistinctIDs() {
        let router = Capability(method: "get_status", title: "Router", detail: "", device: .router)
        let dish = Capability(method: "get_status", title: "Dish", detail: "", device: .dish)
        XCTAssertNotEqual(router.id, dish.id)
    }

    func testDeniedDoesNotClaimKnownAuthorizationMechanism() {
        let capability = Capability(method: "wifi_get_channels", title: "Channels", detail: "", state: .denied, device: .router)
        XCTAssertTrue(capability.explanation.contains("denied"))
        XCTAssertTrue(capability.explanation.contains("unknown"))
    }
}
