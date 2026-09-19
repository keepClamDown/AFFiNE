import CryptoKit
import Foundation

final class LocalAIManager: NSObject {
  static let shared = LocalAIManager()

  struct ModelRecord: Codable {
    var modelId: String
    var version: String
    var status: String
    var downloadURL: String?
    var localPath: String?
    var expectedSha256: String?
    var bytesTotal: Int64?
    var bytesDownloaded: Int64?
    var progress: Double?
    var lastError: String?
    var updatedAt: String
  }

  struct StatePayload: Codable {
    var models: [ModelRecord]
    var modelDirectory: String
    var runtimeAvailable: Bool
    var invocationAvailable: Bool
    var downloadResumableInBackground: Bool
  }

  private struct PersistedState: Codable {
    var models: [String: ModelRecord]
  }

  private let stateQueue = DispatchQueue(label: "pro.affine.local-ai.manager")
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = 60
    configuration.timeoutIntervalForResource = 60 * 60 * 6
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  private var models: [String: ModelRecord] = [:]
  private var activeDownloads: [Int: String] = [:]

  override init() {
    super.init()
    loadPersistedState()
  }

  func currentState() throws -> StatePayload {
    try stateQueue.sync {
      let directory = try ensureModelDirectory()
      return StatePayload(
        models: models.values.sorted { $0.modelId < $1.modelId },
        modelDirectory: directory.path,
        runtimeAvailable: false,
        invocationAvailable: false,
        downloadResumableInBackground: false
      )
    }
  }

  func startDownload(
    modelId: String,
    version: String,
    downloadURL: String,
    expectedSha256: String?
  ) throws {
    try stateQueue.sync {
      _ = try ensureModelDirectory()

      if let existing = models[modelId], existing.status == "downloading" {
        return
      }

      guard let url = URL(string: downloadURL) else {
        throw NSError(
          domain: "LocalAIManager",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Invalid model download URL."]
        )
      }

      let task = session.downloadTask(with: url)
      models[modelId] = ModelRecord(
        modelId: modelId,
        version: version,
        status: "downloading",
        downloadURL: downloadURL,
        localPath: nil,
        expectedSha256: expectedSha256,
        bytesTotal: nil,
        bytesDownloaded: 0,
        progress: 0,
        lastError: nil,
        updatedAt: nowString()
      )
      activeDownloads[task.taskIdentifier] = modelId
      try persistState()
      task.resume()
    }
  }

  func cancelDownload(modelId: String) throws {
    try stateQueue.sync {
      guard let taskId = activeDownloads.first(where: { $0.value == modelId })?.key else {
        return
      }

      activeDownloads.removeValue(forKey: taskId)
      session.getAllTasks { tasks in
        tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
      }

      if var record = models[modelId] {
        record.status = "not-downloaded"
        record.bytesDownloaded = nil
        record.bytesTotal = nil
        record.progress = nil
        record.lastError = nil
        record.updatedAt = nowString()
        models[modelId] = record
      }

      try persistState()
    }
  }

  func deleteModel(modelId: String) throws {
    try stateQueue.sync {
      if let taskId = activeDownloads.first(where: { $0.value == modelId })?.key {
        activeDownloads.removeValue(forKey: taskId)
        session.getAllTasks { tasks in
          tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
        }
      }

      guard var record = models[modelId] else {
        return
      }

      record.status = "deleting"
      record.updatedAt = nowString()
      models[modelId] = record
      try persistState()

      if let localPath = record.localPath {
        let fileURL = URL(fileURLWithPath: localPath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
          try FileManager.default.removeItem(at: fileURL)
        }
      }

      models[modelId] = ModelRecord(
        modelId: modelId,
        version: record.version,
        status: "not-downloaded",
        downloadURL: record.downloadURL,
        localPath: nil,
        expectedSha256: record.expectedSha256,
        bytesTotal: nil,
        bytesDownloaded: nil,
        progress: nil,
        lastError: nil,
        updatedAt: nowString()
      )
      try persistState()
    }
  }

  private func finishDownload(taskIdentifier: Int, result: Result<URL, Error>) {
    stateQueue.async {
      guard let modelId = self.activeDownloads.removeValue(forKey: taskIdentifier),
            var record = self.models[modelId]
      else {
        return
      }

      do {
        switch result {
        case let .success(temporaryURL):
          let destinationURL = try self.finalModelURL(
            modelId: modelId,
            version: record.version
          )
          if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
          }
          try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
          try self.excludeFromBackup(destinationURL)

          if let expectedSha256 = record.expectedSha256 {
            let actualHash = try self.sha256(for: destinationURL)
            guard actualHash.caseInsensitiveCompare(expectedSha256) == .orderedSame else {
              try FileManager.default.removeItem(at: destinationURL)
              throw NSError(
                domain: "LocalAIManager",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Downloaded model checksum mismatch."]
              )
            }
          }

          record.status = "downloaded"
          record.localPath = destinationURL.path
          record.bytesDownloaded = record.bytesTotal
          record.progress = 1
          record.lastError = nil
        case let .failure(error):
          record.status = "failed"
          record.lastError = error.localizedDescription
        }
      } catch {
        record.status = "failed"
        record.lastError = error.localizedDescription
      }

      record.updatedAt = self.nowString()
      self.models[modelId] = record
      try? self.persistState()
    }
  }

  private func ensureLocalAIRootDirectory() throws -> URL {
    let appSupport = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = appSupport.appendingPathComponent("local-ai", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try excludeFromBackup(directory)
    return directory
  }

  private func ensureModelDirectory() throws -> URL {
    let directory = try ensureLocalAIRootDirectory()
      .appendingPathComponent("models", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try excludeFromBackup(directory)
    return directory
  }

  private func stateFileURL() throws -> URL {
    try ensureLocalAIRootDirectory().appendingPathComponent("state.json")
  }

  private func finalModelURL(modelId: String, version: String) throws -> URL {
    let safeModelId = modelId.replacingOccurrences(of: "/", with: "-")
    let safeVersion = version.replacingOccurrences(of: "/", with: "-")
    return try ensureModelDirectory()
      .appendingPathComponent("\(safeModelId)-\(safeVersion).gguf")
  }

  private func persistState() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(PersistedState(models: models))
    try data.write(to: stateFileURL(), options: .atomic)
  }

  private func loadPersistedState() {
    stateQueue.sync {
      do {
        let fileURL = try stateFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          models = [:]
          return
        }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        models = decoded.models
      } catch {
        models = [:]
      }
    }
  }

  private func excludeFromBackup(_ url: URL) throws {
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    var mutableURL = url
    try mutableURL.setResourceValues(resourceValues)
  }

  private func sha256(for fileURL: URL) throws -> String {
    let data = try Data(contentsOf: fileURL)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func nowString() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}

extension LocalAIManager: URLSessionDownloadDelegate {
  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    stateQueue.async {
      guard let modelId = self.activeDownloads[downloadTask.taskIdentifier],
            var record = self.models[modelId]
      else {
        return
      }

      record.bytesDownloaded = totalBytesWritten
      record.bytesTotal = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
      if totalBytesExpectedToWrite > 0 {
        record.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
      }
      record.updatedAt = self.nowString()
      self.models[modelId] = record
      try? self.persistState()
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    finishDownload(taskIdentifier: downloadTask.taskIdentifier, result: .success(location))
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else {
      return
    }
    finishDownload(taskIdentifier: task.taskIdentifier, result: .failure(error))
  }
}
