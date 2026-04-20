//
//  ContentView.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import SwiftUI
import Combine
import UIKit

struct ContentView: View {
    let onShowCaptureList: () -> Void

    @StateObject private var model = CaptureSessionModel()
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(onShowCaptureList: {})
    }
}
