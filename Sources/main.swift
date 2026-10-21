import AppKit

@main
enum CloudetEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        let alreadyRunning = NSRunningApplication
            .runningApplications(withBundleIdentifier: "app.cloudet.mac")
            .count > 1
        if alreadyRunning {
            DistributedNotificationCenter.default().postNotificationName(
                .cloudetShowCloud,
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
            app.terminate(nil)
            return
        }

        app.run()
    }
}
