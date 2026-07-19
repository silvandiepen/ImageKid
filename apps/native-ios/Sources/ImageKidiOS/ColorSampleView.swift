import AVFoundation
import SwiftUI
import UIKit

/// Colour inspector: drag on the image to sample a pixel, save swatches, and
/// copy their HEX or RGB values. Read-only — it never changes the image.
struct ColorSampleView: View {
    let image: CGImage

    @Environment(\.dismiss) private var dismiss
    @State private var current: SampledColor?
    @State private var saved: [SampledColor] = []
    @State private var sampleLocation: CGPoint?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                sampler
                currentSwatch
                savedStrip
            }
            .padding()
            .navigationTitle("Colour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private var sampler: some View {
        GeometryReader { geo in
            let imageRect = AVMakeRect(
                aspectRatio: CGSize(width: image.width, height: image.height),
                insideRect: CGRect(origin: .zero, size: geo.size)
            )
            ZStack {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                if let sampleLocation {
                    let point = CGPoint(
                        x: imageRect.minX + sampleLocation.x * imageRect.width,
                        y: imageRect.minY + sampleLocation.y * imageRect.height
                    )
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .background(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 4))
                        .frame(width: 28, height: 28)
                        .position(point)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let normalized = CGPoint(
                            x: min(max((value.location.x - imageRect.minX) / imageRect.width, 0), 1),
                            y: min(max((value.location.y - imageRect.minY) / imageRect.height, 0), 1)
                        )
                        sampleLocation = normalized
                        current = PixelSampler.sample(image, at: normalized)
                    }
            )
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var currentSwatch: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(current?.color ?? Color(.tertiarySystemFill))
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))

            VStack(alignment: .leading, spacing: 2) {
                Text(current?.hex ?? "—").font(.headline.monospaced())
                Text(current?.rgb ?? "Drag on the image to sample")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let current { saved.append(current) }
            } label: {
                Label("Save", systemImage: "plus.circle.fill")
            }
            .disabled(current == nil)
        }
    }

    private var savedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Saved").font(.headline)
                Spacer()
                if !saved.isEmpty {
                    Button("Clear") { saved.removeAll() }.font(.subheadline)
                }
            }
            if saved.isEmpty {
                Text("Saved colours appear here. Tap one to copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(saved) { swatch in
                            Menu {
                                Button("Copy HEX \(swatch.hex)") { copy(swatch.hex) }
                                Button("Copy \(swatch.rgb)") { copy(swatch.rgb) }
                                Button("Remove", role: .destructive) { remove(swatch) }
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(swatch.color)
                                        .frame(width: 48, height: 48)
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                                    Text(swatch.hex).font(.caption2.monospaced())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
    }

    private func remove(_ swatch: SampledColor) {
        saved.removeAll { $0.id == swatch.id }
    }
}
