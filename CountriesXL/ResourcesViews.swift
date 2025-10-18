import SwiftUI

struct ResourcesView: View {
    let appState: AppState
    @State private var resources: [XFResource] = []
    @State private var isLoading = false
    private let api = XenForoAPI()

    var body: some View {
        Group {
            if isLoading { ProgressView().controlSize(.large) }
            List(resources) { res in
                NavigationLink(destination: ResourceDetailView(appState: appState, resource: res).environmentObject(appState)) {
                    HStack(spacing: 12) {
                        AsyncImage(url: res.iconURL) { phase in
                            switch phase {
                            case .empty: Color.clear.frame(width: 32, height: 32)
                            case .success(let image): image.resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                            case .failure: Image(systemName: "shippingbox").frame(width: 32, height: 32)
                            @unknown default: EmptyView()
                            }
                        }
                        VStack(alignment: .leading) {
                            Text(res.title).font(.headline)
                            HStack(spacing: 8) {
                                if let views = res.viewCount { Label("\(views)", systemImage: "eye") }
                                if let downloads = res.downloadCount { Label("\(downloads)", systemImage: "arrow.down.circle") }
                                if let rating = res.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                            }
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        }
                        Spacer()
                        ResourceDownloadControls(
                            id: res.id,
                            title: res.title,
                            urlProvider: { try await api.resourceDownloadURL(resourceID: res.id, accessToken: appState.accessToken) }
                        )
                        .environmentObject(appState)
                    }
                }
            }
        }
        .environmentObject(appState)
        .navigationTitle("Resources")
        .task { await loadResources() }
    }

    private func loadResources() async {
        // Skip silently when offline or forum inactive; global overlay will communicate state.
        guard (NetworkMonitor.shared.isConnected ?? true) && BoardStatusService.shared.isActive else { return }

        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            resources = try await api.fetchResources(accessToken: appState.accessToken)
        } catch {
            // handle error (keep empty for now)
        }
    }
}

struct ResourceDetailView: View {
    let appState: AppState
    let resource: XFResource
    private let api = XenForoAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let cover = resource.coverURL {
                    AsyncImage(url: cover) { image in
                        image.resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
                    } placeholder: {
                        Rectangle().fill(.quaternary).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text(resource.title).font(.largeTitle).bold()
                if let tagline = resource.tagLine { Text(tagline).foregroundStyle(.secondary) }
                HStack(spacing: 12) {
                    if let rating = resource.rating { Label(String(format: "%.1f", rating), systemImage: "star.fill") }
                    if let downloads = resource.downloadCount { Label("\(downloads) downloads", systemImage: "arrow.down.circle") }
                    if let views = resource.viewCount { Label("\(views) views", systemImage: "eye") }
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
                DownloadButton(
                    id: resource.id,
                    title: resource.title,
                    style: .borderedProminent,
                    urlProvider: { try await api.resourceDownloadURL(resourceID: resource.id, accessToken: appState.accessToken) }
                )
                .environmentObject(appState)
            }
            .padding()
        }
        .navigationTitle("Resource")
    }
}

