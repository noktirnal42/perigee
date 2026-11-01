import Testing
@testable import StarlinkKit

@Suite("Session changes")
@MainActor
struct SessionWriteTests {
    @Test("Demo changes are verified and revert updates the original record")
    func changeAndRevert() async throws {
        let session = StarlinkSession(source: .demo)
        #expect(!session.writesEnabled)
        await session.refreshNow()
        let before = try #require(session.tuning?.channel5)
        session.writesEnabled = true
        let change = try await session.apply(.channel(.ghz5, 149), expected: .channel(.ghz5, before))
        #expect(change.verified)
        #expect(session.tuning?.channel5 == 149)
        let revert = try await session.revert(change)
        #expect(revert.verified)
        #expect(session.tuning?.channel5 == before)
        #expect(session.changeLog.first(where: { $0.id == change.id })?.revertedAt != nil)
        session.stop()
    }

    @Test("Reconnecting turns writes off and clears the old change history")
    func reconnectResetsAuthorization() async throws {
        let session = StarlinkSession(source: .demo)
        await session.refreshNow()
        let before = try #require(session.tuning?.channel5)
        session.writesEnabled = true
        _ = try await session.apply(.channel(.ghz5, 149), expected: .channel(.ghz5, before))
        session.reconnect()
        #expect(!session.writesEnabled)
        #expect(session.changeLog.isEmpty)
        session.stop()
    }
}
