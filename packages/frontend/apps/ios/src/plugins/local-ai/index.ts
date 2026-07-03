import { registerPlugin } from '@capacitor/core';

import type { LocalAIPlugin } from './definitions';

const LocalAI = registerPlugin<LocalAIPlugin>('LocalAI');

export * from './definitions';
export { LocalAI };
