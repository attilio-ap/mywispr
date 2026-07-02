import Foundation

class Logger {
    static let logURL = URL(fileURLWithPath: "/tmp/mywispr.log")
    
    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        print(message)
        
        if let data = logLine.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
    }
    
    static func clear() {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
    }
}
