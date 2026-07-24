import Foundation

/// Binding mechanics for animations: the save-time style-block hook now;
/// bind/unbind/scan/propagate follow (mirroring `NamedStyles`).
public enum AnimationEngine {

    /// The one-liner save hook: recompile the generated style block from
    /// the document's FileMeta (+ workspace context), or remove it when
    /// animations are disabled or nothing is bound. Deterministic, so
    /// re-saves stay byte-identical.
    ///
    /// - `workspace`: the open workfile, if any — supplies workspace
    ///   defaults, and def names decide keyframes namespacing (workspace
    ///   defs compile globally, file-local ones icon-scoped).
    /// - `iconSlug`: sanitized file base name used to scope file-local
    ///   keyframes names; nil (lone SVG) compiles all names globally.
    public static func applyingStyleBlock(
        to doc: GraphicDocument, workspace: Workfile?, iconSlug: String? = nil
    ) -> GraphicDocument {
        let meta = FileMeta.read(from: doc)
        let settings = AnimationSettings.resolved(
            workspace: workspace?.settings?.animations, icon: meta?.animationSettings)
        let enabled = meta?.animationsEnabled ?? settings.enabled ?? true
        guard enabled, let bindings = meta?.animationBindings, !bindings.isEmpty else {
            return AnimationCSS.removing(from: doc)
        }
        // Defs: the icon's resolved copies win; the workspace fills gaps
        // (binding present but its copy not refreshed yet).
        var defs = meta?.animations ?? []
        var have = Set(defs.map(\.name))
        for def in workspace?.animations ?? [] where have.insert(def.name).inserted {
            defs.append(def)
        }
        let css = AnimationCSS.compile(
            defs: defs, bindings: bindings, settings: settings, iconSlug: iconSlug,
            workspaceDefNames: Set((workspace?.animations ?? []).map(\.name)))
        return AnimationCSS.writing(css, to: doc)
    }
}
