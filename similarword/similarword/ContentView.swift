import SwiftUI
import CryptoKit
import AVFoundation

// MARK: - 模型
struct WordEntry: Identifiable, Codable, Hashable {
    let id = UUID()
    let word: String
    let pos: String
    var meaningCN: String
    var meaningAPI: String? = nil
}

struct SavedQuery: Identifiable, Codable {
    let id = UUID()
    let inputWord: String
    var results: [WordEntry]
    let timestamp: Date = Date()
}

enum WordType: String {
    case similar = "-相似词"
    case synonym = "-近义词"
}

struct BaiduTranslateResponse: Codable {
    struct TransResult: Codable {
        let src: String
        let dst: String
    }
    let trans_result: [TransResult]
}

// MARK: - 数据管理
class WordManager: ObservableObject {
    @Published var allWords: [WordEntry] = []
    @Published var savedQueries: [SavedQuery] = []
    @Published var similarityThreshold: Double = 0.6

    let appid = ""// 如需使用百度翻译，请添加api相关信息
    let key = ""

    init() {
        loadWordsFromFile()
        loadSavedQueries()
    }

    func loadWordsFromFile() {
        guard let path = Bundle.main.path(forResource: "ch", ofType: "bin"),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { continue }
            let word = parts[0]
            let rest = parts[1]
            if let dotIndex = rest.firstIndex(of: ".") {
                let pos = String(rest[..<dotIndex])
                let meaningCN = String(rest[rest.index(after: dotIndex)...])
                let entry = WordEntry(word: word, pos: pos, meaningCN: meaningCN)
                allWords.append(entry)
            }
        }
    }

    func levenshtein(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1.lowercased())
        let s2 = Array(s2.lowercased())
        let len1 = s1.count
        let len2 = s2.count
        var dist = Array(repeating: Array(repeating: 0, count: len2 + 1), count: len1 + 1)
        for i in 0...len1 { dist[i][0] = i }
        for j in 0...len2 { dist[0][j] = j }
        for i in 1...len1 {
            for j in 1...len2 {
                if s1[i-1] == s2[j-1] { dist[i][j] = dist[i-1][j-1] }
                else { dist[i][j] = min(dist[i-1][j-1], dist[i][j-1], dist[i-1][j]) + 1 }
            }
        }
        return dist[len1][len2]
    }

    func findSimilarWords(to input: String) -> [WordEntry] {
        var results = allWords.filter {
            let distance = levenshtein($0.word, input)
            let maxLen = max($0.word.count, input.count)
            let similarity = 1.0 - Double(distance)/Double(maxLen)
            return similarity >= similarityThreshold
        }
        if let original = allWords.first(where: { $0.word.lowercased() == input.lowercased() }) {
            results.removeAll { $0.word.lowercased() == input.lowercased() }
            results.insert(original, at: 0)
        }
        return results
    }

    func findSynonyms(word: String, completion: @escaping ([WordEntry]) -> Void) {
        guard let original = allWords.first(where: { $0.word.lowercased() == word.lowercased() }) else {
            completion([])
            return
        }
        let meaningParts = original.meaningCN.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var candidates: [WordEntry] = []
        for part in meaningParts {
            let localMatches = allWords.filter { $0.meaningCN.contains(part) && $0.word.lowercased() != original.word.lowercased() }
            candidates.append(contentsOf: localMatches)
        }
        var results: [WordEntry] = [original]
        let group = DispatchGroup()
        for i in 0..<candidates.count {
            group.enter()
            fetchBaiduTranslation(word: candidates[i].word) { translation in
                DispatchQueue.main.async {
                    candidates[i].meaningAPI = translation
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            results.append(contentsOf: candidates)
            completion(Array(Set(results)))
        }
    }

    func fetchBaiduTranslation(word: String, completion: @escaping (String?) -> Void) {
        let salt = String(Int.random(in: 10000...99999))
        let sign = md5(appid + word + salt + key)
        guard let query = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil)
            return
        }
        let urlStr = "https://fanyi-api.baidu.com/api/trans/vip/translate?q=\(query)&from=en&to=zh&appid=\(appid)&salt=\(salt)&sign=\(sign)"
        guard let url = URL(string: urlStr) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { completion(nil); return }
            if let result = try? JSONDecoder().decode(BaiduTranslateResponse.self, from: data),
               let translation = result.trans_result.first?.dst {
                completion(translation)
            } else { completion(nil) }
        }.resume()
    }

    func md5(_ str: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func saveQuery(inputWord: String, results: [WordEntry], type: WordType) -> Bool {
        let query = SavedQuery(inputWord: inputWord + type.rawValue, results: results)
        if savedQueries.contains(where: { $0.inputWord.lowercased() == query.inputWord.lowercased() }) {
            return false
        }
        savedQueries.append(query)
        persistSavedQueries()
        return true
    }

    func deleteSavedQuery(_ query: SavedQuery) {
        if let index = savedQueries.firstIndex(where: { $0.id == query.id }) {
            savedQueries.remove(at: index)
            persistSavedQueries()
        }
    }

    func persistSavedQueries() {
        if let data = try? JSONEncoder().encode(savedQueries) {
            UserDefaults.standard.set(data, forKey: "SavedQueries")
        }
    }

    func loadSavedQueries() {
        if let data = UserDefaults.standard.data(forKey: "SavedQueries"),
           let queries = try? JSONDecoder().decode([SavedQuery].self, from: data) {
            savedQueries = queries
        }
    }
}

