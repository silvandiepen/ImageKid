import AppKit
import ImageKidCore
import SwiftUI

struct ColorStrip: View {
    let colors: [SampledColor]

    var body: some View {
        if !colors.isEmpty {
            HStack(spacing: 8) {
                ForEach(colors.suffix(8)) { sample in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sample.hex, forType: .string)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: sample.sRGB))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.primary.opacity(0.16)))
                            Text(sample.hex)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(sample.hex)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
    }
}
