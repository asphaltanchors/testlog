#if os(macOS)
import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VideoWorkspaceView: View {
    @Bindable var test: PullTest
    var onDone: (() -> Void)? = nil
    var usesImmersiveStyle = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var coordinator = VideoWorkspaceCoordinator()

    private let syncService: VideoSyncing = DefaultVideoSyncService()
    private let exportService: VideoExporting = DefaultVideoExportService()
    private let testerDataParser: TesterDataParsing = LBYTesterDataParser()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VideoWorkspaceHeader(
                    testID: test.testID,
                    usesImmersiveStyle: usesImmersiveStyle,
                    canExport: coordinator.hasPrimaryVideo,
                    isExportingVideo: coordinator.isExportingVideo,
                    onExport: beginExportFlow,
                    onDone: closeWorkspace
                )

                GroupBox("Preview") {
                    VideoWorkspacePreviewArea(
                        coordinator: coordinator,
                        primaryAsset: coordinator.primaryVideoAsset,
                        equipmentAsset: coordinator.equipmentVideoAsset
                    )
                    .frame(minHeight: 320)
                }

                GroupBox("Timeline") {
                    VideoWorkspaceTimeline(coordinator: coordinator)
                        .frame(height: 136)
                }

                GroupBox("Workspace Controls") {
                    VideoWorkspaceControls(
                        coordinator: coordinator,
                        videoAssets: coordinator.videoAssets
                    )
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(16)
        .background {
            if usesImmersiveStyle {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.08, green: 0.08, blue: 0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        }
        .navigationTitle(usesImmersiveStyle ? "" : "Video Workspace")
        .toolbar {
            if usesImmersiveStyle {
                ToolbarItem(placement: .principal) {
                    Label("Video Edit Mode", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        beginExportFlow()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(coordinator.isExportingVideo || !coordinator.hasPrimaryVideo)

                    Button("Done") {
                        closeWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
        .focusable()
        .onKeyPress(.space) {
            coordinator.handleSpaceBarPress()
            return .handled
        }
        .onAppear {
            coordinator.configure(
                test: test,
                modelContext: modelContext,
                syncService: syncService,
                exportService: exportService,
                testerDataParser: testerDataParser
            )
            Task {
                await coordinator.runInitialAutoSyncIfNeeded()
            }
        }
        .onChange(of: test.assets.count) { _, _ in
            coordinator.refreshSelectionAfterAssetsChange()
        }
        .onDisappear {
            coordinator.handleDisappear()
        }
        .alert(
            "Video Error",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(coordinator.errorMessage ?? "Unknown error.")
        }
        .sheet(
            isPresented: Binding(
                get: { coordinator.exportModalState != nil },
                set: { isPresented in
                    if !isPresented {
                        coordinator.clearExportModalIfIdle()
                    }
                }
            )
        ) {
            VideoWorkspaceExportSheet(
                exportModalState: coordinator.exportModalState,
                isExportingVideo: coordinator.isExportingVideo,
                onClose: {
                    coordinator.exportModalState = nil
                },
                onDone: {
                    coordinator.exportModalState = nil
                    closeWorkspace()
                }
            )
            .frame(minWidth: 430)
            .padding(20)
            .interactiveDismissDisabled(coordinator.isExportingVideo)
        }
    }

    private func beginExportFlow() {
        guard coordinator.hasPrimaryVideo else {
            coordinator.errorMessage = VideoFeatureError.missingPrimaryVideo.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(test.testID ?? "Test")_composed.mp4"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        coordinator.beginExport(to: outputURL)
    }

    private func closeWorkspace() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
}
#endif
