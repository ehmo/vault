(function () {
  const root = document.documentElement;
  const key = 'vaultaire-theme';
  const preferred = window.matchMedia('(prefers-color-scheme: dark)');
  const toggle = document.getElementById('theme-toggle');
  const icon = document.getElementById('theme-icon');
  const label = document.getElementById('theme-label');

  if (!toggle || !icon || !label) return;

  function setTheme(theme, persist) {
    const isDark = theme === 'dark';
    root.dataset.theme = isDark ? 'dark' : 'light';
    icon.textContent = isDark ? '☀︎' : '☽';
    label.textContent = isDark ? 'Light' : 'Dark';
    toggle.setAttribute('aria-pressed', String(!isDark));
    toggle.setAttribute('aria-label', `Switch to ${isDark ? 'light' : 'dark'} mode`);
    if (persist) localStorage.setItem(key, isDark ? 'dark' : 'light');

    window.dispatchEvent(new CustomEvent('vaultaire-themechange', {
      detail: { theme: isDark ? 'dark' : 'light', isDark }
    }));
  }

  const saved = localStorage.getItem(key);
  const hasUserOverride = saved === 'dark' || saved === 'light';
  setTheme(hasUserOverride ? saved : (preferred.matches ? 'dark' : 'light'), false);

  toggle.addEventListener('click', () => {
    setTheme(root.dataset.theme === 'dark' ? 'light' : 'dark', true);
  });

  preferred.addEventListener('change', (event) => {
    if (!localStorage.getItem(key)) {
      setTheme(event.matches ? 'dark' : 'light', false);
    }
  });

  window.VaultaireTheme = {
    getTheme() {
      return root.dataset.theme || 'dark';
    },
    setTheme(theme, persist) {
      setTheme(theme, persist !== false);
    }
  };
})();
