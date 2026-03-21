import SwiftUI

struct LegacyDownloadsView: View {
    var body: some View {
        DownloadsBrowser(showsManualEntry: true)
    }
}

#Preview {
    NavigationStack {
        LegacyDownloadsView()
    }
}
