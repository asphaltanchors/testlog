import SwiftUI
import SwiftData

#if os(macOS)
import AppKit

struct AppPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var allProducts: [Product]
    @Query(sort: \Site.name) private var allSites: [Site]
    @State private var productSearchText = ""
    @State private var showArchivedProducts = true
    @State private var selectedProductID: PersistentIdentifier?
    @State private var pendingProductDeletion: Product?
    @State private var isRepairingMedia = false

    private var filteredProducts: [Product] {
        allProducts.filter { product in
            let matchesArchive = showArchivedProducts || product.isActive
            guard matchesArchive else { return false }
            guard !productSearchText.isEmpty else { return true }
            let search = productSearchText.lowercased()
            return product.name.lowercased().contains(search) ||
                product.category.rawValue.lowercased().contains(search) ||
                (product.notes?.lowercased().contains(search) ?? false)
        }
    }

    private var selectedProduct: Product? {
        guard let selectedProductID else { return nil }
        return allProducts.first { $0.persistentModelID == selectedProductID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Products") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create, edit, archive, and delete products used in tests.")
                        .foregroundStyle(.secondary)

                    HSplitView {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Products")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    createProduct()
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.borderless)
                                .help("New Product")
                            }

                            TextField("Search products", text: $productSearchText)
                                .textFieldStyle(.roundedBorder)

                            Toggle("Show Archived", isOn: $showArchivedProducts)

                            List(selection: $selectedProductID) {
                                ForEach(filteredProducts, id: \.persistentModelID) { product in
                                    HStack {
                                        Text(product.name)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text(product.category.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !product.isActive {
                                            Text("Archived")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .tag(product.persistentModelID)
                                }
                            }
                            .frame(minWidth: 260, minHeight: 260)

                            if allProducts.isEmpty {
                                Button("Seed Default Products") {
                                    seedDefaultProducts(context: modelContext)
                                }
                            }
                        }

                        Group {
                            if let selectedProduct {
                                ProductPreferencesEditor(
                                    product: selectedProduct,
                                    relatedTestCount: selectedProduct.tests.count + selectedProduct.adhesiveTests.count,
                                    onDeleteRequest: {
                                        pendingProductDeletion = selectedProduct
                                    }
                                )
                                .padding(.leading, 12)
                            } else {
                                ContentUnavailableView(
                                    "Select a Product",
                                    systemImage: "shippingbox",
                                    description: Text("Pick a product to edit.")
                                )
                            }
                        }
                        .frame(minWidth: 360)
                    }
                }
            }

            GroupBox("Sites") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up test pads and site grids used in test records.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("New Site") {
                            createSite()
                        }

                        if allSites.isEmpty {
                            Button("Seed Main Pad Site") {
                                seedDefaultSites(context: modelContext)
                            }
                        }
                    }

                    Text("\(allSites.count) total sites")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Media") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scan managed media, reattach missing files, and deduplicate identical files.")
                        .foregroundStyle(.secondary)

                    Button("Fix Media Attachments") {
                        runMediaRepair()
                    }
                    .disabled(isRepairingMedia)
                }
            }
        }
        .onAppear {
            selectFirstVisibleProductIfNeeded()
        }
        .onChange(of: filteredProducts.map(\.persistentModelID)) { _, _ in
            selectFirstVisibleProductIfNeeded()
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
        .padding(20)
        .frame(minWidth: 900, minHeight: 580)
        .onExitCommand {
            dismiss()
        }
    }

    private func createProduct() {
        let product = Product(
            name: "New Product",
            category: .anchor
        )
        modelContext.insert(product)
        selectedProductID = product.persistentModelID
    }

    private var productDeleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingProductDeletion != nil },
            set: { if !$0 { pendingProductDeletion = nil } }
        )
    }

    private func deletePendingProduct() {
        guard let product = pendingProductDeletion else { return }
        let replacementSelection = allProducts
            .first(where: { $0.persistentModelID != product.persistentModelID })?
            .persistentModelID
        modelContext.delete(product)
        selectedProductID = replacementSelection
        pendingProductDeletion = nil
    }

    private func selectFirstVisibleProductIfNeeded() {
        guard !filteredProducts.isEmpty else {
            selectedProductID = nil
            return
        }
        guard let selectedProductID else {
            self.selectedProductID = filteredProducts.first?.persistentModelID
            return
        }
        if !filteredProducts.contains(where: { $0.persistentModelID == selectedProductID }) {
            self.selectedProductID = filteredProducts.first?.persistentModelID
        }
    }

    private func createSite() {
        let site = Site(
            name: "New Site",
            isPrimaryPad: allSites.isEmpty
        )
        modelContext.insert(site)
    }

    private func runMediaRepair() {
        guard !isRepairingMedia else { return }
        isRepairingMedia = true
        let container = modelContext.container
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                let backgroundContext = ModelContext(container)
                do {
                    return Result<MediaAttachmentRepairService.Report, Error>.success(
                        try MediaAttachmentRepairService().run(in: backgroundContext)
                    )
                } catch {
                    return Result<MediaAttachmentRepairService.Report, Error>.failure(error)
                }
            }.value
            isRepairingMedia = false

            switch result {
            case .success(let report):
                showRepairAlert(
                    title: "Media Repair Complete",
                    message: report.summary,
                    style: .informational
                )
            case .failure(let error):
                showRepairAlert(
                    title: "Media Repair Failed",
                    message: error.localizedDescription,
                    style: .critical
                )
            }
        }
    }

    private func showRepairAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private struct ProductPreferencesEditor: View {
    @Bindable var product: Product
    let relatedTestCount: Int
    let onDeleteRequest: () -> Void

    var body: some View {
        Form {
            Section("Product Info") {
                TextField("Name", text: $product.name)

                Picker("Category", selection: $product.category) {
                    ForEach(ProductCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }

                if product.category == .anchor {
                    OptionalEnumPicker("Default Hole Size", selection: $product.defaultHoleDiameter)

                    HStack {
                        Text("Rated Strength (lbs)")
                        Spacer()
                        TextField("lbs", value: $product.ratedStrengthLbs, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }

                Toggle("Active", isOn: $product.isActive)
                    .onChange(of: product.isActive) { _, isActive in
                        if isActive {
                            product.retiredOn = nil
                        } else if product.retiredOn == nil {
                            product.retiredOn = Date()
                        }
                    }

                if !product.isActive {
                    OptionalDatePicker("Retired On", selection: $product.retiredOn)
                    TextField(
                        "Retirement Note",
                        text: Binding(
                            get: { product.retirementNote ?? "" },
                            set: { product.retirementNote = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                }

                TextField(
                    "Notes",
                    text: Binding(
                        get: { product.notes ?? "" },
                        set: { product.notes = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)
            }

            Section("Usage") {
                Text("\(relatedTestCount) tests reference this product")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Delete Product", role: .destructive) {
                    onDeleteRequest()
                }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
