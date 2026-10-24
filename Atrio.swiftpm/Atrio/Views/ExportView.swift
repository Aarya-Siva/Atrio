import PDFKit
import SwiftUI

struct ExportView: View {
    let measurement: Measurement
    let format: ExportFormat
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var errorMessage: String?
    @State private var exporter = ResearchExport()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Export unavailable", systemImage: "doc")
                    } description: { Text(errorMessage) } actions: {
                        Button("Try Again") { Task { await prepare() } }
                    }
                } else if files.isEmpty {
                    ProgressView("Preparing export…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if format == .pdf, let url = files.first {
                        PDFPreview(url: url).accessibilityLabel("Preview of your recording report")
                    } else {
                        Text("Original recording data").font(.title2.weight(.semibold))
                        Text("Three files: original RGB samples, retained pulse intervals, and recording metadata. Timestamps and raw values are preserved for signal analysis.")
                            .font(.body).foregroundStyle(AppColors.secondaryText)
                        ForEach(files, id: \.lastPathComponent) { url in
                            Label(url.lastPathComponent, systemImage: "doc.text").font(.caption).textSelection(.enabled)
                        }
                        Spacer()
                    }
                    Text("Only share with people you choose. Exported copies leave the app’s protected storage and may contain sensitive recording details.")
                        .font(.caption).foregroundStyle(AppColors.secondaryText)
                    ShareLink(items: files) {
                        Label("Share or Save to Files", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accent)
                    .accessibilityIdentifier("shareExportButton")
                }
            }
            .padding(20)
            .background(AppColors.background.ignoresSafeArea())
            .foregroundStyle(AppColors.heading)
            .navigationTitle(format.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await prepare() }
            .onDisappear {
                let exported = files
                Task { await exporter.remove(exported) }
            }
        }
    }

    private func prepare() async {
        guard files.isEmpty else { return }
        errorMessage = nil
        do {
            let pdf = format == .pdf ? ResearchPDFRenderer.render(measurement) : nil
            let prepared = try await exporter.prepare(measurement, pdf: pdf)
            if Task.isCancelled { await exporter.remove(prepared); return }
            files = prepared
        } catch { errorMessage = "The export could not be created. \(error.localizedDescription)" }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = UIColor(AppColors.background)
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) { }
}
