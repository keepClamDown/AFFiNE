import Capacitor
import Foundation

@objc(LocalAIPlugin)
public class LocalAIPlugin: CAPPlugin, CAPBridgedPlugin {
  private let manager = LocalAIManager.shared

  public let identifier = "LocalAIPlugin"
  public let jsName = "LocalAI"
  public let pluginMethods: [CAPPluginMethod] = [
    CAPPluginMethod(name: "getState", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "startDownload", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "cancelDownload", returnType: CAPPluginReturnPromise),
    CAPPluginMethod(name: "deleteModel", returnType: CAPPluginReturnPromise),
  ]

  @objc func getState(_ call: CAPPluginCall) {
    do {
      call.resolve(try stateDictionary())
    } catch {
      call.reject("Failed to read LocalAI state.", nil, error)
    }
  }

  @objc func startDownload(_ call: CAPPluginCall) {
    do {
      let modelId = try call.getStringEnsure("modelId")
      let downloadURL = try call.getStringEnsure("downloadURL")
      let version = call.getString("version") ?? "latest"
      let expectedSha256 = call.getString("expectedSha256")

      try manager.startDownload(
        modelId: modelId,
        version: version,
        downloadURL: downloadURL,
        expectedSha256: expectedSha256
      )

      call.resolve([
        "accepted": true,
        "state": try stateDictionary(),
      ])
    } catch {
      call.reject("Invalid LocalAI download request.", nil, error)
    }
  }

  @objc func cancelDownload(_ call: CAPPluginCall) {
    do {
      let modelId = try call.getStringEnsure("modelId")
      try manager.cancelDownload(modelId: modelId)
      call.resolve([
        "success": true,
        "state": try stateDictionary(),
      ])
    } catch {
      call.reject("Failed to cancel model download.", nil, error)
    }
  }

  @objc func deleteModel(_ call: CAPPluginCall) {
    do {
      let modelId = try call.getStringEnsure("modelId")
      try manager.deleteModel(modelId: modelId)
      call.resolve([
        "success": true,
        "state": try stateDictionary(),
      ])
    } catch {
      call.reject("Failed to delete local model.", nil, error)
    }
  }

  private func stateDictionary() throws -> [String: Any] {
    let state = try manager.currentState()
    let models = state.models.map { model in
      [
        "modelId": model.modelId,
        "version": model.version,
        "status": model.status,
        "downloadURL": model.downloadURL as Any,
        "localPath": model.localPath as Any,
        "expectedSha256": model.expectedSha256 as Any,
        "bytesTotal": model.bytesTotal as Any,
        "bytesDownloaded": model.bytesDownloaded as Any,
        "progress": model.progress as Any,
        "lastError": model.lastError as Any,
        "updatedAt": model.updatedAt,
      ]
    }

    return [
      "models": models,
      "modelDirectory": state.modelDirectory,
      "runtimeAvailable": state.runtimeAvailable,
      "invocationAvailable": state.invocationAvailable,
      "downloadResumableInBackground": state.downloadResumableInBackground,
    ]
  }
}
