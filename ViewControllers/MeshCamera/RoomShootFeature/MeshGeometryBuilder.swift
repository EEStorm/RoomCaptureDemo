//
//  MeshGeometryBuilder.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import ARKit
import SceneKit

enum MeshGeometryBuilder {
    static func buildGeometry(from mesh: ARMeshGeometry) -> SCNGeometry {
        let vertices = extractVertices(mesh: mesh)
        let vertexSource = SCNGeometrySource(vertices: vertices)

        let normals = extractNormals(mesh: mesh)
        let normalSource = SCNGeometrySource(normals: normals)

        let indices = extractTriangleIndices(mesh: mesh)
        let indexData = indices.withUnsafeBytes { Data($0) }

        // Use two elements with different materials:
        // - A semi-transparent fill for depth/shape readability
        // - A brighter wireframe overlay for coverage feedback
        let fillElement = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let wireElement = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [fillElement, wireElement])

        let fillMaterial = SCNMaterial()
        fillMaterial.diffuse.contents = UIColor.green.withAlphaComponent(0.18)
        fillMaterial.isDoubleSided = true
        fillMaterial.lightingModel = .constant
        fillMaterial.fillMode = .fill
        fillMaterial.blendMode = .alpha
        fillMaterial.writesToDepthBuffer = true
        fillMaterial.readsFromDepthBuffer = true

        let wireMaterial = SCNMaterial()
        wireMaterial.diffuse.contents = UIColor.green.withAlphaComponent(0.95)
        wireMaterial.emission.contents = UIColor.green.withAlphaComponent(0.9)
        wireMaterial.isDoubleSided = true
        wireMaterial.lightingModel = .constant
        wireMaterial.fillMode = .lines
        wireMaterial.blendMode = .add
        // Draw as an overlay to keep the wireframe crisp.
        wireMaterial.writesToDepthBuffer = false
        wireMaterial.readsFromDepthBuffer = true

        geometry.materials = [fillMaterial, wireMaterial]

        return geometry
    }

    private static func extractVertices(mesh: ARMeshGeometry) -> [SCNVector3] {
        let vertexBuffer = mesh.vertices.buffer
        let vertexStride = mesh.vertices.stride
        let vertexOffset = mesh.vertices.offset
        let count = mesh.vertices.count

        var result: [SCNVector3] = []
        result.reserveCapacity(count)

        let baseAddress = vertexBuffer.contents().advanced(by: vertexOffset)
        for i in 0..<count {
            let v = baseAddress.advanced(by: i * vertexStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            result.append(SCNVector3(v.x, v.y, v.z))
        }
        return result
    }

    private static func extractNormals(mesh: ARMeshGeometry) -> [SCNVector3] {
        let normalBuffer = mesh.normals.buffer
        let normalStride = mesh.normals.stride
        let normalOffset = mesh.normals.offset
        let count = mesh.normals.count

        var result: [SCNVector3] = []
        result.reserveCapacity(count)

        let baseAddress = normalBuffer.contents().advanced(by: normalOffset)
        for i in 0..<count {
            let n = baseAddress.advanced(by: i * normalStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            result.append(SCNVector3(n.x, n.y, n.z))
        }
        return result
    }

    private static func extractTriangleIndices(mesh: ARMeshGeometry) -> [UInt32] {
        let faces = mesh.faces
        let faceBuffer = faces.buffer
        let bytesPerIndex = faces.bytesPerIndex
        let indexCountPerPrimitive = faces.indexCountPerPrimitive
        let primitiveCount = faces.count

        precondition(indexCountPerPrimitive == 3, "Expected triangles")

        var indices: [UInt32] = []
        indices.reserveCapacity(primitiveCount * indexCountPerPrimitive)

        let baseAddress = faceBuffer.contents()

        for primitiveIndex in 0..<primitiveCount {
            let primitiveBase = baseAddress.advanced(by: primitiveIndex * indexCountPerPrimitive * bytesPerIndex)
            for i in 0..<indexCountPerPrimitive {
                let idxPtr = primitiveBase.advanced(by: i * bytesPerIndex)
                let index: UInt32
                switch bytesPerIndex {
                case 2:
                    index = UInt32(idxPtr.assumingMemoryBound(to: UInt16.self).pointee)
                case 4:
                    index = idxPtr.assumingMemoryBound(to: UInt32.self).pointee
                default:
                    index = 0
                }
                indices.append(index)
            }
        }

        return indices
    }
}
