//
//  MeshReviewSceneBuilder.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//

import Foundation
import SceneKit
import UIKit

enum MeshReviewStyle: String, CaseIterable, Identifiable {
    case realistic = "真实"
    case wireframe = "线框"
    case overlay = "叠加"

    var id: String { rawValue }
}

enum MeshReviewSceneBuilder {
    static func buildScene(objURL: URL, style: MeshReviewStyle) throws -> SCNScene {
        let imported = try SCNScene(url: objURL, options: [
            // Allow SceneKit to compute smoothing when possible.
            SCNSceneSource.LoadingOption.strictConformance: false,
        ])

        let scene = SCNScene()

        // Gather all geometry nodes under a container.
        let container = SCNNode()
        container.name = "meshContainer"
        for n in imported.rootNode.childNodes {
            container.addChildNode(n)
        }

        // Center the mesh around origin for easier inspection.
        let (min0, max0) = boundingBoxRecursive(node: container)
        let center0 = SCNVector3(
            (min0.x + max0.x) * 0.5,
            (min0.y + max0.y) * 0.5,
            (min0.z + max0.z) * 0.5
        )
        container.position = SCNVector3(-center0.x, -center0.y, -center0.z)
        // Recompute bounds after centering so camera/floor are correct.
        let (minV, maxV) = boundingBoxRecursive(node: container)

        // Create nodes for different styles.
        let meshNode: SCNNode
        switch style {
        case .realistic:
            meshNode = container
            applyRealisticMaterials(to: meshNode)
        case .wireframe:
            meshNode = container
            applyWireframeMaterials(to: meshNode)
        case .overlay:
            // Overlay = solid + wireframe clone.
            let solid = container
            applyRealisticMaterials(to: solid)
            let wire = container.clone()
            applyWireframeMaterials(to: wire)
            let group = SCNNode()
            group.addChildNode(solid)
            group.addChildNode(wire)
            meshNode = group
        }

        scene.rootNode.addChildNode(meshNode)

        // Add floor + axes for spatial cues.
        scene.rootNode.addChildNode(makeFloorNode(minV: minV, maxV: maxV))
        scene.rootNode.addChildNode(makeAxisNode(length: max(0.5, CGFloat(maxDimension(minV: minV, maxV: maxV)))))

        // Add camera + lights.
        let cameraNode = makeCameraNode(minV: minV, maxV: maxV)
        scene.rootNode.addChildNode(cameraNode)

        scene.rootNode.addChildNode(makeAmbientLightNode())
        scene.rootNode.addChildNode(makeKeyLightNode())
        scene.rootNode.addChildNode(makeFillLightNode())

        return scene
    }

    // MARK: - Materials

    private static func applyRealisticMaterials(to node: SCNNode) {
        node.enumerateChildNodes { n, _ in
            guard let geo = n.geometry else { return }
            // IMPORTANT: clone shares geometry/material instances; make them unique per node before mutating.
            if let copied = geo.copy() as? SCNGeometry {
                copied.materials = (copied.materials).map { ($0.copy() as? SCNMaterial) ?? $0 }
                n.geometry = copied
            }
            guard let g = n.geometry else { return }
            for m in geo.materials {
                // Physically based without environment maps can look confusing; use Blinn for clearer shape.
                m.lightingModel = .blinn
                m.diffuse.contents = UIColor(white: 0.78, alpha: 1)
                m.specular.contents = UIColor(white: 0.20, alpha: 1)
                m.shininess = 0.12
                m.emission.contents = UIColor(white: 0.02, alpha: 1)
                m.isDoubleSided = true
                m.blendMode = .replace
                m.fillMode = .fill
                m.writesToDepthBuffer = true
                m.readsFromDepthBuffer = true
            }
            _ = g
        }
    }

    private static func applyWireframeMaterials(to node: SCNNode) {
        node.enumerateChildNodes { n, _ in
            guard let geo = n.geometry else { return }
            // Ensure unique instances (clone shares by reference).
            if let copied = geo.copy() as? SCNGeometry {
                copied.materials = (copied.materials).map { ($0.copy() as? SCNMaterial) ?? $0 }
                n.geometry = copied
            }
            for m in geo.materials {
                m.lightingModel = .constant
                m.diffuse.contents = UIColor.green.withAlphaComponent(0.95)
                m.emission.contents = UIColor.green.withAlphaComponent(0.9)
                m.isDoubleSided = true
                m.blendMode = .add
                m.fillMode = .lines
                m.writesToDepthBuffer = false
                m.readsFromDepthBuffer = true
            }
        }
    }

    // MARK: - Helpers

    private static func maxDimension(minV: SCNVector3, maxV: SCNVector3) -> Float {
        max(maxV.x - minV.x, max(maxV.y - minV.y, maxV.z - minV.z))
    }

