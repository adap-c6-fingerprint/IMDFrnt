import Dispatch
import Foundation

/// CLI checks must run before SwiftUI creates NSApplication/LaunchServices.
@main
enum IMDFrntMain {
    @MainActor
    static func main() {
        if AppEnvironment.isRunningSelfTests {
            print("== CLI self-test: before AppKit application startup ==")
            if CommandLine.arguments.contains("--document-open-selftest") {
                Task { await DocumentOpeningSelfTest.runIfRequested() }
                dispatchMain()
            }
            BuildingSelfTest.runIfRequested()
            ProjectSelfTest.runIfRequested()
            RoutingSelfTest.runIfRequested()
            _ = SelfTest.runIfRequested()
            exit(1)
        }
        IMDFrntApp.main()
    }
}
