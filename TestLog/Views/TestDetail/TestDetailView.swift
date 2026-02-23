import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit

struct TestDetailView: View {
    @Bindable var test: PullTest
#if os(macOS)
    var onOpenVideoWorkspace: ((PullTest) -> Void)? = nil
    var pendingAssetDropRequest: TestAssetDropRequest? = nil
    var onConsumePendingAssetDropRequest: ((UUID) -> Void)? = nil
#endif

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var allProducts: [Product]
    @Query(sort: \Site.name) private var allSites: [Site]
    @Query private var allTests: [PullTest]
    @Query private var allAssets: [Asset]

    @State private var showingDeleteConfirmation = false

#if os(macOS)
    @State private var isImportingAssets = false
    @State private var pendingImportCandidates: [ImportedAssetCandidate] = []
    @State private var showingImportReview = false
    @State private var showingVideoWorkspace = false
    @State private var isImportingCandidates = false
    @State private var importStatusMessage: String?
    @State private var duplicateTesterWarning: String?
    @State private var isAssetDropTargeted = false
#endif

    @State private var mediaErrorMessage: String?

    private let importCoordinator = TestAssetImportCoordinator()

    private var anchorProducts: [Product] {
        allProducts.filter {
            $0.category == .anchor
                && ($0.isActive || $0.persistentModelID == test.product?.persistentModelID)
        }
    }

    private var adhesiveProducts: [Product] {
        allProducts.filter {
            $0.category == .adhesive
                && ($0.isActive || $0.persistentModelID == test.adhesive?.persistentModelID)
        }
    }

    private var failureMechanismOptions: [FailureMechanism] {
        FailureMechanism.options(for: test.testType, family: test.failureFamily)
    }

    private var failureBehaviorOptions: [FailureBehavior] {
        FailureBehavior.options(for: test.failureFamily)
    }

    private var failureFamilyOptions: [FailureFamily] {
        FailureFamily.options(for: test.testType)
    }

