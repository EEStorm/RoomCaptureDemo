//
//  LiveMeshPreviewSceneStore.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/5/19.
//

import Foundation
import SceneKit
import simd
import UIKit

@MainActor
final class LiveMeshPreviewSceneStore: ObservableObject {
    @Published private(set) var hasContent: Bool = false

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let containerNode = SCNNode()
    private var anchorNodes: [UUID: SCNNode] = [:]
    private let previewNodeScale: Float = 2.0
    private let previewCameraInteriorDistanceRatio: CGFloat = 1.5
    private let previewCameraBaseElevation: CGFloat = .pi / 4.3
    private let previewCameraMinimumElevation: CGFloat = .pi / 7.4
    private let previewCameraMaximumElevation: CGFloat = .pi / 3.6
    private let previewCameraShoulderOffset: CGFloat = .pi / 5
    private let previewCameraMinimumDistance: CGFloat = 0.55
    private let headingFollowSmoothing: CGFloat = 5.5
    private let pitchNudgeScale: CGFloat = 0.12
    private let pitchNudgeLimit: CGFloat = .pi / 30
    private let framingUpdateInterval: TimeInterval = 0.10
    private let framingSmoothing: CGFloat = 7.0
    private let roomCutawayNearDepthRatio: Float = 0.22
    private let roomCutawayFadeDepthRatio: Float = 0.06
    private let roomCutawayMinimumFadeDepth: Float = 0.035

    private var cameraDistance: CGFloat = 1.8
    private var cameraYaw: CGFloat = .pi / 4
    private var pitchNudge: CGFloat = 0
    private var modelLookAtY: Float = 0
    private var lastFollowTimestamp: TimeInterval?
    private var smoothedContainerPosition: SCNVector3?
    private var smoothedCameraDistance: CGFloat?
    private var smoothedLookAtY: Float?
    private var lastFramingTimestamp: TimeInterval?
    private var lastCutawayTimestamp: TimeInterval?
    private var previewCutDepth: Float = 0
    private var previewCutFade: Float = 0.001

    private static func roomCutawayShaderModifier(cutDepth: Float, cutFade: Float) -> String {
        let cutDepthLiteral = shaderFloatLiteral(cutDepth)
        let cutFadeLiteral = shaderFloatLiteral(max(0.001, cutFade))
        return """
    #pragma body
    float livePreviewCutDepth = \(cutDepthLiteral);
    float livePreviewCutFade = \(cutFadeLiteral);
    float depth = max(0.0, -_surface.position.z);
    float cutAlpha = smoothstep(livePreviewCutDepth, livePreviewCutDepth + livePreviewCutFade, depth);
    float t = clamp(depth / 2.6, 0.0, 1.0);
    t = pow(t, 0.55);
    float shade = mix(0.98, 0.72, smoothstep(0.0, 0.42, t));
    shade = mix(shade, 0.36, smoothstep(0.35, 1.0, t));
    _surface.diffuse = vec4(vec3(shade), _surface.diffuse.a * cutAlpha);
    """
    }

    private static func shaderFloatLiteral(_ value: Float) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    init() {
        scene.background.contents = UIColor.black

        containerNode.name = "liveMeshContainer"
        scene.rootNode.addChildNode(containerNode)

        let camera = SCNCamera()
        camera.fieldOfView = 46
        camera.zNear = 0.01
        camera.zFar = 100
        cameraNode.camera = camera
        cameraNode.name = "liveMeshCamera"
        scene.rootNode.addChildNode(cameraNode)

        applyPreviewCameraPose()
    }

    func reset() {
        anchorNodes.removeAll()
        containerNode.childNodes.forEach { $0.removeFromParentNode() }
        containerNode.position = SCNVector3Make(0, 0, 0)
        hasContent = false
        cameraDistance = 1.8
        cameraYaw = .pi / 4
        pitchNudge = 0
        modelLookAtY = 0
        lastFollowTimestamp = nil
        smoothedContainerPosition = nil
        smoothedCameraDistance = nil
        smoothedLookAtY = nil
        lastFramingTimestamp = nil
        lastCutawayTimestamp = nil
        previewCutDepth = 0
        previewCutFade = 0.001
        applyPreviewCameraPose()
    }

