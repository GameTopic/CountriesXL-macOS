import SwiftUI

struct HomeView: View { var body: some View { PlaceholderView(title: "Home") } }

struct ForumsView: View {
    var body: some View {
        PlaceholderView(title: "Forums (XF 2.3 API)")
    }
}

struct MediaView: View {
    var body: some View {
        PlaceholderView(title: "Media & Albums")
    }
}

struct SearchView: View {
    let query: String
    var body: some View {
        PlaceholderView(title: "Search: \(query)")
    }
}

struct ProfileView: View {
    var body: some View {
        PlaceholderView(title: "My Profile")
    }
}

struct PlaceholderView: View {
    let title: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(title).font(.title2).bold()
            Text("Powered by XenForo API at cities-mods.com").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
