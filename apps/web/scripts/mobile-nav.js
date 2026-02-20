/**
 * Mobile expanding navigation for Vaultaire.
 * Auto-injects hamburger button + expanding nav panel into <header>.
 * Include this script at the end of <body> on any page.
 */
(function () {
  'use strict';

  var header = document.querySelector('header');
  var navCta = header && header.querySelector('.nav-cta');
  if (!header || !navCta) return;

  // Determine path prefix from existing nav links
  var homeLink = header.querySelector('.nav-links a[href*="index.html"]');
  var prefix = '';
  if (homeLink) {
    var href = homeLink.getAttribute('href');
    var idx = href.indexOf('index.html');
    if (idx > 0) prefix = href.substring(0, idx);
  }

  // ── Hamburger button ──
  var btn = document.createElement('button');
  btn.className = 'mobile-menu-btn';
  btn.id = 'mobileMenuBtn';
  btn.type = 'button';
  btn.setAttribute('aria-label', 'Toggle navigation');
  btn.setAttribute('aria-expanded', 'false');
  btn.innerHTML =
    '<svg class="icon-menu" viewBox="0 0 24 24"><line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="17" x2="20" y2="17"/></svg>' +
    '<svg class="icon-close" viewBox="0 0 24 24"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>';
  navCta.appendChild(btn);

  // ── Expanding nav panel ──
  var panel = document.createElement('div');
  panel.className = 'mobile-nav-expand';
  panel.id = 'mobileNavExpand';

  var items = [
    { href: prefix + 'index.html#features', icon: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>', color: 'var(--accent, #CCC3F8)', title: 'Features', desc: 'Encryption, duress, privacy.' },
    { href: prefix + 'index.html#how-it-works', icon: '<circle cx="8" cy="8" r="2"/><circle cx="16" cy="8" r="2"/><circle cx="8" cy="16" r="2"/><circle cx="16" cy="16" r="2"/><line x1="10" y1="8" x2="14" y2="8"/><line x1="8" y1="10" x2="8" y2="14"/><line x1="16" y1="10" x2="16" y2="14"/>', color: '#57E37A', title: 'How it Works', desc: 'Pattern-based security.' },
    { href: prefix + 'index.html#security', icon: '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0110 0v4"/>', color: 'var(--highlight, #FF6F6F)', title: 'Security', desc: 'Zero-knowledge architecture.' },
    { href: prefix + 'manifesto/index.html', icon: '<path d="M2 3h6a4 4 0 014 4v14a3 3 0 00-3-3H2z"/><path d="M22 3h-6a4 4 0 00-4 4v14a3 3 0 013-3h7z"/>', color: '#60a5fa', title: 'Manifesto', desc: 'Why we built Vaultaire.' },
    { href: prefix + 'index.html#faq', icon: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 015.8 1c0 2-3 3-3 3"/><circle cx="12" cy="17" r="0.5" fill="#fbbf24"/>', color: '#fbbf24', title: 'FAQ', desc: 'Common questions.' },
    { href: prefix + 'compare/', icon: '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>', color: '#2dd4bf', title: 'Compare', desc: 'Vaultaire vs competitors.' }
  ];

  var html = '<div class="container"><nav class="mobile-nav-items">';
  items.forEach(function (item) {
    html +=
      '<a class="mobile-nav-item" href="' + item.href + '">' +
        '<div class="mobile-nav-icon"><svg viewBox="0 0 24 24" stroke="' + item.color + '">' + item.icon + '</svg></div>' +
        '<div class="mobile-nav-label"><div class="mobile-nav-label-title">' + item.title + '</div><div class="mobile-nav-label-desc">' + item.desc + '</div></div>' +
      '</a>';
  });
  html +=
    '<div class="mobile-nav-separator"></div>' +
    '<div class="mobile-nav-cta"><a href="https://apps.apple.com/app/vaultaire/id6740526623" class="btn btn-primary">Get App</a></div>' +
    '</nav></div>';

  panel.innerHTML = html;
  header.appendChild(panel);

  // ── Toggle logic ──
  var isOpen = false;

  function setNavHeight() {
    document.body.style.setProperty('--mobile-nav-h', isOpen ? panel.scrollHeight + 'px' : '0px');
  }

  function toggle() {
    isOpen = !isOpen;
    btn.classList.toggle('open', isOpen);
    btn.setAttribute('aria-expanded', String(isOpen));
    panel.classList.toggle('open', isOpen);
    document.body.classList.toggle('mobile-nav-open', isOpen);
    setNavHeight();
  }

  function close() {
    if (!isOpen) return;
    isOpen = false;
    btn.classList.remove('open');
    btn.setAttribute('aria-expanded', 'false');
    panel.classList.remove('open');
    document.body.classList.remove('mobile-nav-open');
    setNavHeight();
  }

  btn.addEventListener('click', toggle);

  panel.querySelectorAll('a').forEach(function (a) {
    a.addEventListener('click', close);
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') close();
  });
})();
