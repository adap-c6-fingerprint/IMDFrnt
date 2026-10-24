import Dispatch
import Foundation

/// CLI checks must run before SwiftUI creates NSApplication/LaunchServices.
@main
enum IMDFrntMain {
    @MainActor
    static func main() {
        if AppEnvironment.isRunningSelfTests {
            print("== CLI self-test: before AppKit application startup ==")
            Task {
                await IMDFComplianceSelfTest.runIfRequested()
                await FootprintRegistrationSelfTest.runIfRequested()
                await DrawingLoadingSelfTest.runIfRequested()
                await DocumentOpeningSelfTest.runIfRequested()
                await BuildingSelfTest.runIfRequested()
                ProjectSelfTest.runIfRequested()
                await RoutingSelfTest.runIfRequested()
                _ = SelfTest.runIfRequested()
                exit(1)
            }
            dispatchMain()
        }
        IMDFrntApp.main()
    }
}
