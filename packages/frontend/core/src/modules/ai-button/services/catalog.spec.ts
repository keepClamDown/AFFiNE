import { ByokKeyStorage, ByokProvider } from '@affine/graphql';
import { describe, expect, test } from 'vitest';

import {
  buildAIModelCatalogSnapshot,
  capabilitiesFor,
  inferProviderFromModel,
  providerLabels,
  toAIModelCatalogItem,
} from './catalog';

describe('ai model catalog helpers', () => {
  test('infers GLM and Gemma providers from model identifiers', () => {
    expect(inferProviderFromModel('glm-4.5')).toBe(ByokProvider.glm);
    expect(inferProviderFromModel('gemma-3-27b-it')).toBe(ByokProvider.gemma);
  });

  test('exposes shared provider labels and capabilities for new providers', () => {
    expect(providerLabels[ByokProvider.glm]).toBe('GLM 5.2');
    expect(providerLabels[ByokProvider.gemma]).toBe('Gemma');
    expect(capabilitiesFor(ByokProvider.glm, ByokKeyStorage.server)).toEqual([
      'Text',
      'Image input',
      'Actions',
    ]);
    expect(capabilitiesFor(ByokProvider.gemma, ByokKeyStorage.server)).toEqual([
      'Text',
      'Image input',
    ]);
  });

  test('marks Gemma as deferred Apple local inference candidate', () => {
    const gemma = toAIModelCatalogItem({
      id: 'gemma-3-27b-it',
      name: 'Gemma 3 27B',
    });

    expect(gemma.appleLocalInferenceState).toBe('deferred_candidate');
    expect(gemma.localCapable).toBe(true);
    expect(gemma.executionLane).toBe('server');
  });

  test('marks configured BYOK providers as cloud private in the snapshot', () => {
    const snapshot = buildAIModelCatalogSnapshot({
      promptModels: {
        defaultModel: 'glm-4.5',
        optionalModels: [{ id: 'glm-4.5', name: 'GLM 4.5' }],
        proModels: [],
      },
      byokSettings: {
        allowedProviders: [ByokProvider.glm],
        keys: [{ provider: ByokProvider.glm, configured: true, enabled: true }],
      },
    });

    expect(snapshot.selectedModel?.privacyState).toBe('cloud_private');
    expect(
      snapshot.providers.find(item => item.provider === ByokProvider.glm)
        ?.privacyState
    ).toBe('cloud_private');
  });

  test('builds a shared snapshot from prompt models and BYOK settings', () => {
    const snapshot = buildAIModelCatalogSnapshot({
      selectedModelId: 'glm-4.5',
      promptModels: {
        defaultModel: 'gemma-3-27b-it',
        optionalModels: [
          { id: 'glm-4.5', name: 'GLM 4.5' },
          { id: 'gemma-3-27b-it', name: 'Gemma 3 27B' },
        ],
        proModels: [{ id: 'glm-4.5', name: 'GLM 4.5' }],
      },
      byokSettings: {
        allowedProviders: [ByokProvider.glm, ByokProvider.gemma],
        customEndpointSupported: true,
        keys: [{ provider: ByokProvider.glm, configured: true, enabled: true }],
        warnings: [
          {
            featureKind: 'workspace_indexing',
            reason: 'Requires server Gemini key',
            requiredProviders: [ByokProvider.gemini],
          },
        ],
      },
    });

    expect(snapshot.selectedModel?.provider).toBe(ByokProvider.glm);
    expect(snapshot.selectedModel?.privacyState).toBe('cloud_private');
    expect(snapshot.defaultModel?.provider).toBe(ByokProvider.gemma);
    expect(
      snapshot.providers.find(item => item.provider === ByokProvider.glm)
    ).toMatchObject({
      allowed: true,
      customEndpointSupported: true,
    });
    expect(snapshot.warnings).toEqual([
      {
        featureKind: 'workspace_indexing',
        reason: 'Requires server Gemini key',
        requiredProviders: [ByokProvider.gemini],
      },
    ]);
  });
});