    func upsert(anchorID: UUID, transform: simd_float4x4, geometry: SCNGeometry) {
        let node = anchorNodes[anchorID] ?? makeAnchorNode()
        node.geometry = makePreviewGeometry(from: geometry)
        node.simdTransform = transform
        node.simdScale = SIMD3<Float>(repeating: previewNodeScale)

        if node.parent == nil {
            containerNode.addChildNode(node)
        }
        anchorNodes[anchorID] = node

        hasContent = !anchorNodes.isEmpty
        frameScene(force: smoothedContainerPosition == nil)
    }

    func remove(anchorID: UUID) {
        guard let node = anchorNodes.removeValue(forKey: anchorID) else { return }
        node.removeFromParentNode()

        hasContent = !anchorNodes.isEmpty
        if hasContent {
            frameScene()
        } else {
            containerNode.position = SCNVector3Make(0, 0, 0)
            cameraDistance = 1.8
            cameraYaw = .pi / 4
            pitchNudge = 0
            modelLookAtY = 0
            lastFollowTimestamp = nil
            smoothedContainerPosition = nil
            smoothedCameraDistance = nil
            smoothedLookAtY = nil
            lastFramingTimestamp = nil
            lastCutawayTimestamp = nil
            previewCutDepth = 0
            previewCutFade = 0.001
            applyPreviewCameraPose()
        }
    }

    func updateDeviceOrientation(cameraTransform: simd_float4x4, timestamp: TimeInterval) {
        guard hasContent else {
            lastFollowTimestamp = timestamp
            return
        }

        let currentRotation = simd_quatf(cameraTransform)
        let forward = currentRotation.act(SIMD3<Float>(0, 0, -1))
        let behindYaw = atan2(CGFloat(-forward.x), CGFloat(-forward.z))
        let targetYaw = normalizeAngle(behindYaw + previewCameraShoulderOffset)

        let horizontalMagnitude = max(0.001, CGFloat(sqrt(forward.x * forward.x + forward.z * forward.z)))
        let devicePitch = atan2(CGFloat(forward.y), horizontalMagnitude)
        let targetPitchNudge = clamp(-devicePitch * pitchNudgeScale, min: -pitchNudgeLimit, max: pitchNudgeLimit)

        guard let previousTimestamp = lastFollowTimestamp else {
            cameraYaw = targetYaw
            pitchNudge = targetPitchNudge
            lastFollowTimestamp = timestamp
            applyPreviewCameraPose()
            return
        }

        let dt = max(timestamp - previousTimestamp, 1.0 / 60.0)
        let alpha = 1.0 - exp(-dt * headingFollowSmoothing)
        let yawDelta = shortestAngle(from: cameraYaw, to: targetYaw)
        cameraYaw = normalizeAngle(cameraYaw + yawDelta * alpha)
        pitchNudge += (targetPitchNudge - pitchNudge) * alpha
        lastFollowTimestamp = timestamp

        applyPreviewCameraPose()
    }

    private func makeAnchorNode() -> SCNNode {
        let node = SCNNode()
        node.name = "liveMeshAnchor"
        return node
    }

    private func frameScene(force: Bool = false) {
        let timestamp = ProcessInfo.processInfo.systemUptime
        if !force,
           let lastFramingTimestamp,
           timestamp - lastFramingTimestamp < framingUpdateInterval
        {
            refreshCutawayUniformsIfNeeded(timestamp: timestamp)
            return
        }

        let (min0, max0) = boundingBoxRecursive(node: containerNode)
        let center0 = SCNVector3(
            (min0.x + max0.x) * 0.5,
            (min0.y + max0.y) * 0.5,
            (min0.z + max0.z) * 0.5
        )
        let targetPosition = SCNVector3(-center0.x, -min0.y, -center0.z)
        let alpha = framingAlpha(timestamp: timestamp, force: force)
        let nextPosition: SCNVector3
        if let smoothedContainerPosition {
            nextPosition = lerp(smoothedContainerPosition, targetPosition, alpha: Float(alpha))
        } else {
            nextPosition = targetPosition
        }
        smoothedContainerPosition = nextPosition
        containerNode.position = nextPosition

        let (minV, maxV) = boundingBoxInScene(node: containerNode) ?? boundingBoxRecursive(node: containerNode)
        let horizontalWidth = CGFloat(maxV.x - minV.x)
        let horizontalDepth = CGFloat(maxV.z - minV.z)
        let shorterHorizontalSpan = max(0.001, min(horizontalWidth, horizontalDepth))
        let targetDistance = max(previewCameraMinimumDistance, shorterHorizontalSpan * previewCameraInteriorDistanceRatio)
        let targetLookAtY = (minV.y + maxV.y) * 0.5

        if let smoothedCameraDistance {
            cameraDistance = smoothedCameraDistance + (targetDistance - smoothedCameraDistance) * alpha
        } else {
            cameraDistance = targetDistance
        }
        smoothedCameraDistance = cameraDistance

        if let smoothedLookAtY {
            modelLookAtY = smoothedLookAtY + (targetLookAtY - smoothedLookAtY) * Float(alpha)
        } else {
            modelLookAtY = targetLookAtY
        }
        smoothedLookAtY = modelLookAtY
        lastFramingTimestamp = timestamp

        applyPreviewCameraPose(forceCutawayUpdate: true)
    }

