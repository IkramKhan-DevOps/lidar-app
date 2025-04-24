import simd

struct CapturedMesh: Codable {
    var vertices: [SIMD3<Float>]
    var indices: [UInt32]
    var transform: [[Float]]
    
    init(vertices: [SIMD3<Float>], indices: [UInt32], transform: simd_float4x4) {
        self.vertices = vertices
        self.indices = indices
        self.transform = transform.toArray()
    }
    
    func getTransform() -> simd_float4x4 {
        return simd_float4x4(self.transform)
    }
}

extension simd_float4x4 {
    func toArray() -> [[Float]] {
        return [
            [columns.0.x, columns.0.y, columns.0.z, columns.0.w],
            [columns.1.x, columns.1.y, columns.1.z, columns.1.w],
            [columns.2.x, columns.2.y, columns.2.z, columns.2.w],
            [columns.3.x, columns.3.y, columns.3.z, columns.3.w]
        ]
    }
    
    init(_ array: [[Float]]) {
        self.init(
            SIMD4<Float>(array[0][0], array[0][1], array[0][2], array[0][3]),
            SIMD4<Float>(array[1][0], array[1][1], array[1][2], array[1][3]),
            SIMD4<Float>(array[2][0], array[2][1], array[2][2], array[2][3]),
            SIMD4<Float>(array[3][0], array[3][1], array[3][2], array[3][3])
        )
    }
}
