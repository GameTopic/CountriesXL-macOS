import AVKit
import SwiftUI
import WebKit

struct ResourcesView: View {
    let appState: AppState
    @State private var resources: [XFResource] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var searchText = ""
    @State private var selectedCategory = ResourceCategoryFilter.all
    @State private var selectedSort = ResourceSortOption.featured
    @State private var selectedRating = ResourceRatingFilter.any
    @State private var selectedPage = 1

    private let api = XenForoAPI()
    private let browsePageSize = 12

    private var availableCategories: [ResourceCategoryFilter] {
        let categories = Set(resources.compactMap { resource in
            let trimmed = resource.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        })

        return [.all] + categories
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(ResourceCategoryFilter.named)
    }

    private var filteredResources: [XFResource] {
        resources.filter { resource in
            selectedCategory.matches(resource) &&
            selectedRating.matches(resource) &&
            matchesSearch(resource)
        }
    }

    private var featuredResources: [XFResource] {
        Array(
            resources
                .sorted { featureScore(for: $0) > featureScore(for: $1) }
                .prefix(5)
        )
    }

    private var latestResources: [XFResource] {
        Array(
            resources
                .sorted { mostRecentDate(for: $0) > mostRecentDate(for: $1) }
                .prefix(4)
        )
    }

    private var sortedResources: [XFResource] {
        filteredResources.sorted { lhs, rhs in
            switch selectedSort {
            case .featured:
                return featureScore(for: lhs) > featureScore(for: rhs)
            case .latest:
                return mostRecentDate(for: lhs) > mostRecentDate(for: rhs)
            case .popular:
                return popularityScore(for: lhs) > popularityScore(for: rhs)
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(sortedResources.count) / Double(browsePageSize))))
    }

    private var pagedResources: [XFResource] {
        let startIndex = max(0, min((selectedPage - 1) * browsePageSize, sortedResources.count))
        let endIndex = min(startIndex + browsePageSize, sortedResources.count)
        guard startIndex < endIndex else { return [] }
        return Array(sortedResources[startIndex ..< endIndex])
    }

    private var browseColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 330, maximum: 420), spacing: 18, alignment: .top)]
    }

    private var categoryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12, alignment: .leading)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    resourceTopShell

                    if let loadError, resources.isEmpty {
                        ResourceLoadErrorView(message: loadError) {
                            Task { await loadResources() }
                        }
                    } else if isLoading && resources.isEmpty {
                        ResourceLoadingStateView()
                    } else {
                        resourceDiscoverySection
                        allResourcesSection
                    }
                }
                .padding(24)
            }
        }
        .environmentObject(appState)
        .navigationTitle("Resources")
        .task { await loadResources() }
        .onChange(of: searchText) { _, _ in selectedPage = 1 }
        .onChange(of: selectedCategory) { _, _ in selectedPage = 1 }
        .onChange(of: selectedSort) { _, _ in selectedPage = 1 }
        .onChange(of: selectedRating) { _, _ in selectedPage = 1 }
    }

    private var resourceTopShell: some View {
        ResourceSurface {
            VStack(alignment: .leading, spacing: 20) {
                ResourceHeroHeader(
                    resourceCount: resources.count,
                    categoryCount: max(availableCategories.count - 1, 0),
                    selectedCategoryTitle: selectedCategory.title
                )

                resourceCommandBar
                resourceCategoryPanel
            }
        }
    }

    @ViewBuilder
    private var resourceDiscoverySection: some View {
        if !featuredResources.isEmpty || !latestResources.isEmpty {
            ResourceSection(title: "Discover", subtitle: "Featured picks on the left, fresh uploads on the right.") {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        if let featured = featuredResources.first {
                            ResourceFeaturedMarqueeCard(
                                appState: appState,
                                resource: featured,
                                allResources: resources
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !latestResources.isEmpty {
                            ResourceLatestColumn(
                                appState: appState,
                                resources: latestResources,
                                allResources: resources
                            )
                            .frame(width: 360)
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        if let featured = featuredResources.first {
                            ResourceFeaturedMarqueeCard(
                                appState: appState,
                                resource: featured,
                                allResources: resources
                            )
                        }

                        if !latestResources.isEmpty {
                            ResourceLatestColumn(
                                appState: appState,
                                resources: latestResources,
                                allResources: resources
                            )
                        }
                    }
                }
            }
        }
    }

    private var allResourcesSection: some View {
        ResourceSection(title: "All Resources", subtitle: browseSubtitle) {
            if sortedResources.isEmpty {
                ResourceEmptyStateView()
            } else {
                ResourcePaginationBar(
                    currentPage: $selectedPage,
                    totalPages: totalPages,
                    itemRangeText: itemRangeText
                )

                LazyVGrid(columns: browseColumns, spacing: 18) {
                    ForEach(pagedResources) { resource in
                        ResourceBrowseCard(appState: appState, resource: resource, allResources: resources)
                    }
                }

                ResourcePaginationBar(
                    currentPage: $selectedPage,
                    totalPages: totalPages,
                    itemRangeText: itemRangeText
                )
            }
        }
    }

    private var resourceCommandBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                searchField
                filtersRow
            }

            VStack(alignment: .leading, spacing: 12) {
                searchField
                filtersRow
            }
        }
    }

    private var resourceCategoryPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ResourceSectionHeader(
                title: "Categories",
                subtitle: "Use categories to narrow the catalog before browsing all resources."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(availableCategories) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 8) {
                                Text(category.title)
                                    .lineLimit(1)
                                Text(categoryCount(for: category).formatted())
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(categoryChipBackground(for: category))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search resources, authors, categories", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.07), lineWidth: 1)
        )
    }

    private var filtersRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Picker("Sort", selection: $selectedSort) {
                ForEach(ResourceSortOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Picker("Rating", selection: $selectedRating) {
                ForEach(ResourceRatingFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)

            Button {
                Task { await loadResources(forceRefresh: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var browseSubtitle: String {
        "\(sortedResources.count.formatted()) resources across \(totalPages.formatted()) page\(totalPages == 1 ? "" : "s")."
    }

    private var itemRangeText: String {
        guard !sortedResources.isEmpty else { return "No results" }
        let lower = ((selectedPage - 1) * browsePageSize) + 1
        let upper = min(selectedPage * browsePageSize, sortedResources.count)
        return "Showing \(lower)-\(upper) of \(sortedResources.count)"
    }

    private func loadResources(forceRefresh: Bool = false) async {
        guard (NetworkMonitor.shared.isConnected ?? true) && BoardStatusService.shared.isActive else { return }
        guard !isLoading || forceRefresh else { return }

        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let items = try await loadAllResources()
            resources = deduplicatedResources(from: items)
            selectedPage = min(selectedPage, totalPages)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadAllResources() async throws -> [XFResource] {
        if let compatibleItems = try? await api.fetchResources(accessToken: appState.accessToken), !compatibleItems.isEmpty {
            return compatibleItems
        }

        let firstPage = try await api.listResources(page: 1, accessToken: appState.accessToken)
        var allItems = firstPage.items
        var page = 2
        let maxPages = 100

        while page <= maxPages {
            do {
                let pageResult = try await api.listResources(page: page, accessToken: appState.accessToken)
                let newItems = pageResult.items.filter { candidate in
                    !allItems.contains(where: { $0.id == candidate.id })
                }

                if newItems.isEmpty {
                    break
                }

                allItems.append(contentsOf: newItems)
                page += 1
            } catch XenForoAPI.APIError.badRequest {
                break
            } catch {
                throw error
            }
        }

        return allItems
    }

    private func deduplicatedResources(from items: [XFResource]) -> [XFResource] {
        var seen = Set<Int>()
        return items.filter { resource in
            seen.insert(resource.id).inserted
        }
    }

    private func matchesSearch(_ resource: XFResource) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let haystacks = [
            resource.title,
            resource.category ?? "",
            resource.tagLine ?? "",
            resource.summary ?? "",
            resource.authorName ?? ""
        ]

        return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private func mostRecentDate(for resource: XFResource) -> Date {
        resource.updatedDate ?? resource.releaseDate ?? .distantPast
    }

    private func popularityScore(for resource: XFResource) -> Int {
        (resource.downloadCount ?? 0) * 3 + (resource.viewCount ?? 0)
    }

    private func featureScore(for resource: XFResource) -> Double {
        let popularity = Double(popularityScore(for: resource))
        let rating = (resource.rating ?? 0) * 125
        let ratingCount = Double(resource.ratingCount ?? 0) * 12
        return popularity + rating + ratingCount
    }

    private func categoryCount(for category: ResourceCategoryFilter) -> Int {
        resources.filter { category.matches($0) }.count
    }

    @ViewBuilder
    private func categoryChipBackground(for category: ResourceCategoryFilter) -> some View {
        if category == selectedCategory {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.90, green: 0.95, blue: 1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

private enum ResourceSortOption: String, CaseIterable, Identifiable {
    case featured
    case latest
    case popular
    case title

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: return "Featured"
        case .latest: return "Latest"
        case .popular: return "Popular"
        case .title: return "A-Z"
        }
    }
}

private enum ResourceRatingFilter: String, CaseIterable, Identifiable {
    case any
    case fourPlus
    case threePlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Rating"
        case .fourPlus: return "4.0+"
        case .threePlus: return "3.0+"
        }
    }

    func matches(_ resource: XFResource) -> Bool {
        switch self {
        case .any:
            return true
        case .fourPlus:
            return (resource.rating ?? 0) >= 4
        case .threePlus:
            return (resource.rating ?? 0) >= 3
        }
    }
}

private enum ResourceCategoryFilter: Hashable, Identifiable {
    case all
    case named(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .named(let value): return value
        }
    }

    var title: String {
        switch self {
        case .all: return "All Resources"
        case .named(let value): return value
        }
    }

    func matches(_ resource: XFResource) -> Bool {
        switch self {
        case .all:
            return true
        case .named(let value):
            return resource.category == value
        }
    }
}

private struct ResourceSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct ResourceHeroHeader: View {
    let resourceCount: Int
    let categoryCount: Int
    let selectedCategoryTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resources")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("A focused browse experience with clearer discovery, cleaner cards, and less visual noise.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ResourceSummaryPill(title: "Catalog", value: resourceCount.formatted())
                ResourceSummaryPill(title: "Categories", value: categoryCount.formatted())
                ResourceSummaryPill(title: "Current Filter", value: selectedCategoryTitle)
            }
        }
    }
}

private struct ResourceSummaryPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ResourceSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ResourceSurface {
            VStack(alignment: .leading, spacing: 16) {
                ResourceSectionHeader(title: title, subtitle: subtitle)
                content
            }
        }
    }
}

