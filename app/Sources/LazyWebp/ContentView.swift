import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Glass / Material Compatibility

struct GlassOrMaterial: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

struct GlassOrMaterialTinted: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(tint.opacity(0.3), lineWidth: 1))
        }
    }
}

struct ClearContainerBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

extension View {
    func glassOrMaterial(cornerRadius: CGFloat) -> some View {
        modifier(GlassOrMaterial(cornerRadius: cornerRadius))
    }

    func glassOrMaterial(cornerRadius: CGFloat, tint: Color) -> some View {
        modifier(GlassOrMaterialTinted(cornerRadius: cornerRadius, tint: tint))
    }
}

private final class SendableURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func append(_ url: URL) { lock.withLock { urls.append(url) } }
    var values: [URL] { lock.withLock { urls } }
}

struct FloatingWindowSetter: NSViewRepresentable {
    final class JsonView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.level = .floating
            window.isMovableByWindowBackground = true
        }
    }
    func makeNSView(context: Context) -> NSView { JsonView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Content View

struct ContentView: View {
    @State private var runner = ConversionRunner()
    @State private var quality: Double = 90
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            controlBar

            if !runner.files.isEmpty {
                fileListSection
            }

            if let error = runner.error {
                errorBanner(error)
            }

            if !runner.logLines.isEmpty && !runner.isRunning {
                logPanel
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 500)
        .animation(.easeInOut(duration: 0.2), value: runner.isRunning)
        .background(FloatingWindowSetter())
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDragOver ? Color.accentColor.opacity(0.08) : .clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDragOver ? Color.accentColor : .clear,
                            lineWidth: 2
                        )
                )

            VStack(spacing: 8) {
                Image(systemName: runner.files.isEmpty ? "arrow.down.doc" : "plus.circle")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text(runner.files.isEmpty ? "Drop images or folders here" : "Drop more files")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("A .webp version is generated next to each file")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("JPG, PNG, GIF, BMP, TIFF")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(minHeight: 140)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !runner.isRunning else { return }
            openPanel()
        }
        .scaleEffect(isDragOver ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragOver)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack {
            Spacer()

            HStack(spacing: 4) {
                Text("Quality")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                Slider(value: $quality, in: 1...100)
                    .frame(width: 70)
                    .controlSize(.mini)
                    .disabled(runner.isRunning)
                Text("\(Int(quality))")
                    .monospacedDigit()
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.15), in: Capsule())
        }
    }

    // MARK: - File List Section

    private var fileListSection: some View {
        VStack(spacing: 0) {
            summaryBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(runner.files) { file in
                        FileRow(file: file)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        if file.id != runner.files.last?.id {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)
        }
        .glassOrMaterial(cornerRadius: 10)
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            if runner.isPreparing {
                ProgressView()
                    .controlSize(.small)
                Text("Resolving \(runner.preparingCount) items...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(runner.doneCount)/\(runner.files.count) converted")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                if runner.convertedCount > 0 {
                    Text(formatBytes(runner.totalResultBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let savings = runner.totalSavings {
                        savingsBadge(savings)
                    }
                }

                Spacer()

                if runner.isRunning {
                    ProgressView(value: runner.overallProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 60)

                    Button("Cancel") {
                        runner.cancel()
                    }
                    .controlSize(.small)
                } else if !runner.files.isEmpty {
                    Button {
                        runner.reset()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear results")
                }
            }
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .glassOrMaterial(cornerRadius: 8, tint: .red)
    }

    // MARK: - Log Panel

    private var logPanel: some View {
        DisclosureGroup {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(runner.logLines) { entry in
                            Text(entry.text)
                                .font(.caption.monospaced())
                                .foregroundStyle(entry.isError ? .red : .secondary)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .frame(maxHeight: 120)
                .glassOrMaterial(cornerRadius: 8)
                .onChange(of: runner.logLines.count) {
                    if let last = runner.logLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        } label: {
            Label("Warnings & Errors (\(runner.logLines.count))", systemImage: "exclamationmark.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - File Row

    struct FileRow: View {
        let file: FileItem

        var body: some View {
            HStack(spacing: 8) {
                statusIcon
                    .frame(width: 20)

                Text(file.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(file.url.path)

                Spacer()

                if let orig = file.originalSize {
                    Text(formatBytes(orig))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if file.status == .done, let resultSize = file.resultSize {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formatBytes(resultSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let savings = file.savings {
                        savingsBadge(savings)
                    }
                }

                if file.status == .failed, let msg = file.errorMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(completionFlash)
        }

        @ViewBuilder
        private var statusIcon: some View {
            switch file.status {
            case .queued:
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .converting:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .skipped:
                Image(systemName: "minus.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        @ViewBuilder
        private var completionFlash: some View {
            if file.status == .done {
                Color.green.opacity(0.05)
            } else if file.status == .failed {
                Color.red.opacity(0.05)
            } else {
                Color.clear
            }
        }

    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let count = providers.count
        runner.prepareForDrop(count: count)

        let urls = SendableURLs()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }

        group.notify(queue: .main) { [quality] in
            let result = urls.values
            guard !result.isEmpty else {
                runner.isPreparing = false
                return
            }
            runner.enumerateFiles(from: result, recursive: true)
            runner.convert(quality: Int(quality))
        }

        return true
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [
            .image, .folder,
            .jpeg, .png, .gif, .bmp, .tiff,
        ]
        panel.message = "Select images or folders to convert to WebP"

        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard !urls.isEmpty else { return }

        runner.prepareForDrop(count: urls.count)
        runner.enumerateFiles(from: urls, recursive: true)
        runner.convert(quality: Int(quality))
    }
}

// MARK: - Shared View Helpers

private func savingsBadgeColor(_ percent: Int) -> Color {
    if percent > 50 { return .green }
    if percent > 20 { return .blue }
    return .gray
}

private func savingsBadge(_ savings: Double) -> some View {
    let percent = Int(savings * 100)
    let color = savingsBadgeColor(percent)
    return Text("-\(percent)%")
        .font(.caption2.bold())
        .monospacedDigit()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
}

// MARK: - Byte Formatting

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var size = Double(bytes)
    var unit = 0
    while size >= 1024 && unit < units.count - 1 {
        size /= 1024
        unit += 1
    }
    if unit == 0 {
        return "\(bytes) B"
    }
    return String(format: "%.1f %@", size, units[unit])
}
