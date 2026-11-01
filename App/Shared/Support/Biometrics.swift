import Foundation
import LocalAuthentication

enum Biometrics {
    /// Face ID / Touch ID / device passcode gate. Returns true when the user proves presence.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
