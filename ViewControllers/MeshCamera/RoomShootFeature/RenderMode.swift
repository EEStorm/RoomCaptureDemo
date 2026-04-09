//
//  RenderMode.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import Foundation

enum RenderMode: String, CaseIterable, Identifiable {
    case mesh = "网格"
    case pointCloud = "点云"
    case planeCoverage = "平面覆盖"
    case depthCoverage = "深度覆盖"
    case skyboxCoverage = "视锥覆盖"

    var id: String { rawValue }
}
