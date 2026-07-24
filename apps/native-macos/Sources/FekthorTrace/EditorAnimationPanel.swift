import FekthorKit
import SwiftUI

// The Animation palette: transport (play/pause/stop/loop) for the canvas
// preview, consumer-context simulation chips (hover/focus/active/gate),
// an Animate menu applying workspace/preset defs to the selection (or the
// whole icon), and the icon's bindings with per-binding trigger editing.
// The timeline drawer (deep keyframe editing) builds on the same scene.

struct AnimationPanelContent: View {
    @ObservedObject var session: EditorSession
    let workspace: WorkspaceSession
    @ObservedObject var preview: AnimationPreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            transport
            simulateChips
            Divider()
            applyMenu
            if session.animationBindings.isEmpty {
                Text("No animations on this icon yet. Select an element (or nothing, for the whole icon) and pick an animation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                bindingRows
            }
        }
        .padding(2)
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 8) {
            Button {
                preview.toggle()
            } label: {
                Image(systemName: preview.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!preview.hasScene(session))
            .help(preview.isPlaying ? "Pause preview" : "Play preview")
            .accessibilityIdentifier("animation.play")

            Button {
                preview.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!preview.hasScene(session))
            .help("Stop and rewind")
            .accessibilityIdentifier("animation.stop")

            Toggle(isOn: $preview.loop) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Loop the preview")

            Spacer()

            Button {
                EditorPanelsState.shared.timelineShown.toggle()
            } label: {
                Image(systemName: "timeline.selection")
            }
            .buttonStyle(.bordered)
            .help("Show the timeline")
            .accessibilityIdentifier("animation.timeline")
        }
    }

    /// Consumer-context simulation: the baked CSS only plays hover/focus/
    /// active/gated animations when the host page provides that state —
    /// these chips pretend it does, so every trigger previews in-editor.
    private var simulateChips: some View {
        HStack(spacing: 6) {
            simChip("Hover", isOn: $preview.state.hover)
            simChip("Focus", isOn: $preview.state.focus)
            simChip("Active", isOn: $preview.state.active)
            simChip(
                "Force",
                isOn: Binding(
                    get: { preview.state.forcePlay },
                    set: { preview.state.forcePlay = $0 }))
            Spacer()
        }
        .font(.caption)
    }

    private func simChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.button)
            .controlSize(.small)
    }

    // MARK: - Apply

    private var applyMenu: some View {
        Menu {
            ForEach(session.availableAnimationDefs, id: \.name) { def in
                Button(def.name) { session.applyAnimation(def) }
            }
        } label: {
            Label(
                session.selection.isEmpty ? "Animate Icon" : "Animate Selection",
                systemImage: "plus")
        }
        .accessibilityIdentifier("animation.apply")
    }

    // MARK: - Bindings

    private var bindingRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.animationBindings, id: \.target) { binding in
                AnimationBindingRow(session: session, preview: preview, binding: binding)
            }
        }
    }
}

/// One binding: def name + scope caption, trigger editing, remove. The
/// gate-class field appears for parent-class triggers.
private struct AnimationBindingRow: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var preview: AnimationPreviewController
    let binding: AnimationBinding

    private var trigger: AnimationTrigger {
        AnimationTrigger.parse(binding.trigger)
            ?? AnimationTrigger.parse(session.resolvedAnimationSettings.defaultTrigger)
            ?? .continuous
    }

    private var scopeCaption: String {
        if AnimationEngine.isWholeIcon(binding.target, in: session.document) {
            return "whole icon"
        }
        let count = AnimationEngine.boundNodeIDs(
            in: session.document, target: binding.target
        ).count
        return count == 1 ? "1 element" : "\(count) elements"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.secondary)
                Text(binding.animation).fontWeight(.medium)
                Text(scopeCaption).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    session.removeAnimation(target: binding.target)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this animation")
            }
            HStack(spacing: 6) {
                Picker("Trigger", selection: triggerSelection) {
                    Text("Continuous").tag("continuous")
                    Text("On Hover").tag("hover")
                    Text("On Focus").tag("focus")
                    Text("While Active").tag("active")
                    Text("Gated by Class").tag("parent-class")
                    Text("Manual").tag("manual")
                }
                .labelsHidden()
                .controlSize(.small)
            }
            if case .parentClass(let cls) = trigger {
                TextField("Gate class", text: gateClass(current: cls))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .help("The icon animates while an ancestor carries this class")
            }
        }
        .contextMenu {
            Button("Select Bound Elements") {
                let ids = AnimationEngine.boundNodeIDs(
                    in: session.document, target: binding.target)
                if !ids.isEmpty { session.selection = Set(ids) }
            }
            Button("Remove Animation", role: .destructive) {
                session.removeAnimation(target: binding.target)
            }
        }
    }

    /// The picker works on the trigger FAMILY; picking "Gated by Class"
    /// starts from the workspace's utility stem as a sensible gate.
    private var triggerSelection: Binding<String> {
        Binding(
            get: {
                if case .parentClass = trigger { return "parent-class" }
                return trigger.rawValue
            },
            set: { picked in
                let raw = picked == "parent-class" ? "parent-class:animate" : picked
                session.updateAnimationBinding(target: binding.target, label: "Trigger") {
                    $0.trigger = raw
                }
            })
    }

    private func gateClass(current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { text in
                let cls = text.isEmpty ? "animate" : text
                session.updateAnimationBinding(
                    target: binding.target, label: "Gate class",
                    coalesceKey: "anim.gate.\(binding.target)"
                ) {
                    $0.trigger = "parent-class:\(cls)"
                }
            })
    }
}