    var body: some View {
        Form {
            TestIdentitySection(test: test)

            TestSiteLocationSection(
                test: test,
                allSites: allSites,
                allTests: allTests,
                modelContext: modelContext
            )

            TestProductsSection(
                test: test,
                anchorProducts: anchorProducts,
                adhesiveProducts: adhesiveProducts
            )

            TestResultsSection(
                test: test,
                failureFamilyOptions: failureFamilyOptions,
                failureMechanismOptions: failureMechanismOptions,
                failureBehaviorOptions: failureBehaviorOptions
            )

            TestMeasurementsSection(test: test, modelContext: modelContext)

#if os(macOS)
            TestMediaSection(
                test: test,
                onAttachFiles: { isImportingAssets = true },
                onOpenWorkspace: {
                    if let onOpenVideoWorkspace {
                        onOpenVideoWorkspace(test)
                    } else {
                        showingVideoWorkspace = true
                    }
                },
                onRemoveAsset: { asset in
                    removeAsset(asset)
                }
            )
#endif
        }
        .navigationTitle(test.testID ?? "New Test")
        .onAppear {
            test.syncFailureFieldsFromModeIfNeeded()
            test.normalizeFailureSelections()
            test.location?.site = test.site
        }
        .onChange(of: test.persistentModelID) { _, _ in
            test.syncFailureFieldsFromModeIfNeeded()
            test.normalizeFailureSelections()
            test.location?.site = test.site
        }
        .onChange(of: test.testType) { _, _ in
            test.normalizeFailureSelections()
        }
        .onChange(of: test.failureFamily) { _, _ in
            test.normalizeFailureSelections()
        }
        .onChange(of: test.product?.persistentModelID) { _, _ in
            if let defaultHole = test.product?.defaultHoleDiameter {
                test.holeDiameter = defaultHole
            }
        }
        .onChange(of: test.site?.persistentModelID) { _, _ in
            test.location?.site = test.site
        }
#if os(macOS)
        .formStyle(.grouped)
        .onDrop(of: [UTType.fileURL], isTargeted: $isAssetDropTargeted) { providers in
            handleDroppedFileProviders(providers) { urls in
                prepareImportCandidates(from: urls)
            }
        }
#endif
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .confirmationDialog("Delete this test?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(test)
                dismiss()
            }
        } message: {
            Text("This will permanently delete \(test.testID ?? "this test") and all its measurements.")
        }
#if os(macOS)
        .onChange(of: pendingAssetDropRequest?.id) { _, _ in
            consumePendingAssetDropIfNeeded()
        }
        .task(id: pendingAssetDropRequest?.id) {
            consumePendingAssetDropIfNeeded()
        }
        .sheet(isPresented: $showingImportReview) {
            TestImportReviewSheet(
                pendingImportCandidates: $pendingImportCandidates,
                isImportingCandidates: isImportingCandidates,
                importStatusMessage: importStatusMessage
            )
            .padding(18)
            .frame(width: 560)
            .fixedSize(horizontal: false, vertical: true)
            .presentationSizing(.fitted)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        guard !isImportingCandidates else { return }
                        pendingImportCandidates = []
                        showingImportReview = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImportingCandidates ? "Importing..." : "Import") {
                        isImportingCandidates = true
                        importStatusMessage = "Preparing import..."
                        Task {
                            await importPendingCandidates()
                        }
                    }
                    .disabled(pendingImportCandidates.isEmpty || isImportingCandidates)
                }
            }
        }
        .sheet(isPresented: $showingVideoWorkspace) {
            VideoWorkspaceView(test: test)
                .frame(minWidth: 980, idealWidth: 1240, minHeight: 760, idealHeight: 920)
                .presentationSizing(.page)
        }
        .onChange(of: showingImportReview) { _, newValue in
            if !newValue {
                isImportingCandidates = false
                importStatusMessage = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingAssets,
            allowedContentTypes: [.movie, .mpeg4Movie, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImportSelection(result)
        }
#endif
        .alert(
            "Media Error",
            isPresented: Binding(
                get: { mediaErrorMessage != nil },
                set: { if !$0 { mediaErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mediaErrorMessage ?? "Unknown error.")
        }
#if os(macOS)
        .alert(
            "File Already Used",
            isPresented: Binding(
                get: { duplicateTesterWarning != nil },
                set: { if !$0 { duplicateTesterWarning = nil } }
            )
        ) {
            Button("Attach Anyway") {
                duplicateTesterWarning = nil
                proceedWithImport()
            }
            Button("Cancel", role: .cancel) {
                duplicateTesterWarning = nil
                pendingImportCandidates = []
            }
        } message: {
            Text("\(duplicateTesterWarning ?? "") is already attached to another test. Attach it to this test as well?")
        }
#endif
    }
}

#if os(macOS)
private extension TestDetailView {
    func consumePendingAssetDropIfNeeded() {
        guard let request = pendingAssetDropRequest else { return }
        guard request.testID == test.persistentModelID else { return }
        prepareImportCandidates(from: request.urls)
        onConsumePendingAssetDropRequest?(request.id)
    }

    func handleFileImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            prepareImportCandidates(from: urls)
        case .failure(let error):
            mediaErrorMessage = error.localizedDescription
        }
    }

    func prepareImportCandidates(from urls: [URL]) {
        let candidates = importCoordinator.buildCandidates(
            urls: urls,
            existingVideos: test.videoAssets
        )
        guard !candidates.isEmpty else { return }
        pendingImportCandidates = candidates

        // Warn if any tester data file is already attached to a different test (by SHA256)
        let dupeNames = candidates.compactMap { candidate -> String? in
            guard candidate.selectedAssetType == .testerData else { return nil }
            guard let hash = sha256(of: candidate.sourceURL) else { return nil }
            let usedElsewhere = allAssets.contains {
                $0.assetType == .testerData &&
                $0.test?.persistentModelID != test.persistentModelID &&
                $0.checksumSHA256 == hash
            }
            return usedElsewhere ? candidate.sourceURL.lastPathComponent : nil
        }
        if !dupeNames.isEmpty {
            duplicateTesterWarning = dupeNames.joined(separator: ", ")
        } else {
            proceedWithImport()
        }
    }

    func proceedWithImport() {
        // If all files are tester data, skip the review sheet and import directly
        if pendingImportCandidates.allSatisfy({ $0.selectedAssetType == .testerData }) {
            isImportingCandidates = true
            Task {
                await importPendingCandidates()
            }
        } else {
            showingImportReview = true
        }
    }

    func importPendingCandidates() async {
        await Task.yield()
        importStatusMessage = "Validating files..."
        defer {
            isImportingCandidates = false
        }

        do {
            importStatusMessage = "Preparing import..."
            try await importCoordinator.importCandidates(
                pendingImportCandidates,
                into: test,
                modelContext: modelContext,
                progress: { message in
                    importStatusMessage = message
                }
            )
            importStatusMessage = "Import complete."
            showingImportReview = false
            pendingImportCandidates = []
        } catch {
            mediaErrorMessage = error.localizedDescription
            importStatusMessage = "Import failed."
        }
    }

    func sha256(of url: URL) -> String? {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = CryptoKit.SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func removeAsset(_ asset: Asset) {
        do {
            try importCoordinator.removeAsset(
                asset,
                from: test,
                allAssets: allAssets,
                modelContext: modelContext
            )
        } catch {
            mediaErrorMessage = error.localizedDescription
        }
    }
}
#endif
