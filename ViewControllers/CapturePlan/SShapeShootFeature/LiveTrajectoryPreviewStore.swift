//
//  LiveTrajectoryPreviewStore.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/5/19.
//

import ARKit
import Combine
import Foundation

@MainActor
final class LiveTrajectoryPreviewStore: ObservableObject {
    @Published private(set) var points: [SIMD2<Double>] = []
    @Published private(set) var boundsMin: SIMD2<Double> = SIMD2<Double>(0, 0)
    @Published private(set) var boundsMax: SIMD2<Double> = SIMD2<Double>(1, 1)

    private var lastPoint: SIMD2<Double>?
    private let minimumDistanceMeters: Double = 0.02
    private let maximumPointCount: Int = 3000
    private let retainedPointCount: Int = 2400

    var hasContent: Bool {
        points.count >= 2
    }

    func reset() {
        points.removeAll(keepingCapacity: true)
        boundsMin = SIMD2<Double>(0, 0)
        boundsMax = SIMD2<Double>(1, 1)
        lastPoint = nil
    }

    func append(frame: ARFrame, isRecording: Bool) {
        guard isRecording else { return }
        let transform = frame.camera.transform
        let point = SIMD2<Double>(
            Double(transform.columns.3.x),
            Double(transform.columns.3.z)
        )
        append(point: point)
    }

    private func append(point: SIMD2<Double>) {
        if let lastPoint, simd_distance(lastPoint, point) < minimumDistanceMeters {
            return
        }

        points.append(point)
        lastPoint = point

        if points.count == 1 {
            boundsMin = point
            boundsMax = point
            return
        }

        boundsMin.x = min(boundsMin.x, point.x)
        boundsMin.y = min(boundsMin.y, point.y)
        boundsMax.x = max(boundsMax.x, point.x)
        boundsMax.y = max(boundsMax.y, point.y)

        if points.count > maximumPointCount {
            let removeCount = points.count - retainedPointCount
            points.removeFirst(removeCount)
            recomputeBounds()
            lastPoint = points.last
        }
    }

    private func recomputeBounds() {
        guard let first = points.first else {
            boundsMin = SIMD2<Double>(0, 0)
            boundsMax = SIMD2<Double>(1, 1)
            return
        }

        var minPt = first
        var maxPt = first
        for point in points.dropFirst() {
            minPt.x = min(minPt.x, point.x)
            minPt.y = min(minPt.y, point.y)
            maxPt.x = max(maxPt.x, point.x)
            maxPt.y = max(maxPt.y, point.y)
        }
        boundsMin = minPt
        boundsMax = maxPt
    }
}
