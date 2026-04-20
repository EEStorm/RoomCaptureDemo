//
//  CaptureReviewView.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//

import AVFoundation
import SceneKit
import SwiftUI

struct CaptureReviewView: View {
    let payload: CaptureReviewPayload

    @State private var selectedTab: Tab = .qa

    enum Tab: String, CaseIterable, Identifiable {
        case qa = "质检"
        case coverage = "覆盖"
        case mesh3d = "3D"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Review", selection: $selectedTab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.top, 10)

                Group {
                    switch selectedTab {
                    case .qa:
                        QASection(qa: payload.qa)
                    case .coverage:
                        CoverageSection(snapshot: payload.meshSnapshot, meshExport: payload.meshExport)
                    case .mesh3d:
                        Mesh3DSection(meshExport: payload.meshExport)
                    }
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Text(payload.exportFolderURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("文件：\(fileNames.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 12)
            }
            .navigationTitle("采集效果")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var fileNames: [String] {
        var names = [payload.videoURL.lastPathComponent, payload.jsonURL.lastPathComponent]
        if let objName = payload.meshExport?.objURL.lastPathComponent {
            names.append(objName)
        }
        return names
    }
}

private struct QASection: View {
    let qa: CaptureQAStats

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "Pose 帧数：%d  时长：%.2fs  平均 FPS：%.1f", qa.poseCount, qa.durationSeconds, qa.averageFPS))
                        .font(.subheadline)
                    Text(String(format: "总路程：%.2fm  最大线速度：%.2fm/s  最大角速度：%.2frad/s", qa.totalDistanceMeters, qa.maxLinearSpeed, qa.maxAngularSpeed))
                        .font(.subheadline)
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("轨迹（俯视 X-Z）")
                    .font(.headline)
                PathPlot2D(points: qa.xzPositions, minPt: qa.boundsMin, maxPt: qa.boundsMax)
                    .frame(height: 220)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("线速度曲线")
                    .font(.headline)
                LinePlot(values: qa.speedOverTime, color: .green)
                    .frame(height: 120)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("角速度曲线")
                    .font(.headline)
                LinePlot(values: qa.angularOverTime, color: .orange)
                    .frame(height: 120)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.vertical, 6)
        }
    }
}

private struct CoverageSection: View {
    let snapshot: UIImage?
    let meshExport: MeshExportInfo?
    @State private var scene: SCNScene?
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mesh 覆盖（可旋转查看洞/缺口）")
                .font(.headline)

            Group {
                if let meshExport {
                    if let scene {
                        SceneView(scene: scene, options: [.allowsCameraControl])
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    } else {
                        ProgressView("加载中…")
                            .padding(10)
                    }
                } else if let snapshot {
                    GeometryReader { proxy in
                        Image(uiImage: snapshot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                } else {
                    Text("暂无 mesh（请确保采集时在“网格”模式并扫出可见 mesh）。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(height: 420)
            .background(Color.black.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task {
                if let meshExport {
                    await loadSceneIfNeeded(url: meshExport.objURL)
                }
            }
        }
    }

    @MainActor
    private func loadSceneIfNeeded(url: URL) async {
        if scene != nil || loadError != nil { return }
        do {
            let loaded: SCNScene = try await Task.detached(priority: .userInitiated) {
                return try MeshReviewSceneBuilder.buildScene(objURL: url, style: .wireframe)
            }.value
            scene = loaded
        } catch {
            loadError = "加载 mesh 失败：\(error.localizedDescription)"
        }
    }
}

private struct Mesh3DSection: View {
    let meshExport: MeshExportInfo?
    @State private var scene: SCNScene?
    @State private var loadError: String?
    @State private var style: MeshReviewStyle = .realistic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3D Mesh 预览（更真实的光照/地面/坐标轴）")
                .font(.headline)

            if let meshExport {
                Text("Anchors：\(meshExport.anchorCount)  Vertices：\(meshExport.vertexCount)  Faces：\(meshExport.faceCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("渲染", selection: $style) {
                    ForEach(MeshReviewStyle.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    if let scene {
                        SceneView(
                            scene: scene,
                            pointOfView: nil,
                            options: [.allowsCameraControl]
                        )
                    } else if let loadError {
                        Text(loadError)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(10)
                    } else {
                        ProgressView("加载中…")
                            .padding(10)
                    }
                }
                .frame(height: 420)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .task { await rebuildScene(url: meshExport.objURL, style: style) }
                .onChange(of: style) { newStyle in
                    Task { await rebuildScene(url: meshExport.objURL, style: newStyle) }
                }
            } else {
                Text("未导出 mesh（仅 LiDAR + mesh 模式下可用）。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    @MainActor
    private func rebuildScene(url: URL, style: MeshReviewStyle) async {
        scene = nil
        loadError = nil
        do {
            let loaded: SCNScene = try await Task.detached(priority: .userInitiated) {
                return try MeshReviewSceneBuilder.buildScene(objURL: url, style: style)
            }.value
            scene = loaded
        } catch {
            loadError = "加载 OBJ 失败：\(error.localizedDescription)"
        }
    }
}

private struct PathPlot2D: View {
    let points: [SIMD2<Double>]
    let minPt: SIMD2<Double>
    let maxPt: SIMD2<Double>

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let pad: Double = 16
            let w = Double(size.width)
            let h = Double(size.height)
            let sx = (w - pad * 2) / Swift.max(1e-9, (maxPt.x - minPt.x))
            let sy = (h - pad * 2) / Swift.max(1e-9, (maxPt.y - minPt.y))
            let s = min(sx, sy)

            func map(_ p: SIMD2<Double>) -> CGPoint {
                let x = (p.x - minPt.x) * s + pad
                // Z axis downwards for screen.
                let y = (maxPt.y - p.y) * s + pad
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: map(points[0]))
            for p in points.dropFirst() {
                path.addLine(to: map(p))
            }

            ctx.stroke(path, with: .color(.green.opacity(0.9)), lineWidth: 2)

            // Start/end markers
            let start = map(points.first!)
            let end = map(points.last!)
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(.blue))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.red))
        }
        .padding(10)
    }
}

private struct LinePlot: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let pad: Double = 10
            let w = Double(size.width)
            let h = Double(size.height)
            let minV = values.min() ?? 0
            let maxV = max(values.max() ?? 1, minV + 1e-6)
            let dx = (w - pad * 2) / Double(values.count - 1)

            func map(i: Int) -> CGPoint {
                let x = pad + Double(i) * dx
                let t = (values[i] - minV) / (maxV - minV)
                let y = pad + (1.0 - t) * (h - pad * 2)
                return CGPoint(x: x, y: y)
            }

            var path = Path()
            path.move(to: map(i: 0))
            for i in 1..<values.count {
                path.addLine(to: map(i: i))
            }

            ctx.stroke(path, with: .color(color.opacity(0.95)), lineWidth: 2)
        }
        .padding(10)
    }
}