    private func applyPreviewCameraPose(forceCutawayUpdate: Bool = false) {
        let elevation = clamp(
            previewCameraBaseElevation + pitchNudge,
            min: previewCameraMinimumElevation,
            max: previewCameraMaximumElevation
        )
        let horizontalRadius = Float(cameraDistance)
        let height = Float(cameraDistance * tan(elevation))
        let x = Float(sin(cameraYaw)) * horizontalRadius
        let z = Float(cos(cameraYaw)) * horizontalRadius
        cameraNode.position = SCNVector3(x, height, z)
        cameraNode.look(
            at: SCNVector3Make(0, modelLookAtY, 0),
            up: SCNVector3Make(0, 1, 0),
            localFront: SCNVector3Make(0, 0, -1)
        )
        refreshCutawayUniformsIfNeeded(force: forceCutawayUpdate)
    }

    private func makePreviewGeometry(from geometry: SCNGeometry) -> SCNGeometry {
        guard let previewGeometry = geometry.copy() as? SCNGeometry else {
            return geometry
        }
        let previewMaterials = makePreviewMaterials(materialCount: max(1, previewGeometry.materials.count))
        previewGeometry.materials = previewMaterials
        return previewGeometry
    }

    private func makePreviewMaterials(materialCount: Int) -> [SCNMaterial] {
        guard materialCount > 1 else {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.96, alpha: 0.62)
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.fillMode = .fill
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            applyCutawayShader(to: material)
            return [material]
        }

        let fillMaterial = SCNMaterial()
        fillMaterial.diffuse.contents = UIColor(white: 0.90, alpha: 0.26)
        fillMaterial.isDoubleSided = true
        fillMaterial.lightingModel = .constant
        fillMaterial.fillMode = .fill
        fillMaterial.blendMode = .alpha
        fillMaterial.writesToDepthBuffer = false
        fillMaterial.readsFromDepthBuffer = true
        applyCutawayShader(to: fillMaterial)

        let wireMaterial = SCNMaterial()
        wireMaterial.diffuse.contents = UIColor(white: 1.0, alpha: 0.82)
        wireMaterial.emission.contents = UIColor(white: 1.0, alpha: 0.18)
        wireMaterial.isDoubleSided = true
        wireMaterial.lightingModel = .constant
        wireMaterial.fillMode = .lines
        wireMaterial.blendMode = .add
        wireMaterial.writesToDepthBuffer = false
        wireMaterial.readsFromDepthBuffer = true
        applyCutawayShader(to: wireMaterial)

        if materialCount == 2 {
            return [fillMaterial, wireMaterial]
        }

