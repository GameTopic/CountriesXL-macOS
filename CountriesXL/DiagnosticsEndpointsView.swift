import SwiftUI
import Foundation

struct DiagnosticsEndpointsView: View {
    @Environment(\.xfAPI) var api
    
    @State private var resourceStatus: Int? = nil
    @State private var mediaStatus: Int? = nil
    @State private var threadsStatus: Int? = nil
    @State private var errorMessage: String = ""
    
    private var resourcePrefix: String {
        UserDefaults.standard.string(forKey: "xf_resource_route_prefix") ?? "resources"
    }
    private var mediaPrefix: String {
        UserDefaults.standard.string(forKey: "xf_media_route_prefix") ?? "media"
    }
    private var threadsPrefix: String {
        UserDefaults.standard.string(forKey: "xf_thread_route_prefix") ?? "threads"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Resource Endpoint: /\(resourcePrefix)/")
                .font(.headline)
            Text(statusText(for: resourceStatus))
                .foregroundColor(color(for: resourceStatus))
            
            Text("Media Endpoint: /\(mediaPrefix)/")
                .font(.headline)
            Text(statusText(for: mediaStatus))
                .foregroundColor(color(for: mediaStatus))
            
            Text("Threads Endpoint: /\(threadsPrefix)/")
                .font(.headline)
            Text(statusText(for: threadsStatus))
                .foregroundColor(color(for: threadsStatus))
            
            if !errorMessage.isEmpty {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            
            Button("Retry") {
                runChecks()
            }
            .padding(.top, 12)
        }
        .padding()
        .onAppear {
            runChecks()
        }
    }
    
    private func statusText(for status: Int?) -> String {
        if let status = status {
            return "Status Code: \(status)"
        } else {
            return "Status: Unknown"
        }
    }
    
    private func color(for status: Int?) -> Color {
        guard let status = status else { return .gray }
        switch status {
        case 200..<300: return .green
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }
    
    private func runChecks() {
        errorMessage = ""
        resourceStatus = nil
        mediaStatus = nil
        threadsStatus = nil
        
        Task {
            do {
                resourceStatus = try await api.fetchResourcesStatus()
            } catch {
                errorMessage = "Resource endpoint error: \(error.localizedDescription)"
                resourceStatus = nil
            }
        }
        Task {
            do {
                mediaStatus = try await api.fetchMediaStatus()
            } catch {
                errorMessage = "Media endpoint error: \(error.localizedDescription)"
                mediaStatus = nil
            }
        }
        Task {
            do {
                threadsStatus = try await api.fetchThreadsStatus()
            } catch {
                errorMessage = "Threads endpoint error: \(error.localizedDescription)"
                threadsStatus = nil
            }
        }
    }
}
