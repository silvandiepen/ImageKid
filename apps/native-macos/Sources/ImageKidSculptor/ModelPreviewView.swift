import SceneKit
import SwiftUI

/// Interactive 3D preview of a generated model.
///
/// This is a product requirement, not debugging UI: a generation is only useful
/// if the user can rotate behind it and judge the inferred hidden geometry.
///
/// Loads the worker's preview PLY rather than the canonical GLB — Model I/O,
/// which backs SceneKit's asset loading, does not read GLB. Keeping the export
/// and the preview on separate files means the viewer never dictates what the
/// user's exported asset looks like.
struct ModelPreviewView: NSViewRepresentable {
    let previewURL: URL
    /// Bumped by the caller to force a reload when a new model is generated.
    let generation: Int

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        // Neutral studio ground, independent of the model's own colours.
        view.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        view.scene = makeScene()
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.loadedGeneration != generation else { return }
        context.coordinator.loadedGeneration = generation
        view.scene = makeScene()
        view.pointOfView = view.scene?.rootNode.childNode(
            withName: "camera", recursively: true
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedGeneration = -1
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        let modelNode = loadModel() ?? SCNNode()
        modelNode.name = "model"
        scene.rootNode.addChildNode(modelNode)

        frameCamera(on: modelNode, in: scene)
        addLighting(to: scene)
        return scene
    }

    private func loadModel() -> SCNNode? {
        guard FileManager.default.fileExists(atPath: previewURL.path) else { return nil }
        guard let loaded = try? SCNScene(url: previewURL, options: [
            .createNormalsIfAbsent: true
        ]) else { return nil }

        let node = SCNNode()
        for child in loaded.rootNode.childNodes {
            node.addChildNode(child)
        }

        // The worker exports per-vertex colour. SceneKit only shows it when a
        // material is told to read from that geometry source.
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            let material = geometry.firstMaterial ?? SCNMaterial()
            material.isDoubleSided = true

            if geometry.sources.contains(where: { $0.semantic == .color }) {
                // Vertex colour reaches the shader through `_geometry.color`,
                // which no material property exposes — assigning a colour to
                // `diffuse` just paints over it, and there is no
                // "use vertex colour" flag to set. A one-line surface modifier
                // is the supported way to read it.
                //
                // Lambert rather than physically-based: the models are painted
                // in flat tones, and PBR's specular response puts gradients and
                // highlights back over exactly the flatness that was the point.
                material.lightingModel = .lambert
                material.diffuse.contents = NSColor.white
                material.shaderModifiers = [
                    .surface: "_surface.diffuse *= _geometry.color;"
                ]
            } else {
                material.lightingModel = .lambert
                material.diffuse.contents = NSColor(calibratedWhite: 0.78, alpha: 1)
            }
            geometry.firstMaterial = material
        }
        return node
    }

    /// Frames the whole object so the user starts with it fully visible.
    private func frameCamera(on node: SCNNode, in scene: SCNScene) {
        let (minimum, maximum) = node.boundingBox
        let size = SCNVector3(
            maximum.x - minimum.x, maximum.y - minimum.y, maximum.z - minimum.z
        )
        let longest = max(size.x, max(size.y, size.z))
        let radius = max(Double(longest), 0.001)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 40
        camera.zNear = 0.001
        camera.zFar = radius * 40

        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        // Slightly above and in front, so the first view reads as a three
        // quarter rather than a flat elevation.
        cameraNode.position = SCNVector3(
            radius * 1.6, Double(minimum.y) + radius * 1.2, radius * 2.2
        )
        cameraNode.look(
            at: SCNVector3(0, Double(minimum.y) + radius * 0.45, 0)
        )
        scene.rootNode.addChildNode(cameraNode)
    }

    private func addLighting(to scene: SCNScene) {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 260
        ambient.color = NSColor(calibratedWhite: 1.0, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // A key and a fill, so the inferred back side is readable rather than
        // falling into silhouette when the user rotates around.
        for (position, intensity) in [
            (SCNVector3(4, 6, 6), 900.0), (SCNVector3(-5, 3, -5), 500.0)
        ] {
            let light = SCNLight()
            light.type = .omni
            light.intensity = intensity
            let node = SCNNode()
            node.light = light
            node.position = position
            scene.rootNode.addChildNode(node)
        }
    }
}
