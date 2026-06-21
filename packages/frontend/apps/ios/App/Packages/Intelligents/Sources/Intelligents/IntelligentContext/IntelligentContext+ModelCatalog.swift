import AffineGraphQL
import ApolloAPI
import Foundation

extension IntelligentContext {
  struct IntelligentModelCatalog: Codable {
    struct Model: Codable, Hashable {
      let id: String
      let name: String
      let category: String
      let version: String
      let provider: String?
      let providerLabel: String?
      let deploymentKind: String
      let executionLane: String
      let privacyState: String
      let localCapable: Bool
      let appleLocalInferenceState: String
      let isPro: Bool
      let isDefault: Bool
    }

    struct Provider: Codable, Hashable {
      let provider: String
      let label: String
      let capabilities: [String]
      let executionLane: String
      let privacyState: String
      let localCapable: Bool
      let appleLocalInferenceState: String
      let allowed: Bool
      let customEndpointSupported: Bool
    }

    struct Warning: Codable, Hashable {
      let featureKind: String
      let reason: String
      let requiredProviders: [String]
    }

    let selectedModelId: String?
    let defaultModelId: String?
    let models: [Model]
    let providers: [Provider]
    let warnings: [Warning]

    func model(for selectedModelId: String?) -> Model? {
      if let selectedModelId {
        return models.first(where: { $0.id == selectedModelId }) ?? defaultModel
      }
      return defaultModel
    }

    var defaultModel: Model? {
      models.first(where: { $0.isDefault })
    }

    func badgeTitle(for selectedModelId: String?) -> String? {
      guard let model = model(for: selectedModelId) else {
        return nil
      }
      let laneTitle = displayTitle(forExecutionLane: model.executionLane)
      let privacyTitle = displayTitle(forPrivacyState: model.privacyState)
      let suffix = laneTitle == privacyTitle
        ? laneTitle
        : "\(laneTitle) · \(privacyTitle)"
      guard let providerLabel = model.providerLabel else {
        return "\(model.name) · \(suffix)"
      }
      return "\(providerLabel) • \(model.name) · \(suffix)"
    }
  }

  var currentModelCatalog: IntelligentModelCatalog? {
    qlMetadata[.modelCatalogKey] as? IntelligentModelCatalog
  }

  static func buildModelCatalog(
    promptModels: GetPromptModelsQuery.Data.CurrentUser.Copilot.Models?,
    byokSettings: WorkspaceByokSettingsQuery.Data.Workspace.ByokSettings?,
    selectedModelId: String?
  ) -> IntelligentModelCatalog? {
    guard promptModels != nil || byokSettings != nil else {
      return nil
    }

    let optionalModels: [GetPromptModelsQuery.Data.CurrentUser.Copilot.Models.OptionalModel] =
      promptModels?.optionalModels ?? []
    let proModels: [GetPromptModelsQuery.Data.CurrentUser.Copilot.Models.ProModel] =
      promptModels?.proModels ?? []
    let proModelIds = Set(proModels.map { $0.id })
    let defaultModelId = promptModels?.defaultModel
    let configuredProviders: Set<String> = Set(
      (byokSettings?.keys ?? []).compactMap { key in
        guard key.configured, key.enabled else {
          return nil
        }
        return providerRawValue(key.provider)
      }
    )
    var models = [IntelligentModelCatalog.Model]()
    models.reserveCapacity(optionalModels.count)

    for model in optionalModels {
      let provider = inferProvider(from: model.id, name: model.name)
      let providerDetails = provider.flatMap { providerInfo(for: $0) }
      let (category, version) = splitModelName(model.name, fallbackId: model.id)

      let privacyState = provider.map {
        configuredProviders.contains($0) ? "cloud_private" : "cloud"
      } ?? "cloud"

      models.append(
        IntelligentModelCatalog.Model(
          id: model.id,
          name: model.name,
          category: category,
          version: version,
          provider: provider,
          providerLabel: providerDetails?.label,
          deploymentKind: "server",
          executionLane: "server",
          privacyState: privacyState,
          localCapable: providerDetails?.localCapable ?? false,
          appleLocalInferenceState: providerDetails?.appleLocalInferenceState ?? "not_applicable",
          isPro: proModelIds.contains(model.id),
          isDefault: model.id == defaultModelId
        )
      )
    }

    let allowedProviders = Set((byokSettings?.allowedProviders ?? []).map(providerRawValue))
    let customEndpointSupported = byokSettings?.customEndpointSupported ?? false
    let providerOrder = ["openai", "anthropic", "gemini", "fal", "glm", "gemma"]
    let providers = providerOrder.compactMap { provider -> IntelligentModelCatalog.Provider? in
      guard let info = providerInfo(for: provider) else {
        return nil
      }
      return IntelligentModelCatalog.Provider(
        provider: provider,
        label: info.label,
        capabilities: info.capabilities,
        executionLane: "server",
        privacyState: configuredProviders.contains(provider) ? "cloud_private" : "cloud",
        localCapable: info.localCapable,
        appleLocalInferenceState: info.appleLocalInferenceState,
        allowed: allowedProviders.isEmpty || allowedProviders.contains(provider),
        customEndpointSupported: customEndpointSupported
      )
    }
    let warnings = (byokSettings?.warnings ?? []).map { warning in
      IntelligentModelCatalog.Warning(
        featureKind: warning.featureKind,
        reason: warning.reason,
        requiredProviders: warning.requiredProviders.map(providerRawValue)
      )
    }

    return IntelligentModelCatalog(
      selectedModelId: selectedModelId ?? defaultModelId,
      defaultModelId: defaultModelId,
      models: models,
      providers: providers,
      warnings: warnings
    )
  }

