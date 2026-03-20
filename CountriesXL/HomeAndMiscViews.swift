import AVKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var resources: [XFResource] = []
    @State private var mediaItems: [XFMedia] = []
    @State private var threads: [XFThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ContentHeaderCard(
                    title: "Home",
                    subtitle: "Jump back into recent resources, media, and forum activity."
                ) {
                    HStack(spacing: 12) {
                        StatBadge(label: "Resources", value: resources.count.formatted())
                        StatBadge(label: "Media", value: mediaItems.count.formatted())
                        StatBadge(label: "Threads", value: threads.count.formatted())
                    }
                }

                if let errorMessage {
                    InlineErrorCard(message: errorMessage) {
                        Task { await loadDashboard(forceRefresh: true) }
                    }
                } else if isLoading && resources.isEmpty && mediaItems.isEmpty && threads.isEmpty {
                    ProgressCard(title: "Loading home dashboard")
                } else {
                    HomeSection(title: "Recent Resources") {
                        ForEach(resources.prefix(4)) { resource in
                            NavigationLink(
                                value: AppNavigationDestination.resource(
                                    ResourceNavigationContext(
                                        resource: resource,
                                        fallbackRelatedResources: resources
                                    )
                                )
                            ) {
                                SearchResourceRow(resource: resource)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HomeSection(title: "Latest Media") {
                        ForEach(mediaItems.prefix(4)) { media in
                            NavigationLink(value: AppNavigationDestination.media(media)) {
                                SearchMediaRow(media: media)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HomeSection(title: "Forum Activity") {
                        ForEach(threads.prefix(5)) { thread in
                            NavigationLink(value: AppNavigationDestination.thread(thread)) {
                                ThreadRowCard(thread: thread)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Home")
        .task { await loadDashboard() }
    }

    private func loadDashboard(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedResources = try await api.fetchResources(accessToken: appState.accessToken)
            let loadedMediaResponse = try await api.listMedia(accessToken: appState.accessToken)
            let loadedThreadsResponse = try await api.listThreads(accessToken: appState.accessToken)
            let loadedMedia = loadedMediaResponse.items
            let loadedThreads = loadedThreadsResponse.items

            resources = Array(
                loadedResources
                    .sorted { ($0.updatedDate ?? $0.releaseDate ?? .distantPast) > ($1.updatedDate ?? $1.releaseDate ?? .distantPast) }
                    .prefix(6)
            )
            mediaItems = Array(loadedMedia.prefix(6))
            threads = Array(
                loadedThreads
                    .sorted { ($0.postDate ?? .distantPast) > ($1.postDate ?? .distantPast) }
                    .prefix(8)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @State private var resources: [XFResource] = []
    @State private var mediaItems: [XFMedia] = []
    @State private var threads: [XFThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ContentHeaderCard(
                    title: "Discover",
                    subtitle: "A full discovery hub for resources, media, threads, and quick jumps across the community."
                ) {
                    HStack(spacing: 12) {
                        StatBadge(label: "Resources", value: resources.count.formatted())
                        StatBadge(label: "Media", value: mediaItems.count.formatted())
                        StatBadge(label: "Threads", value: threads.count.formatted())
                    }
                }

                if let errorMessage {
                    InlineErrorCard(message: errorMessage) {
                        Task { await loadDiscover(forceRefresh: true) }
                    }
                } else if isLoading && resources.isEmpty && mediaItems.isEmpty && threads.isEmpty {
                    ProgressCard(title: "Loading discovery hub")
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            featuredDiscoveryColumn
                                .frame(maxWidth: .infinity, alignment: .leading)
                            secondaryDiscoveryColumn
                                .frame(width: 360)
                        }

                        VStack(alignment: .leading, spacing: 18) {
                            featuredDiscoveryColumn
                            secondaryDiscoveryColumn
                        }
                    }

                    HomeSection(title: "Trending Threads") {
                        ForEach(threads.prefix(6)) { thread in
                            NavigationLink(value: AppNavigationDestination.thread(thread)) {
                                ThreadRowCard(thread: thread)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HomeSection(title: "More To Explore") {
                        DiscoverShortcutGrid()
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Discover")
        .task { await loadDiscover() }
    }

    private var featuredDiscoveryColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let resource = resources.first {
                NavigationLink(
                    value: AppNavigationDestination.resource(
                        ResourceNavigationContext(
                            resource: resource,
                            fallbackRelatedResources: resources
                        )
                    )
                ) {
                    DiscoveryFeatureCard(
                        eyebrow: "Featured Resource",
                        title: resource.title,
                        summary: resource.tagLine ?? resource.summary ?? "Explore this highlighted resource.",
                        imageURL: resource.coverURL ?? resource.iconURL,
                        accent: .blue
                    )
                }
                .buttonStyle(.plain)
            }

            if let media = mediaItems.first {
                NavigationLink(value: AppNavigationDestination.media(media)) {
                    DiscoveryFeatureCard(
                        eyebrow: "Media Spotlight",
                        title: media.title,
                        summary: media.mediaURL.host ?? media.mediaURL.absoluteString,
                        imageURL: media.thumbnailURL ?? media.mediaURL,
                        accent: .orange
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var secondaryDiscoveryColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSection(title: "Recent Resources") {
                ForEach(resources.prefix(4)) { resource in
                    NavigationLink(
                        value: AppNavigationDestination.resource(
                            ResourceNavigationContext(
                                resource: resource,
                                fallbackRelatedResources: resources
                            )
                        )
                    ) {
                        SearchResourceRow(resource: resource)
                    }
                    .buttonStyle(.plain)
                }
            }

            HomeSection(title: "Latest Media") {
                ForEach(mediaItems.prefix(4)) { media in
                    NavigationLink(value: AppNavigationDestination.media(media)) {
                        SearchMediaRow(media: media)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadDiscover(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedResources = try await api.fetchResources(accessToken: appState.accessToken)
            let loadedMediaResponse = try await api.listMedia(accessToken: appState.accessToken)
            let loadedThreadsResponse = try await api.listThreads(accessToken: appState.accessToken)

            resources = Array(
                loadedResources
                    .sorted { ($0.updatedDate ?? $0.releaseDate ?? .distantPast) > ($1.updatedDate ?? $1.releaseDate ?? .distantPast) }
                    .prefix(8)
            )
            mediaItems = Array(loadedMediaResponse.items.prefix(8))
            threads = Array(
                loadedThreadsResponse.items
                    .sorted { ($0.postDate ?? .distantPast) > ($1.postDate ?? .distantPast) }
                    .prefix(8)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ForumsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var threads: [XFThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ContentListContainer(
            title: "Forums",
            subtitle: "Latest discussions from the XenForo community.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            retry: { Task { await loadThreads(forceRefresh: true) } }
        ) {
            LazyVStack(spacing: 12) {
                ForEach(threads) { thread in
                    NavigationLink(value: AppNavigationDestination.thread(thread)) {
                        ThreadRowCard(thread: thread)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await loadThreads() }
    }

    private func loadThreads(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.listThreads(accessToken: appState.accessToken)
            threads = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MediaView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mediaItems: [XFMedia] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedKind: XFMediaKind = .unknown
    @State private var selectedSort: MediaGallerySortOption = .newest
    @State private var selectedCategoryFilter: MediaCategoryFilter = .all
    @State private var selectedAlbumFilter: MediaAlbumFilter = .all
    @State private var categoryNames: [Int: String] = [:]
    @State private var albumNames: [Int: String] = [:]
    @State private var serverMediaTotal = 0
    @State private var serverLastPage = 1
    @State private var currentPage = 1
    @State private var showUploadSheet = false
    private let api = XenForoAPI()
    private let mediaPageSize = 12

    private var heroMedia: XFMedia? {
        pagedMedia.first ?? sortedMedia.first
    }

    private var quickPicks: [XFMedia] {
        Array(sortedMedia.dropFirst().prefix(4))
    }

    private var browseColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18, alignment: .top)]
    }

    private var filteredMedia: [XFMedia] {
        mediaItems.filter { media in
            let matchesKind = selectedKind == .unknown || media.kind == selectedKind
            let matchesCategory = selectedCategoryFilter.matches(media)
            let matchesAlbum = selectedAlbumFilter.matches(media)
            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool

            if trimmed.isEmpty {
                matchesSearch = true
            } else {
                let haystacks = [
                    media.title,
                    media.description ?? "",
                    media.username ?? "",
                    media.categoryTitle ?? categoryName(for: media) ?? "",
                    media.albumTitle ?? albumName(for: media) ?? "",
                    media.mediaURL.host ?? media.mediaURL.absoluteString
                ]
                matchesSearch = haystacks.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }

            return matchesKind && matchesCategory && matchesAlbum && matchesSearch
        }
    }

    private var sortedMedia: [XFMedia] {
        filteredMedia.sorted { lhs, rhs in
            switch selectedSort {
            case .newest:
                return mediaSortDate(for: lhs) > mediaSortDate(for: rhs)
            case .oldest:
                return mediaSortDate(for: lhs) < mediaSortDate(for: rhs)
            case .popular:
                return mediaScore(for: lhs) > mediaScore(for: rhs)
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(sortedMedia.count) / Double(mediaPageSize))))
    }

    private var pagedMedia: [XFMedia] {
        let safePage = min(max(currentPage, 1), totalPages)
        let start = (safePage - 1) * mediaPageSize
        let end = min(start + mediaPageSize, sortedMedia.count)
        guard start < end else { return [] }
        return Array(sortedMedia[start..<end])
    }

    private var availableCategoryFilters: [MediaCategoryFilter] {
        let categoryIDs = Set(mediaItems.compactMap { media -> Int? in
            guard let categoryID = media.categoryID, categoryID > 0 else { return nil }
            return categoryID
        })

        return [.all] + categoryIDs.sorted().map { MediaCategoryFilter.category(id: $0) }
    }

    private var availableAlbumFilters: [MediaAlbumFilter] {
        let albumIDs = Set(mediaItems.compactMap { media -> Int? in
            guard let albumID = media.albumID, albumID > 0 else { return nil }
            return albumID
        })

        var filters: [MediaAlbumFilter] = [.all]
        if mediaItems.contains(where: { ($0.albumID ?? 0) == 0 }) {
            filters.append(.standalone)
        }
        filters.append(contentsOf: albumIDs.sorted().map { MediaAlbumFilter.album(id: $0) })
        return filters
    }

    private var pageRangeText: String {
        guard !sortedMedia.isEmpty else { return "No results" }
        let lower = ((currentPage - 1) * mediaPageSize) + 1
        let upper = min(currentPage * mediaPageSize, sortedMedia.count)
        return "Showing \(lower)-\(upper) of \(sortedMedia.count)"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 0.99),
                    Color(red: 0.98, green: 0.98, blue: 0.96),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    mediaHero
                    mediaToolbar
                    mediaFilterTabs
                    categoryDiscoveryPanel
                    albumDiscoveryPanel

                    if let errorMessage, mediaItems.isEmpty {
                        InlineErrorCard(message: errorMessage) {
                            Task { await loadMedia(forceRefresh: true) }
                        }
                    } else if isLoading && mediaItems.isEmpty {
                        ProgressCard(title: "Loading media gallery")
                    } else {
                        if let heroMedia {
                            mediaDiscovery(featured: heroMedia)
                        }

                        MediaSectionShell(
                            title: "Browse All",
                            subtitle: "\(sortedMedia.count.formatted()) items across \(totalPages.formatted()) pages."
                        ) {
                            if sortedMedia.isEmpty {
                                EmptyStateCard(
                                    title: "No media matches",
                                    message: "Try a different tab or clear your search to widen the gallery."
                                )
                            } else {
                                MediaPaginationBar(
                                    currentPage: $currentPage,
                                    totalPages: totalPages,
                                    summary: pageRangeText
                                )

                                LazyVGrid(columns: browseColumns, spacing: 18) {
                                    ForEach(pagedMedia) { media in
                                        NavigationLink(value: AppNavigationDestination.media(media)) {
                                            MediaCard(media: media, style: .standard)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                MediaPaginationBar(
                                    currentPage: $currentPage,
                                    totalPages: totalPages,
                                    summary: pageRangeText
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Media")
        .sheet(isPresented: $showUploadSheet) {
            MediaUploadSheet(
                appState: appState,
                api: api
            ) { uploadedMedia in
                mediaItems.insert(uploadedMedia, at: 0)
            }
        }
        .onChange(of: searchText) { _, _ in currentPage = 1 }
        .onChange(of: selectedSort) { _, _ in currentPage = 1 }
        .task { await loadMedia() }
    }

    private var mediaHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.24, blue: 0.42),
                            Color(red: 0.88, green: 0.48, blue: 0.29),
                            Color(red: 0.95, green: 0.86, blue: 0.66)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 240, height: 240)
                .offset(x: 110, y: -50)

            VStack(alignment: .leading, spacing: 18) {
                Text("Media Gallery")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Browse uploaded images, videos, audio, and embeds with dedicated detail pages, cleaner discovery, and direct uploads from the app.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    MediaMetricPill(title: "Catalog", value: (serverMediaTotal > 0 ? serverMediaTotal : mediaItems.count).formatted())
                    MediaMetricPill(title: "Loaded", value: mediaItems.count.formatted())
                    MediaMetricPill(title: "Filtered", value: sortedMedia.count.formatted())
                    MediaMetricPill(title: "Page", value: "\(currentPage)/\(totalPages)")
                }
            }
            .padding(28)
        }
        .frame(minHeight: 230)
    }

    private var mediaToolbar: some View {
        MediaSectionShell(title: "Discover", subtitle: "Filter faster, refresh the gallery, or push new uploads into XenForo Media Gallery.") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    mediaSearchField
                    mediaSortMenu
                    actionButtons
                }

                VStack(alignment: .leading, spacing: 12) {
                    mediaSearchField
                    HStack(spacing: 12) {
                        mediaSortMenu
                        actionButtons
                    }
                }
            }
        }
    }

    private var mediaSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search media, creators, categories, hosts", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mediaSortMenu: some View {
        Picker("Sort", selection: $selectedSort) {
            ForEach(MediaGallerySortOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 150)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                Task { await loadMedia(forceRefresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                showUploadSheet = true
            } label: {
                Label("Upload Media", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var mediaFilterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(XFMediaKind.allCases.reversed()), id: \.id) { kind in
                    Button {
                        selectedKind = kind
                        currentPage = 1
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: kind.symbolName)
                            Text(kind.title)
                            Text(filterCount(for: kind).formatted())
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(mediaTabBackground(for: kind))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryDiscoveryPanel: some View {
        MediaSectionShell(title: "Categories", subtitle: "Website-style category discovery based on the media gallery records currently available from XenForo.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableCategoryFilters, id: \.id) { filter in
                        Button {
                            selectedCategoryFilter = filter
                            currentPage = 1
                        } label: {
                            MediaFilterChip(
                                title: title(for: filter),
                                count: categoryCount(for: filter),
                                isSelected: selectedCategoryFilter == filter
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var albumDiscoveryPanel: some View {
        MediaSectionShell(title: "Albums", subtitle: "Browse standalone uploads separately from media grouped into albums.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableAlbumFilters, id: \.id) { filter in
                        Button {
                            selectedAlbumFilter = filter
                            currentPage = 1
                        } label: {
                            MediaFilterChip(
                                title: title(for: filter),
                                count: albumCount(for: filter),
                                isSelected: selectedAlbumFilter == filter
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaTabBackground(for kind: XFMediaKind) -> some View {
        if kind == selectedKind {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.89, green: 0.94, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private func mediaDiscovery(featured: XFMedia) -> some View {
        MediaSectionShell(title: "Spotlight", subtitle: "Start with a featured pick, then move into the latest uploads.") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    NavigationLink(value: AppNavigationDestination.media(featured)) {
                        MediaFeatureCard(media: featured)
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 12) {
                        ForEach(quickPicks) { media in
                            NavigationLink(value: AppNavigationDestination.media(media)) {
                                SearchMediaRow(media: media)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 360)
                }

                VStack(alignment: .leading, spacing: 18) {
                    NavigationLink(value: AppNavigationDestination.media(featured)) {
                        MediaFeatureCard(media: featured)
                    }
                    .buttonStyle(.plain)

                    ForEach(quickPicks) { media in
                        NavigationLink(value: AppNavigationDestination.media(media)) {
                            SearchMediaRow(media: media)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadMedia(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await loadAllMedia()
            mediaItems = deduplicatedMedia(from: response)
            applyResolvedNames(from: mediaItems)
            await resolveFilterTitlesIfNeeded()
            if !availableCategoryFilters.contains(selectedCategoryFilter) {
                selectedCategoryFilter = .all
            }
            if !availableAlbumFilters.contains(selectedAlbumFilter) {
                selectedAlbumFilter = .all
            }
            currentPage = min(currentPage, totalPages)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAllMedia() async throws -> [XFMedia] {
        let firstPage = try await api.fetchMediaGalleryPage(accessToken: appState.accessToken)
        var items = firstPage.items
        serverMediaTotal = firstPage.pagination?.total ?? firstPage.items.count
        serverLastPage = firstPage.pagination?.lastPage ?? 1
        var currentPage = 2

        while currentPage <= serverLastPage {
            do {
                let page = try await api.fetchMediaGalleryPage(page: currentPage, accessToken: appState.accessToken)
                let newItems = page.items.filter { candidate in
                    !items.contains(where: { $0.id == candidate.id })
                }
                if newItems.isEmpty {
                    break
                }
                items.append(contentsOf: newItems)
                currentPage += 1
            } catch {
                break
            }
        }

        return items
    }

    private func deduplicatedMedia(from items: [XFMedia]) -> [XFMedia] {
        var seen = Set<Int>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func mediaSortDate(for media: XFMedia) -> Date {
        media.updatedDate ?? media.postedDate ?? .distantPast
    }

    private func mediaScore(for media: XFMedia) -> Int {
        (media.viewCount ?? 0) + (media.commentCount ?? 0) * 4 + (media.reactionScore ?? 0) * 3
    }

    private func filterCount(for kind: XFMediaKind) -> Int {
        guard kind != .unknown else { return mediaItems.count }
        return mediaItems.filter { $0.kind == kind }.count
    }

    private func categoryCount(for filter: MediaCategoryFilter) -> Int {
        mediaItems.filter { filter.matches($0) }.count
    }

    private func albumCount(for filter: MediaAlbumFilter) -> Int {
        mediaItems.filter { filter.matches($0) }.count
    }

    private func title(for filter: MediaCategoryFilter) -> String {
        switch filter {
        case .all:
            return "All Categories"
        case .category(let id):
            return categoryNames[id] ?? "Category #\(id)"
        }
    }

    private func title(for filter: MediaAlbumFilter) -> String {
        switch filter {
        case .all:
            return "All Albums"
        case .standalone:
            return "Standalone"
        case .album(let id):
            return albumNames[id] ?? "Album #\(id)"
        }
    }

    private func categoryName(for media: XFMedia) -> String? {
        if let title = media.categoryTitle, !title.isEmpty {
            return title
        }
        guard let id = media.categoryID else { return nil }
        return categoryNames[id]
    }

    private func albumName(for media: XFMedia) -> String? {
        if let title = media.albumTitle, !title.isEmpty {
            return title
        }
        guard let id = media.albumID else { return nil }
        return albumNames[id]
    }

    private func applyResolvedNames(from items: [XFMedia]) {
        for media in items {
            if let categoryID = media.categoryID, let categoryTitle = media.categoryTitle, !categoryTitle.isEmpty {
                categoryNames[categoryID] = categoryTitle
            }
            if let albumID = media.albumID, albumID > 0, let albumTitle = media.albumTitle, !albumTitle.isEmpty {
                albumNames[albumID] = albumTitle
            }
        }
    }

    private func resolveFilterTitlesIfNeeded() async {
        let unresolvedCategorySamples = Dictionary(
            grouping: mediaItems.filter { ($0.categoryID ?? 0) > 0 && categoryNames[$0.categoryID ?? 0] == nil },
            by: { $0.categoryID ?? 0 }
        ).compactMapValues(\.first)

        let unresolvedAlbumSamples = Dictionary(
            grouping: mediaItems.filter { ($0.albumID ?? 0) > 0 && albumNames[$0.albumID ?? 0] == nil },
            by: { $0.albumID ?? 0 }
        ).compactMapValues(\.first)

        guard !unresolvedCategorySamples.isEmpty || !unresolvedAlbumSamples.isEmpty else { return }

        await withTaskGroup(of: XFMedia?.self) { group in
            for media in Set(unresolvedCategorySamples.values).union(Set(unresolvedAlbumSamples.values)) {
                group.addTask {
                    try? await api.getMedia(id: media.id, accessToken: appState.accessToken)
                }
            }

            for await resolved in group {
                guard let resolved else { continue }
                if let categoryID = resolved.categoryID, let categoryTitle = resolved.categoryTitle, !categoryTitle.isEmpty {
                    categoryNames[categoryID] = categoryTitle
                }
                if let albumID = resolved.albumID, albumID > 0, let albumTitle = resolved.albumTitle, !albumTitle.isEmpty {
                    albumNames[albumID] = albumTitle
                }
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    let query: String

    @State private var results: SearchResults?
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ContentListContainer(
            title: "Search",
            subtitle: query.isEmpty ? "Enter a query in the toolbar to search resources, media, and threads." : "Results for \"\(query)\".",
            isLoading: isLoading,
            errorMessage: errorMessage,
            retry: { Task { await loadResults(forceRefresh: true) } }
        ) {
            if let results {
                VStack(alignment: .leading, spacing: 20) {
                    if !results.resources.isEmpty {
                        SearchSection(title: "Resources") {
                            ForEach(results.resources) { resource in
                                NavigationLink(
                                    value: AppNavigationDestination.resource(
                                        ResourceNavigationContext(
                                            resource: resource,
                                            fallbackRelatedResources: results.resources
                                        )
                                    )
                                ) {
                                    SearchResourceRow(resource: resource)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !results.media.isEmpty {
                        SearchSection(title: "Media") {
                            ForEach(results.media) { media in
                                NavigationLink(value: AppNavigationDestination.media(media)) {
                                    SearchMediaRow(media: media)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !results.threads.isEmpty {
                        SearchSection(title: "Threads") {
                            ForEach(results.threads) { thread in
                                NavigationLink(value: AppNavigationDestination.thread(thread)) {
                                    ThreadRowCard(thread: thread)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if results.resources.isEmpty && results.media.isEmpty && results.threads.isEmpty {
                        EmptyStateCard(
                            title: "No results",
                            message: "Try a broader query or different keywords."
                        )
                    }
                }
            } else if !query.isEmpty {
                EmptyStateCard(
                    title: "No results loaded",
                    message: "Run the search again to refresh the results."
                )
            } else {
                EmptyStateCard(
                    title: "Search the community",
                    message: "Use the toolbar search field to load resources, media, and threads."
                )
            }
        }
        .task(id: query) { await loadResults() }
    }

    private func loadResults(forceRefresh: Bool = false) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = nil
            errorMessage = nil
            return
        }
        guard !isLoading || forceRefresh else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            results = try await api.search(query: trimmedQuery, accessToken: appState.accessToken)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var user: XFUser?
    @State private var resources: [XFResource] = []
    @State private var threads: [XFThread] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if appState.isAuthenticated {
                    profileHeader

                    if let errorMessage {
                        InlineErrorCard(message: errorMessage) {
                            Task { await loadProfile(forceRefresh: true) }
                        }
                    } else if isLoading && user == nil {
                        ProgressCard(title: "Loading profile")
                    } else {
                        HomeSection(title: "Recent Resources") {
                            ForEach(resources.prefix(4)) { resource in
                                NavigationLink(
                                    value: AppNavigationDestination.resource(
                                        ResourceNavigationContext(
                                            resource: resource,
                                            fallbackRelatedResources: resources
                                        )
                                    )
                                ) {
                                    SearchResourceRow(resource: resource)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HomeSection(title: "Recent Threads") {
                            ForEach(threads.prefix(4)) { thread in
                                NavigationLink(value: AppNavigationDestination.thread(thread)) {
                                    ThreadRowCard(thread: thread)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    ContentHeaderCard(
                        title: "My Profile",
                        subtitle: "Sign in to view your account details and recent community activity."
                    ) {
                        Button("Sign In") {
                            Task { await appState.beginSignInFlow() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("My Profile")
        .task(id: appState.isAuthenticated) {
            if appState.isAuthenticated {
                await loadProfile()
            }
        }
    }

    private var profileHeader: some View {
        ContentHeaderCard(
            title: appState.settings.displayName.isEmpty ? (user?.username ?? "My Profile") : appState.settings.displayName,
            subtitle: user?.username ?? "Signed in"
        ) {
            HStack(spacing: 16) {
                if let avatarURL = user?.avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        default:
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "person.crop.circle.fill"))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    StatBadge(label: "Resources", value: resources.count.formatted())
                    StatBadge(label: "Threads", value: threads.count.formatted())
                }

                Button("Sign Out") {
                    Task { await appState.signOut() }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func loadProfile(forceRefresh: Bool = false) async {
        guard appState.isAuthenticated else { return }
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            user = try await api.me(accessToken: appState.accessToken)
            resources = Array((try await api.fetchResources(accessToken: appState.accessToken)).prefix(6))
            let loadedThreadsResponse = try await api.listThreads(accessToken: appState.accessToken)
            threads = Array(loadedThreadsResponse.items.prefix(6))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ThreadDetailView: View {
    @EnvironmentObject private var appState: AppState
    let thread: XFThread

    @State private var posts: [XFPost] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let api = XenForoAPI()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ContentHeaderCard(
                    title: thread.title,
                    subtitle: "Started by \(thread.author)"
                ) {
                    HStack(spacing: 12) {
                        StatBadge(label: "Replies", value: thread.replyCount.formatted())
                        StatBadge(label: "Views", value: thread.viewCount.formatted())
                        if let date = thread.postDate {
                            StatBadge(label: "Posted", value: date.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                if let errorMessage {
                    InlineErrorCard(message: errorMessage) {
                        Task { await loadPosts(forceRefresh: true) }
                    }
                } else if isLoading && posts.isEmpty {
                    ProgressCard(title: "Loading thread")
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(posts) { post in
                            PostCard(post: post)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Thread")
        .task { await loadPosts() }
    }

    private func loadPosts(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.listPosts(threadID: thread.id, accessToken: appState.accessToken)
            posts = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    let media: XFMedia
    private let api = XenForoAPI()

    @State private var mediaItem: XFMedia
    @State private var playbackURL: URL?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(media: XFMedia) {
        self.media = media
        _mediaItem = State(initialValue: media)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.99, green: 0.98, blue: 0.95),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    MediaDetailHero(media: mediaItem, playbackURL: playbackURL)
                    MediaPreviewPanel(media: mediaItem, playbackURL: playbackURL)

                    if let errorMessage {
                        InlineErrorCard(message: errorMessage) {
                            Task { await loadMediaDetail(forceRefresh: true) }
                        }
                    } else if isLoading && playbackURL == nil {
                        ProgressCard(title: "Resolving media playback")
                    }

                    MediaSectionShell(title: "Overview", subtitle: "Metadata, publishing info, and gallery context.") {
                        VStack(alignment: .leading, spacing: 16) {
                            if let description = mediaItem.description, !description.isEmpty {
                                Text(description)
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)], spacing: 12) {
                                MediaInfoTile(title: "Type", value: mediaItem.kind.title)
                                MediaInfoTile(title: "Uploader", value: mediaItem.username ?? "Unknown")
                                MediaInfoTile(title: "Category", value: mediaItem.categoryTitle ?? "Media Gallery")
                                MediaInfoTile(title: "Published", value: mediaDateText(mediaItem.postedDate))
                                MediaInfoTile(title: "Updated", value: mediaDateText(mediaItem.updatedDate))
                                MediaInfoTile(title: "Host", value: mediaItem.mediaURL.host ?? "Direct File")
                            }
                        }
                    }

                    MediaSectionShell(title: "Actions", subtitle: "Open the original asset, jump to playback, or inspect the thumbnail source.") {
                        VStack(alignment: .leading, spacing: 12) {
                            Link(destination: mediaItem.viewURL ?? mediaItem.mediaURL) {
                                Label("Open In Browser", systemImage: "safari")
                            }
                            .buttonStyle(.borderedProminent)

                            if let playbackURL {
                                Link(destination: playbackURL) {
                                    Label("Open Playback URL", systemImage: "play.rectangle")
                                }
                                .buttonStyle(.bordered)
                            }

                            Link(destination: mediaItem.mediaURL) {
                                Label("Original Media URL", systemImage: "link")
                            }
                            .buttonStyle(.bordered)

                            if let thumbnailURL = mediaItem.thumbnailURL {
                                Link(destination: thumbnailURL) {
                                    Label("Thumbnail URL", systemImage: "photo")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .navigationTitle("Media")
        .task { await loadMediaDetail() }
    }

    private func loadMediaDetail(forceRefresh: Bool = false) async {
        guard !isLoading || forceRefresh else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let fetchedMedia = api.getMedia(id: media.id, accessToken: appState.accessToken)
            async let resolvedPlayback = api.mediaPlaybackURL(id: media.id, accessToken: appState.accessToken)
            mediaItem = try await fetchedMedia
            playbackURL = try await resolvedPlayback
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mediaDateText(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct PlaceholderView: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2)
                .bold()
            Text("Powered by XenForo API at cities-mods.com")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct ContentListContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let isLoading: Bool
    let errorMessage: String?
    let retry: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ContentHeaderCard(title: title, subtitle: subtitle) {
                    EmptyView()
                }

                if let errorMessage {
                    InlineErrorCard(message: errorMessage, retry: retry)
                } else if isLoading {
                    ProgressCard(title: "Loading \(title)")
                } else {
                    content
                }
            }
            .padding(24)
        }
        .navigationTitle(title)
    }
}

private struct HomeSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(spacing: 12) {
                content
            }
        }
    }
}

private struct ContentHeaderCard<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .bold))

            Text(subtitle)
                .foregroundStyle(.secondary)

            accessory
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct ThreadRowCard: View {
    let thread: XFThread

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "text.bubble").foregroundStyle(Color.accentColor))

            VStack(alignment: .leading, spacing: 8) {
                Text(thread.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("by \(thread.author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(thread.replyCount.formatted(), systemImage: "arrowshape.turn.up.left")
                    Label(thread.viewCount.formatted(), systemImage: "eye")
                    if let postDate = thread.postDate {
                        Label(postDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MediaCard: View {
    let media: XFMedia
    var style: MediaCardStyle = .compact

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaArtwork(media: media, height: style == .featured ? 240 : 180)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: media.kind.symbolName)
                            .foregroundStyle(Color.accentColor)
                        Text(media.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(media.title)
                        .font(style == .featured ? .title3.weight(.semibold) : .headline)
                        .foregroundStyle(.primary)
                        .lineLimit(style == .featured ? 3 : 2)

                    Text(media.description ?? media.mediaURL.host ?? media.mediaURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(style == .featured ? 3 : 2)
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 12) {
                if let username = media.username, !username.isEmpty {
                    Label(username, systemImage: "person")
                }
                if let postedDate = media.postedDate {
                    Label(postedDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if let viewCount = media.viewCount {
                    Label(viewCount.formatted(), systemImage: "eye")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 20, y: 10)
    }
}

private struct PostCard: View {
    let post: XFPost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(post.username)
                    .font(.headline)
                Spacer()
                Text(Date(timeIntervalSince1970: TimeInterval(post.post_date)).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(BBCodeParser.attributedString(from: post.message_parsed ?? post.message, attachmentLookup: post.attachmentURLs))
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SearchSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
            VStack(spacing: 12) {
                content
            }
        }
    }
}

private struct SearchResourceRow: View {
    let resource: XFResource

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: resource.iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                default:
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 72, height: 46)
                        .overlay(Image(systemName: "shippingbox"))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(resource.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let category = resource.category {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SearchMediaRow: View {
    let media: XFMedia

    var body: some View {
        HStack(spacing: 12) {
            MediaArtwork(media: media, height: 58)
                .frame(width: 88)

            VStack(alignment: .leading, spacing: 6) {
                Text(media.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(media.description ?? media.mediaURL.host ?? media.mediaURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(media.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let postedDate = media.postedDate {
                    Text(postedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private enum MediaCardStyle: Equatable {
    case compact
    case standard
    case featured
}

private enum MediaGallerySortOption: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case popular
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .popular: return "Popular"
        case .title: return "Title"
        }
    }
}

private enum MediaUploadMode: String, CaseIterable, Identifiable {
    case file
    case embed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .file: return "File Upload"
        case .embed: return "Embed URL"
        }
    }
}

private enum MediaCategoryFilter: Hashable, Identifiable {
    case all
    case category(id: Int)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .category(let id):
            return "category-\(id)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All Categories"
        case .category(let id):
            return "Category #\(id)"
        }
    }

    func matches(_ media: XFMedia) -> Bool {
        switch self {
        case .all:
            return true
        case .category(let id):
            return media.categoryID == id
        }
    }
}

private enum MediaAlbumFilter: Hashable, Identifiable {
    case all
    case standalone
    case album(id: Int)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .standalone:
            return "standalone"
        case .album(let id):
            return "album-\(id)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All Albums"
        case .standalone:
            return "Standalone"
        case .album(let id):
            return "Album #\(id)"
        }
    }

    func matches(_ media: XFMedia) -> Bool {
        switch self {
        case .all:
            return true
        case .standalone:
            return (media.albumID ?? 0) == 0
        case .album(let id):
            return media.albumID == id
        }
    }
}

private struct MediaSectionShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MediaFilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
            Text(count.formatted())
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(background)
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.89, green: 0.94, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

private struct MediaPaginationBar: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let summary: String

    private var visiblePages: [Int] {
        if totalPages <= 7 {
            return Array(1...totalPages)
        }

        let lower = max(1, currentPage - 2)
        let upper = min(totalPages, currentPage + 2)
        var pages = Set([1, totalPages])
        for page in lower...upper {
            pages.insert(page)
        }
        return pages.sorted()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                controls
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                controls
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                currentPage = max(1, currentPage - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 1)

            ForEach(visiblePages, id: \.self) { page in
                Button {
                    currentPage = page
                } label: {
                    Text(page.formatted())
                        .frame(minWidth: 30)
                }
                .buttonStyle(.borderedProminent)
                .tint(page == currentPage ? .accentColor : .gray.opacity(0.35))
            }

            Button {
                currentPage = min(totalPages, currentPage + 1)
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == totalPages)
        }
    }
}

private struct MediaMetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MediaFeatureCard: View {
    let media: XFMedia

    var body: some View {
        MediaCard(media: media, style: .featured)
    }
}

private struct MediaArtwork: View {
    let media: XFMedia
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: media.thumbnailURL ?? media.mediaURL) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }

            Label(media.kind.title, systemImage: media.kind.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.58), in: Capsule())
                .foregroundStyle(.white)
                .padding(12)
        }
        .frame(height: height)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.16),
                        Color.orange.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(height: height)
            .overlay(
                Image(systemName: media.kind.symbolName)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            )
    }
}

private struct MediaDetailHero: View {
    let media: XFMedia
    let playbackURL: URL?

    var body: some View {
        MediaSectionShell(title: media.title, subtitle: "Media item #\(media.id)") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(media.description ?? "Open this media item in a dedicated view with playback, metadata, and source links.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        MediaMiniStat(label: "Type", value: media.kind.title)
                        MediaMiniStat(label: "Views", value: (media.viewCount ?? 0).formatted())
                        MediaMiniStat(label: "Comments", value: (media.commentCount ?? 0).formatted())
                    }
                }

                Spacer(minLength: 18)

                VStack(alignment: .trailing, spacing: 10) {
                    if let playbackURL {
                        Link(destination: playbackURL) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Link(destination: media.viewURL ?? media.mediaURL) {
                        Label("Open", systemImage: "arrow.up.forward")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

private struct MediaMiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MediaInfoTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MediaPreviewPanel: View {
    let media: XFMedia
    let playbackURL: URL?
    @State private var player: AVPlayer?

    var body: some View {
        MediaSectionShell(title: "Preview", subtitle: "Inline playback when available, with a safe fallback for remote embeds.") {
            Group {
                switch media.kind {
                case .image:
                    imagePreview
                case .video, .audio:
                    playbackPreview
                case .embed, .unknown:
                    embedPreview
                }
            }
        }
        .onAppear {
            if case .video = media.kind {
                player = AVPlayer(url: playbackURL ?? media.mediaURL)
            } else if case .audio = media.kind {
                player = AVPlayer(url: playbackURL ?? media.mediaURL)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var imagePreview: some View {
        AsyncImage(url: media.thumbnailURL ?? media.mediaURL) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 360)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 280)
                    .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            case .failure:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 360)
                    .overlay(Image(systemName: "photo"))
            @unknown default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var playbackPreview: some View {
        if let player {
            VideoPlayer(player: player)
                .frame(minHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
                .frame(height: 320)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: media.kind.symbolName)
                            .font(.system(size: 28))
                        Text("Playback will appear when the media URL resolves.")
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }

    private var embedPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.12), Color.orange.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 260)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.system(size: 28))
                        Text(media.mediaURL.host ?? "Remote media")
                            .font(.headline)
                        Text("This item opens in the browser or its dedicated playback URL.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                )

            Link(destination: media.viewURL ?? playbackURL ?? media.mediaURL) {
                Label("Open Remote Media", systemImage: "arrow.up.forward.square")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct MediaUploadSheet: View {
    let appState: AppState
    let api: XenForoAPI
    let onUploaded: (XFMedia) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: MediaUploadMode = .file
    @State private var title = ""
    @State private var description = ""
    @State private var categoryIDText = "1"
    @State private var embedURLText = ""
    @State private var selectedFileURL: URL?
    @State private var selectedMimeType = "application/octet-stream"
    @State private var isPickingFile = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    private let allowedTypes: [UTType] = [.image, .movie, .audio]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Upload Media")
                .font(.title2.weight(.bold))

            Picker("Mode", selection: $mode) {
                ForEach(MediaUploadMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Title", text: $title)
            TextField("Category ID", text: $categoryIDText)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            if mode == .file {
                VStack(alignment: .leading, spacing: 10) {
                    if let selectedFileURL {
                        Text(selectedFileURL.lastPathComponent)
                            .font(.subheadline)
                    } else {
                        Text("Allowed media types: images, videos, and audio files.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button("Choose File") {
                        isPickingFile = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                TextField("Embed URL", text: $embedURLText)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    Task { await upload() }
                } label: {
                    if isUploading {
                        ProgressView()
                    } else {
                        Text("Upload")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUploading || !canUpload)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fileImporter(isPresented: $isPickingFile, allowedContentTypes: allowedTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                selectedFileURL = url
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    title = url.deletingPathExtension().lastPathComponent
                }
                selectedMimeType = mimeType(for: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var canUpload: Bool {
        guard Int(categoryIDText) != nil else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        switch mode {
        case .file:
            return selectedFileURL != nil
        case .embed:
            return URL(string: embedURLText) != nil
        }
    }

    private func upload() async {
        guard let categoryID = Int(categoryIDText) else {
            errorMessage = "Enter a valid category ID."
            return
        }

        isUploading = true
        errorMessage = nil
        defer { isUploading = false }

        do {
            let uploadedMedia: XFMedia

            switch mode {
            case .file:
                guard let selectedFileURL else {
                    errorMessage = "Choose a file first."
                    return
                }
                let accessGranted = selectedFileURL.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        selectedFileURL.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try Data(contentsOf: selectedFileURL)
                uploadedMedia = try await api.uploadMediaFile(
                    categoryID: categoryID,
                    title: title,
                    fileData: data,
                    filename: selectedFileURL.lastPathComponent,
                    mimeType: selectedMimeType,
                    description: description.isEmpty ? nil : description,
                    accessToken: appState.accessToken
                )
            case .embed:
                guard let embedURL = URL(string: embedURLText) else {
                    errorMessage = "Enter a valid embed URL."
                    return
                }
                uploadedMedia = try await api.uploadMedia(
                    categoryID: categoryID,
                    title: title,
                    mediaURL: embedURL,
                    description: description.isEmpty ? nil : description,
                    accessToken: appState.accessToken
                )
            }

            onUploaded(uploadedMedia)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mimeType(for url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension),
              let mimeType = type.preferredMIMEType else {
            return "application/octet-stream"
        }
        return mimeType
    }
}

private struct DiscoveryFeatureCard: View {
    let eyebrow: String
    let title: String
    let summary: String
    let imageURL: URL?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(height: 210)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                case .failure:
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(height: 210)
                        .overlay(Image(systemName: "sparkles"))
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DiscoverShortcutGrid: View {
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            DiscoverShortcutCard(
                icon: "shippingbox.fill",
                title: "Resource Catalog",
                message: "Browse recently updated downloads and featured releases."
            )
            DiscoverShortcutCard(
                icon: "photo.on.rectangle.angled",
                title: "Media Gallery",
                message: "Open uploaded media and playback links in one place."
            )
            DiscoverShortcutCard(
                icon: "text.bubble.fill",
                title: "Community Threads",
                message: "Follow active discussions and jump into thread details."
            )
            DiscoverShortcutCard(
                icon: "magnifyingglass.circle.fill",
                title: "Global Search",
                message: "Search resources, media, and threads from the toolbar."
            )
        }
    }
}

private struct DiscoverShortcutCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct InlineErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Couldn’t load content")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ProgressCard: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
