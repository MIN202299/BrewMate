import SwiftUI

struct JobLogView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedJobID: UUID? = nil

    var current: JobLog? {
        if let sel = selectedJobID, let j = model.jobs.first(where: { $0.id == sel }) { return j }
        return model.jobs.last
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("任务日志").font(.subheadline.bold())
                Spacer()
                // 横向标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(model.jobs) { job in
                            jobTab(job)
                        }
                    }
                }
                .frame(maxWidth: 500)
                Button {
                    model.showLogPanel = false
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if let job = current {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(job.lines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(idx)
                            }
                            Color.clear.frame(height: 1).id("__bottom__")
                        }
                        .padding(10)
                    }
                    .onChange(of: job.lines.count) { _, _ in
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo("__bottom__", anchor: .bottom)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                Text("无任务").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func jobTab(_ job: JobLog) -> some View {
        let isSelected = (current?.id == job.id)
        Button {
            selectedJobID = job.id
        } label: {
            HStack(spacing: 4) {
                statusIcon(job)
                Text(job.title).lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(_ job: JobLog) -> some View {
        switch job.status {
        case .running:
            ProgressView().controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
