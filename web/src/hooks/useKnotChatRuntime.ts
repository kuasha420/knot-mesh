import { useExternalStoreRuntime, type ThreadMessageLike } from '@assistant-ui/react';
import type { KnotChatMessage, NodeId } from '../types/knot';

interface UseKnotChatRuntimeProps {
  messages: KnotChatMessage[];
  onSendMessage: (content: string, targetNode?: NodeId | null, convId?: string) => Promise<void>;
  selectedTarget?: NodeId | null;
  activeConvId?: string;
  isRunning?: boolean;
}

export function useKnotChatRuntime({
  messages,
  onSendMessage,
  selectedTarget,
  activeConvId,
  isRunning = false,
}: UseKnotChatRuntimeProps) {
  return useExternalStoreRuntime({
    messages,
    isRunning,
    convertMessage: (msg: KnotChatMessage): ThreadMessageLike => {
      const isHuman =
        msg.sender_id.startsWith('human') ||
        msg.sender_id === 'user' ||
        msg.sender_id === 'operator';

      return {
        id: msg.id,
        role: isHuman ? 'user' : 'assistant',
        content: msg.content,
        createdAt: new Date(msg.timestamp * 1000),
        metadata: {
          custom: {
            sender_id: msg.sender_id,
            target_node: msg.target_node,
            channel: msg.channel,
            meta: msg.meta,
          },
        },
      };
    },
    onNew: async (message) => {
      const text = message.content
        .filter((part): part is { type: 'text'; text: string } => part.type === 'text')
        .map((p) => p.text)
        .join('\n');

      if (!text.trim()) return;
      await onSendMessage(text, selectedTarget, activeConvId);
    },
  });
}
