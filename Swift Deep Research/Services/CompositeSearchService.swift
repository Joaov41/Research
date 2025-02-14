class CompositeSearchService: SearchServiceProtocol {
    private let services: [SearchServiceProtocol]
    
    init(services: [SearchServiceProtocol]) {
        self.services = services
    }
    
    func search(query: String) async throws -> [SearchResult] {
        var allResults = Set<SearchResult>() // Use Set to avoid duplicates
        var errors: [Error] = []
        
        print("🔄 Starting composite search with \(services.count) services")
        
        // Try each search service
        for service in services {
            do {
                print("🔍 Trying search service: \(type(of: service))")
                let results = try await service.search(query: query)
                print("✅ Got \(results.count) results from \(type(of: service))")
                results.forEach { allResults.insert($0) }
            } catch {
                print("⚠️ Search service error (\(type(of: service))): \(error.localizedDescription)")
                errors.append(error)
            }
        }
        
        // If we have no results and all services failed, throw the first error
        if allResults.isEmpty && !errors.isEmpty {
            print("❌ All search services failed")
            throw errors[0]
        }
        
        let uniqueResults = Array(allResults)
        print("🎯 Total unique results across all services: \(uniqueResults.count)")
        return uniqueResults
    }
} 