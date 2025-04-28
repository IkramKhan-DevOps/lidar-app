import Foundation
import ZIPFoundation
import os // Import os for os_log and OSLog

extension FileManager {
    func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var success = false
        
        coordinator.coordinate(readingItemAt: sourceURL, options: [.forUploading], error: &coordinationError) { (zipURL) in
            do {
                if fileExists(atPath: destinationURL.path) {
                    try removeItem(at: destinationURL)
                }
                try moveItem(at: zipURL, to: destinationURL)
                success = true
            } catch let moveError {
                os_log("ZIP operation failed: %@", log: OSLog.default, type: .error, moveError.localizedDescription)
            }
        }
        
        if !success, let error = coordinationError {
            throw error
        }
    }
}
