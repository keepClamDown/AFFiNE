export interface LocalAIModelDescriptor {
  modelId: string;
  version: string;
  status:
    | 'not-downloaded'
    | 'downloading'
    | 'downloaded'
    | 'failed'
    | 'deleting';
  downloadURL?: string;
  localPath?: string;
  expectedSha256?: string;
  bytesTotal?: number;
  bytesDownloaded?: number;
  progress?: number;
  lastError?: string;
  updatedAt: string;
}

export interface LocalAIState {
  models: LocalAIModelDescriptor[];
  modelDirectory: string;
  runtimeAvailable: boolean;
  invocationAvailable: boolean;
  downloadResumableInBackground: boolean;
}

export interface LocalAIPlugin {
  getState(): Promise<LocalAIState>;
  startDownload(options: {
    modelId: string;
    version?: string;
    downloadURL: string;
    expectedSha256?: string;
  }): Promise<{ accepted: boolean; state: LocalAIState }>;
  cancelDownload(options: { modelId: string }): Promise<{
    success: boolean;
    state: LocalAIState;
  }>;
  deleteModel(options: { modelId: string }): Promise<{
    success: boolean;
    state: LocalAIState;
  }>;
}
