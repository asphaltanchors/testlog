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
    case session(PersistentIdentifier)
    case product(PersistentIdentifier)
    case status(TestStatus)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestSession.sessionDate, order: .reverse) private var sessions: [TestSession]
    @Query(sort: \Product.sku) private var allProducts: [Product]

    private var anchorProducts: [Product] {
        allProducts.filter { $0.category == .anchor }
    }
    private var adhesiveProducts: [Product] {
        allProducts.filter { $0.category == .adhesive }
    }
    @Query private var allTests: [PullTest]

    @State private var selectedSidebarItem: SidebarItem? = .allTests
    @State private var selectedTestIDs: Set<PersistentIdentifier> = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingSessionEditor: TestSession?
    @State private var showingProductEditor: Product?
    @State private var pendingSessionDeletion: TestSession?
    @State private var pendingProductDeletion: Product?

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
        .sheet(item: $showingSessionEditor) { session in
            NavigationStack {
                SessionDetailView(session: session)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSessionEditor = nil }
                        }
                    }
            }
            .frame(minWidth: 400, minHeight: 300)
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
            "Delete this session?",
            isPresented: sessionDeleteDialogBinding
        ) {
            Button("Delete", role: .destructive) {
                deletePendingSession()
            }
            Button("Cancel", role: .cancel) {
                pendingSessionDeletion = nil
            }
        } message: {
            if let session = pendingSessionDeletion {
                Text("This will delete the session and all \(session.tests.count) associated tests.")
            }
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
                Text("This will delete \(product.sku). Tests using this product will lose their product reference.")
            }
        }
        .onChange(of: selectedSidebarItem) { _, _ in
            // Keep detail pane in sync with the active middle-column dataset.
            selectedTestIDs.removeAll()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section("Library") {
                sidebarRow("All Tests", icon: "flask", tag: .allTests, badge: allTests.count)
            }

            Section("Status") {
                ForEach(TestStatus.allCases) { status in
                    let count = allTests.filter { $0.status == status }.count
                    sidebarRow(status.rawValue, icon: iconForStatus(status), tag: .status(status), badge: count)
                }
            }

            Section("Sessions") {
                ForEach(sessions, id: \.persistentModelID) { session in
                    sidebarRow(
                        session.sessionDate.formatted(.dateTime.month(.abbreviated).day().year()),
                        icon: "calendar",
                        tag: .session(session.persistentModelID),
                        badge: session.tests.count
                    )
                    .contextMenu {
                        Button("Edit Session...") {
                            showingSessionEditor = session
                        }
                        Divider()
                        Button("Delete Session", role: .destructive) {
                            pendingSessionDeletion = session
                        }
                    }
                }

                Button {
                    let session = TestSession(sessionDate: Date())
                    modelContext.insert(session)
                    selectedSidebarItem = .session(session.persistentModelID)
                } label: {
                    Label("New Session", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("Anchors") {
                ForEach(anchorProducts, id: \.persistentModelID) { product in
                    productSidebarRow(product)
                }

                Button {
                    let product = Product(sku: "NEW", displayName: "New Anchor", category: .anchor)
                    modelContext.insert(product)
                    selectedSidebarItem = .product(product.persistentModelID)
                    showingProductEditor = product
                } label: {
                    Label("New Anchor", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            Section("Adhesives") {
                ForEach(adhesiveProducts, id: \.persistentModelID) { product in
                    productSidebarRow(product)
                }

                Button {
                    let product = Product(sku: "NEW", displayName: "New Adhesive", category: .adhesive)
                    modelContext.insert(product)
                    selectedSidebarItem = .product(product.persistentModelID)
                    showingProductEditor = product
                } label: {
                    Label("New Adhesive", systemImage: "plus.circle")
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
            product.sku,
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
        case .status(let status):
            TestTableView(
                tests: allTests.filter { $0.status == status },
                selectedTestIDs: $selectedTestIDs,
                title: status.rawValue
            )
        case .session(let sessionID):
            if let session = sessions.first(where: { $0.persistentModelID == sessionID }) {
                TestTableView(
                    tests: session.tests,
                    selectedTestIDs: $selectedTestIDs,
                    title: session.sessionDate.formatted(.dateTime.month(.wide).day().year()),
                    session: session
                )
            } else {
                ContentUnavailableView("Session Not Found", systemImage: "calendar")
            }
        case .product(let productID):
            if let product = allProducts.first(where: { $0.persistentModelID == productID }) {
                let relatedTests = Array(Set(product.tests + product.adhesiveTests))
                TestTableView(
                    tests: relatedTests,
                    selectedTestIDs: $selectedTestIDs,
                    title: "\(product.sku) — \(product.displayName)"
                )
            } else {
                ContentUnavailableView("Product Not Found", systemImage: "shippingbox")
            }
        case nil:
            ContentUnavailableView("Select a Category", systemImage: "sidebar.left", description: Text("Choose a category from the sidebar."))
        }
    }

    // MARK: - Detail (right column)

    @ViewBuilder
    private var detailView: some View {
        let selected = selectedTests
        if selected.count > 1 {
            BulkEditView(tests: selected)
        } else if let test = selected.first {
            TestDetailView(test: test)
        } else {
            ContentUnavailableView("Select a Test", systemImage: "flask", description: Text("Choose a test to view its details."))
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

    private var sessionDeleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingSessionDeletion != nil },
            set: { if !$0 { pendingSessionDeletion = nil } }
        )
    }

    private var productDeleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingProductDeletion != nil },
            set: { if !$0 { pendingProductDeletion = nil } }
        )
    }

    private func deletePendingSession() {
        guard let session = pendingSessionDeletion else { return }
        if case .session(let id) = selectedSidebarItem, id == session.persistentModelID {
            selectedSidebarItem = .allTests
        }
        modelContext.delete(session)
        pendingSessionDeletion = nil
    }

    private func deletePendingProduct() {
        guard let product = pendingProductDeletion else { return }
        if case .product(let id) = selectedSidebarItem, id == product.persistentModelID {
            selectedSidebarItem = .allTests
        }
        modelContext.delete(product)
        pendingProductDeletion = nil
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PullTest.self, Product.self, TestSession.self], inMemory: true)
}
