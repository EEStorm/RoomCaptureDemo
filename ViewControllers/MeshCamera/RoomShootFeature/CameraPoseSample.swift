//
//  CameraPoseSample.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import Foundation
import simd

// 每帧与视频严格同步保存:
// 1) timestamp
// 2) transform (4x4 外参)
// 3) intrinsics (3x3 内参)
struct CameraPoseSample: Codable {
    let timestamp: Double
    let transformColumns: [[Float]] // 4 columns, each 4 floats
    let intrinsicsColumns: [[Float]] // 3 columns, each 3 floats
}

extension simd_float4x4 {
    var columnsArray: [[Float]] {
        [
            [columns.0.x, columns.0.y, columns.0.z, columns.0.w],
            [columns.1.x, columns.1.y, columns.1.z, columns.1.w],
            [columns.2.x, columns.2.y, columns.2.z, columns.2.w],
            [columns.3.x, columns.3.y, columns.3.z, columns.3.w],
        ]
    }
}

extension simd_float3x3 {
    var columnsArray: [[Float]] {
        [
            [columns.0.x, columns.0.y, columns.0.z],
            [columns.1.x, columns.1.y, columns.1.z],
            [columns.2.x, columns.2.y, columns.2.z],
        ]
    }
}

