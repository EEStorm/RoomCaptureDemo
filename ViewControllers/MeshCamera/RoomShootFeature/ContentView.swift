//
//  ContentView.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI
import Combine
import SceneKit
import UIKit

enum CaptureLivePreviewKind {
    case mesh
    case trajectory
}

struct ContentView: View {
    let onShowCaptureList: () -> Void
    var showsRenderModePicker: Bool = true
    var showsDownloadListButton: Bool = true
    var showsMainMeshOverlay: Bool = true
    var livePreviewKind: CaptureLivePreviewKind = .mesh

    @StateObject private var model = CaptureSessionModel()
    @StateObject private var liveMeshPreviewStore = LiveMeshPreviewSceneStore()
    @StateObject private var liveTrajectoryPreviewStore = LiveTrajectoryPreviewStore()
    @State private var blink = false

    var body: some View {
        ZStack {
            ARSCNViewContainer(
                isMovingTooFast: $model.isMovingTooFast,
                isRecording: $model.isRecording,
                renderMode: $model.renderMode,
                renderResetCounter: $model.renderResetCounter,
                reviewSnapshotRequestCounter: $model.reviewSnapshotRequestCounter,
                reviewMeshExportRequestCounter: $model.reviewMeshExportRequestCounter,
                reviewMeshExportFolderPath: $model.reviewMeshExportFolderPath,
                liveMeshPreviewStore: liveMeshPreviewStore,
                showsMainMeshOverlay: showsMainMeshOverlay,
                onMotionUpdate: { linear, angular, tooFast in
                    model.handleMotion(linearSpeed: linear, angularSpeed: angular, isTooFast: tooFast)
                },
                onPointCloudStatsUpdate: { depthAvailable, count, max, rendered in
                    model.pointCloudDepthAvailable = depthAvailable
                    model.pointCloudPointCount = count
                    model.pointCloudMaxPoints = max
                    model.pointCloudRenderedCount = rendered
                },
                onPlaneCoverageStatsUpdate: { planeCount, ratio in
                    model.planeCoveragePlaneCount = planeCount
                    model.planeCoverageRatio = ratio
                },
                onSkyboxCoverageStatsUpdate: { ratio in
                    model.skyboxCoverageRatio = ratio
                },
                onFrameForRecording: { frame in
                    model.handleFrameForRecording(frame)
                    if livePreviewKind == .trajectory {
                        liveTrajectoryPreviewStore.append(frame: frame, isRecording: model.isRecording)
                    }
                },
                onReviewSnapshotReady: { image in
                    model.handleReviewSnapshot(image)
                },
                onReviewMeshExportReady: { url, anchorCount, vertexCount, faceCount in
                    model.handleReviewMeshExport(objURL: url, anchorCount: anchorCount, vertexCount: vertexCount, faceCount: faceCount)
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.isRecording ? "录制中" : "未录制")
                            .font(.headline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text(String(format: "线速度: %.2f m/s", model.lastLinearSpeed))
                            .font(.caption)
                            .foregroundStyle(.white)
                        Text(String(format: "角速度: %.2f rad/s", model.lastAngularSpeed))
                            .font(.caption)
                            .foregroundStyle(.white)

                        if model.renderMode == .pointCloud {
                            Text("点云: \(model.pointCloudDepthAvailable ? "sceneDepth" : "featurePoints") 体素 \(model.pointCloudPointCount)/\(model.pointCloudMaxPoints) 渲染 \(model.pointCloudRenderedCount)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        if model.renderMode == .depthCoverage {
                            Text("深度覆盖: \(model.pointCloudDepthAvailable ? "sceneDepth" : "N/A") 体素 \(model.pointCloudPointCount)/\(model.pointCloudMaxPoints) 渲染 \(model.pointCloudRenderedCount)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        if model.renderMode == .planeCoverage {
                            Text(String(format: "平面覆盖: %d  覆盖率: %.1f%%", model.planeCoveragePlaneCount, model.planeCoverageRatio * 100))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                        if model.renderMode == .skyboxCoverage {
                            Text(String(format: "视锥覆盖(方向): 覆盖率 %.1f%%", model.skyboxCoverageRatio * 100))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.top, 12)

                    Spacer()
                }

                if showsRenderModePicker {
                    HStack {
                        Picker("渲染模式", selection: $model.renderMode) {
                            ForEach(model.availableRenderModes) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                        if model.renderMode != .mesh {
                            Button("清空") {
                                model.renderResetCounter += 1
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.gray.opacity(0.7))
                            .padding(.top, 6)
                            .padding(.trailing, 12)
                        }

                        Spacer()
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    if model.isMovingTooFast {
                        Text("移动过快，请放慢速度！")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.65))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    HStack(spacing: 14) {
                        Button {
                            model.startRecording()
                        } label: {
                            Text("开始采集")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(model.isRecording ? Color.gray : Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(model.isRecording)

                        Button {
                            model.stopRecording()
                        } label: {
                            Text("停止采集")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(model.isRecording ? Color.red : Color.gray)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!model.isRecording)
                    }

                    if model.isPackaging || model.reviewPayload != nil || model.isGeneratingReview {
                        Button {
                            model.isReviewPresented = true
                        } label: {
                            Text(model.isGeneratingReview ? "生成效果…" : "查看效果")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(model.isGeneratingReview ? Color.gray : Color.indigo)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(model.isGeneratingReview && model.reviewPayload == nil)
                    }

                    if showsDownloadListButton {
                        Button {
                            onShowCaptureList()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "tray.full.fill")
                                Text("下载列表")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.92))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    if let lastExport = model.lastExportSummary {
                        Text(lastExport)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }

            if shouldShowPreviewPanel {
                VStack {
                    HStack {
                        Spacer()
                        CaptureModelPreviewPanel(
                            payload: model.reviewPayload,
                            liveMeshPreviewStore: liveMeshPreviewStore,
                            liveTrajectoryPreviewStore: liveTrajectoryPreviewStore,
                            renderMode: model.renderMode,
                            livePreviewKind: livePreviewKind,
                            isGeneratingReview: model.isGeneratingReview,
                            isRecording: model.isRecording
                        )
                        .allowsHitTesting(false)
                        .frame(width: 200, height: 260)
                        .padding(.trailing, 12)
                        .padding(.top, 12)
                    }
                    Spacer()
                }
            }

            if model.isMovingTooFast {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.red.opacity(blink ? 0.95 : 0.2), lineWidth: 10)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.35), value: blink)
                    .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
                        blink.toggle()
                    }
            }
        }
        .onChange(of: model.isMovingTooFast) { newValue in
            if !newValue {
                blink = false
            }
        }
        .onChange(of: model.isRecording) { newValue in
            if newValue {
                liveMeshPreviewStore.reset()
                liveTrajectoryPreviewStore.reset()
            }
        }
        .sheet(isPresented: $model.isReviewPresented) {
            if let payload = model.reviewPayload {
                CaptureReviewView(payload: payload)
            } else {
                VStack(spacing: 12) {
                    ProgressView("正在生成采集效果…")
                    Text("（LiDAR + 网格模式下会额外生成 mesh 截图与 OBJ 预览）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding()
            }
        }
    }

    private var shouldShowPreviewPanel: Bool {
        if model.isGeneratingReview || model.reviewPayload != nil {
            return true
        }
        switch livePreviewKind {
        case .mesh:
            return model.isRecording && model.renderMode == .mesh
        case .trajectory:
            return model.isRecording || liveTrajectoryPreviewStore.hasContent
        }
    }
}

private struct CaptureModelPreviewPanel: View {
    let payload: CaptureReviewPayload?
    @ObservedObject var liveMeshPreviewStore: LiveMeshPreviewSceneStore
    @ObservedObject var liveTrajectoryPreviewStore: LiveTrajectoryPreviewStore
    let renderMode: RenderMode
    let livePreviewKind: CaptureLivePreviewKind
    let isGeneratingReview: Bool
    let isRecording: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: previewHeaderSymbolName)
                    .font(.caption.weight(.semibold))
                Text(previewHeaderTitle)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 6)
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.14))
                    .clipShape(Capsule())
            }
            .foregroundStyle(.white)

            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(10)
        .background(.black.opacity(0.50))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var previewBody: some View {
        if livePreviewKind == .mesh, isRecording, renderMode == .mesh, liveMeshPreviewStore.hasContent {
            LiveMeshPreviewView(store: liveMeshPreviewStore)
                .overlay(alignment: .bottomLeading) {
                    Text("实时")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(6)
                }
        } else if livePreviewKind == .mesh, isRecording, renderMode == .mesh {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)

                    Text("实时建模中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        } else if livePreviewKind == .trajectory {
            if let trajectory = trajectoryPlot {
                PathPlot2D(points: trajectory.points, minPt: trajectory.minPt, maxPt: trajectory.maxPt)
                    .overlay(alignment: .bottomLeading) {
                        Text(isRecording ? "实时轨迹" : "轨迹")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(6)
                    }
            } else if isGeneratingReview {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)

                        Text("实时轨迹生成中")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                    VStack(spacing: 8) {
                        Image(systemName: "location.north.line")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))

                        Text(statusText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        } else if let meshExport = payload?.meshExport {
            MeshScenePreviewView(objURL: meshExport.objURL)
                .overlay(alignment: .bottomLeading) {
                    Text(String(format: "%d/%d", meshExport.anchorCount, meshExport.faceCount))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(6)
                }
        } else if let snapshot = payload?.meshSnapshot {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.06))
                VStack(spacing: 8) {
                    if isGeneratingReview {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: isRecording ? "cube.transparent.fill" : "sparkles")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private var statusText: String {
        if livePreviewKind == .mesh, isRecording, renderMode == .mesh, liveMeshPreviewStore.hasContent {
            return "实时"
        }
        if livePreviewKind == .mesh, isRecording, renderMode == .mesh {
            return "建模中"
        }
        if livePreviewKind == .trajectory {
            if isRecording, liveTrajectoryPreviewStore.hasContent {
                return "实时轨迹"
            }
            if trajectoryPlot != nil {
                return "轨迹"
            }
            if isGeneratingReview {
                return "生成中"
            }
            return "等待轨迹"
        }
        if payload?.meshExport != nil {
            return "已生成"
        }
        if payload?.meshSnapshot != nil {
            return "快照"
        }
        if isGeneratingReview {
            return "生成中"
        }
        if isRecording {
            return "采集中"
        }
        return "待生成"
    }

    private var previewHeaderTitle: String {
        livePreviewKind == .mesh ? "模型" : "轨迹"
    }

    private var previewHeaderSymbolName: String {
        livePreviewKind == .mesh ? "cube.transparent" : "location.north.line"
    }

    private var trajectoryPlot: (points: [SIMD2<Double>], minPt: SIMD2<Double>, maxPt: SIMD2<Double>)? {
        if let payload, payload.qa.xzPositions.count >= 2 {
            return (payload.qa.xzPositions, payload.qa.boundsMin, payload.qa.boundsMax)
        }
        if liveTrajectoryPreviewStore.points.count >= 2 {
            return (liveTrajectoryPreviewStore.points, liveTrajectoryPreviewStore.boundsMin, liveTrajectoryPreviewStore.boundsMax)
        }
        return nil
    }
}

private struct LiveMeshPreviewView: View {
    @ObservedObject var store: LiveMeshPreviewSceneStore

    var body: some View {
        SceneView(
            scene: store.scene,
            pointOfView: store.cameraNode,
            options: []
        )
        .background(Color.black.opacity(0.18))
    }
}

private struct MeshScenePreviewView: View {
    let objURL: URL

    @State private var scene: SCNScene?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let scene {
                SceneView(
                    scene: scene,
                    pointOfView: nil,
                    options: [.allowsCameraControl]
                )
            } else if let loadError {
                Text(loadError)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(8)
            } else {
                ProgressView("加载模型")
                    .font(.caption2)
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .background(Color.black.opacity(0.18))
        .task(id: objURL.path) {
            scene = nil
            loadError = nil
            do {
                let loaded: SCNScene = try await Task.detached(priority: .userInitiated) {
                    try MeshReviewSceneBuilder.buildScene(objURL: objURL, style: .realistic)
                }.value
                scene = loaded
            } catch {
                loadError = "加载失败"
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(onShowCaptureList: {})
    }
}
