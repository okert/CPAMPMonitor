import Foundation
import MonitorCore

@MainActor final class Tunnel {
    private var process: Process?
    private var identity = ""
    func prepare(_ config: Configuration) async throws {
        guard !config.sshHost.isEmpty else { stop(); return }
        let id = "\(config.sshHost):\(config.sshPort):\(config.localPort)"
        if process?.isRunning == true && identity == id { return }
        stop()
        guard !Self.canConnect(config.localPort) else {
            throw MonitorError("本地通道端口已被占用，请更换端口或关闭另一实例。")
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        child.arguments = ["-N", "-T", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes",
                           "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                           "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
                           "-L", "127.0.0.1:\(config.localPort):127.0.0.1:\(config.sshPort)", config.sshHost]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child; identity = id
        // Check process ownership as well as socket readiness; never reuse an
        // unrelated service already listening on the requested local port.
        for _ in 0..<110 {
            try await Task.sleep(nanoseconds: 100_000_000)
            guard child.isRunning else { throw MonitorError("SSH 通道失败：检查主机别名、免密登录和本地端口占用。") }
            if Self.canConnect(config.localPort) {
                try await Task.sleep(nanoseconds: 200_000_000)
                guard child.isRunning else { throw MonitorError("SSH 本地端口被占用。") }
                return
            }
        }
        stop()
        throw MonitorError("SSH 通道建立超时。")
    }
    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil; identity = ""
    }
    private static func canConnect(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