        var materials: [SCNMaterial] = [fillMaterial, wireMaterial]
        if materialCount > 2 {
            let fallback = SCNMaterial()
            fallback.diffuse.contents = UIColor(white: 0.90, alpha: 0.30)
            fallback.isDoubleSided = true
            fallback.lightingModel = .constant
            fallback.fillMode = .fill
            fallback.blendMode = .alpha
            fallback.writesToDepthBuffer = false
            fallback.readsFromDepthBuffer = true
            applyCutawayShader(to: fallback)
            while materials.count < materialCount - 1 {
                let fallbackCopy = fallback.copy() as? SCNMaterial ?? fallback
                applyCutawayShader(to: fallbackCopy)
                materials.append(fallbackCopy)
            }
            materials.append(wireMaterial)
        }
        return materials
    }

    private func refreshCutawayUniformsIfNeeded(
        force: Bool = false,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard hasContent else { return }
        if !force,
           let lastCutawayTimestamp,
           timestamp - lastCutawayTimestamp < framingUpdateInterval
        {
            return
        }
        lastCutawayTimestamp = timestamp

        guard let (minV, maxV) = boundingBoxInScene(node: containerNode) else {
            previewCutDepth = 0
            previewCutFade = 0.001
            applyCutawayShaderToCurrentMaterials()
            return
        }

        var nearDepth = Float.greatestFiniteMagnitude
        var farDepth = -Float.greatestFiniteMagnitude
        for corner in corners(min: minV, max: maxV) {
            let cameraPoint = cameraNode.convertPosition(corner, from: scene.rootNode)
            let depth = max(0, -cameraPoint.z)
            guard depth.isFinite else { continue }
            nearDepth = min(nearDepth, depth)
            farDepth = max(farDepth, depth)
        }

        let depthSpan = farDepth - nearDepth
        guard nearDepth.isFinite, farDepth.isFinite, depthSpan > 0.001 else {
            previewCutDepth = 0
            previewCutFade = 0.001
            applyCutawayShaderToCurrentMaterials()
            return
        }

        previewCutDepth = nearDepth + depthSpan * roomCutawayNearDepthRatio
        previewCutFade = max(roomCutawayMinimumFadeDepth, depthSpan * roomCutawayFadeDepthRatio)
        applyCutawayShaderToCurrentMaterials()
    }

    private func applyCutawayShaderToCurrentMaterials() {
        for node in anchorNodes.values {
            node.geometry?.materials.forEach { material in
                applyCutawayShader(to: material)
            }
        }
    }

    private func applyCutawayShader(to material: SCNMaterial) {
        material.shaderModifiers = [
            .surface: Self.roomCutawayShaderModifier(
                cutDepth: previewCutDepth,
                cutFade: previewCutFade
            )
        ]
    }

    private func boundingBoxRecursive(node: SCNNode) -> (SCNVector3, SCNVector3) {
        var minAll = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxAll = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        node.enumerateChildNodes { n, _ in
            guard n.geometry != nil else { return }
            let (minV, maxV) = n.boundingBox
            if minV.x.isFinite, minV.y.isFinite, minV.z.isFinite,
               maxV.x.isFinite, maxV.y.isFinite, maxV.z.isFinite
            {
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

    private func boundingBoxInScene(node: SCNNode) -> (SCNVector3, SCNVector3)? {
        var minAll = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxAll = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var hasGeometry = false

        node.enumerateChildNodes { n, _ in
            guard n.geometry != nil else { return }
            let (minV, maxV) = n.boundingBox
            if minV.x.isFinite, minV.y.isFinite, minV.z.isFinite,
               maxV.x.isFinite, maxV.y.isFinite, maxV.z.isFinite
            {
                for c in corners(min: minV, max: maxV) {
                    let p = n.convertPosition(c, to: scene.rootNode)
                    minAll.x = min(minAll.x, p.x)
                    minAll.y = min(minAll.y, p.y)
                    minAll.z = min(minAll.z, p.z)
                    maxAll.x = max(maxAll.x, p.x)
                    maxAll.y = max(maxAll.y, p.y)
                    maxAll.z = max(maxAll.z, p.z)
                    hasGeometry = true
                }
            }
        }

        guard hasGeometry else { return nil }
        return (minAll, maxAll)
    }

    private func corners(min minV: SCNVector3, max maxV: SCNVector3) -> [SCNVector3] {
        [
            SCNVector3(minV.x, minV.y, minV.z),
            SCNVector3(maxV.x, minV.y, minV.z),
            SCNVector3(minV.x, maxV.y, minV.z),
            SCNVector3(minV.x, minV.y, maxV.z),
            SCNVector3(maxV.x, maxV.y, minV.z),
            SCNVector3(maxV.x, minV.y, maxV.z),
            SCNVector3(minV.x, maxV.y, maxV.z),
            SCNVector3(maxV.x, maxV.y, maxV.z),
        ]
    }

    private func framingAlpha(timestamp: TimeInterval, force: Bool) -> CGFloat {
        guard !force, let lastFramingTimestamp else { return 1 }
        let dt = max(timestamp - lastFramingTimestamp, 1.0 / 60.0)
        return 1.0 - exp(-dt * framingSmoothing)
    }

    private func lerp(_ current: SCNVector3, _ target: SCNVector3, alpha: Float) -> SCNVector3 {
        SCNVector3(
            current.x + (target.x - current.x) * alpha,
            current.y + (target.y - current.y) * alpha,
            current.z + (target.z - current.z) * alpha
        )
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }

    private func shortestAngle(from current: CGFloat, to target: CGFloat) -> CGFloat {
        normalizeAngle(target - current)
    }

    private func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle
        while result > .pi {
            result -= .pi * 2
        }
        while result < -.pi {
            result += .pi * 2
        }
        return result
    }
}