    private static func boundingBoxRecursive(node: SCNNode) -> (SCNVector3, SCNVector3) {
        var minAll = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxAll = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        node.enumerateChildNodes { n, _ in
            guard n.geometry != nil else { return }
            let (minV, maxV) = n.boundingBox
            if minV.x.isFinite, minV.y.isFinite, minV.z.isFinite,
               maxV.x.isFinite, maxV.y.isFinite, maxV.z.isFinite
            {
                // Transform local bbox into container space.
                let corners = [
                    SCNVector3(minV.x, minV.y, minV.z),
                    SCNVector3(maxV.x, minV.y, minV.z),
                    SCNVector3(minV.x, maxV.y, minV.z),
                    SCNVector3(minV.x, minV.y, maxV.z),
                    SCNVector3(maxV.x, maxV.y, minV.z),
                    SCNVector3(maxV.x, minV.y, maxV.z),
                    SCNVector3(minV.x, maxV.y, maxV.z),
                    SCNVector3(maxV.x, maxV.y, maxV.z),
                ]
                for c in corners {
                    let p = n.convertPosition(c, to: node)
                    minAll.x = min(minAll.x, p.x)
                    minAll.y = min(minAll.y, p.y)
                    minAll.z = min(minAll.z, p.z)
                    maxAll.x = max(maxAll.x, p.x)
                    maxAll.y = max(maxAll.y, p.y)
                    maxAll.z = max(maxAll.z, p.z)
                }
            }
        }

        if !minAll.x.isFinite || !minAll.y.isFinite || !minAll.z.isFinite {
            minAll = SCNVector3(-0.5, -0.5, -0.5)
            maxAll = SCNVector3(0.5, 0.5, 0.5)
        }

        return (minAll, maxAll)
    }

    private static func makeCameraNode(minV: SCNVector3, maxV: SCNVector3) -> SCNNode {
        let cam = SCNCamera()
        cam.fieldOfView = 55
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = true

        let node = SCNNode()
        node.camera = cam
        node.name = "reviewCamera"

        let center = SCNVector3(
            (minV.x + maxV.x) * 0.5,
            (minV.y + maxV.y) * 0.5,
            (minV.z + maxV.z) * 0.5
        )
        let d = CGFloat(maxDimension(minV: minV, maxV: maxV))
        let dist = max(1.2, d * 2.2)

        node.position = SCNVector3(center.x + Float(dist), center.y + Float(dist * 0.7), center.z + Float(dist))
        node.look(at: center)
        return node
    }

    private static func makeAmbientLightNode() -> SCNNode {
        let l = SCNLight()
        l.type = .ambient
        l.intensity = 520
        l.color = UIColor(white: 1, alpha: 1)
        let n = SCNNode()
        n.light = l
        return n
    }

    private static func makeKeyLightNode() -> SCNNode {
        let l = SCNLight()
        l.type = .directional
        l.intensity = 1200
        l.color = UIColor(white: 1, alpha: 1)
        l.castsShadow = true
        l.shadowMode = .deferred
        l.shadowRadius = 6
        l.shadowColor = UIColor.black.withAlphaComponent(0.35)
        let n = SCNNode()
        n.light = l
        n.eulerAngles = SCNVector3(-0.8, 0.8, 0)
        return n
    }

    private static func makeFillLightNode() -> SCNNode {
        let l = SCNLight()
        l.type = .omni
        l.intensity = 700
        l.color = UIColor(white: 1, alpha: 1)
        let n = SCNNode()
        n.light = l
        n.position = SCNVector3(-1.8, 1.8, -1.2)
        return n
    }

    private static func makeFloorNode(minV: SCNVector3, maxV: SCNVector3) -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.reflectionFalloffEnd = 0
        floor.reflectionFalloffStart = 0

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = makeGridImage(size: 512, step: 32)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        floor.materials = [material]

        let n = SCNNode(geometry: floor)
        n.name = "reviewFloor"

        // Put floor slightly below the mesh.
        let y = minV.y - 0.02
        n.position = SCNVector3(0, y, 0)

        // Scale tiling based on size.
        let d = CGFloat(maxDimension(minV: minV, maxV: maxV))
        let repeatScale = max(1, min(10, d))
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(repeatScale), Float(repeatScale), 1)

        return n
    }

    private static func makeAxisNode(length: CGFloat) -> SCNNode {
        let root = SCNNode()
        root.name = "reviewAxis"

        func makeLine(color: UIColor, to v: SCNVector3) -> SCNNode {
            let src = SCNGeometrySource(vertices: [SCNVector3Zero, v])
            let idx: [UInt32] = [0, 1]
            let data = idx.withUnsafeBytes { Data($0) }
            let element = SCNGeometryElement(
                data: data,
                primitiveType: .line,
                primitiveCount: 1,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            let g = SCNGeometry(sources: [src], elements: [element])
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = color
            g.materials = [m]
            return SCNNode(geometry: g)
        }

        root.addChildNode(makeLine(color: .systemRed, to: SCNVector3(Float(length), 0, 0)))   // X
        root.addChildNode(makeLine(color: .systemGreen, to: SCNVector3(0, Float(length), 0))) // Y
        root.addChildNode(makeLine(color: .systemBlue, to: SCNVector3(0, 0, Float(length))))  // Z

        return root
    }

    private static func makeGridImage(size: Int, step: Int) -> UIImage {
        let w = max(64, size)
        let h = w
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        return renderer.image { ctx in
            UIColor(white: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            let path = UIBezierPath()
            for x in stride(from: 0, through: w, by: step) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
            }
            for y in stride(from: 0, through: h, by: step) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
            path.lineWidth = 1
            UIColor(white: 0.18, alpha: 1).setStroke()
            path.stroke()

            // major lines
            let major = UIBezierPath()
            let majorStep = step * 4
            for x in stride(from: 0, through: w, by: majorStep) {
                major.move(to: CGPoint(x: x, y: 0))
                major.addLine(to: CGPoint(x: x, y: h))
            }
            for y in stride(from: 0, through: h, by: majorStep) {
                major.move(to: CGPoint(x: 0, y: y))
                major.addLine(to: CGPoint(x: w, y: y))
            }
            major.lineWidth = 1.5
            UIColor(white: 0.28, alpha: 1).setStroke()
            major.stroke()
        }
    }
}
