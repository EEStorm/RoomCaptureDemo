//
//  CaptureReviewModels.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//

import Foundation
import UIKit

struct CaptureQAStats: Equatable {
    var poseCount: Int
    var durationSeconds: Double
    var averageFPS: Double

    var totalDistanceMeters: Double
    var maxLinearSpeed: Double
    var maxAngularSpeed: Double
    var speedOverTime: [Double]
    var angularOverTime: [Double]

    // For a simple 2D top-down plot.
    var xzPositions: [SIMD2<Double>]
    var boundsMin: SIMD2<Double>
    var boundsMax: SIMD2<Double>
}

struct MeshExportInfo: Equatable {
    var objURL: URL
    var vertexCount: Int
    var faceCount: Int
    var anchorCount: Int
}

struct CaptureReviewPayload: Equatable {
    var exportFolderURL: URL
    var videoURL: URL
    var jsonURL: URL

    var qa: CaptureQAStats
    var meshSnapshot: UIImage?
    var meshExport: MeshExportInfo?
}
