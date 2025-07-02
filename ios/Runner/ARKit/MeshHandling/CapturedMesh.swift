import ARKit
import simd

public struct CapturedMesh: Codable {
    public var vertices: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var indices: [UInt32]
    public var transform: [[Float]]
    
    public init(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.normals = normals
        self.indices = indices
        self.transform = transform.toArray()
    }
    
    public var serializableRepresentation: [String: Any] {
        return [
            "vertices": vertices.map { ["x": $0.x, "y": $0.y, "z": $0.z] },
            "normals": normals.map { ["x": $0.x, "y": $0.y, "z": $0.z] },
            "indices": indices,
            "transform": transform
        ]
    }
    
    public func exportAsPLY() -> String {
        var header = """
        ply
        format ascii 1.0
        comment Generated from ARKit scan
        element vertex \(vertices.count)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        element face \(indices.count / 3)
        property list uchar uint vertex_indices
        end_header\n\n
        """
        
        var body = ""
        for i in 0..<vertices.count {
            let v = vertices[i]
            let n = normals[i]
            body += "\(v.x) \(v.y) \(v.z) \(n.x) \(n.y) \(n.z)\n"
        }
        
        for i in stride(from: 0, to: indices.count, by: 3) {
            body += "3 \(indices[i]) \(indices[i+1]) \(indices[i+2])\n"
        }
        
        return header + body
    }
}

extension simd_float4x4 {
    public func toArray() -> [[Float]] {
        return [
            [columns.0.x, columns.0.y, columns.0.z, columns.0.w],
            [columns.1.x, columns.1.y, columns.1.z, columns.1.w],
            [columns.2.x, columns.2.y, columns.2.z, columns.2.w],
            [columns.3.x, columns.3.y, columns.3.z, columns.3.w]
        ]
    }
    
    public init(_ array: [[Float]]) {
        self.init(
            SIMD4<Float>(array[0][0], array[0][1], array[0][2], array[0][3]),
            SIMD4<Float>(array[1][0], array[1][1], array[1][2], array[1][3]),
            SIMD4<Float>(array[2][0], array[2][1], array[2][2], array[2][3]),
            SIMD4<Float>(array[3][0], array[3][1], array[3][2], array[3][3])
        )
    }
}