private struct ResourceSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ResourceLoadingStateView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Loading the full resources catalog…")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 72)
            Spacer()
        }
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ResourceLoadErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Couldn’t load resources")
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ResourceFeaturedMarqueeCard: View {
    let appState: AppState
    let resource: XFResource
    let allResources: [XFResource]

    var body: some View {
        NavigationLink(
            destination: ResourceDetailView(appState: appState, resource: resource, fallbackRelatedResources: allResources)
                .environmentObject(appState)
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ResourceArtworkView(resource: resource, fillsWidth: true)

                VStack(alignment: .leading, spacing: 12) {
                    if let category = resource.category, !category.isEmpty {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.92, green: 0.96, blue: 1.0), in: Capsule())
                    }

                    Text(resource.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let summary = resource.tagLine ?? resource.summary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    HStack(alignment: .center, spacing: 14) {
                        ResourceInlineMetaRow(resource: resource)

                        Spacer()

                        Text("Open Resource")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white, Color(red: 0.97, green: 0.985, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceLatestColumn: View {
    let appState: AppState
    let resources: [XFResource]
    let allResources: [XFResource]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(resources) { resource in
                ResourceLatestRowCard(
                    appState: appState,
                    resource: resource,
                    allResources: allResources
                )
            }
        }
    }
}

private struct ResourceLatestRowCard: View {
    let appState: AppState
    let resource: XFResource
    let allResources: [XFResource]

    var body: some View {
        NavigationLink(
            destination: ResourceDetailView(appState: appState, resource: resource, fallbackRelatedResources: allResources)
                .environmentObject(appState)
        ) {
            HStack(spacing: 12) {
                ResourceArtworkView(resource: resource, fillsWidth: false, fixedWidth: 139)

                VStack(alignment: .leading, spacing: 8) {
                    Text(resource.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let summary = resource.tagLine ?? resource.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    ResourceInlineMetaRow(resource: resource)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceInlineMetaRow: View {
    let resource: XFResource

    var body: some View {
        HStack(spacing: 10) {
            if let downloads = resource.downloadCount {
                Label(downloads.formatted(), systemImage: "arrow.down.circle")
            }
            if let rating = resource.rating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
            }
            if let date = resource.updatedDate ?? resource.releaseDate {
                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ResourceBrowseCard: View {
    let appState: AppState
    let resource: XFResource
    let allResources: [XFResource]
    private let api = XenForoAPI()

    var body: some View {
        NavigationLink(
            destination: ResourceDetailView(appState: appState, resource: resource, fallbackRelatedResources: allResources)
                .environmentObject(appState)
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ResourceArtworkView(resource: resource, fillsWidth: true)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(resource.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            if let category = resource.category {
                                Text(category)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)

                        ResourceDownloadControls(
                            id: resource.id,
                            title: resource.title,
                            requestProvider: {
                                try await api.resolvedResourceDownloadRequest(resourceID: resource.id, accessToken: appState.accessToken)
                            }
                        )
                        .environmentObject(appState)
                    }

                    if let summary = resource.tagLine ?? resource.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    ResourceMetaRow(resource: resource)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceArtworkView: View {
    let resource: XFResource
    let fillsWidth: Bool
    var fixedWidth: CGFloat = 139

    private let height: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.95, blue: 1.0),
                            Color(red: 0.97, green: 0.98, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let iconURL = resource.iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : fixedWidth, alignment: .leading)
        .frame(width: fillsWidth ? nil : fixedWidth)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "shippingbox.fill")
                .font(.title3)
            Text("Resource")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResourceMetaRow: View {
    let resource: XFResource

    var body: some View {
        HStack(spacing: 12) {
            if let downloads = resource.downloadCount {
                Label(downloads.formatted(), systemImage: "arrow.down.circle")
            }
            if let views = resource.viewCount {
                Label(views.formatted(), systemImage: "eye")
            }
            if let rating = resource.rating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
            }
            if let date = resource.updatedDate ?? resource.releaseDate {
                Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

private struct ResourcePaginationBar: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let itemRangeText: String

    private var visiblePages: [Int] {
        let lower = max(1, currentPage - 2)
        let upper = min(totalPages, currentPage + 2)
        return Array(lower ... upper)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(itemRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Previous") {
                currentPage = max(1, currentPage - 1)
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == 1)

            HStack(spacing: 8) {
                ForEach(visiblePages, id: \.self) { page in
                    Button {
                        currentPage = page
                    } label: {
                        Text(page.formatted())
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 18)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(pageBackground(for: page))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Next") {
                currentPage = min(totalPages, currentPage + 1)
            }
            .buttonStyle(.bordered)
            .disabled(currentPage == totalPages)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pageBackground(for page: Int) -> some View {
        if page == currentPage {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.clear)
        }
    }
}

private struct ResourceEmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No resources match the current filters.")
                .font(.headline)
            Text("Try a different category, rating threshold, or search phrase.")
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ResourceDetailView: View {
    struct TabItem: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let appState: AppState
    let resource: XFResource
    let fallbackRelatedResources: [XFResource]

    @State private var detailedResource: XFResource?
    @State private var relatedResources: [XFResource] = []
    @State private var isLoadingDetails = false
    @State private var selectedTab: String = "about"
    @State private var availableWidth: CGFloat = 0
    @State private var selectedImageGallery: ResourceImageGallerySelection?
    @State private var selectedVideo: XFResourceVideo?
    @State private var selectedAudio: ResourceAudioSelection?

    private let api = XenForoAPI()

    init(appState: AppState, resource: XFResource, fallbackRelatedResources: [XFResource] = []) {
        self.appState = appState
        self.resource = resource
        self.fallbackRelatedResources = fallbackRelatedResources
    }

    private var currentResource: XFResource {
        detailedResource ?? resource
    }

    private var sidebarFacts: [ResourceFact] {
        var facts: [ResourceFact] = []

        if let versionString = currentResource.versionString {
            facts.append(ResourceFact(title: "Version", value: versionString))
        }
        if let category = currentResource.category {
            facts.append(ResourceFact(title: "Category", value: category))
        }
        if let fileSize = currentResource.fileSize {
            facts.append(ResourceFact(title: "File Size", value: ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)))
        }
        if let releaseDate = currentResource.releaseDate {
            facts.append(ResourceFact(title: "Released", value: releaseDate.formatted(date: .abbreviated, time: .omitted)))
        }
        if let updatedDate = currentResource.updatedDate {
            facts.append(ResourceFact(title: "Updated", value: updatedDate.formatted(date: .abbreviated, time: .omitted)))
        }
        if let downloads = currentResource.downloadCount {
            facts.append(ResourceFact(title: "Downloads", value: downloads.formatted()))
        }
        if let views = currentResource.viewCount {
            facts.append(ResourceFact(title: "Views", value: views.formatted()))
        }
        if let authorName = currentResource.authorName {
            facts.append(ResourceFact(title: "Author", value: authorName))
        }

        return facts
    }

    private var installText: String {
        if let installInstructions = currentResource.installInstructions, !installInstructions.isEmpty {
            return installInstructions
        }

        return "Installation instructions have not been provided for this resource yet."
    }

    private var resourceDetailsText: String? {
        currentResource.descriptionBBCode ?? currentResource.summary ?? currentResource.tagLine
    }

    private var resourceDetailsHTMLBlocks: [BBCodeParser.HTMLBlock] {
        guard let resourceDetailsText else { return [] }
        return BBCodeParser.extractHTMLBlocks(from: resourceDetailsText)
    }

    private var resourceDetailsEmbeds: [BBCodeParser.Embed] {
        guard let resourceDetailsText else { return [] }
        var seen = Set<String>()
        return BBCodeParser.extractEmbeds(from: resourceDetailsText, attachmentLookup: currentResource.attachmentURLs).filter { embed in
            seen.insert("\(embed.kind.rawValue)|\(embed.identifier)").inserted
        }
    }

    private var resourceDetailsInlineImages: [URL] {
        guard let resourceDetailsText else { return [] }
        let extracted = BBCodeParser.extractImageURLs(from: resourceDetailsText, attachmentLookup: currentResource.attachmentURLs)
        let combined = currentResource.screenshots + extracted
        var seen = Set<String>()
        return combined.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private var historyItems: [XFResourceUpdate] {
        if !currentResource.updates.isEmpty {
            return currentResource.updates
        }

        if currentResource.versionString != nil || currentResource.updatedDate != nil {
            return [
                XFResourceUpdate(
                    id: currentResource.id,
                    title: currentResource.title,
                    versionString: currentResource.versionString,
                    message: currentResource.descriptionBBCode ?? "",
                    date: currentResource.updatedDate,
                    downloadURL: nil,
                    attachmentURLs: currentResource.attachmentURLs,
                    imageURLs: currentResource.screenshots,
                    videoURLs: currentResource.videos.map(\.url)
                )
            ]
        }

        return []
    }

    private var sectionTabs: [TabItem] {
        var tabs: [TabItem] = [
            TabItem(id: "about", title: "About"),
            TabItem(id: "updates", title: "Updates"),
            TabItem(id: "history", title: "History"),
            TabItem(id: "reviews", title: "Reviews"),
            TabItem(id: "videos", title: "Videos"),
            TabItem(id: "how_to_install", title: "How To Install")
        ]

        if !extraInfoFields.isEmpty {
            tabs.append(TabItem(id: "extra_info", title: "Extra Info"))
        }

        tabs.append(contentsOf: ownFieldTabs.map {
            TabItem(id: "field_tab:\($0.id)", title: $0.title)
        })

        return tabs
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                resourceHeader
                ViewThatFits(in: .horizontal) {
                    detailColumns
                }
            }
            .padding(24)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { availableWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in
                            availableWidth = newValue
                        }
                }
            )
        }
        .navigationTitle("Resource")
        .task(id: resource.id) { await loadResourceDetail() }
        .sheet(item: $selectedVideo) { video in
            ResourceVideoPlayerSheet(video: video)
        }
        .sheet(item: $selectedAudio) { audio in
            ResourceAudioPlayerSheet(audio: audio)
        }
        .sheet(item: $selectedImageGallery) { selection in
            ResourceImageGallerySheet(
                screenshots: selection.urls,
                selectedIndex: selection.index
            )
        }
    }

    private var resourceHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let cover = currentResource.coverURL {
                AsyncImage(url: cover) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.quaternary)
                            .frame(height: 220)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    case .failure:
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.quaternary)
                            .frame(height: 220)
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            HStack(alignment: .top, spacing: 16) {
                AsyncImage(url: currentResource.iconURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary)
                            .frame(width: 56, height: 56)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.quaternary)
                            .frame(width: 56, height: 56)
                            .overlay(Image(systemName: "shippingbox"))
                    @unknown default:
                        EmptyView()
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(currentResource.title)
                        .font(.system(size: 34, weight: .bold))

                    if let tagline = currentResource.tagLine ?? currentResource.summary {
                        Text(tagline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 14) {
                        if let rating = currentResource.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        }
                        if let downloads = currentResource.downloadCount {
                            Label("\(downloads.formatted()) downloads", systemImage: "arrow.down.circle")
                        }
                        if let views = currentResource.viewCount {
                            Label("\(views.formatted()) views", systemImage: "eye")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 12) {
                    DownloadButton(
                        id: currentResource.id,
                        title: currentResource.title,
                        style: .borderedProminent,
                        requestProvider: { try await api.resolvedResourceDownloadRequest(resourceID: currentResource.id, accessToken: appState.accessToken) }
                    )
                    .environmentObject(appState)

                    if isLoadingDetails {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Section", selection: $selectedTab) {
                ForEach(sectionTabs) { tab in
                    Text(tab.title).tag(tab.id)
                }
            }
            .pickerStyle(.segmented)

            tabContent

            if !resolvedRelatedResources.isEmpty {
                relatedResourcesSection
            }
        }
    }

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            ResourceCard(title: "File Info") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sidebarFacts) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                        }
                    }
                }
            }

            sidebarLinksSection

            if !sidebarButtonFields.isEmpty {
                ResourceFieldSectionCard(title: "Details", fields: sidebarButtonFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == "about" {
            ResourceCard(title: "About") {
                VStack(alignment: .leading, spacing: 16) {
                    if !comingSoonFields.isEmpty {
                        ResourceFieldSectionCard(title: "Coming Soon", fields: comingSoonFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
                    }

                    resourceDetailsSection

                    if !descriptionTopFields.isEmpty {
                        ResourceFieldSectionCard(title: "Overview", fields: descriptionTopFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
                    }

                    if let description = currentResource.descriptionBBCode ?? currentResource.summary,
                       description != resourceDetailsText {
                        VStack(alignment: .leading, spacing: 14) {
                            if let summary = currentResource.summary, summary != description {
                                Text(summary)
                                    .font(.headline)
                            }

                            Text(BBCodeParser.attributedString(from: description, attachmentLookup: currentResource.attachmentURLs))
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("No description has been provided for this resource.")
                            .foregroundStyle(.secondary)
                    }

                    if !descriptionBottomFields.isEmpty {
                        ResourceFieldSectionCard(title: "More Information", fields: descriptionBottomFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
                    }
                }
            }
        } else if selectedTab == "updates" {
            ResourceCard(title: "Updates") {
                if currentResource.updates.isEmpty {
                    if let updatedDate = currentResource.updatedDate {
                        Text("Latest known update: \(updatedDate.formatted(date: .abbreviated, time: .omitted)).")
                    } else {
                        Text("No update history is available for this resource.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(currentResource.updates) { update in
                            updateCard(for: update)
                        }
                    }
                }
            }
        } else if selectedTab == "history" {
            ResourceCard(title: "History") {
                if historyItems.isEmpty {
                    Text("No version history is available for this resource.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(historyItems) { update in
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(update.versionString ?? update.title)
                                            .font(.headline)

                                        if let date = update.date {
                                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if let version = update.versionString, version != update.title {
                                        Text(update.title)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        } else if selectedTab == "reviews" {
            ResourceCard(title: "Reviews") {
                VStack(alignment: .leading, spacing: 14) {
                    if !ratingTopFields.isEmpty {
                        ResourceFieldSectionCard(title: "Before Ratings", fields: ratingTopFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
                    }

                    if let rating = currentResource.rating {
                        HStack(spacing: 8) {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            if let count = currentResource.ratingCount {
                                Text("\(count.formatted()) ratings")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if currentResource.reviews.isEmpty {
                        Text("No written reviews are available for this resource.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(currentResource.reviews) { review in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(review.title ?? review.author)
                                    .font(.headline)
                                if let rating = review.rating {
                                    HStack(spacing: 8) {
                                        StarRatingView(rating: rating)
                                        Text(String(format: "%.1f", rating))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(BBCodeParser.attributedString(from: review.message, attachmentLookup: currentResource.attachmentURLs))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if !ratingBottomFields.isEmpty {
                        ResourceFieldSectionCard(title: "After Ratings", fields: ratingBottomFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
                    }
                }
            }
        } else if selectedTab == "videos" {
            ResourceCard(title: "Videos") {
                if currentResource.videos.isEmpty {
                    Text("No videos were found for this resource.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(currentResource.videos) { video in
                            Link(destination: video.url) {
                                Label(video.title, systemImage: "play.rectangle")
                            }
                        }
                    }
                }
            }
        } else if selectedTab == "how_to_install" {
            ResourceCard(title: "How To Install") {
                Text(BBCodeParser.attributedString(from: installText, attachmentLookup: currentResource.attachmentURLs))
                    .textSelection(.enabled)
            }
        } else if selectedTab == "extra_info" {
            ResourceFieldSectionCard(title: "Extra Information", fields: extraInfoFields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
        } else if let ownTab = ownFieldTabs.first(where: { "field_tab:\($0.id)" == selectedTab }) {
            ResourceFieldSectionCard(title: ownTab.title, fields: ownTab.fields, attachmentLookup: currentResource.attachmentURLs, onOpenGallery: openImageGallery)
        }
    }

    private var resolvedRelatedResources: [XFResource] {
        if !relatedResources.isEmpty {
            return relatedResources
        }

        if !currentResource.relatedResources.isEmpty {
            return currentResource.relatedResources.filter { $0.id != currentResource.id }
        }

        return fallbackRelatedResources.filter {
            $0.id != currentResource.id && $0.category == currentResource.category
        }
    }

    @ViewBuilder
    private var detailColumns: some View {
        if availableWidth > 980 {
            HStack(alignment: .top, spacing: 24) {
                contentColumn
                    .frame(maxWidth: .infinity, alignment: .leading)

                sidebarColumn
                    .frame(width: 300)
                    .layoutPriority(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                sidebarColumn
                contentColumn
            }
        }
    }

    private var relatedResourcesSection: some View {
        ResourceCard(title: "Related Resources") {
            LazyVGrid(columns: relatedGridColumns, spacing: 14) {
                ForEach(resolvedRelatedResources.prefix(6)) { related in
                    NavigationLink(destination: ResourceDetailView(appState: appState, resource: related, fallbackRelatedResources: fallbackRelatedResources)) {
                        RelatedResourceCard(resource: related)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var relatedGridColumns: [GridItem] {
        availableWidth > 1220
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible(), spacing: 14)]
    }

    private var descriptionTopFields: [XFResourceField] {
        fields(for: [.aboveDescription])
    }

    private var descriptionBottomFields: [XFResourceField] {
        fields(for: [.belowDescription])
    }

    private var ratingTopFields: [XFResourceField] {
        fields(for: [.aboveRating])
    }

    private var ratingBottomFields: [XFResourceField] {
        fields(for: [.belowRating])
    }

    private var sidebarButtonFields: [XFResourceField] {
        fields(for: [.belowSidebarButtons])
    }

    private var extraInfoFields: [XFResourceField] {
        currentResource.fields.filter { placement(for: $0) == .extraInformationTab || placement(for: $0) == .unplaced }
    }

    private var otherResourceLinks: [ResourceLinkItem] {
        var items: [ResourceLinkItem] = []

        let existing = Set(items.map(\.url))
        for video in currentResource.videos where !existing.contains(video.url) {
            items.append(ResourceLinkItem(title: video.title, subtitle: video.url.host, url: video.url, systemImage: "link"))
        }

        return items
    }

    private var comingSoonFields: [XFResourceField] {
        fields(for: [.comingSoonWindow])
    }

    private var ownFieldTabs: [FieldTabGroup] {
        let groups = Dictionary(grouping: currentResource.fields.filter { placement(for: $0) == .ownTab }) { field in
            let rawTitle = field.ownTabTitle ?? field.title
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "More" : title
        }

        return groups
            .map { title, fields in
                FieldTabGroup(id: title.lowercased().replacingOccurrences(of: " ", with: "_"), title: title, fields: fields.sorted(by: fieldSort)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func fields(for placements: Set<FieldPlacement>) -> [XFResourceField] {
        currentResource.fields
            .filter { placements.contains(placement(for: $0)) }
            .sorted(by: fieldSort)
    }

    private func placement(for field: XFResourceField) -> FieldPlacement {
        let raw = (field.displayLocation ?? "").lowercased()
        if raw.contains("above resource description") {
            return .aboveDescription
        }
        if raw.contains("below resource description") {
            return .belowDescription
        }
        if raw.contains("above resource rating") {
            return .aboveRating
        }
        if raw.contains("below resource rating") {
            return .belowRating
        }
        if raw.contains("below sidebar buttons") {
            return .belowSidebarButtons
        }
        if raw.contains("extra information tab") {
            return .extraInformationTab
        }
        if raw.contains("own tab") {
            return .ownTab
        }
        if raw.contains("coming soon") {
            return .comingSoonWindow
        }
        return .unplaced
    }

    private var fieldSort: (XFResourceField, XFResourceField) -> Bool {
        { lhs, rhs in
            let leftOrder = lhs.displayOrder ?? .max
            let rightOrder = rhs.displayOrder ?? .max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func loadResourceDetail() async {
        guard (NetworkMonitor.shared.isConnected ?? true) && BoardStatusService.shared.isActive else { return }
        guard !isLoadingDetails else { return }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            let detailed = try await api.fetchResourceDetail(id: resource.id, accessToken: appState.accessToken)
            detailedResource = detailed
            if !sectionTabs.contains(where: { $0.id == selectedTab }) {
                selectedTab = "about"
            }

            if !detailed.relatedResources.isEmpty {
                relatedResources = detailed.relatedResources.filter { $0.id != detailed.id }
            } else if fallbackRelatedResources.isEmpty {
                let resources = try await api.fetchResources(accessToken: appState.accessToken)
                relatedResources = resources.filter { $0.id != detailed.id && $0.category == detailed.category }
            }
        } catch {
            if fallbackRelatedResources.isEmpty {
                do {
                    let resources = try await api.fetchResources(accessToken: appState.accessToken)
                    relatedResources = resources.filter { $0.id != resource.id && $0.category == resource.category }
                } catch {
                    // Keep the fallback empty.
                }
            }
        }
    }

    @ViewBuilder
    private var resourceDetailsSection: some View {
        if hasResourceDetailsContent {
            ResourceCard(title: "Resource Details") {
                VStack(alignment: .leading, spacing: 18) {
                    if let detailsText = resourceDetailsText {
                        Text(BBCodeParser.attributedString(from: BBCodeParser.stripParseHTMLBlocks(from: detailsText), attachmentLookup: currentResource.attachmentURLs))
                            .textSelection(.enabled)
                    }

                    if !resourceDetailsHTMLBlocks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(resourceDetailsHTMLBlocks) { block in
                                ParseHTMLCardView(html: block.html)
                            }
                        }
                    }

                    if !resourceDetailsInlineImages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Images")
                                .font(.headline)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Array(resourceDetailsInlineImages.enumerated()), id: \.offset) { index, screenshot in
                                        Button {
                                            selectedImageGallery = ResourceImageGallerySelection(urls: resourceDetailsInlineImages, index: index)
                                        } label: {
                                            screenshotThumbnail(for: screenshot)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if !resourceDetailsEmbeds.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Media")
                                .font(.headline)

                            ForEach(resourceDetailsEmbeds) { embed in
                                ResourceDetailsEmbedCard(embed: embed) { video in
                                    selectedVideo = video
                                } onOpenAudio: { audio in
                                    selectedAudio = audio
                                }
                            }
                        }
                    }

                    if !currentResource.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Videos")
                                .font(.headline)

                            ForEach(currentResource.videos) { video in
                                Button {
                                    selectedVideo = video
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .frame(width: 52, height: 52)
                                            .overlay(
                                                Image(systemName: "play.fill")
                                                    .foregroundStyle(Color.accentColor)
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(video.title)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text(video.url.host ?? video.url.absoluteString)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "play.rectangle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(.quaternary.opacity(0.35))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !otherResourceLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Other")
                                .font(.headline)

                            ForEach(otherResourceLinks) { item in
                                Link(destination: item.url) {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.systemImage)
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .foregroundStyle(.primary)
                                            if let subtitle = item.subtitle {
                                                Text(subtitle)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var hasResourceDetailsContent: Bool {
        resourceDetailsText != nil
            || !resourceDetailsInlineImages.isEmpty
            || !resourceDetailsEmbeds.isEmpty
            || !currentResource.videos.isEmpty
            || !otherResourceLinks.isEmpty
    }

    @ViewBuilder
    private var sidebarLinksSection: some View {
        ResourceCard(title: "Links") {
            VStack(alignment: .leading, spacing: 10) {
                if let viewURL = currentResource.viewURL {
                    Link(destination: viewURL) {
                        sidebarLinkLabel(title: "Open Resource", subtitle: viewURL.host, systemImage: "safari")
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    selectedTab = !extraInfoFields.isEmpty ? "extra_info" : "about"
                } label: {
                    sidebarLinkLabel(
                        title: "More Info",
                        subtitle: !extraInfoFields.isEmpty ? "Open extra details" : "Jump to about",
                        systemImage: "info.circle"
                    )
                }
                .buttonStyle(.plain)

                if let supportURL = supportURL {
                    Link(destination: supportURL) {
                        sidebarLinkLabel(title: "Get Support", subtitle: supportURL.host, systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var supportURL: URL? {
        if let viewURL = currentResource.viewURL {
            return viewURL
        }
        return URL(string: "https://cities-mods.com/help")
    }

    private func sidebarLinkLabel(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
    }

    private func screenshotThumbnail(for screenshot: URL) -> some View {
        AsyncImage(url: screenshot) { phase in
            switch phase {
            case .empty:
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .frame(width: 220, height: 136)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 220, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
            case .failure:
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .frame(width: 220, height: 136)
                    .overlay(Image(systemName: "photo"))
            @unknown default:
                EmptyView()
            }
        }
    }

    private func openImageGallery(urls: [URL], index: Int) {
        selectedImageGallery = ResourceImageGallerySelection(urls: urls, index: index)
    }

    private func updateImages(for update: XFResourceUpdate) -> [URL] {
        if !update.imageURLs.isEmpty {
            return update.imageURLs
        }
        return BBCodeParser.extractImageURLs(from: update.message, attachmentLookup: update.attachmentURLs.isEmpty ? currentResource.attachmentURLs : update.attachmentURLs)
    }

    private func updateEmbeds(for update: XFResourceUpdate) -> [BBCodeParser.Embed] {
        var seen = Set<String>()
        return BBCodeParser.extractEmbeds(
            from: update.message,
            attachmentLookup: update.attachmentURLs.isEmpty ? currentResource.attachmentURLs : update.attachmentURLs
        )
            .filter { embed in
                seen.insert("\(embed.kind.rawValue)|\(embed.identifier)").inserted
            }
    }

    @ViewBuilder
    private func updateCard(for update: XFResourceUpdate) -> some View {
        let images = updateImages(for: update)
        let embeds = updateEmbeds(for: update)
        let htmlBlocks = BBCodeParser.extractHTMLBlocks(from: update.message)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(update.title)
                            .font(.headline)

                        if let version = update.versionString, !version.isEmpty {
                            Text(version)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }

                    if let date = update.date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                DownloadButton(
                    id: currentResource.id,
                    title: currentResource.title,
                    style: .bordered,
                    requestProvider: { try await api.resolvedResourceDownloadRequest(resourceID: currentResource.id, accessToken: appState.accessToken) }
                )
                .environmentObject(appState)
            }

            if !update.message.isEmpty {
                Text(BBCodeParser.attributedString(
                    from: update.message,
                    attachmentLookup: update.attachmentURLs.isEmpty ? currentResource.attachmentURLs : update.attachmentURLs
                ))
                    .textSelection(.enabled)
            }

            if !htmlBlocks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(htmlBlocks) { block in
                        ParseHTMLCardView(html: block.html)
                    }
                }
            }

            if !images.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Images")
                        .font(.headline)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Button {
                                    selectedImageGallery = ResourceImageGallerySelection(urls: images, index: index)
                                } label: {
                                    screenshotThumbnail(for: image)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !embeds.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Videos & Media")
                        .font(.headline)

                    ForEach(embeds) { embed in
                        ResourceDetailsEmbedCard(embed: embed) { video in
                            selectedVideo = video
                        } onOpenAudio: { audio in
                            selectedAudio = audio
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.quaternary.opacity(0.25))
        )
    }
}

private struct ResourceFact: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct ResourceLinkItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let url: URL
    let systemImage: String
}

private struct ResourceImageGallerySelection: Identifiable {
    let id = UUID()
    let urls: [URL]
    let index: Int
}

private enum FieldPlacement {
    case aboveDescription
    case belowDescription
    case aboveRating
    case belowRating
    case belowSidebarButtons
    case extraInformationTab
    case ownTab
    case comingSoonWindow
    case unplaced
}

private struct FieldTabGroup: Identifiable {
    let id: String
    let title: String
    let fields: [XFResourceField]
}

private struct ResourceCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ResourceFieldSectionCard: View {
    let title: String
    let fields: [XFResourceField]
    let attachmentLookup: [String: URL]
    let onOpenGallery: ([URL], Int) -> Void

    var body: some View {
        ResourceCard(title: title) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.title)
                            .font(.headline)

                        if let description = field.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(BBCodeParser.attributedString(from: field.value, attachmentLookup: attachmentLookup))
                            .textSelection(.enabled)

                        if !field.imageURLs.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(field.imageURLs.enumerated()), id: \.offset) { index, imageURL in
                                        Button {
                                            onOpenGallery(field.imageURLs, index)
                                        } label: {
                                            AsyncImage(url: imageURL) { phase in
                                                switch phase {
                                                case .empty:
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(.quaternary)
                                                        .frame(width: 180, height: 112)
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .frame(width: 180, height: 112)
                                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                                case .failure:
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(.quaternary)
                                                        .frame(width: 180, height: 112)
                                                        .overlay(Image(systemName: "photo"))
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ParseHTMLCardView: View {
    let html: String

    var body: some View {
        EmbeddedHTMLView(html: wrappedHTML)
            .frame(minHeight: 120, maxHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }

    private var wrappedHTML: String {
        """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 16px;
                    background: transparent;
                    color: -apple-system-label;
                    font: 14px -apple-system, BlinkMacSystemFont, sans-serif;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }
}

private struct ResourceDetailsEmbedCard: View {
    let embed: BBCodeParser.Embed
    let onOpenVideo: (XFResourceVideo) -> Void
    let onOpenAudio: (ResourceAudioSelection) -> Void

    var body: some View {
        Group {
            if let html = embed.embedHTML {
                EmbeddedHTMLView(html: html)
                    .frame(minHeight: 220, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06))
                    )
            } else if let videoURL = embed.url, embed.kind == .directVideo {
                Button {
                    onOpenVideo(XFResourceVideo(title: embed.displayTitle, url: videoURL))
                } label: {
                    resourceDetailsLinkLabel(
                        title: embed.displayTitle,
                        subtitle: embed.subtitle,
                        systemImage: "play.rectangle"
                    )
                }
                .buttonStyle(.plain)
            } else if let audioURL = embed.url, embed.kind == .audioFile {
                Button {
                    onOpenAudio(ResourceAudioSelection(title: embed.displayTitle, url: audioURL))
                } label: {
                    resourceDetailsLinkLabel(
                        title: embed.displayTitle,
                        subtitle: embed.subtitle,
                        systemImage: "waveform"
                    )
                }
                .buttonStyle(.plain)
            } else if let url = embed.canonicalURL {
                Link(destination: url) {
                    resourceDetailsLinkLabel(
                        title: embed.displayTitle,
                        subtitle: embed.subtitle,
                        systemImage: embed.systemImage
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resourceDetailsLinkLabel(title: String, subtitle: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: embed.kind == .directVideo ? "play.fill" : "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

private struct EmbeddedHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: URL(string: "https://cities-mods.com"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(html, baseURL: URL(string: "https://cities-mods.com"))
    }
}

private struct ResourceAudioSelection: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

private extension BBCodeParser.Embed {
    var displayTitle: String {
        switch kind {
        case .youtube:
            return "YouTube"
        case .facebook:
            return "Facebook"
        case .instagram:
            return "Instagram"
        case .steam:
            return "Steam"
        case .imdb:
            return "IMDb"
        case .vimeo:
            return "Vimeo"
        case .dailymotion:
            return "Dailymotion"
        case .streamable:
            return "Streamable"
        case .twitch:
            return "Twitch"
        case .soundcloud:
            return "SoundCloud"
        case .spotify:
            return "Spotify"
        case .directVideo:
            return "Video"
        case .audioFile:
            return "Audio"
        case .embed:
            return canonicalURL?.host ?? "Embed"
        case .xenforoMedia:
            return "Media"
        case .url:
            return canonicalURL?.host ?? "Link"
        case .unknown:
            return provider?.capitalized ?? "Media"
        }
    }

    var subtitle: String? {
        canonicalURL?.absoluteString ?? provider
    }

    var systemImage: String {
        switch kind {
        case .youtube, .facebook, .instagram, .vimeo, .dailymotion, .streamable, .twitch, .directVideo, .soundcloud, .spotify:
            return "play.rectangle"
        case .audioFile:
            return "waveform"
        case .steam:
            return "gamecontroller"
        case .imdb:
            return "film"
        case .embed, .url, .xenforoMedia, .unknown:
            return "link"
        }
    }

    var canonicalURL: URL? {
        switch kind {
        case .youtube:
            if identifier.hasPrefix("http") {
                return URL(string: identifier)
            }
            return URL(string: "https://www.youtube.com/watch?v=\(identifier)")
        case .facebook, .instagram, .steam, .imdb, .vimeo, .dailymotion, .streamable, .twitch, .soundcloud, .spotify, .directVideo, .audioFile, .embed, .url, .xenforoMedia, .unknown:
            return URL(string: identifier)
        }
    }

    var embedHTML: String? {
        let iframeURL: String?
        switch kind {
        case .youtube:
            let value = identifier.hasPrefix("http") ? URL(string: identifier)?.absoluteString : "https://www.youtube.com/embed/\(identifier)"
            iframeURL = value
        case .facebook:
            if let encoded = canonicalURL?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                iframeURL = "https://www.facebook.com/plugins/video.php?href=\(encoded)"
            } else {
                iframeURL = nil
            }
        case .instagram:
            iframeURL = nil
        case .steam:
            if let appID = steamAppID {
                iframeURL = "https://store.steampowered.com/widget/\(appID)"
            } else {
                iframeURL = nil
            }
        case .imdb:
            iframeURL = nil
        case .vimeo:
            if let url = URL(string: identifier),
               let last = url.pathComponents.last, !last.isEmpty {
                iframeURL = "https://player.vimeo.com/video/\(last)"
            } else {
                iframeURL = nil
            }
        case .dailymotion:
            if let url = URL(string: identifier) {
                let last = url.pathComponents.last ?? ""
                let videoID = last.replacingOccurrences(of: "video/", with: "")
                iframeURL = videoID.isEmpty ? nil : "https://www.dailymotion.com/embed/video/\(videoID)"
            } else {
                iframeURL = nil
            }
        case .streamable:
            if let url = URL(string: identifier),
               let last = url.pathComponents.last, !last.isEmpty {
                iframeURL = "https://streamable.com/e/\(last)"
            } else {
                iframeURL = nil
            }
        case .twitch:
            iframeURL = nil
        case .soundcloud:
            if let encoded = canonicalURL?.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                iframeURL = "https://w.soundcloud.com/player/?url=\(encoded)"
            } else {
                iframeURL = nil
            }
        case .spotify:
            iframeURL = spotifyEmbedURL
        case .directVideo, .audioFile, .embed, .url, .xenforoMedia, .unknown:
            iframeURL = nil
        }

        guard let iframeURL else { return nil }
        return """
        <!doctype html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                html, body {
                    margin: 0;
                    padding: 0;
                    background: #111827;
                }
                iframe {
                    display: block;
                    width: 100%;
                    height: 100%;
                    border: 0;
                }
            </style>
        </head>
        <body>
            <iframe src="\(iframeURL)" allowfullscreen allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"></iframe>
        </body>
        </html>
        """
    }

    private var steamAppID: String? {
        guard let url = URL(string: identifier) else { return nil }
        let parts = url.pathComponents
        guard let appIndex = parts.firstIndex(of: "app"), parts.indices.contains(appIndex + 1) else { return nil }
        return parts[appIndex + 1]
    }

    private var spotifyEmbedURL: String? {
        guard let url = canonicalURL else { return nil }
        let absolute = url.absoluteString
        if absolute.contains("/embed/") {
            return absolute
        }
        return absolute.replacingOccurrences(of: "open.spotify.com/", with: "open.spotify.com/embed/")
    }
}

private struct StarRatingView: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .foregroundStyle(.yellow)
            }
        }
    }

    private func symbol(for index: Int) -> String {
        let threshold = Double(index) + 1
        if rating >= threshold {
            return "star.fill"
        }
        if rating >= threshold - 0.5 {
            return "star.leadinghalf.filled"
        }
        return "star"
    }
}

private struct RelatedResourceCard: View {
    let resource: XFResource

    var body: some View {
        HStack(spacing: 12) {
            iconBadge

            VStack(alignment: .leading, spacing: 6) {
                Text(resource.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let category = resource.category {
                        Label(category, systemImage: "folder")
                    }
                    if let rating = resource.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(cardBackground)
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 46, height: 46)
            .overlay(iconContent)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let iconURL = resource.iconURL {
            AsyncImage(url: iconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                default:
                    fallbackIcon
                }
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "shippingbox.fill")
            .foregroundStyle(Color.accentColor)
            .frame(width: 24, height: 24)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.001))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

private struct ResourceVideoPlayerSheet: View {
    let video: XFResourceVideo
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(video.title)
                .font(.title2.weight(.semibold))

            if let player {
                VideoPlayer(player: player)
                    .frame(minHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 420)
            }
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 560)
        .task {
            if player == nil {
                player = AVPlayer(url: video.url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct ResourceAudioPlayerSheet: View {
    let audio: ResourceAudioSelection
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(audio.title)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(audio.url.lastPathComponent)
                            .font(.headline)
                        Text(audio.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let player {
                    VideoPlayer(player: player)
                        .frame(minHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 320)
        .task {
            if player == nil {
                player = AVPlayer(url: audio.url)
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}

private struct ResourceImageGallerySheet: View {
    let screenshots: [URL]
    let selectedIndex: Int

    @State private var selection: Int

    init(screenshots: [URL], selectedIndex: Int) {
        self.screenshots = screenshots
        self.selectedIndex = selectedIndex
        _selection = State(initialValue: selectedIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screenshots")
                .font(.title2.weight(.semibold))

            HStack {
                Button {
                    selection = max(selection - 1, 0)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(selection == 0)

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.black.opacity(0.92))

                    if screenshots.indices.contains(selection) {
                        AsyncImage(url: screenshots[selection]) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .interpolation(.high)
                                    .antialiased(true)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    selection = min(selection + 1, screenshots.count - 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(selection >= screenshots.count - 1)
            }

            if screenshots.indices.contains(selection) {
                HStack {
                    Text(screenshots[selection].lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(selection + 1) of \(screenshots.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 1100, minHeight: 760)
    }
}
