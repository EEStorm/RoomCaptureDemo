//
//  MeshPreviewRenderer.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//

import Foundation
import Metal
import SceneKit
import UIKit

@MainActor
enum MeshPreviewRenderer {
    struct Output: Equatable {
        var realisticPNG: URL
        var wireframePNG: URL
        var overlayPNG: URL
    }

    static func renderPreviews(objURL: URL, folderURL: URL) throws -> Output {
        // Keep it lightweight; long captures can produce very large meshes.
        let size = CGSize(width: 960, height: 540)
        let device = MTLCreateSystemDefaultDevice()

        func render(style: MeshReviewStyle, name: String) throws -> URL {
            try autoreleasepool {
                let scene = try MeshReviewSceneBuilder.buildScene(objURL: objURL, style: style)
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.pointOfView = scene.rootNode.childNode(withName: "reviewCamera", recursively: true)
                let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
                let url = folderURL.appendingPathComponent(name)
                guard let data = image.pngData() else {
                    throw NSError(domain: "MeshPreviewRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
                }
                try data.write(to: url, options: [.atomic])
                renderer.scene = nil
                return url
            }
        }

        let realistic = try render(style: .realistic, name: "mesh_preview_realistic.png")
        let wire = try render(style: .wireframe, name: "mesh_preview_wireframe.png")
        let overlay = try render(style: .overlay, name: "mesh_preview_overlay.png")

        return Output(realisticPNG: realistic, wireframePNG: wire, overlayPNG: overlay)
    }
}
