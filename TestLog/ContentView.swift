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
    @AppStorage("sidebar.products.anchorsExpanded") private var isAnchorsExpanded = true
    @AppStorage("sidebar.products.adhesivesExpanded") private var isAdhesivesExpanded = true

    private var selectedTests: [PullTest] {
        allTests.filter { selectedTestIDs.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            contentView
        } detail: {
            detailView
        }
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

                Button {
                    createProductAndOpenEditor()
                } label: {
                    Label("New Product", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("Sites") {
                ForEach(allSites, id: \.persistentModelID) { site in
                    siteSidebarRow(site)
                }
                Button {
                    createSite()
                } label: {
                    Label("New Site", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
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
                title: "All Tests"
            )
        case .allProducts:
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
        case .allSites:
            SiteTableView(
                sites: allSites,
                selectedSiteIDs: $selectedSiteIDs,
                title: "All Sites",
                onAddSite: {
                    createSite(destination: .allSites)
                }
            )
        case .productCategory(let category):
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
        case .status(let status):
            TestTableView(
                tests: allTests.filter { $0.status == status },
                selectedTestIDs: $selectedTestIDs,
                title: status.rawValue
            )
        case .product(let productID):
            if let product = allProducts.first(where: { $0.persistentModelID == productID }) {
                let relatedTests = Array(Set(product.tests + product.adhesiveTests))
                TestTableView(
                    tests: relatedTests,
                    selectedTestIDs: $selectedTestIDs,
                    title: product.name
                )
            } else {
                ContentUnavailableView("Product Not Found", systemImage: "shippingbox")
            }
        case .site(let siteID):
            if let site = allSites.first(where: { $0.persistentModelID == siteID }) {
                let related = allTests.filter { $0.site?.persistentModelID == siteID }
                TestTableView(
                    tests: related,
                    selectedTestIDs: $selectedTestIDs,
                    title: site.name
                )
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
        case .site(let siteID):
            if let site = allSites.first(where: { $0.persistentModelID == siteID }) {
                SiteDetailView(site: site)
            } else {
                ContentUnavailableView("Site Not Found", systemImage: "map")
            }
        default:
            let selected = selectedTests
            if selected.count > 1 {
                BulkEditView(tests: selected)
            } else if let test = selected.first {
                TestDetailView(test: test)
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
        case .invalid: "xmark.circle"
        case .partial: "exclamationmark.triangle"
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
}

#Preview {
    ContentView()
        .modelContainer(for: [PullTest.self, Product.self, Site.self, Location.self, TestMeasurement.self, Asset.self], inMemory: true)
}