// MARK: - 主页面
struct ContentView: View {
    @State private var inputWord = ""
    @State private var searchResults: [WordEntry] = []
    @ObservedObject var manager = WordManager()
    @State private var isLoading = false
    @State private var showSavedAnimation = false
    @State private var savedType: WordType = .similar
    @State private var savedMessage = ""
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextField("请输入单词", text: $inputWord)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

                VStack {
                    HStack {
                        Text("相似度: \(String(format: "%.2f", manager.similarityThreshold))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Slider(value: $manager.similarityThreshold, in: 0.5...1.0, step: 0.01)
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 16) {
                    Button(action: {
                        hideKeyboard()
                        searchResults = manager.findSimilarWords(to: inputWord)
                        savedType = .similar
                    }) {
                        Label("相似词", systemImage: "text.magnifyingglass")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 3)
                    }

                    Button(action: {
                        hideKeyboard()
                        isLoading = true
                        savedType = .synonym
                        manager.findSynonyms(word: inputWord) { results in
                            DispatchQueue.main.async {
                                searchResults = results
                                isLoading = false
                            }
                        }
                    }) {
                        Label("近义词", systemImage: "arrow.triangle.branch")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 3)
                    }
                }
                .padding(.horizontal)

                if isLoading {
                    ProgressView("查询中...")
                        .padding()
                }

                if !searchResults.isEmpty {
                    Button(action: saveQuery) {
                        Label("保存本次查询", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .shadow(radius: 3)
                    }
                    .padding(.horizontal)
                }

                List {
                    ForEach(searchResults) { word in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(word.word) [\(word.pos)]").font(.headline).foregroundColor(.primary)
                                Text("中文: \(word.meaningCN)").font(.subheadline).foregroundColor(.secondary)
                                if let api = word.meaningAPI {
                                    Text("百度释义: \(api)").font(.subheadline).foregroundColor(.blue)
                                }
                            }
                            Spacer()
                            if audioExists(for: word.word) {
                                Button(action: { playWordAudio(word.word) }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                        .padding()
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .toolbar {
                NavigationLink(destination: SavedQueriesView(manager: manager)) {
                    Text("已保存")
                }
            }
            .overlay(
                Group {
                    if showSavedAnimation {
                        Text(savedMessage)
                            .font(.title2)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(15)
                            .shadow(radius: 5)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(1)
                    }
                },
                alignment: .top
            )
        }
    }

    private func saveQuery() {
        let success = manager.saveQuery(inputWord: inputWord, results: searchResults, type: savedType)
        savedMessage = success ? "✅ 已保存 \(savedType.rawValue)" : "⚠️ 已保存过 \(savedType.rawValue)"
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showSavedAnimation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.5)) { showSavedAnimation = false }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func playWordAudio(_ word: String) {
        guard let url = Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch { print("播放失败: \(error.localizedDescription)") }
    }

    private func audioExists(for word: String) -> Bool {
        return Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") != nil
    }
}

// MARK: - 已保存页面
struct SavedQueriesView: View {
    @ObservedObject var manager: WordManager
    @State private var sortOption: SavedQuerySortOption = .time
    @State private var audioPlayer: AVAudioPlayer?

