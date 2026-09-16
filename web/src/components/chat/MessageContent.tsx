import React, { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';
import 'katex/dist/katex.min.css';
import Prism from 'prismjs';
import 'prismjs/components/prism-bash';
import 'prismjs/components/prism-python';
import 'prismjs/components/prism-javascript';
import 'prismjs/components/prism-typescript';
import 'prismjs/components/prism-json';
import 'prismjs/components/prism-yaml';
import 'prismjs/components/prism-sql';
import 'prismjs/components/prism-markdown';
import {
  Check,
  Copy,
  ExternalLink,
  Laptop,
  Monitor,
  Gamepad2,
  Sparkles,
  Bot,
} from 'lucide-react';

interface MessageContentProps {
  content: string;
  meta?: Record<string, unknown>;
}

// Helper to render inline node mention tags
function renderTextWithMentions(text: string): React.ReactNode {
  const mentionRegex = /(@desktop|@laptop|@steamdeck|@swarm|@all)\b/g;
  const parts = text.split(mentionRegex);

  if (parts.length === 1) return text;

  return parts.map((part, index) => {
    if (part === '@desktop') {
      return (
        <span
          key={index}
          className="inline-flex items-center gap-1 px-1.5 py-0.2 mx-0.5 rounded text-[11px] font-mono font-semibold bg-night-magenta/15 text-night-magenta border border-night-magenta/30"
        >
          <Monitor className="w-2.5 h-2.5" />
          @desktop
        </span>
      );
    }
    if (part === '@laptop') {
      return (
        <span
          key={index}
          className="inline-flex items-center gap-1 px-1.5 py-0.2 mx-0.5 rounded text-[11px] font-mono font-semibold bg-night-cyan/15 text-night-cyan border border-night-cyan/30"
        >
          <Laptop className="w-2.5 h-2.5" />
          @laptop
        </span>
      );
    }
    if (part === '@steamdeck') {
      return (
        <span
          key={index}
          className="inline-flex items-center gap-1 px-1.5 py-0.2 mx-0.5 rounded text-[11px] font-mono font-semibold bg-night-orange/15 text-night-orange border border-night-orange/30"
        >
          <Gamepad2 className="w-2.5 h-2.5" />
          @steamdeck
        </span>
      );
    }
    if (part === '@swarm' || part === '@all') {
      return (
        <span
          key={index}
          className="inline-flex items-center gap-1 px-1.5 py-0.2 mx-0.5 rounded text-[11px] font-mono font-semibold bg-night-yellow/15 text-night-yellow border border-night-yellow/30"
        >
          <Sparkles className="w-2.5 h-2.5" />
          {part}
        </span>
      );
    }
    return part;
  });
}

// Code block with syntax highlighting and copy button
const CodeBlock: React.FC<{
  language: string;
  code: string;
}> = ({ language, code }) => {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
    }
  };

  const cleanLang = language.replace(/^language-/, '').toLowerCase() || 'text';
  let highlightedHtml = '';
  try {
    const grammar = Prism.languages[cleanLang] || Prism.languages.text;
    highlightedHtml = Prism.highlight(code, grammar, cleanLang);
  } catch {
    highlightedHtml = '';
  }

  const lineCount = code.split('\n').length;

  return (
    <div className="my-2.5 rounded-lg border border-night-border/80 bg-night-bg overflow-hidden shadow-md">
      {/* Code Header Bar */}
      <div className="flex items-center justify-between px-3 py-1.5 bg-night-panel/90 border-b border-night-border/70 text-[10px] font-mono">
        <div className="flex items-center space-x-2">
          {/* Terminal Dots */}
          <div className="flex items-center space-x-1">
            <span className="w-2 h-2 rounded-full bg-night-red/80 inline-block" />
            <span className="w-2 h-2 rounded-full bg-night-yellow/80 inline-block" />
            <span className="w-2 h-2 rounded-full bg-night-green/80 inline-block" />
          </div>
          <span className="text-night-cyan font-bold uppercase tracking-wider pl-1">
            {cleanLang}
          </span>
          <span className="text-night-muted">({lineCount} {lineCount === 1 ? 'line' : 'lines'})</span>
        </div>

        <button
          onClick={handleCopy}
          className="flex items-center gap-1 px-2 py-0.5 rounded text-night-muted hover:text-night-text hover:bg-night-surface/60 transition-colors"
          title="Copy code to clipboard"
        >
          {copied ? (
            <>
              <Check className="w-3 h-3 text-night-green" />
              <span className="text-night-green font-semibold">Copied!</span>
            </>
          ) : (
            <>
              <Copy className="w-3 h-3" />
              <span>Copy</span>
            </>
          )}
        </button>
      </div>

      {/* Code Content */}
      <pre className="p-3 text-[11px] font-mono leading-relaxed overflow-x-auto selection:bg-night-blue/30">
        {highlightedHtml ? (
          <code
            dangerouslySetInnerHTML={{ __html: highlightedHtml }}
            className={`language-${cleanLang}`}
          />
        ) : (
          <code>{code}</code>
        )}
      </pre>
    </div>
  );
};

