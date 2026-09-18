import AppKit
import Foundation

private final class StateDispatcher: @unchecked Sendable {
    private let command: URL
    private let lock = NSLock()
    private var generation = 0
    private var desiredState: String?
    private var currentProcess: Process?

    init(command: URL) {
        self.command = command
    }

    func setState(_ state: String, retryDelays: [TimeInterval]) {
        lock.lock()
        guard desiredState != state else {
            lock.unlock()
            return
        }

        desiredState = state
        generation += 1
        let requestedGeneration = generation
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [self] in
            for delay in retryDelays {
                if delay > 0 {
                    Thread.sleep(forTimeInterval: delay)
                }

                lock.lock()
                guard generation == requestedGeneration else {
                    lock.unlock()
                    return
                }

                let process = Process()
                process.executableURL = command
                process.arguments = [state]

                do {
                    try process.run()
                    currentProcess = process
                    lock.unlock()
                } catch {
                    lock.unlock()
                    writeError("could not run \(command.path): \(error)")
                    continue
                }

                process.waitUntilExit()

                lock.lock()
                if currentProcess === process {
                    currentProcess = nil
                }
                let isCurrent = generation == requestedGeneration
                lock.unlock()

                if !isCurrent || process.terminationStatus == 0 {
                    return
                }
            }

            writeError("could not set desk lights to \(state)")
        }
    }
}

private func writeError(_ message: String) {
    let line = "desk-lights-watcher: \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

private let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
private let command = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : executableDirectory.appendingPathComponent("desk-lights")

guard FileManager.default.isExecutableFile(atPath: command.path) else {
    writeError("desk-lights is not executable at \(command.path)")
    exit(1)
}

private let dispatcher = StateDispatcher(command: command)
let notifications = NSWorkspace.shared.notificationCenter

let systemSleepObserver = notifications.addObserver(
    forName: NSWorkspace.willSleepNotification,
    object: nil,
    queue: .main
) { _ in
    writeError("system will sleep; setting off")
    dispatcher.setState("off", retryDelays: [0])
}

let sleepObserver = notifications.addObserver(
    forName: NSWorkspace.screensDidSleepNotification,
    object: nil,
    queue: .main
) { _ in
    writeError("displays slept; setting off")
    dispatcher.setState("off", retryDelays: [0])
}

let systemWakeObserver = notifications.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { _ in
    writeError("system woke; setting normal")
    dispatcher.setState("normal", retryDelays: [0, 1, 2, 4])
}

let wakeObserver = notifications.addObserver(
    forName: NSWorkspace.screensDidWakeNotification,
    object: nil,
    queue: .main
) { _ in
    writeError("displays woke; setting normal")
    // A full system wake can briefly precede Wi-Fi and Bonjour availability.
    dispatcher.setState("normal", retryDelays: [0, 1, 2, 4])
}

writeError("watching for display and system sleep/wake events")

withExtendedLifetime([
    systemSleepObserver,
    sleepObserver,
    systemWakeObserver,
    wakeObserver,
]) {
    RunLoop.main.run()
}
