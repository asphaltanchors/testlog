//
//  PhotoMapPickerView.swift
//  TestLog
//
//  Created by Oren Teich on 2/20/26.
//

import SwiftUI
import PhotosUI

#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct PhotoMapPickerView: View {
    @Bindable var site: Site
    @Binding var x: Double?
    @Binding var y: Double?
    var showGridOverlay: Bool = false

    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label(site.mapImageData == nil ? "Select Map Photo" : "Change Map Photo", systemImage: "photo")
                }

                if site.mapImageData != nil {
                    Button("Clear Photo", role: .destructive) {
                        site.mapImageData = nil
                        x = nil
                        y = nil
                    }
                }
            }

            if let image = mapImage {
                GeometryReader { geometry in
                    ZStack {
                        mapImageView(image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { gesture in
                                        updateCoordinate(from: gesture.location, in: geometry.size)
                                    }
                            )

                        if showGridOverlay {
                            gridOverlay(in: geometry.size)
                        }

                        if let x, let y {
                            Circle()
                                .fill(.red)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .position(x: geometry.size.width * x, y: geometry.size.height * y)
                        }
                    }
                }
                .frame(height: 220)

                if let x, let y {
                    Text("Pin: \(x.formatted(.number.precision(.fractionLength(3)))), \(y.formatted(.number.precision(.fractionLength(3))))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap the image to place a pin.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a map photo, then tap it to pin the test location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        site.mapImageData = data
                    }
                }
            }
        }
    }

    private var mapImage: PlatformImage? {
        guard let data = site.mapImageData else { return nil }
        return PlatformImage(data: data)
    }

    private func mapImageView(_ image: PlatformImage) -> Image {
        #if os(iOS)
        return Image(uiImage: image)
        #elseif os(macOS)
        return Image(nsImage: image)
        #endif
    }

    private func updateCoordinate(from location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let normalizedX = min(max(location.x / size.width, 0), 1)
        let normalizedY = min(max(location.y / size.height, 0), 1)
        x = normalizedX
        y = normalizedY
    }

    @ViewBuilder
    private func gridOverlay(in size: CGSize) -> some View {
        let columns = max(site.gridColumns ?? 0, 0)
        let rows = max(site.gridRows ?? 0, 0)

        if columns > 1 && rows > 1 {
            Path { path in
                for col in 1..<columns {
                    let x = size.width * Double(col) / Double(columns)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for row in 1..<rows {
                    let y = size.height * Double(row) / Double(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(.white.opacity(0.25), lineWidth: 0.5)
            .allowsHitTesting(false)
        }
    }
}
