import AppKit
import ArgumentParser
import Foundation
import SwiftUI

// Main entry point for Zeit
// - When run with no arguments (or launched from Finder): starts menubar app
// - When run with CLI arguments: executes the command

// Ensure data directory and default config exist before anything else
ZeitConfig.ensureSetup()

// Check if we have CLI arguments (beyond just the program name)
let args = CommandLine.arguments.dropFirst()

// If no arguments, or first argument starts with "-psn" (Finder launch), run GUI
if args.isEmpty || args.first?.hasPrefix("-psn") == true {
    // Run GUI mode
    NSApplication.shared.setActivationPolicy(.accessory)
    ZeitAppGUI.main()
} else {
    // Run CLI mode synchronously using a semaphore
    let semaphore = DispatchSemaphore(value: 0)
    var cliError: Error?

    Task {
        do {
            var command = try ZeitCLI.parseAsRoot()

            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            cliError = error
        }
        semaphore.signal()
    }

    semaphore.wait()

    if let error = cliError {
        ZeitCLI.exit(withError: error)
    }
}
