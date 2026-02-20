//
//  TestListView.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//
//  Shared components used by TestTableView and other views.

import SwiftUI

// MARK: - Test Row (for iOS list / detail pane)

struct TestRowView: View {
    let test: PullTest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(test.testID ?? "New Test")
                    .font(.headline)
                Spacer()
                StatusBadge(status: test.status)
            }
            HStack(spacing: 8) {
                if let product = test.product {
                    Label(product.sku, systemImage: "shippingbox")
                        .font(.subheadline)
                }
                if let adhesive = test.adhesive {
                    Text(adhesive.sku)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let diameter = test.holeDiameter {
                    Text(diameter.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let date = test.testedDate {
                Text(date, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: TestStatus

    var color: Color {
        switch status {
        case .planned: .blue
        case .installed: .orange
        case .completed: .green
        case .invalid: .red
        case .partial: .yellow
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