export const MessageContent: React.FC<MessageContentProps> = ({ content, meta }) => {
  return (
    <div className="text-xs leading-relaxed space-y-2">
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[rehypeKatex]}
        components={{
          // Custom Code Renderer
          code({ className, children, ...props }) {
            const isInline = !className && typeof children === 'string' && !children.includes('\n');
            const codeString = String(children || '').replace(/\n$/, '');

            if (isInline) {
              return (
                <code
                  className="px-1.5 py-0.5 rounded text-[11px] font-mono bg-night-surface/90 text-night-cyan border border-night-cyan/30 font-medium"
                  {...props}
                >
                  {children}
                </code>
              );
            }

            const match = /language-(\w+)/.exec(className || '');
            const lang = match ? match[1] : '';

            return <CodeBlock language={lang} code={codeString} />;
          },

          // Custom Paragraph with mention chip highlighting
          p({ children }) {
            if (typeof children === 'string') {
              return <p className="mb-2 leading-relaxed">{renderTextWithMentions(children)}</p>;
            }
            // If children is an array or React elements
            return (
              <p className="mb-2 leading-relaxed">
                {React.Children.map(children, (child) => {
                  if (typeof child === 'string') {
                    return renderTextWithMentions(child);
                  }
                  return child;
                })}
              </p>
            );
          },

          // Custom Link with conversation:// deep link styling
          a({ href, children }) {
            const url = href || '';
            if (url.startsWith('conversation://')) {
              const sessionId = url.replace('conversation://', '');
              return (
                <a
                  href={url}
                  title="Click to focus conversation transcript in Antigravity Desktop App / IDE"
                  className="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-night-surface/90 hover:bg-night-surface border border-night-cyan/50 text-night-cyan font-bold transition-all shadow-sm hover:shadow-night-cyan/20"
                >
                  <Bot className="w-3 h-3 text-night-cyan" />
                  <span>session: {sessionId.slice(0, 8)}...</span>
                  <ExternalLink className="w-2.5 h-2.5 text-night-cyan/70 ml-0.5" />
                </a>
              );
            }

            return (
              <a
                href={url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-0.5 text-night-blue hover:text-night-cyan underline decoration-night-blue/40 hover:decoration-night-cyan transition-colors"
              >
                <span>{children}</span>
                <ExternalLink className="w-2.5 h-2.5 inline-block opacity-70" />
              </a>
            );
          },

          // Headings
          h1: ({ children }) => (
            <h1 className="text-sm font-bold text-night-cyan border-b border-night-border/70 pb-1 mt-3 mb-1.5">
              {children}
            </h1>
          ),
          h2: ({ children }) => (
            <h2 className="text-xs font-bold text-night-blue border-b border-night-border/40 pb-0.5 mt-2.5 mb-1">
              {children}
            </h2>
          ),
          h3: ({ children }) => (
            <h3 className="text-xs font-semibold text-night-magenta mt-2 mb-1">{children}</h3>
          ),

          // Lists
          ul: ({ children }) => <ul className="list-disc pl-4 space-y-1 mb-2 text-night-text/95">{children}</ul>,
          ol: ({ children }) => <ol className="list-decimal pl-4 space-y-1 mb-2 text-night-text/95">{children}</ol>,
          li: ({ children }) => (
            <li className="pl-0.5">
              {React.Children.map(children, (child) => {
                if (typeof child === 'string') {
                  return renderTextWithMentions(child);
                }
                return child;
              })}
            </li>
          ),

          // Blockquotes
          blockquote: ({ children }) => (
            <blockquote className="border-l-2 border-night-blue/70 bg-night-surface/40 px-3 py-1.5 my-2 rounded-r italic text-night-text/90">
              {children}
            </blockquote>
          ),

          // Tables
          table: ({ children }) => (
            <div className="overflow-x-auto my-2 rounded-lg border border-night-border">
              <table className="min-w-full divide-y divide-night-border text-left">{children}</table>
            </div>
          ),
          thead: ({ children }) => <thead className="bg-night-surface/90 text-night-cyan font-bold">{children}</thead>,
          tbody: ({ children }) => <tbody className="divide-y divide-night-border/50 bg-night-panel/60">{children}</tbody>,
          tr: ({ children }) => <tr className="hover:bg-night-surface/40 transition-colors">{children}</tr>,
          th: ({ children }) => <th className="px-3 py-1.5 text-[10px] uppercase font-mono">{children}</th>,
          td: ({ children }) => <td className="px-3 py-1 text-[11px] font-mono">{children}</td>,
        }}
      >
        {content}
      </ReactMarkdown>

      {/* Explicit Session Deep Link Footer if meta provides session_id */}
      {(() => {
        const sessionId = meta?.session_id ? String(meta.session_id) : null;
        const duration = typeof meta?.duration_seconds === 'number' ? meta.duration_seconds : null;
        const tokens = typeof meta?.tokens_used === 'number' ? meta.tokens_used : null;

        if (!sessionId) return null;

        return (
          <div className="mt-2 pt-2 border-t border-night-border/40 flex flex-wrap items-center gap-2 text-[10px] font-mono">
            <a
              href={`conversation://${sessionId}`}
              title="Open native Antigravity conversation session"
              className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded bg-night-surface/90 hover:bg-night-surface border border-night-cyan/40 text-night-cyan font-bold transition-all shadow-sm hover:border-night-cyan"
            >
              <Bot className="w-3.5 h-3.5 text-night-cyan" />
              <span>native session: {sessionId.slice(0, 8)}...</span>
              <ExternalLink className="w-3 h-3 text-night-cyan/70" />
            </a>
            {duration !== null && (
              <span className="text-night-muted bg-night-surface/40 px-2 py-0.5 rounded border border-night-border/50">
                ⏱ {duration}s
              </span>
            )}
            {tokens !== null && (
              <span className="text-night-muted bg-night-surface/40 px-2 py-0.5 rounded border border-night-border/50">
                ⚡ {tokens.toLocaleString()} tok
              </span>
            )}
          </div>
        );
      })()}
    </div>
  );
};