  private static func splitModelName(
    _ name: String,
    fallbackId: String
  ) -> (String, String) {
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = normalizedName.isEmpty ? fallbackId : normalizedName

    guard let firstSpace = source.firstIndex(of: " ") else {
      return (source, "")
    }

    return (
      String(source[..<firstSpace]),
      String(source[source.index(after: firstSpace)...])
    )
  }

  private static func inferProvider(from modelId: String, name: String) -> String? {
    let candidate = "\(modelId) \(name)".lowercased()

    if candidate.contains("glm") {
      return "glm"
    }
    if candidate.contains("gemma") {
      return "gemma"
    }
    if candidate.contains("gemini") {
      return "gemini"
    }
    if candidate.contains("claude") {
      return "anthropic"
    }
    if candidate.contains("fal") {
      return "fal"
    }
    if candidate.contains("gpt") ||
      candidate.contains("chatgpt") ||
      candidate.contains("text-embedding") ||
      candidate.contains("o1") ||
      candidate.contains("o3") ||
      candidate.contains("o4") ||
      candidate.contains("omni") {
      return "openai"
    }

    return nil
  }

  private static func providerInfo(
    for provider: String
  ) -> (
    label: String,
    capabilities: [String],
    localCapable: Bool,
    appleLocalInferenceState: String
  )? {
    switch provider {
    case "openai":
      return ("OpenAI", ["Text", "Image input", "Actions", "Image generate"], false, "not_applicable")
    case "anthropic":
      return ("Anthropic", ["Text", "Image input"], false, "not_applicable")
    case "gemini":
      return (
        "Gemini",
        ["Text", "Image input", "Actions", "Image generate", "Transcript", "Indexing"],
        false,
        "not_applicable"
      )
    case "fal":
      return ("FAL", ["Image generate"], false, "not_applicable")
    case "glm":
      return ("GLM 5.2", ["Text", "Image input", "Actions"], false, "not_applicable")
    case "gemma":
      return ("Gemma", ["Text", "Image input"], true, "deferred_candidate")
    default:
      return nil
    }
  }

  private static func displayTitle(forExecutionLane executionLane: String) -> String {
    switch executionLane {
    case "local":
      return "Local"
    default:
      return "Cloud"
    }
  }

  private static func displayTitle(forPrivacyState privacyState: String) -> String {
    switch privacyState {
    case "cloud_private":
      return "Cloud private"
    case "local_private":
      return "Local private"
    default:
      return "Cloud"
    }
  }

  private static func providerRawValue(
    _ provider: GraphQLEnum<AffineGraphQL.ByokProvider>
  ) -> String {
    switch provider {
    case .case(.anthropic):
      return "anthropic"
    case .case(.fal):
      return "fal"
    case .case(.gemini):
      return "gemini"
    case .case(.gemma):
      return "gemma"
    case .case(.glm):
      return "glm"
    case .case(.openai):
      return "openai"
    case let .unknown(rawValue):
      return rawValue
    }
  }
}
