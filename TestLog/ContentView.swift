//
//  ContentView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import SwiftUI
import SwiftData

// MARK: - Sidebar Navigation Model

enum SidebarItem: Hashable {
    case allTests
    case allProducts
    case allSites
    case productCategory(ProductCategory)
    case product(PersistentIdentifier)
    case site(PersistentIdentifier)
    case status(TestStatus)
}

#if os(macOS)
struct TestAssetDropRequest {
    let id = UUID()
    let testID: PersistentIdentifier
    let urls: [URL]
}
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.name) private var allProducts: [Product]
    @Query(sort: \Site.name) private var allSites: [Site]

    @Query private var allTests: [PullTest]

    private var anchorProducts: [Product] {
        allProducts.filter { $0.category == .anchor && $0.isActive }
    }

    private var adhesiveProducts: [Product] {
        allProducts.filter { $0.category == .adhesive && $0.isActive }
    }

    @State private var selectedSidebarItem: SidebarItem? = .allTests
    @State private var selectedTestIDs: Set<PersistentIdentifier> = []
    @State private var selectedProductIDs: Set<PersistentIdentifier> = []
    @State private var selectedSiteIDs: Set<PersistentIdentifier> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingProductEditor: Product?
    @State private var pendingProductDeletion: Product?
#if os(macOS)
    @State private var videoWorkspaceTestID: PersistentIdentifier?
    @State private var previousColumnVisibility: NavigationSplitViewVisibility = .all
    @State private var pendingTestAssetDropRequest: TestAssetDropRequest?
