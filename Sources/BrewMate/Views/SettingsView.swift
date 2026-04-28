import SwiftUI

struct SettingsView: View {
    @State private var settings = ProxySettings.shared
    @State private var testResult: String? = nil
    @State private var isTesting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack {
                Text("设置").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // ── Toggle row ───────────────────────────────────────────────
            HStack {
                Label("启用代理", systemImage: "network")
                Spacer()
                Toggle("", isOn: $settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .scaleEffect(0.85, anchor: .trailing)
                    .onChange(of: settings.enabled) { _, _ in testResult = nil }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)

            Divider()

            // ── URL fields ───────────────────────────────────────────────
            urlRow(label: "HTTP / HTTPS",
                   placeholder: "http://127.0.0.1:7890",
                   text: $settings.httpProxy)

            Divider()

            urlRow(label: "SOCKS5（可选）",
                   placeholder: "socks5://127.0.0.1:7890",
                   text: $settings.allProxy)

            Divider()

            // ── Test row ─────────────────────────────────────────────────
            HStack(spacing: 10) {
                Button {
                    isTesting = true
                    testResult = nil
                    Task {
                        testResult = await proxyConnectivityTest()
                        isTesting = false
                    }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("测试连接")
                    }
                }
                .disabled(!settings.enabled || settings.httpProxy.isEmpty || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? Color.green : .secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)

            Divider()

            // ── Footer ───────────────────────────────────────────────────
            Text("生效变量：http_proxy · https_proxy · all_proxy")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 400)
    }

    @ViewBuilder
    private func urlRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .disabled(!settings.enabled)
        .opacity(settings.enabled ? 1 : 0.4)
    }

    private func proxyConnectivityTest() async -> String {
        let proxy = settings.httpProxy
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                proc.arguments = [
                    "--max-time", "8",
                    "--connect-timeout", "6",
                    "--noproxy", "",        // 禁止任何系统代理干扰，只走 --proxy 指定的
                    "--proxy", proxy,
                    "-s", "-o", "/dev/null",
                    "-w", "%{http_code}",
                    "https://www.google.com"
                ]
                proc.standardOutput = Pipe()
                let outPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let code = String(data: data, encoding: .utf8) ?? ""
                    if proc.terminationStatus == 0, code == "200" {
                        continuation.resume(returning: "✓ 代理连通（HTTP \(code)）")
                    } else if proc.terminationStatus != 0 {
                        continuation.resume(returning: "✗ 连接失败（curl 退出码 \(proc.terminationStatus)）")
                    } else {
                        continuation.resume(returning: "△ 响应 HTTP \(code)，请检查代理配置")
                    }
                } catch {
                    continuation.resume(returning: "✗ \(error.localizedDescription)")
                }
            }
        }
    }
}
