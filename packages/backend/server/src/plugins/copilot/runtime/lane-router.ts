import { Injectable } from '@nestjs/common';

export type CopilotExecutionLane = 'server' | 'local';

export type CopilotLaneSelection = {
  requestedExecutionLane?: CopilotExecutionLane;
  localCapable?: boolean;
};

export type CopilotLaneResolution = {
  executionLane: CopilotExecutionLane;
  localCapable: boolean;
  localRequested: boolean;
  localDeferred: boolean;
};

@Injectable()
export class CopilotLaneRouter {
  resolve(selection: CopilotLaneSelection = {}): CopilotLaneResolution {
    const localRequested = selection.requestedExecutionLane === 'local';
    const localCapable = !!selection.localCapable;

    return {
      executionLane: 'server',
      localCapable,
      localRequested,
      localDeferred: localRequested && localCapable,
    };
  }
}