#endif
    @AppStorage("sidebar.products.anchorsExpanded") private var isAnchorsExpanded = true
    @AppStorage("sidebar.products.adhesivesExpanded") private var isAdhesivesExpanded = true

    private var selectedTests: [PullTest] {
        allTests.filter { selectedTestIDs.contains($0.persistentModelID) }
    }

    private var testDropHandler: ((PullTest, [URL]) -> Void)? {
#if os(macOS)
        handleDroppedFilesOntoTest
#else
        nil
#endif
    }

    var body: some View {
        #if os(macOS)
        ZStack {
            if !isVideoWorkspaceMode {
                mainSplitView
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if let videoWorkspaceTest {
                videoWorkspaceOverlay(for: videoWorkspaceTest)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: isVideoWorkspaceMode)
        .onChange(of: isVideoWorkspaceMode) { _, isWorkspace in
            let appearance: NSAppearance? = isWorkspace ? NSAppearance(named: .darkAqua) : nil
            NSApp.mainWindow?.appearance = appearance
        }
        .onChange(of: allTests.count) { _, _ in
            guard videoWorkspaceTestID != nil, videoWorkspaceTest == nil else { return }
            closeVideoWorkspaceEditMode()
        }
        #else
        mainSplitView
        #endif
    }

    @ViewBuilder
    private var splitViewBody: some View {
        if case .site(let siteID) = selectedSidebarItem,
           let site = allSites.first(where: { $0.persistentModelID == siteID }) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                #if os(macOS)
                sidebar.background(SplitColumnAutosave(key: "TestLog.2col"))
                #else
                sidebar
                #endif
            } detail: {
                SiteDetailView(site: site)
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                #if os(macOS)
                sidebar.background(SplitColumnAutosave(key: "TestLog.3col"))
                #else
                sidebar
                #endif
            } content: {
                contentView
            } detail: {
                detailView
            }
        }
    }

    private var mainSplitView: some View {
        splitViewBody
        .sheet(item: $showingProductEditor) { product in
            NavigationStack {
                ProductDetailView(product: product)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingProductEditor = nil }
                        }
                    }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
        .confirmationDialog(
            "Delete this product?",
            isPresented: productDeleteDialogBinding
        ) {
            Button("Delete", role: .destructive) {
                deletePendingProduct()
            }
            Button("Cancel", role: .cancel) {
                pendingProductDeletion = nil
            }
        } message: {
            if let product = pendingProductDeletion {
                Text("This will delete \(product.name). Tests using this product will lose their product reference.")
            }
        }
        .onChange(of: selectedSidebarItem) { _, _ in
            // Keep detail pane in sync with the active middle-column dataset.
            selectedTestIDs.removeAll()
            selectedProductIDs.removeAll()
            selectedSiteIDs.removeAll()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section("Library") {
                sidebarRow("All Tests", icon: "flask", tag: .allTests, badge: allTests.count)
                sidebarRow("All Products", icon: "shippingbox", tag: .allProducts, badge: allProducts.count)
                sidebarRow("All Sites", icon: "map", tag: .allSites, badge: allSites.count)
            }

            Section("Status") {
                ForEach(TestStatus.allCases) { status in
                    let count = allTests.filter { $0.status == status }.count
                    sidebarRow(status.rawValue, icon: iconForStatus(status), tag: .status(status), badge: count)
                }
            }

            Section("Products") {
                DisclosureGroup(isExpanded: $isAnchorsExpanded) {
                    ForEach(anchorProducts, id: \.persistentModelID) { product in
                        productSidebarRow(product)
                    }
                } label: {
                    Label("Anchors", systemImage: "folder")
                }
                .tag(SidebarItem.productCategory(.anchor))

                DisclosureGroup(isExpanded: $isAdhesivesExpanded) {
                    ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                        productSidebarRow(product)
                    }
                } label: {
                    Label("Adhesives", systemImage: "folder")
                }
                .tag(SidebarItem.productCategory(.adhesive))

#if os(iOS)
                Button {
                    createProductAndOpenEditor()
                } label: {
                    Label("New Product", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
#endif
            }

            Section("Sites") {
                ForEach(allSites, id: \.persistentModelID) { site in
                    siteSidebarRow(site)
                }
#if os(iOS)
                Button {
                    createSite()
                } label: {
                    Label("New Site", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
#endif
            }

            if allProducts.isEmpty {
                Section {
                    Button {
                        seedDefaultProducts(context: modelContext)
                    } label: {
                        Label("Seed Default Products", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if allSites.isEmpty {
                Section {
                    Button {
                        seedDefaultSites(context: modelContext)
                    } label: {
                        Label("Seed Main Pad Site", systemImage: "map")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("TestLog")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        #endif
    }

    private func sidebarRow(_ title: String, icon: String, tag: SidebarItem, badge: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(tag)
    }

    private func productSidebarRow(_ product: Product) -> some View {
        let count = product.tests.count + product.adhesiveTests.count
        return sidebarRow(
            product.name,
            icon: product.category == .anchor ? "shippingbox" : "drop.fill",
            tag: .product(product.persistentModelID),
            badge: count
        )
        .contextMenu {
            Button("Edit Product...") {
                showingProductEditor = product
            }
            Divider()
            Button("Delete Product", role: .destructive) {
                pendingProductDeletion = product
            }
        }
    }

    private func siteSidebarRow(_ site: Site) -> some View {
        let count = allTests.filter { $0.site?.persistentModelID == site.persistentModelID }.count
        return sidebarRow(
            site.name,
            icon: site.isPrimaryPad ? "star.circle.fill" : "map",
            tag: .site(site.persistentModelID),
            badge: count
        )
    }

    // MARK: - Content (middle column)

    @ViewBuilder
    private var contentView: some View {
        switch selectedSidebarItem {
        case .allTests:
            TestTableView(
                tests: allTests,
                selectedTestIDs: $selectedTestIDs,
                title: "All Tests",
                onDropFilesOntoTest: testDropHandler
            )
        case .allProducts:
#if os(iOS)
            ProductTableView(
                products: allProducts,
                selectedProductIDs: $selectedProductIDs,
                title: "All Products",
                onAddProduct: {
                    createProductAndOpenEditor(
                        preferredCategory: .anchor,
                        destination: .allProducts
                    )
                }
            )
#else
            ProductTableView(
                products: allProducts,
                selectedProductIDs: $selectedProductIDs,
                title: "All Products"
            )
#endif
        case .allSites:
#if os(iOS)
            SiteTableView(
                sites: allSites,
                selectedSiteIDs: $selectedSiteIDs,
                title: "All Sites",
                onAddSite: {
                    createSite(destination: .allSites)
                }
            )
#else
            SiteTableView(
                sites: allSites,
                selectedSiteIDs: $selectedSiteIDs,
                title: "All Sites"
            )
#endif
        case .productCategory(let category):
#if os(iOS)
            ProductTableView(
                products: allProducts.filter { $0.category == category },
                selectedProductIDs: $selectedProductIDs,
                title: category == .anchor ? "Anchor Products" : "Adhesive Products",
                onAddProduct: {
                    createProductAndOpenEditor(
                        preferredCategory: category,
                        destination: .productCategory(category)
                    )
                }
            )
#else
            ProductTableView(
                products: allProducts.filter { $0.category == category },
                selectedProductIDs: $selectedProductIDs,
                title: category == .anchor ? "Anchor Products" : "Adhesive Products"
            )
#endif
        case .status(let status):
            TestTableView(
                tests: allTests.filter { $0.status == status },
                selectedTestIDs: $selectedTestIDs,
                title: status.rawValue,
                onDropFilesOntoTest: testDropHandler
            )
        case .product(let productID):
            if let product = allProducts.first(where: { $0.persistentModelID == productID }) {
                let relatedTests = Array(Set(product.tests + product.adhesiveTests))
                TestTableView(
                    tests: relatedTests,
                    selectedTestIDs: $selectedTestIDs,
                    title: product.name,
                    onDropFilesOntoTest: testDropHandler
                )
            } else {
                ContentUnavailableView("Product Not Found", systemImage: "shippingbox")
            }
        case .site(let siteID):
            if let site = allSites.first(where: { $0.persistentModelID == siteID }) {
                SiteDetailView(site: site)
            } else {
                ContentUnavailableView("Site Not Found", systemImage: "map")
            }
        case nil:
            ContentUnavailableView("Select a Category", systemImage: "sidebar.left", description: Text("Choose a category from the sidebar."))
        }
    }

    // MARK: - Detail (right column)

    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarItem {
        case .allProducts, .productCategory(_):
            let selectedProducts = allProducts.filter { selectedProductIDs.contains($0.persistentModelID) }
            if let product = selectedProducts.first, selectedProducts.count == 1 {
                ProductDetailView(product: product)
            } else {
                ContentUnavailableView("Select a Product", systemImage: "shippingbox", description: Text("Choose a product to view its details."))
            }
        case .allSites:
            let selectedSites = allSites.filter { selectedSiteIDs.contains($0.persistentModelID) }
            if let site = selectedSites.first, selectedSites.count == 1 {
                SiteDetailView(site: site)
            } else {
                ContentUnavailableView("Select a Site", systemImage: "map", description: Text("Choose a site to view its details."))
            }
        case .site:
            EmptyView()
        default:
            let selected = selectedTests
            if selected.count > 1 {
                BulkEditView(tests: selected)
            } else if let test = selected.first {
                #if os(macOS)
                TestDetailView(
                    test: test,
                    onOpenVideoWorkspace: openVideoWorkspace,
                    pendingAssetDropRequest: pendingTestAssetDropRequest,
                    onConsumePendingAssetDropRequest: consumePendingAssetDropRequest
                )
                    .id(test.persistentModelID)
                #else
                TestDetailView(test: test)
                    .id(test.persistentModelID)
                #endif
            } else {
                ContentUnavailableView("Select a Test", systemImage: "flask", description: Text("Choose a test to view its details."))
            }
        }
    }

    // MARK: - Helpers

    private func iconForStatus(_ status: TestStatus) -> String {
        switch status {
        case .planned: "clock"
        case .installed: "wrench"
        case .completed: "checkmark.circle"
        }
    }

    private var productDeleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingProductDeletion != nil },
            set: { if !$0 { pendingProductDeletion = nil } }
        )
    }

    private func deletePendingProduct() {
        guard let product = pendingProductDeletion else { return }
        if case .product(let id) = selectedSidebarItem, id == product.persistentModelID {
            selectedSidebarItem = .allTests
        }
        selectedProductIDs.remove(product.persistentModelID)
        modelContext.delete(product)
        pendingProductDeletion = nil
    }

    #if os(iOS)
    private func createProductAndOpenEditor(
        preferredCategory: ProductCategory = .anchor,
        destination: SidebarItem = .allProducts
    ) {
        let product = Product(
            name: "New Product",
            category: preferredCategory
        )
        modelContext.insert(product)
        selectedSidebarItem = destination
        selectedProductIDs = [product.persistentModelID]
        showingProductEditor = product
    }

    private func createSite(destination: SidebarItem = .allSites) {
        let site = Site(
            name: "New Site",
            isPrimaryPad: allSites.isEmpty
        )
        modelContext.insert(site)
        selectedSidebarItem = destination
        selectedSiteIDs = [site.persistentModelID]
    }
    #endif

    #if os(macOS)
    private var videoWorkspaceTest: PullTest? {
        guard let videoWorkspaceTestID else { return nil }
        return allTests.first(where: { $0.persistentModelID == videoWorkspaceTestID })
    }

    private var isVideoWorkspaceMode: Bool {
        videoWorkspaceTest != nil
    }

    private func openVideoWorkspace(_ test: PullTest) {
        if videoWorkspaceTestID == nil {
            previousColumnVisibility = columnVisibility
        }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            videoWorkspaceTestID = test.persistentModelID
            columnVisibility = .detailOnly
        }
    }

    private func closeVideoWorkspaceEditMode() {
        guard videoWorkspaceTestID != nil else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            videoWorkspaceTestID = nil
            columnVisibility = previousColumnVisibility
        }
    }

    private func videoWorkspaceOverlay(for test: PullTest) -> some View {
        VideoWorkspaceView(
            test: test,
            onDone: closeVideoWorkspaceEditMode,
            usesImmersiveStyle: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    private func handleDroppedFilesOntoTest(_ test: PullTest, _ urls: [URL]) {
        guard !urls.isEmpty else { return }
        selectedTestIDs = [test.persistentModelID]
        pendingTestAssetDropRequest = TestAssetDropRequest(
            testID: test.persistentModelID,
            urls: urls
        )
    }

    private func consumePendingAssetDropRequest(_ requestID: UUID) {
        guard pendingTestAssetDropRequest?.id == requestID else { return }
        pendingTestAssetDropRequest = nil
    }
    #endif
}

// MARK: - NSSplitView column-width autosave

#if os(macOS)
/// Embed as `.background(SplitColumnAutosave(key:))` inside a NavigationSplitView column to
/// persist and restore split-view column widths across destroy/recreate cycles.
private struct SplitColumnAutosave: NSViewRepresentable {
    let key: String

    func makeCoordinator() -> Coordinator { Coordinator(key: key) }
    func makeNSView(context: Context) -> ProbeView { ProbeView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: ProbeView, context: Context) {}

    // MARK: Probe view — lives inside a column, walks up to find the NSSplitView
    final class ProbeView: NSView {
        weak var coordinator: Coordinator?
        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { [weak self] in self?.findSplitView() }
        }

        private func findSplitView() {
            var v: NSView? = superview
            while let current = v {
                if let sv = current as? NSSplitView {
                    coordinator?.connect(to: sv)
                    return
                }
                v = current.superview
            }
        }
    }

    // MARK: Coordinator — observes resize notifications and saves/restores positions
    final class Coordinator: NSObject {
        let key: String
        private weak var connectedSplitView: NSSplitView?

        init(key: String) { self.key = key }

        func connect(to sv: NSSplitView) {
            guard connectedSplitView !== sv else { return }
            connectedSplitView = sv
            sv.autosaveName = key
        }
    }
}
#endif

#Preview {
    ContentView()
        .modelContainer(for: [PullTest.self, Product.self, Site.self, Location.self, TestMeasurement.self, Asset.self, VideoSyncConfiguration.self], inMemory: true)
}
