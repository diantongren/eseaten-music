import SwiftUI

/// 独立的搜索页：工具栏里是搜索框和“单曲 / 专辑 / 歌手 / 歌单”范围切换
struct SearchView: View {
    @Bindable var model: SearchModel

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        content
            .navigationTitle("搜索")
            .searchable(text: $model.text, placement: .toolbar, prompt: "搜索\(model.scope.rawValue)")
            .searchFocused($isFieldFocused)
            .toolbar {
                // macOS 上 primaryAction 在工具栏左侧；搜索框和范围切换要像 Apple Music 一样靠右
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .automatic) {
                    Picker("范围", selection: $model.scope) {
                        ForEach(SearchModel.Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .task(id: model.key) { await model.load() }
            // 进来时还没有关键词就直接聚焦搜索框
            .onAppear { if model.text.isEmpty { isFieldFocused = true } }
    }

    @ViewBuilder
    private var content: some View {
        let keyword = model.key.keyword
        if keyword.isEmpty {
            prompt
        } else if let shown = model.shown, shown.key.scope == model.scope {
            results(shown.results, keyword: shown.key.keyword)
                .overlay(alignment: .top) {
                    if model.isLoading { ProgressView().controlSize(.small).padding(8) }
                }
        } else if let error = model.error {
            ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark",
                                   description: Text(error.localizedDescription))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 还没输入时的占位，和 Apple Music 一样只放一个大图标和一句话
    private var prompt: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64, weight: .regular))
            Text("在网易云音乐中搜索")
                .font(.system(size: 26, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func results(_ results: SearchModel.Results, keyword: String) -> some View {
        let title = "“\(keyword)”的搜索结果"
        switch results {
        case .songs(let songs):
            SongsView(title: title, songs: songs)
        case .albums(let albums):
            CollectionGridView(title: title, items: albums, emptyText: "没有找到专辑")
        case .artists(let artists):
            ArtistsView(title: title, artists: artists, emptyText: "没有找到歌手")
        case .playlists(let playlists):
            CollectionGridView(title: title, items: playlists, emptyText: "没有找到歌单")
        }
    }
}
