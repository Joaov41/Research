import Foundation

actor RateLimiter {
    private let requestsPerMinute: Int
    private var timestamps: [Date] = []
    
    init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
    }
    
    func waitForSlot() async throws {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        // Remove timestamps older than 1 minute
        timestamps = timestamps.filter { $0 > oneMinuteAgo }
        
        // If we haven't hit the limit, add timestamp and continue
        if timestamps.count < requestsPerMinute {
            timestamps.append(now)
            return
        }
        
        // Calculate wait time until next available slot
        if let oldestTimestamp = timestamps.first {
            let waitTime = oldestTimestamp.timeIntervalSince(oneMinuteAgo)
            if waitTime > 0 {
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
            timestamps.removeFirst()
            timestamps.append(now)
        }
    }
} 