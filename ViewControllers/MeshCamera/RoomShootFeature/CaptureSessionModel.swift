//
//  CaptureSessionModel.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import ARKit
import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class CaptureSessionModel: ObservableObject {
    @Published var isMovingTooFast: Bool = false
    @Published var isRecording: Bool = false
    @Published var renderMode: RenderMode = .mesh
    @Published var availableRenderModes: [RenderMode] = [.planeCoverage, .pointCloud]

    @Published var lastLinearSpeed: Double = 0
    @Published var lastAngularSpeed: Double = 0
    @Published var pointCloudDepthAvailable: Bool = false
    @Published var pointCloudPointCount: Int = 0
    @Published var pointCloudMaxPoints: Int = 0
    @Published var pointCloudRenderedCount: Int = 0
    @Published var planeCoveragePlaneCount: Int = 0
    @Published var planeCoverageRatio: Double = 0
    @Published var skyboxCoverageRatio: Double = 0

    @Published var renderResetCounter: Int = 0

    @Published var lastExportSummary: String?
    @Published var isPackaging: Bool = false

    // Review (post-capture QA/coverage/3D preview) – LiDAR focus.
    @Published var isReviewPresented: Bool = false
    @Published var isGeneratingReview: Bool = false
    @Published var reviewPayload: CaptureReviewPayload?
    @Published var reviewSnapshotRequestCounter: Int = 0
    @Published var reviewMeshExportRequestCounter: Int = 0
    @Published var reviewMeshExportFolderPath: String?

    private var pendingExportForReview: VideoPoseRecorder.ExportResult?
    private var pendingReviewSnapshot: UIImage?
    private var pendingReviewMeshExport: MeshExportInfo?

    private let recorder = VideoPoseRecorder()

    init() {
        // Build a device-capability driven mode list so the same app runs on both LiDAR and non-LiDAR devices.
        // Non‑LiDAR friendly: skybox/frustum coverage always works.
        var modes: [RenderMode] = [.skyboxCoverage, .planeCoverage, .pointCloud]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            modes.insert(.mesh, at: 0)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            // Scheme B: depth-based coverage preview (preferred when depth is available).
            if !modes.contains(.depthCoverage) {
                modes.append(.depthCoverage)
            }
        }
        // Keep pointCloud available even without sceneDepth (it can fall back to rawFeaturePoints).
        availableRenderModes = modes
        if !availableRenderModes.contains(renderMode) {
            renderMode = availableRenderModes.first ?? .planeCoverage
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        lastExportSummary = nil
        isPackaging = false
        recorder.startNewRecording()
        isRecording = true
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        isPackaging = true

        recorder.stop { [weak self] result in
            Task { @MainActor in
                self?.isPackaging = false
                switch result {
                case .success(let export):
                    self?.lastExportSummary = """
                    已保存:
                    \(export.videoURL.lastPathComponent)
                    \(export.jsonURL.lastPathComponent)
                    \(export.folderURL.path)
                    """
                    print("Video saved at: \(export.videoURL.path)")
                    print("Pose JSON saved at: \(export.jsonURL.path)")

                    // Kick off on-device review generation (acceptable slight wait).
                    await self?.startGeneratingReview(export: export)
                case .failure(let error):
                    self?.lastExportSummary = "保存失败: \(error.localizedDescription)"
                    print("Export failed: \(error)")
                }
            }
        }
    }

    func handleMotion(linearSpeed: Double, angularSpeed: Double, isTooFast: Bool) {
        lastLinearSpeed = linearSpeed
        lastAngularSpeed = angularSpeed
        isMovingTooFast = isTooFast
    }

    func handleFrameForRecording(_ frame: ARFrame) {
        guard isRecording else { return }
        recorder.append(frame: frame)
    }

    // MARK: - Review

    private func startGeneratingReview(export: VideoPoseRecorder.ExportResult) async {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            // Non-LiDAR devices are out-of-scope per request.
            return
        }
        isGeneratingReview = true
        isReviewPresented = true // show sheet immediately with “生成中…”
        reviewPayload = nil
        pendingExportForReview = export
        pendingReviewSnapshot = nil
        pendingReviewMeshExport = nil

        // Request mesh snapshot + OBJ export from AR view coordinator.
        reviewMeshExportFolderPath = export.folderURL.path
        reviewMeshExportRequestCounter += 1

        // Compute QA stats (poses + duration) off-main.
        do {
            let qa = try await computeQAStats(jsonURL: export.jsonURL, videoURL: export.videoURL)
            // Build partial payload; finalize when snapshot/mesh export arrive.
            reviewPayload = CaptureReviewPayload(
                exportFolderURL: export.folderURL,
                videoURL: export.videoURL,
                jsonURL: export.jsonURL,
                qa: qa,
                meshSnapshot: nil,
                meshExport: nil
            )
            tryFinalizeReviewIfPossible()
        } catch {
            // Still allow viewing other info.
            let fallback = CaptureQAStats(
                poseCount: 0,
                durationSeconds: 0,
                averageFPS: 0,
                totalDistanceMeters: 0,
                maxLinearSpeed: 0,
                maxAngularSpeed: 0,
                speedOverTime: [],
                angularOverTime: [],
                xzPositions: [],
                boundsMin: SIMD2<Double>(0, 0),
                boundsMax: SIMD2<Double>(1, 1)
            )
            reviewPayload = CaptureReviewPayload(
                exportFolderURL: export.folderURL,
                videoURL: export.videoURL,
                jsonURL: export.jsonURL,
                qa: fallback,
                meshSnapshot: nil,
                meshExport: nil
            )
            print("Review QA compute failed: \(error)")
            tryFinalizeReviewIfPossible()
        }
    }

    func handleReviewSnapshot(_ image: UIImage) {
        pendingReviewSnapshot = image
        tryFinalizeReviewIfPossible()
    }

    func handleReviewMeshExport(objURL: URL, anchorCount: Int, vertexCount: Int, faceCount: Int) {
        pendingReviewMeshExport = MeshExportInfo(objURL: objURL, vertexCount: vertexCount, faceCount: faceCount, anchorCount: anchorCount)
        if let summary = lastExportSummary, !summary.contains("mesh.obj") {
            lastExportSummary = summary + "\nmesh.obj"
        }
        tryFinalizeReviewIfPossible()
    }

    private func tryFinalizeReviewIfPossible() {
        guard var payload = reviewPayload else { return }
        if payload.meshSnapshot == nil, let snap = pendingReviewSnapshot {
            payload.meshSnapshot = snap
        }
        if payload.meshExport == nil, let mesh = pendingReviewMeshExport {
            payload.meshExport = mesh
        }
        reviewPayload = payload

        // Consider review “ready” once we have QA + (snapshot OR mesh export).
        if pendingReviewSnapshot != nil || pendingReviewMeshExport != nil {
            isGeneratingReview = false
        }
    }

    private func computeQAStats(jsonURL: URL, videoURL: URL) async throws -> CaptureQAStats {
        let poses: [CameraPoseSample] = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([CameraPoseSample].self, from: data)
        }.value

        let durationSeconds: Double = await Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: videoURL)
            let duration = asset.duration
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        }.value

        let poseCount = poses.count
        let averageFPS = durationSeconds > 0 ? Double(poseCount) / durationSeconds : 0

        // Extract positions + rotations from transform columns.
        var positions: [SIMD3<Double>] = []
        positions.reserveCapacity(poses.count)

        var times: [Double] = []
        times.reserveCapacity(poses.count)

        var rotations: [simd_quatd] = []
        rotations.reserveCapacity(poses.count)

        for p in poses {
            times.append(p.timestamp)
            let t = p.transformColumns
            if t.count == 4, t[0].count == 4, t[1].count == 4, t[2].count == 4, t[3].count == 4 {
                let m = simd_double4x4(
                    SIMD4<Double>(Double(t[0][0]), Double(t[0][1]), Double(t[0][2]), Double(t[0][3])),
                    SIMD4<Double>(Double(t[1][0]), Double(t[1][1]), Double(t[1][2]), Double(t[1][3])),
                    SIMD4<Double>(Double(t[2][0]), Double(t[2][1]), Double(t[2][2]), Double(t[2][3])),
                    SIMD4<Double>(Double(t[3][0]), Double(t[3][1]), Double(t[3][2]), Double(t[3][3]))
                )
                positions.append(SIMD3<Double>(m.columns.3.x, m.columns.3.y, m.columns.3.z))
                rotations.append(simd_quatd(m))
            }
        }

        var speedOverTime: [Double] = []
        var angularOverTime: [Double] = []
        speedOverTime.reserveCapacity(max(0, positions.count - 1))
        angularOverTime.reserveCapacity(max(0, positions.count - 1))

        var totalDistance: Double = 0
        var maxSpeed: Double = 0
        var maxAngular: Double = 0

        if positions.count >= 2 {
            for i in 1..<positions.count {
                let dt = max(1e-6, times[i] - times[i - 1])
                let dp = positions[i] - positions[i - 1]
                let dist = simd_length(dp)
                let v = dist / dt
                totalDistance += dist
                maxSpeed = max(maxSpeed, v)
                speedOverTime.append(v)

                let q0 = rotations[i - 1]
                let q1 = rotations[i]
                let dq = simd_normalize(q1 * simd_inverse(q0))
                let angle = 2.0 * acos(min(1.0, max(-1.0, dq.real)))
                let w = angle / dt
                maxAngular = max(maxAngular, w)
                angularOverTime.append(w)
            }
        }

        var xz: [SIMD2<Double>] = []
        xz.reserveCapacity(positions.count)
        var minXZ = SIMD2<Double>(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var maxXZ = SIMD2<Double>(-Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        for p in positions {
            let pt = SIMD2<Double>(p.x, p.z)
            xz.append(pt)
            minXZ.x = min(minXZ.x, pt.x)
            minXZ.y = min(minXZ.y, pt.y)
            maxXZ.x = max(maxXZ.x, pt.x)
            maxXZ.y = max(maxXZ.y, pt.y)
        }
        if !minXZ.x.isFinite || !minXZ.y.isFinite || !maxXZ.x.isFinite || !maxXZ.y.isFinite {
            minXZ = SIMD2<Double>(0, 0)
            maxXZ = SIMD2<Double>(1, 1)
        }

        return CaptureQAStats(
            poseCount: poseCount,
            durationSeconds: durationSeconds,
            averageFPS: averageFPS,
            totalDistanceMeters: totalDistance,
            maxLinearSpeed: maxSpeed,
            maxAngularSpeed: maxAngular,
            speedOverTime: speedOverTime,
            angularOverTime: angularOverTime,
            xzPositions: xz,
            boundsMin: minXZ,
            boundsMax: maxXZ
        )
    }
}
