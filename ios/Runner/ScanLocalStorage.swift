import Foundation
import os.log

class ScanLocalStorage {
    static let shared = ScanLocalStorage()
    private let fileManager = FileManager.default
    
    private init() {}
    
    // MARK: - Directory Management
    
    private func getScanDirectory() -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let scanDirectory = documentsPath.appendingPathComponent("Scans")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: scanDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return scanDirectory
    }
    
    // MARK: - Scan Management
    
    func getAllScans() -> [(url: URL, metadata: ScanMetadata?)] {
        let scanDirectory = getScanDirectory()
        
        do {
            let scanFolders = try fileManager.contentsOfDirectory(at: scanDirectory, includingPropertiesForKeys: nil)
            
            return scanFolders.compactMap { folderURL in
                guard folderURL.hasDirectoryPath else { return nil }
                
                let metadata = loadMetadata(from: folderURL)
                return (url: folderURL, metadata: metadata)
            }.sorted { scan1, scan2 in
                // Sort by timestamp (newest first)
                let timestamp1 = scan1.metadata?.timestamp ?? Date.distantPast
                let timestamp2 = scan2.metadata?.timestamp ?? Date.distantPast
                return timestamp1 > timestamp2
            }
        } catch {
            os_log("Failed to get scan directories: %@", log: OSLog.default, type: .error, error.localizedDescription)
            return []
        }
    }
    
    func loadMetadata(from scanURL: URL) -> ScanMetadata? {
        let metadataURL = scanURL.appendingPathComponent("metadata.json")
        
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ScanMetadata.self, from: data)
        } catch {
            os_log("Failed to load metadata from %@: %@", log: OSLog.default, type: .error, metadataURL.path, error.localizedDescription)
            return nil
        }
    }
    
    func saveMetadata(_ metadata: ScanMetadata, to scanURL: URL) -> Bool {
        let metadataURL = scanURL.appendingPathComponent("metadata.json")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL)
            return true
        } catch {
            os_log("Failed to save metadata to %@: %@", log: OSLog.default, type: .error, metadataURL.path, error.localizedDescription)
            return false
        }
    }
    
    func updateScanStatus(_ status: String, for scanURL: URL) -> Bool {
        guard var metadata = loadMetadata(from: scanURL) else {
            os_log("No metadata found for scan at %@", log: OSLog.default, type: .error, scanURL.path)
            return false
        }
        
        // Create new metadata with updated status
        let updatedMetadata = ScanMetadata(
            name: metadata.name,
            timestamp: metadata.timestamp,
            scanID: metadata.scanID,
            coordinates: metadata.coordinates,
            coordinateTimestamps: metadata.coordinateTimestamps,
            locationName: metadata.locationName,
            modelSizeBytes: metadata.modelSizeBytes,
            imageCount: metadata.imageCount,
            status: status,
            snapshotPath: metadata.snapshotPath,
            durationSeconds: metadata.durationSeconds,
            boundsSize: metadata.boundsSize,
            areaCovered: metadata.areaCovered,
            height: metadata.height
        )
        
        return saveMetadata(updatedMetadata, to: scanURL)
    }
    
    func updateScanName(_ name: String, for scanURL: URL) -> Bool {
        guard var metadata = loadMetadata(from: scanURL) else {
            os_log("No metadata found for scan at %@", log: OSLog.default, type: .error, scanURL.path)
            return false
        }
        
        // Create new metadata with updated name
        let updatedMetadata = ScanMetadata(
            name: name,
            timestamp: metadata.timestamp,
            scanID: metadata.scanID,
            coordinates: metadata.coordinates,
            coordinateTimestamps: metadata.coordinateTimestamps,
            locationName: metadata.locationName,
            modelSizeBytes: metadata.modelSizeBytes,
            imageCount: metadata.imageCount,
            status: metadata.status,
            snapshotPath: metadata.snapshotPath,
            durationSeconds: metadata.durationSeconds,
            boundsSize: metadata.boundsSize,
            areaCovered: metadata.areaCovered,
            height: metadata.height
        )
        
        return saveMetadata(updatedMetadata, to: scanURL)
    }
    
    func deleteScan(at scanURL: URL) -> Bool {
        do {
            try fileManager.removeItem(at: scanURL)
            os_log("Successfully deleted scan at %@", log: OSLog.default, type: .info, scanURL.path)
            return true
        } catch {
            os_log("Failed to delete scan at %@: %@", log: OSLog.default, type: .error, scanURL.path, error.localizedDescription)
            return false
        }
    }
    
    func hasUSDZModel(in scanURL: URL) -> Bool {
        let usdzURL = scanURL.appendingPathComponent("model.usdz")
        return fileManager.fileExists(atPath: usdzURL.path)
    }
    
    // MARK: - Image Management
    
    func getScanImages(folderPath: String) -> [String]? {
        let folderURL = URL(fileURLWithPath: folderPath)
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            let imageFiles = contents.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["jpg", "jpeg", "png", "heic"].contains(pathExtension)
            }
            
            return imageFiles.map { $0.path }
        } catch {
            os_log("Failed to get images from folder %@: %@", log: OSLog.default, type: .error, folderPath, error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Utility Methods
    
    func createScanFolder(withName name: String) -> URL? {
        let scanDirectory = getScanDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let folderName = "\(name)_\(timestamp)".replacingOccurrences(of: ":", with: "-")
        let scanFolderURL = scanDirectory.appendingPathComponent(folderName)
        
        do {
            try fileManager.createDirectory(at: scanFolderURL, withIntermediateDirectories: true, attributes: nil)
            return scanFolderURL
        } catch {
            os_log("Failed to create scan folder %@: %@", log: OSLog.default, type: .error, scanFolderURL.path, error.localizedDescription)
            return nil
        }
    }
    
    func getScanCount() -> Int {
        return getAllScans().count
    }
    
    func getTotalScanSize() -> Int64 {
        let scans = getAllScans()
        var totalSize: Int64 = 0
        
        for scan in scans {
            do {
                let folderSize = try getFolderSize(at: scan.url)
                totalSize += folderSize
            } catch {
                os_log("Failed to calculate size for scan at %@: %@", log: OSLog.default, type: .error, scan.url.path, error.localizedDescription)
            }
        }
        
        return totalSize
    }
    
    private func getFolderSize(at url: URL) throws -> Int64 {
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var totalSize: Int64 = 0
        
        for fileURL in contents {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
}
