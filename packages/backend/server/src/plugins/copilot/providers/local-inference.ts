import { Injectable } from '@nestjs/common';

import type { CopilotExecutionLane } from '../runtime/lane-router';

export type LocalInferenceResolution = {
  requestedExecutionLane?: CopilotExecutionLane;
  resolvedExecutionLane: 'server';
  localCapable: boolean;
  deferred: boolean;
};

@Injectable()
export class LocalInferenceProvider {
  resolve(options: {
    requestedExecutionLane?: CopilotExecutionLane;
    localCapable?: boolean;
  }): LocalInferenceResolution {
    const localCapable = !!options.localCapable;
    const requestedExecutionLane = options.requestedExecutionLane;

    return {
      requestedExecutionLane,
      resolvedExecutionLane: 'server',
      localCapable,
      deferred: requestedExecutionLane === 'local' && localCapable,
    };
  }
}
