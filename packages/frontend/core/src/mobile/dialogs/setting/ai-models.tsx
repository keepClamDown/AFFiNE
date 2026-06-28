import { WorkspaceServerService } from '@affine/core/modules/cloud';
import { WorkspaceService } from '@affine/core/modules/workspace';
import {
  getPromptModelsQuery,
  workspaceByokSettingsQuery,
} from '@affine/graphql';
import { useService } from '@toeverything/infra';
import { useEffect, useState } from 'react';

import {
  buildAIModelCatalogSnapshot,
  executionLaneTitle,
  privacyStateTitle,
  providerLabels,
} from '../../../modules/ai-button/services/catalog';
import { SettingGroup } from './group';
import { RowLayout } from './row.layout';

const PROMPT_NAME = 'Chat With AFFiNE AI';

type AISettingsState = {
  modelTitle: string;
  executionLane: string;
  privacyState: string;
  localCapability: string;
  providerAccess: string;
};

function emptyState(message: string): AISettingsState {
  return {
    modelTitle: message,
    executionLane: 'Cloud',
    privacyState: 'Cloud',
    localCapability: 'Unavailable',
    providerAccess: 'Unavailable',
  };
}

export const AIModelsGroup = () => {
  const workspace = useService(WorkspaceService).workspace;
  const workspaceServer = useService(WorkspaceServerService);
  const [state, setState] = useState<AISettingsState>(emptyState('Loading…'));

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      if (!workspaceServer.server) {
        if (!cancelled) {
          setState(emptyState('Cloud workspace required'));
        }
        return;
      }

      const to = new Date();
      const from = new Date(to.getTime() - 30 * 24 * 60 * 60 * 1000);
      const gql = workspaceServer.server.gql;
      const [promptData, byokData] = await Promise.all([
        gql({
          query: getPromptModelsQuery,
          variables: { promptName: PROMPT_NAME },
        }),
        gql({
          query: workspaceByokSettingsQuery,
          variables: {
            id: workspace.id,
            from: from.toISOString(),
            to: to.toISOString(),
          },
        }),
      ]);

      const snapshot = buildAIModelCatalogSnapshot({
        promptModels: promptData.currentUser?.copilot?.models ?? null,
        byokSettings: byokData.workspace?.byokSettings ?? null,
      });
      const selectedModel = snapshot.selectedModel ?? snapshot.defaultModel;
      const allowedProviders = snapshot.providers
        .filter(provider => provider.allowed)
        .map(provider => {
          const privacy = privacyStateTitle(provider.privacyState);
          return `${providerLabels[provider.provider]} (${privacy})`;
        });

      if (!cancelled) {
        setState({
          modelTitle: selectedModel
            ? selectedModel.providerLabel
              ? `${selectedModel.providerLabel} • ${selectedModel.name}`
              : selectedModel.name
            : 'Unavailable',
          executionLane: selectedModel
            ? executionLaneTitle(selectedModel.executionLane)
            : 'Cloud',
          privacyState: selectedModel
            ? privacyStateTitle(selectedModel.privacyState)
            : 'Cloud',
          localCapability: selectedModel?.localCapable
            ? 'Deferred candidate (v2)'
            : 'Unavailable',
          providerAccess: allowedProviders.length
            ? allowedProviders.join(', ')
            : 'No providers allowed',
        });
      }
    };

    load().catch(() => {
      if (!cancelled) {
        setState(emptyState('Unavailable'));
      }
    });

    return () => {
      cancelled = true;
    };
  }, [workspace.id, workspaceServer.server]);

  return (
    <SettingGroup title="AI Models & Provider Access">
      <RowLayout label="Current model">{state.modelTitle}</RowLayout>
      <RowLayout label="Execution lane">{state.executionLane}</RowLayout>
      <RowLayout label="Privacy state">{state.privacyState}</RowLayout>
      <RowLayout label="Apple local inference">
        {state.localCapability}
      </RowLayout>
      <RowLayout label="Allowed providers">{state.providerAccess}</RowLayout>
    </SettingGroup>
  );
};
