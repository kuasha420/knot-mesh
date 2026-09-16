import type { SwarmModel } from '../types/knot';

export interface GroupedModelOption extends SwarmModel {
  shortLabel: string;
  depthLabel: string;
}

export interface ModelFamilyGroup {
  groupName: string;
  family: string;
  models: GroupedModelOption[];
}

/**
 * Groups models by their model family and thinking depth, matching native Antigravity IDE style.
 */
export function groupModelsByDepth(models: SwarmModel[]): ModelFamilyGroup[] {
  if (!models || models.length === 0) {
    return [];
  }

  const groups: ModelFamilyGroup[] = [
    { groupName: '⚡ Gemini 3.8 Flash', family: 'gemini-3.8', models: [] },
    { groupName: '⚡ Gemini 3.7 Flash', family: 'gemini-3.7', models: [] },
    { groupName: '⚡ Gemini 3.6 Flash', family: 'gemini-3.6', models: [] },
    { groupName: '🧠 Gemini 3.1 Pro', family: 'gemini-3.1', models: [] },
    { groupName: '🎭 Anthropic Claude', family: 'claude', models: [] },
    { groupName: '🌐 Open Source / Local', family: 'oss', models: [] },
  ];

  const others: GroupedModelOption[] = [];

  for (const m of models) {
    let depthLabel = 'Standard';
    if (m.id.includes('-high')) {
      depthLabel = 'High Thinking';
    } else if (m.id.includes('-medium')) {
      depthLabel = 'Medium Thinking';
    } else if (m.id.includes('-low')) {
      depthLabel = 'Low Thinking';
    } else if (m.id.includes('-thinking')) {
      depthLabel = 'Extended Thinking';
    }

    let shortLabel = m.name || m.id;

    if (m.id.startsWith('gemini-3.8-flash')) {
      shortLabel = `3.8 Flash • ${depthLabel}`;
      groups[0].models.push({ ...m, shortLabel, depthLabel });
    } else if (m.id.startsWith('gemini-3.7-flash')) {
      shortLabel = `3.7 Flash • ${depthLabel}`;
      groups[1].models.push({ ...m, shortLabel, depthLabel });
    } else if (m.id.startsWith('gemini-3.6-flash')) {
      shortLabel = `3.6 Flash • ${depthLabel}`;
      groups[2].models.push({ ...m, shortLabel, depthLabel });
    } else if (m.id.startsWith('gemini-3.1-pro')) {
      shortLabel = `3.1 Pro • ${depthLabel}`;
      groups[3].models.push({ ...m, shortLabel, depthLabel });
    } else if (m.id.includes('claude')) {
      shortLabel = m.id.includes('opus')
        ? 'Claude Opus 4.6 • Thinking'
        : 'Claude Sonnet 4.6 • Thinking';
      groups[4].models.push({ ...m, shortLabel, depthLabel: 'Thinking' });
    } else if (m.id.includes('gpt-oss')) {
      shortLabel = 'GPT-OSS 120B • Medium';
      groups[5].models.push({ ...m, shortLabel, depthLabel: 'Medium Thinking' });
    } else {
      others.push({ ...m, shortLabel, depthLabel });
    }
  }

  const result = groups.filter((g) => g.models.length > 0);
  if (others.length > 0) {
    result.push({
      groupName: '✨ Custom / Other Models',
      family: 'custom',
      models: others,
    });
  }

  return result;
}
