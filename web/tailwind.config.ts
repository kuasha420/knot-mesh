import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        night: {
          bg: '#16161e',
          panel: '#1a1b26',
          surface: '#24283b',
          border: '#292e42',
          blue: '#7aa2f7',
          cyan: '#7dcfff',
          green: '#9ece6a',
          orange: '#ff9e64',
          magenta: '#bb9af7',
          red: '#f7768e',
          yellow: '#e0af68',
          muted: '#565f89',
          text: '#c0caf5',
        },
      },
      fontFamily: {
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
    },
  },
  plugins: [],
} satisfies Config;
