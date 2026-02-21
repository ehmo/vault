(() => {
  const APPLE_STORE_URL = "https://apps.apple.com/app/vaultaire/id6758529311";
  const COMPARE_ICON_FALLBACK = "/assets/compare-fallback-icon.svg";
  const APP_STORE_ICON_HOST = /is1-ssl\.mzstatic\.com/;

  function toRgba(hex, alpha) {
    const normalized = (hex || "").replace("#", "").trim();
    const fullHex = normalized.length === 3
      ? normalized.split("").map((ch) => ch + ch).join("")
      : normalized;

    if (!/^[0-9a-fA-F]{6}$/.test(fullHex)) {
      return `rgba(204, 195, 248, ${alpha})`;
    }

    const r = parseInt(fullHex.slice(0, 2), 16);
    const g = parseInt(fullHex.slice(2, 4), 16);
    const b = parseInt(fullHex.slice(4, 6), 16);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }

  function setElementText(element, value) {
    if (element) element.textContent = value;
  }

  function shouldHandleCompetitorImage(img) {
    return img instanceof HTMLImageElement
      && (img.hasAttribute("data-competitor-icon")
        || APP_STORE_ICON_HOST.test(img.currentSrc || img.src || ""));
  }

  document.addEventListener("alpine:init", () => {
    Alpine.data("vaultaireApp", () => ({
      theme: "dark",
      _initialized: false,
      _cleanupCallbacks: [],
      _aborted: false,
      _homeRuntime: null,

      get isDark() {
        return this.theme === "dark";
      },

      get themeIcon() {
        return this.isDark ? "☀︎" : "☽";
      },

      get themeLabel() {
        return this.isDark ? "Light" : "Dark";
      },

      get themeAriaLabel() {
        return `Switch to ${this.isDark ? "light" : "dark"} mode`;
      },

      init() {
        if (this._initialized) return;
        this._initialized = true;
        this._registerPagehideCleanup();
        this._initTheme();
        this._initCompareIconFallback();
        this._initMobileNav();
        this._initInvitePage();
        this._initHomePage();
      },

      destroy() {
        if (this._aborted) return;
        this._aborted = true;
        while (this._cleanupCallbacks.length) {
          const fn = this._cleanupCallbacks.pop();
          try {
            fn();
          } catch (_) {
            // no-op
          }
        }
      },

      _pushCleanup(fn) {
        this._cleanupCallbacks.push(fn);
      },

      _registerPagehideCleanup() {
        const onPageHide = (event) => {
          if (event.persisted) {
            if (this._homeRuntime && typeof this._homeRuntime.pause === "function") {
              this._homeRuntime.pause();
            }
            return;
          }
          this.destroy();
        };

        window.addEventListener("pagehide", onPageHide);
        this._pushCleanup(() => window.removeEventListener("pagehide", onPageHide));
      },

      _initTheme() {
        const root = document.documentElement;
        const toggle = document.getElementById("theme-toggle");
        const icon = document.getElementById("theme-icon");
        const label = document.getElementById("theme-label");
        const preferred = window.matchMedia("(prefers-color-scheme: dark)");
        const key = "vaultaire-theme";
        const readTheme = () => {
          try {
            return localStorage.getItem(key);
          } catch (_) {
            return null;
          }
        };
        const writeTheme = (value) => {
          try {
            localStorage.setItem(key, value);
          } catch (_) {
            // no-op (private mode / blocked storage)
          }
        };

        const applyTheme = (theme, persist) => {
          this.theme = theme === "light" ? "light" : "dark";
          root.dataset.theme = this.theme;
          if (persist) {
            writeTheme(this.theme);
          }

          const isDark = this.theme === "dark";
          if (toggle) {
            toggle.setAttribute("aria-pressed", String(!isDark));
            toggle.setAttribute("aria-label", this.themeAriaLabel);
          }
          setElementText(icon, this.themeIcon);
          setElementText(label, this.themeLabel);

          window.dispatchEvent(new CustomEvent("vaultaire-themechange", {
            detail: { theme: this.theme, isDark }
          }));
        };

        const saved = readTheme();
        const hasOverride = saved === "dark" || saved === "light";
        applyTheme(hasOverride ? saved : (preferred.matches ? "dark" : "light"), false);

        const onToggleClick = () => {
          applyTheme(this.isDark ? "light" : "dark", true);
        };

        const onPreferredChange = (event) => {
          if (!readTheme()) {
            applyTheme(event.matches ? "dark" : "light", false);
          }
        };

        if (toggle) {
          toggle.addEventListener("click", onToggleClick);
          this._pushCleanup(() => toggle.removeEventListener("click", onToggleClick));
        }

        if (typeof preferred.addEventListener === "function") {
          preferred.addEventListener("change", onPreferredChange);
          this._pushCleanup(() => preferred.removeEventListener("change", onPreferredChange));
        } else if (typeof preferred.addListener === "function") {
          preferred.addListener(onPreferredChange);
          this._pushCleanup(() => preferred.removeListener(onPreferredChange));
        }
      },

      _initCompareIconFallback() {
        const onImageError = (event) => {
          const img = event.target;
          if (!shouldHandleCompetitorImage(img)) return;
          if (img.dataset.fallbackApplied === "1") return;
          img.dataset.fallbackApplied = "1";
          img.src = COMPARE_ICON_FALLBACK;
        };

        document.addEventListener("error", onImageError, true);
        this._pushCleanup(() => document.removeEventListener("error", onImageError, true));
      },

      _initMobileNav() {
        const header = document.querySelector("header");
        const navCta = header && header.querySelector(".nav-cta");
        if (!header || !navCta || header.querySelector("#mobileMenuBtn")) return;

        const homeLink = header.querySelector('.nav-links a[href*="index.html"]');
        let prefix = "";
        if (homeLink) {
          const href = homeLink.getAttribute("href") || "";
          const idx = href.indexOf("index.html");
          if (idx > 0) prefix = href.substring(0, idx);
        }

        const btn = document.createElement("button");
        btn.className = "mobile-menu-btn";
        btn.id = "mobileMenuBtn";
        btn.type = "button";
        btn.setAttribute("aria-label", "Toggle navigation");
        btn.setAttribute("aria-expanded", "false");
        btn.innerHTML =
          '<svg class="icon-menu" viewBox="0 0 24 24"><line x1="4" y1="7" x2="20" y2="7"/><line x1="4" y1="17" x2="20" y2="17"/></svg>' +
          '<svg class="icon-close" viewBox="0 0 24 24"><line x1="6" y1="6" x2="18" y2="18"/><line x1="18" y1="6" x2="6" y2="18"/></svg>';
        navCta.appendChild(btn);

        const panel = document.createElement("div");
        panel.className = "mobile-nav-expand";
        panel.id = "mobileNavExpand";

        const items = [
          { href: `${prefix}index.html#features`, icon: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>', color: "var(--accent, #CCC3F8)", title: "Features", desc: "Encryption, duress, privacy." },
          { href: `${prefix}index.html#how-it-works`, icon: '<circle cx="8" cy="8" r="2"/><circle cx="16" cy="8" r="2"/><circle cx="8" cy="16" r="2"/><circle cx="16" cy="16" r="2"/><line x1="10" y1="8" x2="14" y2="8"/><line x1="8" y1="10" x2="8" y2="14"/><line x1="16" y1="10" x2="16" y2="14"/>', color: "#2FA14A", title: "How it Works", desc: "Pattern-based security." },
          { href: `${prefix}index.html#security`, icon: '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0110 0v4"/>', color: "#D55454", title: "Security", desc: "Zero-knowledge architecture." },
          { href: `${prefix}manifesto/index.html`, icon: '<path d="M2 3h6a4 4 0 014 4v14a3 3 0 00-3-3H2z"/><path d="M22 3h-6a4 4 0 00-4 4v14a3 3 0 013-3h7z"/>', color: "#467CE6", title: "Manifesto", desc: "Why we built Vaultaire." },
          { href: `${prefix}index.html#faq`, icon: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 015.8 1c0 2-3 3-3 3"/><circle cx="12" cy="17" r="0.5" fill="#C98700"/>', color: "#C98700", title: "FAQ", desc: "Common questions." },
          { href: `${prefix}compare/`, icon: '<line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>', color: "#1DA694", title: "Compare", desc: "Vaultaire vs competitors." }
        ];

        let html = '<div class="container"><nav class="mobile-nav-items">';
        items.forEach((item) => {
          html +=
            `<a class="mobile-nav-item" href="${item.href}">` +
              `<div class="mobile-nav-icon"><svg viewBox="0 0 24 24" stroke="${item.color}">${item.icon}</svg></div>` +
              `<div class="mobile-nav-label"><div class="mobile-nav-label-title">${item.title}</div><div class="mobile-nav-label-desc">${item.desc}</div></div>` +
            "</a>";
        });
        html +=
          '<div class="mobile-nav-separator"></div>' +
          `<div class="mobile-nav-cta"><a href="${APPLE_STORE_URL}" class="btn btn-primary">Get App</a></div>` +
          "</nav></div>";
        panel.innerHTML = html;
        header.appendChild(panel);

        let isOpen = false;
        const setNavHeight = () => {
          document.body.style.setProperty("--mobile-nav-h", isOpen ? `${panel.scrollHeight}px` : "0px");
        };
        const close = () => {
          if (!isOpen) return;
          isOpen = false;
          btn.classList.remove("open");
          btn.setAttribute("aria-expanded", "false");
          panel.classList.remove("open");
          document.body.classList.remove("mobile-nav-open");
          setNavHeight();
        };
        const toggle = () => {
          isOpen = !isOpen;
          btn.classList.toggle("open", isOpen);
          btn.setAttribute("aria-expanded", String(isOpen));
          panel.classList.toggle("open", isOpen);
          document.body.classList.toggle("mobile-nav-open", isOpen);
          setNavHeight();
        };
        const onKeydown = (event) => {
          if (event.key === "Escape") close();
        };

        btn.addEventListener("click", toggle);
        panel.querySelectorAll("a").forEach((a) => a.addEventListener("click", close));
        document.addEventListener("keydown", onKeydown);

        this._pushCleanup(() => {
          btn.removeEventListener("click", toggle);
          document.removeEventListener("keydown", onKeydown);
          panel.querySelectorAll("a").forEach((a) => a.removeEventListener("click", close));
          panel.remove();
          btn.remove();
          document.body.classList.remove("mobile-nav-open");
          document.body.style.removeProperty("--mobile-nav-h");
        });
      },

      _initInvitePage() {
        const openInAppButton = document.getElementById("open-in-app");
        if (!openInAppButton) return;

        const darkHero = document.getElementById("hero-logo-dark");
        const lightHero = document.getElementById("hero-logo-light");

        const buildUniversalInviteUrl = () => {
          const url = new URL(window.location.href);
          url.protocol = "https:";
          url.host = "vaultaire.app";
          if (url.pathname === "/s/index.html") url.pathname = "/s";
          url.searchParams.set("open_in_app", String(Date.now()));
          return url.toString();
        };

        const buildCustomSchemeInviteUrl = () => {
          const token = window.location.hash ? window.location.hash.slice(1) : "";
          if (!token) return "vaultaire://s";
          return `vaultaire://s?p=${encodeURIComponent(token)}#${token}`;
        };

        const syncHeroLogo = (isDark) => {
          if (darkHero) darkHero.style.display = isDark ? "block" : "none";
          if (lightHero) lightHero.style.display = isDark ? "none" : "block";
        };

        const onThemeChange = (event) => {
          syncHeroLogo(Boolean(event.detail && event.detail.isDark));
        };

        openInAppButton.href = buildCustomSchemeInviteUrl();
        const onOpenClick = (event) => {
          event.preventDefault();
          const fallbackUrl = buildUniversalInviteUrl();
          const schemeUrl = buildCustomSchemeInviteUrl();

          const onVisibilityChange = () => {
            if (document.visibilityState === "hidden") {
              window.clearTimeout(fallbackTimer);
              document.removeEventListener("visibilitychange", onVisibilityChange);
            }
          };

          document.addEventListener("visibilitychange", onVisibilityChange);
          const fallbackTimer = window.setTimeout(() => {
            document.removeEventListener("visibilitychange", onVisibilityChange);
            if (document.visibilityState === "visible") {
              window.location.assign(fallbackUrl);
            }
          }, 900);
          this._pushCleanup(() => window.clearTimeout(fallbackTimer));

          window.location.assign(schemeUrl);
        };

        syncHeroLogo(this.isDark);
        openInAppButton.addEventListener("click", onOpenClick);
        window.addEventListener("vaultaire-themechange", onThemeChange);

        this._pushCleanup(() => {
          openInAppButton.removeEventListener("click", onOpenClick);
          window.removeEventListener("vaultaire-themechange", onThemeChange);
        });
      },

      _initHomePage() {
        const canvas = document.getElementById("pattern-canvas");
        const pathEl = document.getElementById("drawing-path");
        const cursorEl = document.getElementById("drawing-cursor");
        const svgEl = document.getElementById("mockup-svg");
        const lockZone = document.getElementById("pattern-lock-zone");
        const phoneScreen = document.querySelector(".phone-screen");
        const dots = Array.from(document.querySelectorAll(".grid-dot"));
        const mockupTimeEl = document.getElementById("mockup-time");

        if (!canvas || !pathEl || !cursorEl || !svgEl || !lockZone || !phoneScreen || dots.length === 0 || !mockupTimeEl) {
          return;
        }

        const ctx = canvas.getContext("2d");
        if (!ctx) return;

        const runtime = {
          disposed: false,
          heroVisible: true,
          width: 0,
          height: 0,
          bgDots: [],
          accentColor: "#CCC3F8",
          accentTrailColor: "rgba(204, 195, 248, 0.4)",
          drawingPath: false,
          drawingResetTimerId: 0,
          drawRafId: 0,
          minuteTimerId: 0,
          sequenceIndex: 0,
          nodeCenters: [],
          patternLoopTicket: 0,
          patternLoopRunning: false,
          timeoutIds: new Set(),
          sequences: [[0, 5, 6, 7, 12, 17, 16, 15, 20, 21, 22, 23, 24]]
        };

        let resizeRafId = 0;

        const scheduleTimeout = (fn, ms) => {
          const id = window.setTimeout(() => {
            runtime.timeoutIds.delete(id);
            if (!runtime.disposed) fn();
          }, ms);
          runtime.timeoutIds.add(id);
          return id;
        };

        const clearScheduledTimeout = (id) => {
          if (!id) return;
          window.clearTimeout(id);
          runtime.timeoutIds.delete(id);
        };

        const clearAllTimeouts = () => {
          runtime.timeoutIds.forEach((id) => window.clearTimeout(id));
          runtime.timeoutIds.clear();
          runtime.drawingResetTimerId = 0;
          runtime.minuteTimerId = 0;
        };

        const updateCanvasTheme = () => {
          const styles = getComputedStyle(document.documentElement);
          runtime.accentColor = styles.getPropertyValue("--accent-dark").trim() || "#CCC3F8";
          runtime.accentTrailColor = toRgba(runtime.accentColor, 0.35);
        };

        const initDots = () => {
          runtime.bgDots = [];
          const spacing = 110;
          const rows = Math.ceil(runtime.height / spacing);
          const cols = Math.ceil(runtime.width / spacing);
          for (let i = 0; i < cols; i += 1) {
            for (let j = 0; j < rows; j += 1) {
              runtime.bgDots.push({
                x: i * spacing + (Math.random() * 24),
                y: j * spacing + (Math.random() * 24)
              });
            }
          }
        };

        const resize = () => {
          if (runtime.disposed) return;
          runtime.width = canvas.width = canvas.parentElement.offsetWidth;
          runtime.height = canvas.height = canvas.parentElement.offsetHeight;
          initDots();
        };

        const scheduleResize = () => {
          if (runtime.disposed || resizeRafId) return;
          resizeRafId = window.requestAnimationFrame(() => {
            resizeRafId = 0;
            if (!runtime.disposed) {
              resize();
            }
          });
        };

        const drawRandomPattern = () => {
          if (runtime.drawingPath || runtime.bgDots.length === 0 || runtime.disposed || document.hidden || !runtime.heroVisible) return;
          runtime.drawingPath = true;

          const startIndex = Math.floor(Math.random() * runtime.bgDots.length);
          const pathLength = 4 + Math.floor(Math.random() * 3);
          const start = runtime.bgDots[startIndex];
          let current = start;

          ctx.strokeStyle = runtime.accentTrailColor;
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.moveTo(start.x, start.y);

          for (let i = 0; i < pathLength; i += 1) {
            const next = runtime.bgDots[Math.floor(Math.random() * runtime.bgDots.length)];
            const dist = Math.hypot(next.x - current.x, next.y - current.y);
            if (dist < 200 && dist > 36) {
              ctx.lineTo(next.x, next.y);
              current = next;
            }
          }
          ctx.stroke();

          clearScheduledTimeout(runtime.drawingResetTimerId);
          runtime.drawingResetTimerId = scheduleTimeout(() => {
            runtime.drawingPath = false;
            runtime.drawingResetTimerId = 0;
          }, 540);
        };

        const draw = () => {
          if (runtime.disposed || document.hidden || !runtime.heroVisible) {
            runtime.drawRafId = 0;
            return;
          }

          ctx.clearRect(0, 0, runtime.width, runtime.height);
          ctx.fillStyle = runtime.accentColor;
          runtime.bgDots.forEach((dot) => {
            ctx.beginPath();
            ctx.arc(dot.x, dot.y, 1.4, 0, Math.PI * 2);
            ctx.fill();
          });

          if (Math.random() > 0.95) drawRandomPattern();
          runtime.drawRafId = window.requestAnimationFrame(draw);
        };

        const startDrawLoop = () => {
          if (runtime.disposed || document.hidden || !runtime.heroVisible || runtime.drawRafId) return;
          runtime.drawRafId = window.requestAnimationFrame(draw);
        };

        const stopDrawLoop = () => {
          if (!runtime.drawRafId) return;
          window.cancelAnimationFrame(runtime.drawRafId);
          runtime.drawRafId = 0;
        };

        const updateMockupTime = () => {
          const now = new Date();
          const hour = ((now.getHours() + 11) % 12) + 1;
          const minute = String(now.getMinutes()).padStart(2, "0");
          mockupTimeEl.textContent = `${hour}:${minute}`;
        };

        const scheduleMinuteTick = () => {
          if (runtime.disposed || document.hidden || !runtime.heroVisible) return;
          updateMockupTime();
          const now = new Date();
          const msUntilNextMinute = ((60 - now.getSeconds()) * 1000) - now.getMilliseconds();
          clearScheduledTimeout(runtime.minuteTimerId);
          runtime.minuteTimerId = scheduleTimeout(() => {
            runtime.minuteTimerId = 0;
            scheduleMinuteTick();
          }, Math.max(200, msUntilNextMinute));
        };

        const computeNodeCenters = () => {
          const baseRect = lockZone.getBoundingClientRect();
          svgEl.setAttribute("viewBox", `0 0 ${baseRect.width} ${baseRect.height}`);
          svgEl.setAttribute("width", `${baseRect.width}`);
          svgEl.setAttribute("height", `${baseRect.height}`);
          runtime.nodeCenters = dots.map((dot) => {
            const rect = dot.getBoundingClientRect();
            return {
              x: rect.left - baseRect.left + (rect.width / 2),
              y: rect.top - baseRect.top + (rect.height / 2)
            };
          });
        };

        const setPath = (points) => {
          if (points.length === 0) {
            pathEl.setAttribute("d", "");
            cursorEl.style.opacity = "0";
            return;
          }
          const commands = points.map((point, idx) => `${idx === 0 ? "M" : "L"} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`);
          pathEl.setAttribute("d", commands.join(" "));
          const tail = points[points.length - 1];
          cursorEl.setAttribute("cx", tail.x.toFixed(2));
          cursorEl.setAttribute("cy", tail.y.toFixed(2));
          cursorEl.style.opacity = "1";
        };

        const sleep = (ms, ticket) => new Promise((resolve) => {
          scheduleTimeout(() => resolve(!runtime.disposed && !document.hidden && runtime.heroVisible && ticket === runtime.patternLoopTicket), ms);
        });

        const animateSegment = (stablePoints, fromPoint, toPoint, durationMs, ticket) => new Promise((resolve) => {
          const startedAt = performance.now();
          const tick = (now) => {
            if (runtime.disposed || document.hidden || !runtime.heroVisible || ticket !== runtime.patternLoopTicket) {
              resolve(false);
              return;
            }
            const progress = Math.min(1, (now - startedAt) / durationMs);
            const x = fromPoint.x + ((toPoint.x - fromPoint.x) * progress);
            const y = fromPoint.y + ((toPoint.y - fromPoint.y) * progress);
            setPath([...stablePoints, { x, y }]);
            if (progress < 1) {
              window.requestAnimationFrame(tick);
            } else {
              resolve(true);
            }
          };
          window.requestAnimationFrame(tick);
        });

        const runSequence = async (sequence, ticket) => {
          dots.forEach((dot) => dot.classList.remove("active"));
          setPath([]);
          const points = [];
          computeNodeCenters();
          if (!(await sleep(250, ticket))) return false;
          if (sequence.length === 0) return true;

          const firstNode = sequence[0];
          dots[firstNode].classList.add("active");
          points.push(runtime.nodeCenters[firstNode]);
          setPath(points);

          for (let i = 1; i < sequence.length; i += 1) {
            const prevPoint = runtime.nodeCenters[sequence[i - 1]];
            const nextPoint = runtime.nodeCenters[sequence[i]];
            const stablePoints = points.slice(0);
            const segmentOk = await animateSegment(stablePoints, prevPoint, nextPoint, 170, ticket);
            if (!segmentOk) return false;
            dots[sequence[i]].classList.add("active");
            points.push(nextPoint);
            setPath(points);
          }

          if (!(await sleep(220, ticket))) return false;
          phoneScreen.classList.add("mockup-unlocking");
          if (!(await sleep(980, ticket))) return false;
          phoneScreen.classList.remove("mockup-unlocking");
          phoneScreen.classList.add("mockup-vault");
          if (!(await sleep(5000, ticket))) return false;
          phoneScreen.classList.remove("mockup-vault");

          dots.forEach((dot) => dot.classList.remove("active"));
          setPath([]);
          return sleep(430, ticket);
        };

        const animatePatternLoop = async (ticket) => {
          if (!(await sleep(700, ticket))) return;
          while (!runtime.disposed && !document.hidden && runtime.heroVisible && ticket === runtime.patternLoopTicket) {
            const sequence = runtime.sequences[runtime.sequenceIndex];
            const ok = await runSequence(sequence, ticket);
            if (!ok) break;
            runtime.sequenceIndex = (runtime.sequenceIndex + 1) % runtime.sequences.length;
          }
          if (ticket === runtime.patternLoopTicket) {
            runtime.patternLoopRunning = false;
          }
        };

        const startPatternLoop = () => {
          if (runtime.disposed || document.hidden || !runtime.heroVisible || runtime.patternLoopRunning) return;
          runtime.patternLoopRunning = true;
          runtime.patternLoopTicket += 1;
          animatePatternLoop(runtime.patternLoopTicket).catch(() => {
            runtime.patternLoopRunning = false;
          });
        };

        const stopPatternLoop = () => {
          runtime.patternLoopTicket += 1;
          runtime.patternLoopRunning = false;
          dots.forEach((dot) => dot.classList.remove("active"));
          setPath([]);
          phoneScreen.classList.remove("mockup-unlocking");
          phoneScreen.classList.remove("mockup-vault");
        };

        const pause = () => {
          stopDrawLoop();
          stopPatternLoop();
          clearScheduledTimeout(runtime.minuteTimerId);
          runtime.minuteTimerId = 0;
          clearScheduledTimeout(runtime.drawingResetTimerId);
          runtime.drawingResetTimerId = 0;
          runtime.drawingPath = false;
        };

        const resume = () => {
          if (runtime.disposed || document.hidden || !runtime.heroVisible) return;
          resize();
          updateCanvasTheme();
          startDrawLoop();
          scheduleMinuteTick();
          startPatternLoop();
        };

        const dispose = () => {
          if (runtime.disposed) return;
          runtime.disposed = true;
          pause();
          clearAllTimeouts();
        };

        const onVisibility = () => {
          if (document.hidden || !runtime.heroVisible) {
            pause();
          } else {
            resume();
          }
        };

        const onThemeChange = () => {
          updateCanvasTheme();
        };

        const heroSection = document.querySelector(".hero");
        let heroObserver = null;

        if (heroSection && typeof IntersectionObserver !== "undefined") {
          heroObserver = new IntersectionObserver((entries) => {
            const entry = entries[0];
            runtime.heroVisible = Boolean(entry && entry.isIntersecting);
            if (runtime.heroVisible && !document.hidden) {
              resume();
            } else {
              pause();
            }
          }, { threshold: 0.05 });
          heroObserver.observe(heroSection);
        } else {
          runtime.heroVisible = true;
        }

        document.addEventListener("visibilitychange", onVisibility);
        window.addEventListener("pageshow", resume);
        window.addEventListener("vaultaire-themechange", onThemeChange);
        window.addEventListener("resize", scheduleResize);

        this._pushCleanup(() => {
          document.removeEventListener("visibilitychange", onVisibility);
          window.removeEventListener("pageshow", resume);
          window.removeEventListener("vaultaire-themechange", onThemeChange);
          window.removeEventListener("resize", scheduleResize);
          if (resizeRafId) {
            window.cancelAnimationFrame(resizeRafId);
            resizeRafId = 0;
          }
          if (heroObserver) {
            heroObserver.disconnect();
            heroObserver = null;
          }
          dispose();
        });

        this._homeRuntime = { pause, resume, dispose };
        resume();
      }
    }));
  });
})();
