import Darwin
import Foundation

enum HelperError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case readFailed(String)
    case writeFailed(String)
    case unsafeHostsPath(String)
    case commandFailed(String)

    var description: String {
        switch self {
        case .invalidRequest(let message): return message
        case .readFailed(let message): return message
        case .writeFailed(let message): return message
        case .unsafeHostsPath(let message): return message
        case .commandFailed(let message): return message
        }
    }
}

struct RequestPayload: Codable {
    let command: String
    let hosts_path: String?
    let input: String?
}

struct ResponsePayload: Codable {
    let ok: Bool
    let message: String
}

private func validatedHostsPath(_ rawPath: String?) throws -> String {
    let path = rawPath ?? "/etc/hosts"
    guard path == "/etc/hosts" else {
        throw HelperError.unsafeHostsPath("Refusing write outside /etc/hosts.")
    }
    return path
}

private func requireEffectiveRoot() throws {
    if geteuid() != 0 {
        throw HelperError.commandFailed("Helper must run with effective UID 0.")
    }
    if setuid(0) != 0 {
        throw HelperError.commandFailed(errnoMessage("Unable to promote helper real UID"))
    }
}

private func errnoMessage(_ prefix: String) -> String {
    "\(prefix): \(String(cString: strerror(errno)))"
}

private func copyFile(from inputPath: String, to outputPath: String) throws {
    let inputFD = open(inputPath, O_RDONLY)
    if inputFD < 0 {
        throw HelperError.readFailed(errnoMessage("Unable to read pending hosts content"))
    }
    defer {
        close(inputFD)
    }

    let outputFD = open(outputPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if outputFD < 0 {
        throw HelperError.writeFailed(errnoMessage("Unable to write \(outputPath)"))
    }
    defer {
        close(outputFD)
    }

    let bufferSize = 64 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer {
        buffer.deallocate()
    }

    while true {
        let bytesRead = read(inputFD, buffer, bufferSize)
        if bytesRead < 0 {
            throw HelperError.readFailed(errnoMessage("Unable to read pending hosts content"))
        }
        if bytesRead == 0 {
            break
        }

        var bytesWritten = 0
        while bytesWritten < bytesRead {
            let result = write(outputFD, buffer + bytesWritten, bytesRead - bytesWritten)
            if result < 0 {
                throw HelperError.writeFailed(errnoMessage("Unable to write \(outputPath)"))
            }
            bytesWritten += result
        }
    }

    if fsync(outputFD) != 0 {
        throw HelperError.writeFailed(errnoMessage("Unable to sync \(outputPath)"))
    }
}

@discardableResult
private func runCommand(_ executable: String, _ arguments: [String]) throws -> Int32 {
    var argv: [UnsafeMutablePointer<CChar>?] = []
    argv.append(strdup(executable))
    for argument in arguments {
        argv.append(strdup(argument))
    }
    argv.append(nil)
    defer {
        for pointer in argv {
            free(pointer)
        }
    }

    var pid = pid_t()
    let spawnResult = argv.withUnsafeMutableBufferPointer { buffer in
        posix_spawn(&pid, executable, nil, nil, buffer.baseAddress, nil)
    }
    if spawnResult != 0 {
        errno = spawnResult
        throw HelperError.commandFailed(errnoMessage("Failed to run \(executable)"))
    }

    var status: Int32 = 0
    if waitpid(pid, &status, 0) < 0 {
        throw HelperError.commandFailed(errnoMessage("Failed to wait for \(executable)"))
    }

    let exited = (status & 0x7f) == 0
    let exitCode = (status >> 8) & 0xff
    if !exited || exitCode != 0 {
        throw HelperError.commandFailed("Command failed: \(executable)")
    }
    return status
}

private func flushDNS() throws {
    _ = try runCommand("/usr/bin/dscacheutil", ["-flushcache"])
    _ = try runCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
}

private let helperSocketPath = "/var/run/com.serverengine.app.helper.sock"

private func handleRequest(_ request: RequestPayload) throws -> String {
    switch request.command {
    case "write-hosts":
        try requireEffectiveRoot()
        guard let inputPath = request.input, !inputPath.isEmpty else {
            throw HelperError.invalidRequest("write-hosts requires input.")
        }
        let hostsPath = try validatedHostsPath(request.hosts_path)
        try copyFile(from: inputPath, to: hostsPath)
        try flushDNS()
        return "Hosts file updated."
    case "flush-dns":
        try requireEffectiveRoot()
        try flushDNS()
        return "DNS cache flushed."
    default:
        throw HelperError.invalidRequest("Unknown command: \(request.command)")
    }
}

private func writeResponse(_ fd: Int32, ok: Bool, message: String) {
    let payload = ResponsePayload(ok: ok, message: message)
    guard let data = try? JSONEncoder().encode(payload) else {
        _ = Darwin.write(fd, "{\"ok\":false,\"message\":\"encode failed\"}\n", 39)
        return
    }
    _ = data.withUnsafeBytes { bytes in
        Darwin.write(fd, bytes.baseAddress, bytes.count)
    }
    _ = Darwin.write(fd, "\n", 1)
}

private func processClient(_ clientFD: Int32) {
    defer { close(clientFD) }
    var buffer = [UInt8](repeating: 0, count: 8192)
    let bytesRead = read(clientFD, &buffer, buffer.count)
    if bytesRead <= 0 {
        writeResponse(clientFD, ok: false, message: "Empty request.")
        return
    }
    let raw = Data(buffer[0..<bytesRead])
    let decoder = JSONDecoder()
    do {
        let request = try decoder.decode(RequestPayload.self, from: raw)
        let message = try handleRequest(request)
        writeResponse(clientFD, ok: true, message: message)
    } catch {
        let message: String
        if let helperError = error as? HelperError {
            message = helperError.description
        } else {
            message = "\(error)"
        }
        writeResponse(clientFD, ok: false, message: message)
    }
}

private func runServer() throws {
    try requireEffectiveRoot()

    unlink(helperSocketPath)
    let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    if serverFD < 0 {
        throw HelperError.commandFailed(errnoMessage("Unable to create helper socket"))
    }
    defer { close(serverFD) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(helperSocketPath.utf8CString)
    if pathBytes.count > MemoryLayout.size(ofValue: addr.sun_path) {
        throw HelperError.commandFailed("Socket path too long.")
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
        for (idx, byte) in pathBytes.enumerated() {
            raw[idx] = byte
        }
    }

    let addrLen = socklen_t(MemoryLayout.size(ofValue: addr.sun_family) + pathBytes.count)
    let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            Darwin.bind(serverFD, sockaddrPtr, addrLen)
        }
    }
    if bindResult != 0 {
        throw HelperError.commandFailed(errnoMessage("Unable to bind helper socket"))
    }
    if chmod(helperSocketPath, 0o666) != 0 {
        throw HelperError.commandFailed(errnoMessage("Unable to set helper socket permissions"))
    }
    if listen(serverFD, 16) != 0 {
        throw HelperError.commandFailed(errnoMessage("Unable to listen on helper socket"))
    }

    while true {
        let clientFD = accept(serverFD, nil, nil)
        if clientFD < 0 {
            continue
        }
        processClient(clientFD)
    }
}

do {
    try runServer()
    exit(EXIT_SUCCESS)
} catch {
    let message: String
    if let helperError = error as? HelperError {
        message = helperError.description
    } else {
        message = "\(error)"
    }
    fputs("ERROR: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}