    enum SavedQuerySortOption: String, CaseIterable {
        case alphabetical = "按字母排序"
        case time = "按保存时间"
    }

    var body: some View {
        VStack {
            Picker("排序方式", selection: $sortOption) {
                ForEach(SavedQuerySortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if sortedQueries.isEmpty {
                Spacer()
                Text("暂无保存的单词").foregroundColor(.secondary).font(.headline)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedQueries) { query in
                            NavigationLink {
                                QueryDetailView(query: query, manager: manager)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(query.inputWord).font(.title3).fontWeight(.semibold).foregroundColor(.primary)
                                        Spacer()
                                        if audioExists(for: query.inputWord) {
                                            Button(action: { playWordAudio(query.inputWord) }) {
                                                Image(systemName: "speaker.wave.2.fill").foregroundColor(.blue)
                                            }
                                        }
                                    }
                                    Text("保存时间: \(query.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemBackground))
                                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                            }
                            .contextMenu {
                                Button(role: .destructive) { manager.deleteSavedQuery(query) } label: { Label("删除", systemImage: "trash") }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("已保存单词")
    }

    private var sortedQueries: [SavedQuery] {
        switch sortOption {
        case .alphabetical: return manager.savedQueries.sorted { $0.inputWord.lowercased() < $1.inputWord.lowercased() }
        case .time: return manager.savedQueries.sorted { $0.timestamp > $1.timestamp }
        }
    }

    private func playWordAudio(_ word: String) {
        guard let url = Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") else { return }
        do { audioPlayer = try AVAudioPlayer(contentsOf: url); audioPlayer?.prepareToPlay(); audioPlayer?.play() }
        catch { print("播放失败: \(error.localizedDescription)") }
    }

    private func audioExists(for word: String) -> Bool {
        return Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") != nil
    }
}

// MARK: - 详情页
struct QueryDetailView: View {
    let query: SavedQuery
    let manager: WordManager
    @State private var audioPlayer: AVAudioPlayer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let original = manager.allWords.first(where: {
                    $0.word.lowercased() == query.inputWord
                        .replacingOccurrences(of: WordType.similar.rawValue, with: "")
                        .replacingOccurrences(of: WordType.synonym.rawValue, with: "")
                        .lowercased()
                }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("【本单词】").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            if audioExists(for: original.word) {
                                Button(action: { playWordAudio(original.word) }) {
                                    Image(systemName: "speaker.wave.2.fill").foregroundColor(.blue)
                                }
                            }
                        }
                        Text("\(original.word) [\(original.pos)]").font(.title3).fontWeight(.bold)
                        Text("中文: \(original.meaningCN)").font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(query.results) { word in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(word.word).font(.headline)
                                Spacer()
                                if audioExists(for: word.word) {
                                    Button(action: { playWordAudio(word.word) }) {
                                        Image(systemName: "speaker.wave.2.fill").foregroundColor(.blue)
                                    }
                                }
                            }
                            Text("中文: \(word.meaningCN)").font(.subheadline).foregroundColor(.secondary)
                            if let api = word.meaningAPI { Text("百度释义: \(api)").font(.subheadline).foregroundColor(.blue) }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(query.inputWord)
    }

    private func playWordAudio(_ word: String) {
        guard let url = Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") else { return }
        do { audioPlayer = try AVAudioPlayer(contentsOf: url); audioPlayer?.prepareToPlay(); audioPlayer?.play() }
        catch { print("播放失败: \(error.localizedDescription)") }
    }

    private func audioExists(for word: String) -> Bool {
        return Bundle.main.url(forResource: word.lowercased(), withExtension: "mp3", subdirectory: "speech") != nil
    }
}

// MARK: - 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
