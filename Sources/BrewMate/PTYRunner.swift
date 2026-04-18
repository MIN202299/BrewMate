import Foundation
import Darwin

enum PTYSpawnError: Error, LocalizedError {
    case openptyFailed(Int32)
    case posixSpawnFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openptyFailed(let e):
            return "openpty failed: \(String(cString: strerror(e)))"
        case .posixSpawnFailed(let e):
            return "posix_spawn failed (\(e)): \(String(cString: strerror(e)))"
        }
    }
}

/// 管理一个运行在伪终端中的子进程
final class PTYController: @unchecked Sendable {
    let masterFD: Int32
    let pid: pid_t
    private var closed = false

    init(masterFD: Int32, pid: pid_t) {
        self.masterFD = masterFD
        self.pid = pid
    }

    func terminate() {
        if pid > 0 { _ = kill(pid, SIGTERM) }
    }

    func closeMaster() {
        if !closed { close(masterFD); closed = true }
    }

    func waitForExit() -> Int32 {
        var status: Int32 = 0
        var ret: pid_t
        repeat { ret = waitpid(pid, &status, 0) } while ret == -1 && errno == EINTR
        if (status & 0x7F) == 0 {
            return (status >> 8) & 0xFF
        } else {
            return 128 + (status & 0x7F)
        }
    }
}

/// 向 PTY 写入一行（密码输入），以 '\n' 结束
func writePTYPassword(_ s: String, toFD masterFD: Int32) {
    var bytes = Array(s.utf8)
    bytes.append(0x0A)
    bytes.withUnsafeBufferPointer { buf in
        var remaining = buf.count
        var offset = 0
        while remaining > 0 {
            let n = Darwin.write(masterFD, buf.baseAddress!.advanced(by: offset), remaining)
            if n <= 0 { break }
            remaining -= n; offset += n
        }
    }
}

/// 在一个新建的伪终端中启动子进程
func spawnPTY(executable: String, args: [String], env: [String: String]) throws -> PTYController {
    var master: Int32 = 0
    var slave: Int32 = 0
    var ws = winsize(ws_row: 40, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)

    if openpty(&master, &slave, nil, nil, &ws) != 0 {
        throw PTYSpawnError.openptyFailed(errno)
    }

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
    posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
    posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
    posix_spawn_file_actions_addclose(&fileActions, slave)
    posix_spawn_file_actions_addclose(&fileActions, master)

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

    let argvStrs = [executable] + args
    var argvPtrs: [UnsafeMutablePointer<CChar>?] = argvStrs.map { strdup($0) }
    argvPtrs.append(nil)
    defer { argvPtrs.forEach { if let p = $0 { free(p) } } }

    let envStrs = env.map { "\($0.key)=\($0.value)" }
    var envPtrs: [UnsafeMutablePointer<CChar>?] = envStrs.map { strdup($0) }
    envPtrs.append(nil)
    defer { envPtrs.forEach { if let p = $0 { free(p) } } }

    var pid: pid_t = 0
    let spawnResult = argvPtrs.withUnsafeBufferPointer { argvBuf in
        envPtrs.withUnsafeBufferPointer { envBuf in
            posix_spawn(&pid, executable, &fileActions, &attr, argvBuf.baseAddress, envBuf.baseAddress)
        }
    }

    close(slave)
    if spawnResult != 0 {
        close(master)
        throw PTYSpawnError.posixSpawnFailed(spawnResult)
    }

    return PTYController(masterFD: master, pid: pid)
}
