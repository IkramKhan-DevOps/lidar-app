import Foundation

@objc class ScanMetadata: NSObject, Codable {
    let name: String
    let timestamp: Date
    let scanID: String
    let coordinates: [[Double]]?
    let coordinateTimestamps: [String]?
    let locationName: String?
    let modelSizeBytes: Double?    // Changed from Int64 to Double to match data_size_mb
    let imageCount: Int
    let status: String
    let snapshotPath: String?
    let durationSeconds: Int?      // Changed from Double to Int to match duration field
    let boundsSize: String?
    let areaCovered: Double?       // Added to match area_covered
    let height: Double?            // Added to match height field
    
    init(name: String,
         timestamp: Date,
         scanID: String,
         coordinates: [[Double]]? = nil,
         coordinateTimestamps: [String]? = nil,
         locationName: String? = nil,
         modelSizeBytes: Double? = nil,    // Changed type
         imageCount: Int = 0,
         status: String = "pending",
         snapshotPath: String? = nil,
         durationSeconds: Int? = nil,      // Changed type
         boundsSize: String? = nil,
         areaCovered: Double? = nil,       // Added parameter
         height: Double? = nil) {          // Added parameter
        
        self.name = name
        self.timestamp = timestamp
        self.scanID = scanID
        self.coordinates = coordinates
        self.coordinateTimestamps = coordinateTimestamps
        self.locationName = locationName
        self.modelSizeBytes = modelSizeBytes
        self.imageCount = imageCount
        self.status = status
        self.snapshotPath = snapshotPath
        self.durationSeconds = durationSeconds
        self.boundsSize = boundsSize
        self.areaCovered = areaCovered      // Added assignment
        self.height = height                // Added assignment
        
        super.init()
    }
}
