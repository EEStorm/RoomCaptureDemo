//
//  ARSCNViewContainer.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//
//  Info.plist 需要添加:
//  - NSCameraUsageDescription (相机权限说明)
//  - UIRequiredDeviceCapabilities: ["arkit"] (允许非 LiDAR 设备安装；LiDAR 能力在运行时判断)
//

import ARKit
import SceneKit
import SwiftUI
import UIKit

struct ARSCNViewContainer: UIViewRepresentable {
    @Binding var isMovingTooFast: Bool
    @Binding var isRecording: Bool
    @Binding var renderMode: RenderMode
    @Binding var renderResetCounter: Int
    @Binding var reviewSnapshotRequestCounter: Int
    @Binding var reviewMeshExportRequestCounter: Int
    @Binding var reviewMeshExportFolderPath: String?

    let onMotionUpdate: (Double, Double, Bool) -> Void
    let onPointCloudStatsUpdate: (Bool, Int, Int, Int) -> Void
    let onPlaneCoverageStatsUpdate: (Int, Double) -> Void
    let onSkyboxCoverageStatsUpdate: (Double) -> Void
    let onFrameForRecording: (ARFrame) -> Void
    let onReviewSnapshotReady: (UIImage) -> Void
    let onReviewMeshExportReady: (URL, Int, Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isMovingTooFast: $isMovingTooFast,
            onMotionUpdate: onMotionUpdate,
            onPointCloudStatsUpdate: onPointCloudStatsUpdate,
            onPlaneCoverageStatsUpdate: onPlaneCoverageStatsUpdate,
            onSkyboxCoverageStatsUpdate: onSkyboxCoverageStatsUpdate,
            onFrameForRecording: onFrameForRecording,
            onReviewSnapshotReady: onReviewSnapshotReady,
            onReviewMeshExportReady: onReviewMeshExportReady
        )
    }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.automaticallyUpdatesLighting = false
        view.scene = SCNScene()
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator

        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.contentScaleFactor = UIScreen.main.scale

        context.coordinator.attach(to: view)
        context.coordinator.runSessionIfNeeded(mode: renderMode, options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Avoid mutating SwiftUI state (e.g. @Binding/@Published) inside view updates.
        // Recording is gated in the SwiftUI model (`CaptureSessionModel.handleFrameForRecording`).
        context.coordinator.renderMode = renderMode
        context.coordinator.runSessionIfNeeded(mode: renderMode, options: [])
        context.coordinator.handleResetIfNeeded(counter: renderResetCounter)
        context.coordinator.handleReviewSnapshotIfNeeded(counter: reviewSnapshotRequestCounter)
        context.coordinator.handleReviewMeshExportIfNeeded(counter: reviewMeshExportRequestCounter, folderPath: reviewMeshExportFolderPath)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        @Binding var isMovingTooFast: Bool

        private let onMotionUpdate: (Double, Double, Bool) -> Void
        private let onPointCloudStatsUpdate: (Bool, Int, Int, Int) -> Void
        private let onPlaneCoverageStatsUpdate: (Int, Double) -> Void
        private let onSkyboxCoverageStatsUpdate: (Double) -> Void
        private let onFrameForRecording: (ARFrame) -> Void
        private let onReviewSnapshotReady: (UIImage) -> Void
        private let onReviewMeshExportReady: (URL, Int, Int, Int) -> Void

        var renderMode: RenderMode = .mesh {
            didSet {
                if oldValue != renderMode {
                    DispatchQueue.main.async { [weak self] in
                        self?.applyVisibility()
                    }
                }
            }
        }

        private let linearSpeedThreshold: Double = 0.5 // m/s
        private let angularSpeedThreshold: Double = 1.0 // rad/s (约 57.3°/s)

        private var lastFrameTimestamp: TimeInterval?
        private var lastCameraTransform: simd_float4x4?

        private weak var view: ARSCNView?
        private weak var rootNode: SCNNode?
        private let pointCloud = PointCloudAccumulator()
        private let pointCloudNode = SCNNode()
        private let depthCoverage = DepthCoverageAccumulator()
        private let depthCoverageNode = SCNNode()
        private let skyboxCoverage = SkyboxCoverageAccumulator()
        private let skyboxNode = SCNNode()
        private var planeCoverage: [UUID: PlaneCoverageState] = [:]
        private var lastResetCounter: Int = 0
        private var lastPlanePaintTimestamp: TimeInterval = 0
        private var lastSkyboxPaintTimestamp: TimeInterval = 0
        private var lastAppliedMode: RenderMode?
        private var lastReviewSnapshotCounter: Int = 0
        private var lastReviewMeshExportCounter: Int = 0

        init(
            isMovingTooFast: Binding<Bool>,
            onMotionUpdate: @escaping (Double, Double, Bool) -> Void,
            onPointCloudStatsUpdate: @escaping (Bool, Int, Int, Int) -> Void,
            onPlaneCoverageStatsUpdate: @escaping (Int, Double) -> Void,
            onSkyboxCoverageStatsUpdate: @escaping (Double) -> Void,
            onFrameForRecording: @escaping (ARFrame) -> Void,
            onReviewSnapshotReady: @escaping (UIImage) -> Void,
            onReviewMeshExportReady: @escaping (URL, Int, Int, Int) -> Void
        ) {
            _isMovingTooFast = isMovingTooFast
            self.onMotionUpdate = onMotionUpdate
            self.onPointCloudStatsUpdate = onPointCloudStatsUpdate
            self.onPlaneCoverageStatsUpdate = onPlaneCoverageStatsUpdate
            self.onSkyboxCoverageStatsUpdate = onSkyboxCoverageStatsUpdate
            self.onFrameForRecording = onFrameForRecording
            self.onReviewSnapshotReady = onReviewSnapshotReady
            self.onReviewMeshExportReady = onReviewMeshExportReady

            pointCloudNode.name = "pointCloud"
            depthCoverageNode.name = "depthCoverage"
            skyboxNode.name = "skyboxCoverage"
        }

        func attach(to view: ARSCNView) {
            self.view = view
            self.rootNode = view.scene.rootNode
            if pointCloudNode.parent == nil, let rootNode = self.rootNode {
                rootNode.addChildNode(pointCloudNode)
            }
            if depthCoverageNode.parent == nil, let rootNode = self.rootNode {
                rootNode.addChildNode(depthCoverageNode)
            }
            if skyboxNode.parent == nil, let rootNode = self.rootNode {
                rootNode.addChildNode(skyboxNode)
            }
            applyVisibility()
        }

        func runSessionIfNeeded(mode: RenderMode, options: ARSession.RunOptions) {
            guard let view else { return }
            guard lastAppliedMode != mode else { return }

            let config = ARWorldTrackingConfiguration()
            config.worldAlignment = .gravity

            // LiDAR devices: keep mesh reconstruction enabled regardless of UI mode, so the mesh is always
            // available for post-capture review/export.
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            }

            switch mode {
            case .mesh:
                // Keep depth enabled for better mesh/recording on supported devices.
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
            case .pointCloud:
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
            case .depthCoverage:
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    config.frameSemantics.insert(.sceneDepth)
                }
            case .planeCoverage:
                config.planeDetection = [.horizontal, .vertical]
            case .skyboxCoverage:
                break
            }

            view.session.run(config, options: options)
            lastAppliedMode = mode
        }

        func handleResetIfNeeded(counter: Int) {
            guard counter != lastResetCounter else { return }
            lastResetCounter = counter
            pointCloud.reset()
            depthCoverage.reset()
            skyboxCoverage.reset()
            for (_, state) in planeCoverage {
                state.painter.reset()
                state.node.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
            }
            DispatchQueue.main.async { [weak self] in
                self?.pointCloudNode.geometry = nil
                self?.depthCoverageNode.geometry = nil
                self?.skyboxNode.geometry = nil
                self?.onPointCloudStatsUpdate(false, 0, self?.pointCloud.maxVoxels ?? 0, 0)
                self?.onPlaneCoverageStatsUpdate(self?.planeCoverage.count ?? 0, 0)
                self?.onSkyboxCoverageStatsUpdate(0)
            }
        }

        func handleReviewSnapshotIfNeeded(counter: Int) {
            guard counter != lastReviewSnapshotCounter else { return }
            lastReviewSnapshotCounter = counter
            guard let view else { return }
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                let image = view.snapshot()
                self.onReviewSnapshotReady(image)
            }
        }

        func handleReviewMeshExportIfNeeded(counter: Int, folderPath: String?) {
            guard counter != lastReviewMeshExportCounter else { return }
            lastReviewMeshExportCounter = counter
            guard let folderPath, !folderPath.isEmpty else { return }
            guard let view else { return }
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else { return }

            let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            let outURL = folderURL.appendingPathComponent("mesh.obj")

            // Export off-main; mesh can be large.
            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak view] in
                guard let self, let view else { return }
                let anchors = (view.session.currentFrame?.anchors ?? []).compactMap { $0 as? ARMeshAnchor }
                guard !anchors.isEmpty else { return }
                do {
                    let stats = try MeshOBJExporter.exportOBJ(from: anchors, to: outURL)
                    DispatchQueue.main.async {
                        self.onReviewMeshExportReady(outURL, stats.anchorCount, stats.vertexCount, stats.faceCount)
                    }
                } catch {
                    print("Mesh export failed: \(error)")
                }
            }
        }

        private func applyVisibility() {
            pointCloudNode.isHidden = (renderMode != .pointCloud)
            depthCoverageNode.isHidden = (renderMode != .depthCoverage)
            skyboxNode.isHidden = (renderMode != .skyboxCoverage)
            rootNode?.enumerateChildNodes { node, _ in
                if node.name == "mesh" {
                    node.isHidden = (self.renderMode != .mesh)
                }
            }
            for (_, state) in planeCoverage {
                state.node.isHidden = (renderMode != .planeCoverage)
            }
        }

        // MARK: ARSessionDelegate (速度监控 + 录制)

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateMotionState(frame: frame)
            onFrameForRecording(frame)

            if renderMode == .pointCloud {
                pointCloud.ingest(frame: frame)
                if pointCloud.shouldUpdateGeometry(at: frame.timestamp) {
                    let geometry = pointCloud.makePointGeometryAndMarkUpdated(at: frame.timestamp, cameraTransform: frame.camera.transform)
                    DispatchQueue.main.async { [weak self] in
                        self?.pointCloudNode.geometry = geometry
                    }
                }
                let depthAvailable = (frame.sceneDepth != nil)
                let count = pointCloud.currentVoxelCount
                let max = pointCloud.maxVoxels
                let rendered = pointCloud.lastRenderedPointCount
                DispatchQueue.main.async { [weak self] in
                    _ = self
                    self?.onPointCloudStatsUpdate(depthAvailable, count, max, rendered)
                }
            }

            if renderMode == .planeCoverage {
                paintPlaneCoverage(frame: frame)
            }

            if renderMode == .depthCoverage {
                depthCoverage.ingest(frame: frame)
                if depthCoverage.shouldUpdateGeometry(at: frame.timestamp) {
                    let geometry = depthCoverage.makeGeometryAndMarkUpdated(at: frame.timestamp, cameraTransform: frame.camera.transform)
                    DispatchQueue.main.async { [weak self] in
                        self?.depthCoverageNode.geometry = geometry
                    }
                }
                let depthAvailable = (frame.sceneDepth != nil)
                let count = depthCoverage.currentVoxelCount
                let max = depthCoverage.maxVoxels
                let rendered = depthCoverage.lastRenderedPointCount
                DispatchQueue.main.async { [weak self] in
                    _ = self
                    self?.onPointCloudStatsUpdate(depthAvailable, count, max, rendered)
                }
            }

            if renderMode == .skyboxCoverage {
                paintSkyboxCoverage(frame: frame)
            }
        }

        private func paintSkyboxCoverage(frame: ARFrame) {
            guard let view else { return }

            // Throttle to avoid excessive texture rebuild on older devices.
            if lastSkyboxPaintTimestamp != 0, (frame.timestamp - lastSkyboxPaintTimestamp) < 0.06 {
                return
            }
            lastSkyboxPaintTimestamp = frame.timestamp

            let orientation: UIInterfaceOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            skyboxCoverage.paintDirections(from: frame, in: view.bounds, interfaceOrientation: orientation)

            if skyboxCoverage.shouldUpdateTexture(at: frame.timestamp),
               let tex = skyboxCoverage.makeTextureAndMarkUpdated(at: frame.timestamp)
            {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let sphere: SCNSphere
                    if let existing = self.skyboxNode.geometry as? SCNSphere {
                        sphere = existing
                    } else {
                        sphere = SCNSphere(radius: 0.9)
                        sphere.segmentCount = 64
                        self.skyboxNode.geometry = sphere
                        self.skyboxNode.renderingOrder = -10
                    }

                    let material: SCNMaterial
                    if let m = sphere.firstMaterial {
                        material = m
                    } else {
                        material = SCNMaterial()
                        sphere.firstMaterial = material
                    }
                    material.diffuse.contents = tex
                    material.isDoubleSided = true
                    // View from inside the sphere.
                    material.cullMode = .front
                    material.lightingModel = .constant
                    material.blendMode = .alpha
                    material.writesToDepthBuffer = false
                    material.readsFromDepthBuffer = false
                }
            }

            // Keep the sphere centered on the camera (direction coverage, not world surface coverage).
            let t = frame.camera.transform
            let p = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
            DispatchQueue.main.async { [weak self] in
                self?.skyboxNode.simdPosition = p
                self?.onSkyboxCoverageStatsUpdate(self?.skyboxCoverage.coverageRatio() ?? 0)
            }
        }

        // MARK: Plane coverage painting

        private final class PlaneCoverageState {
            let node: SCNNode
            let painter: PlaneCoveragePainter
            var extentX: Float
            var extentZ: Float
            var centerX: Float
            var centerZ: Float

            init(node: SCNNode, painter: PlaneCoveragePainter, extentX: Float, extentZ: Float, centerX: Float, centerZ: Float) {
                self.node = node
                self.painter = painter
                self.extentX = extentX
                self.extentZ = extentZ
                self.centerX = centerX
                self.centerZ = centerZ
            }
        }

        private func makePlaneCoverageState(for anchor: ARPlaneAnchor) -> PlaneCoverageState {
            let painter = PlaneCoveragePainter()
            let node = makePlaneCoverageNode(for: anchor, texture: painter.makeTextureAndMarkUpdated(at: 0))
            return PlaneCoverageState(
                node: node,
                painter: painter,
                extentX: anchor.extent.x,
                extentZ: anchor.extent.z,
                centerX: anchor.center.x,
                centerZ: anchor.center.z
            )
        }

        private func makePlaneCoverageNode(for anchor: ARPlaneAnchor, texture: UIImage?) -> SCNNode {
            let plane = SCNPlane(width: CGFloat(max(anchor.extent.x, 0.01)), height: CGFloat(max(anchor.extent.z, 0.01)))
            let material = SCNMaterial()
            material.diffuse.contents = texture ?? UIColor.clear
            material.isDoubleSided = true
            material.lightingModel = .constant
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = true
            plane.materials = [material]

            let node = SCNNode(geometry: plane)
            node.name = "planeCoverage"
            // IMPORTANT:
            // This node is returned from `renderer(_:nodeFor:)`, meaning ARSCNView already applies the
            // anchor's world transform. Here we only set LOCAL transforms (center + plane orientation).
            node.simdPosition = SIMD3<Float>(anchor.center.x, 0, anchor.center.z)
            // SCNPlane is in local X-Y; rotate it into X-Z to match ARPlaneAnchor local coordinates.
            node.eulerAngles.x = .pi / 2
            return node
        }

        private func paintPlaneCoverage(frame: ARFrame) {
            guard let view else { return }
            guard !planeCoverage.isEmpty else { return }

            // Sample a small grid of screen points near the center for stable coverage feedback.
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return }

            // Throttle raycasts: heavy on older devices.
            if lastPlanePaintTimestamp != 0, (frame.timestamp - lastPlanePaintTimestamp) < 0.10 {
                return
            }
            lastPlanePaintTimestamp = frame.timestamp

            let cols = 3
            let rows = 5
            let margin: CGFloat = 0.18
            let minX = bounds.minX + bounds.width * margin
            let maxX = bounds.maxX - bounds.width * margin
            let minY = bounds.minY + bounds.height * margin
            let maxY = bounds.maxY - bounds.height * margin

            var touched = Set<UUID>()

            for r in 0..<rows {
                let ty = CGFloat(r) / CGFloat(max(1, rows - 1))
                let y = minY + (maxY - minY) * ty
                for c in 0..<cols {
                    let tx = CGFloat(c) / CGFloat(max(1, cols - 1))
                    let x = minX + (maxX - minX) * tx
                    let p = CGPoint(x: x, y: y)

                    // Use both extent-limited and infinite plane hits.
                    // `.existingPlaneUsingExtent` is stable but can miss areas before the plane extent is fully expanded.
                    let hits = view.hitTest(p, types: [.existingPlaneUsingExtent, .existingPlane])
                    guard let hit = hits.first, let anchor = hit.anchor as? ARPlaneAnchor else { continue }
                    let id = anchor.identifier
                    guard let state = planeCoverage[id] else { continue }

                    // hit.localTransform is in the anchor's local coordinates.
                    let lt = hit.localTransform
                    let lx = lt.columns.3.x
                    let lz = lt.columns.3.z

                    let ex = max(state.extentX, 1e-3)
                    let ez = max(state.extentZ, 1e-3)
                    let u = (lx - state.centerX) / ex + 0.5
                    let v = (lz - state.centerZ) / ez + 0.5
                    if u >= 0, u <= 1, v >= 0, v <= 1 {
                        state.painter.paint(u: u, v: v)
                        touched.insert(id)
                    }
                }
            }

            // Update textures only for planes we touched this cycle.
            var coveredSum: Double = 0
            var planeCount = planeCoverage.count
            for (id, state) in planeCoverage {
                if touched.contains(id),
                   state.painter.shouldUpdateTexture(at: frame.timestamp),
                   let tex = state.painter.makeTextureAndMarkUpdated(at: frame.timestamp)
                {
                    DispatchQueue.main.async {
                        state.node.geometry?.firstMaterial?.diffuse.contents = tex
                    }
                }
                coveredSum += state.painter.coverageRatio()
            }

            let ratio = planeCount == 0 ? 0 : (coveredSum / Double(planeCount))
            DispatchQueue.main.async { [weak self] in
                self?.onPlaneCoverageStatsUpdate(planeCount, ratio)
            }
        }

        private func updateMotionState(frame: ARFrame) {
            let currentTimestamp = frame.timestamp
            let currentTransform = frame.camera.transform

            guard let lastTS = lastFrameTimestamp, let lastT = lastCameraTransform else {
                lastFrameTimestamp = currentTimestamp
                lastCameraTransform = currentTransform
                DispatchQueue.main.async { [weak self] in
                    self?.isMovingTooFast = false
                    self?.onMotionUpdate(0, 0, false)
                }
                return
            }

            let dt = max(currentTimestamp - lastTS, 1e-6)

            let p0 = SIMD3<Float>(lastT.columns.3.x, lastT.columns.3.y, lastT.columns.3.z)
            let p1 = SIMD3<Float>(currentTransform.columns.3.x, currentTransform.columns.3.y, currentTransform.columns.3.z)
            let dp = p1 - p0
            let linearSpeed = Double(simd_length(dp)) / dt

            let q0 = simd_quatf(lastT)
            let q1 = simd_quatf(currentTransform)
            let dq = simd_normalize(q1 * simd_inverse(q0))
            let angle = 2.0 * acos(min(1.0, max(-1.0, Double(dq.real))))
            let angularSpeed = angle / dt

            let tooFast = (linearSpeed > linearSpeedThreshold) || (angularSpeed > angularSpeedThreshold)

            DispatchQueue.main.async { [weak self] in
                self?.isMovingTooFast = tooFast
                self?.onMotionUpdate(linearSpeed, angularSpeed, tooFast)
            }

            lastFrameTimestamp = currentTimestamp
            lastCameraTransform = currentTransform
        }

        // MARK: ARSCNViewDelegate (网格渲染)

        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            if renderMode == .mesh, let meshAnchor = anchor as? ARMeshAnchor {
                let node = SCNNode()
                node.name = "mesh"
                node.geometry = MeshGeometryBuilder.buildGeometry(from: meshAnchor.geometry)
                return node
            }

            if renderMode == .planeCoverage, let planeAnchor = anchor as? ARPlaneAnchor {
                if let existing = planeCoverage[planeAnchor.identifier] {
                    existing.node.isHidden = (renderMode != .planeCoverage)
                    return existing.node
                } else {
                    let state = makePlaneCoverageState(for: planeAnchor)
                    state.node.isHidden = (renderMode != .planeCoverage)
                    planeCoverage[planeAnchor.identifier] = state
                    return state.node
                }
            }

            return nil
        }

        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            if let meshAnchor = anchor as? ARMeshAnchor {
                guard renderMode == .mesh else {
                    if node.name == "mesh" { node.isHidden = true }
                    return
                }
                node.name = "mesh"
                node.isHidden = false
                node.geometry = MeshGeometryBuilder.buildGeometry(from: meshAnchor.geometry)
                return
            }

            if let planeAnchor = anchor as? ARPlaneAnchor {
                guard renderMode == .planeCoverage else {
                    if node.name == "planeCoverage" { node.isHidden = true }
                    return
                }

                guard let state = planeCoverage[planeAnchor.identifier] else { return }
                let oldMapping = PlaneCoveragePainter.Mapping(
                    centerX: state.centerX,
                    centerZ: state.centerZ,
                    extentX: state.extentX,
                    extentZ: state.extentZ
                )

                state.extentX = planeAnchor.extent.x
                state.extentZ = planeAnchor.extent.z
                state.centerX = planeAnchor.center.x
                state.centerZ = planeAnchor.center.z

                // IMPORTANT:
                // This `node` is managed by ARSCNView: it is automatically positioned/oriented by the anchor transform.
                // So here we only update LOCAL (anchor-space) transforms for the plane geometry itself.
                state.node.simdPosition = SIMD3<Float>(planeAnchor.center.x, 0, planeAnchor.center.z)
                state.node.eulerAngles.x = .pi / 2

                if let plane = state.node.geometry as? SCNPlane {
                    plane.width = CGFloat(max(planeAnchor.extent.x, 0.01))
                    plane.height = CGFloat(max(planeAnchor.extent.z, 0.01))
                }

                // As plane center/extent refines, keep user-painted coverage by remapping UVs instead of wiping.
                let newMapping = PlaneCoveragePainter.Mapping(
                    centerX: state.centerX,
                    centerZ: state.centerZ,
                    extentX: state.extentX,
                    extentZ: state.extentZ
                )
                let centerShift = max(abs(Double(newMapping.centerX - oldMapping.centerX)), abs(Double(newMapping.centerZ - oldMapping.centerZ)))
                let extentRatioX = abs(Double(newMapping.extentX - oldMapping.extentX)) / max(0.001, Double(oldMapping.extentX))
                let extentRatioZ = abs(Double(newMapping.extentZ - oldMapping.extentZ)) / max(0.001, Double(oldMapping.extentZ))
                let shouldRemap = (centerShift > 0.01) || (extentRatioX > 0.05) || (extentRatioZ > 0.05)
                if shouldRemap {
                    state.painter.remap(from: oldMapping, to: newMapping)
                    if let tex = state.painter.makeTextureAndMarkUpdated(at: 0) {
                        DispatchQueue.main.async {
                            state.node.geometry?.firstMaterial?.diffuse.contents = tex
                        }
                    }
                }

                state.node.isHidden = false
                return
            }
        }
    }
}
