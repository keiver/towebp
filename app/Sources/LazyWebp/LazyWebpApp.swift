import ServiceManagement
import SwiftUI

@main
struct LazyWebpApp: App {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Lazy Webp", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 650)

        MenuBarExtra("Lazy Webp", systemImage: "arrow.triangle.2.circlepath") {
            Button("Open Lazy Webp") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o")

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = newValue
                    } catch {
                        print("Launch at login error: \(error)")
                    }
                }
            ))

            Button("Install to Applications...") {
                installToApplications()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func installToApplications() {
        let scriptName = "install-app.sh"
        var foundPath: String?

        // Check bundle resources first (production builds)
        if let resourcePath = Bundle.main.resourceURL?.appendingPathComponent(scriptName).path,
           FileManager.default.fileExists(atPath: resourcePath)
        {
            foundPath = resourcePath
        }

        // Fallback: check bundle parent directory (dev builds)
        if foundPath == nil {
            let bundleParent = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(scriptName)
                .path
            if FileManager.default.fileExists(atPath: bundleParent) {
                foundPath = bundleParent
            }
        }

        guard let finalPath = foundPath else {
            let alert = NSAlert()
            alert.messageText = "Install Script Not Found"
            alert.informativeText = "Could not locate install-app.sh. Make sure it exists in the app/ directory."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [finalPath]
            proc.currentDirectoryURL = URL(fileURLWithPath: finalPath).deletingLastPathComponent()

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            do {
                try proc.run()
                proc.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                await MainActor.run {
                    let alert = NSAlert()
                    if proc.terminationStatus == 0 {
                        alert.messageText = "Installed Successfully"
                        alert.informativeText = "Lazy Webp has been installed to /Applications/Lazy Webp.app"
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = "Installation Failed"
                        alert.informativeText = output.isEmpty
                            ? "install-app.sh exited with code \(proc.terminationStatus)"
                            : output
                        alert.alertStyle = .critical
                    }
                    alert.runModal()
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Installation Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }
}
