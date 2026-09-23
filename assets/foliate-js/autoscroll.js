// Auto-scroll controller for smooth continuous scrolling in Foliate-js
(function () {
  let isScrolling = false;
  let isPaused = false;
  let isTouching = false;
  let resumeTimer = null;
  let animFrameId = null;
  let speedLevel = 5; // 1 - 10
  let lastTimestamp = null;
  let accumulatedDelta = 0;

  // Map 1-10 levels to px/second: Level 1 ~ 20px/s, Level 10 ~ 220px/s
  function getSpeedPxPerSec(level) {
    const minSpeed = 20.0;
    const maxSpeed = 220.0;
    const clamped = Math.max(1, Math.min(10, level));
    return minSpeed + (maxSpeed - minSpeed) * ((clamped - 1) / 9.0);
  }

  function getScrollTarget() {
    try {
      const r = (typeof reader !== 'undefined' && reader) || globalThis.reader;
      const renderer = r?.view?.renderer;
      if (renderer) {
        const container = renderer.shadowRoot?.querySelector('#container');
        if (container) {
          return {
            container: container,
            renderer: renderer,
            scroll: (delta) => {
              if (typeof renderer.scrollBy === 'function') {
                renderer.scrollBy(0, delta);
              } else {
                container.scrollTop += delta;
              }
            },
            getScrollTop: () => container.scrollTop,
          };
        }
      }

      // Method 2: foliate-view elements directly in DOM
      const views = document.querySelectorAll('foliate-view');
      for (const v of views) {
        if (v.shadowRoot) {
          const p = v.shadowRoot.querySelector('foliate-paginator');
          if (p && p.shadowRoot) {
            const c = p.shadowRoot.querySelector('#container');
            if (c) {
              return {
                container: c,
                renderer: p,
                scroll: (delta) => {
                  if (typeof p.scrollBy === 'function') {
                    p.scrollBy(0, delta);
                  } else {
                    c.scrollTop += delta;
                  }
                },
                getScrollTop: () => c.scrollTop,
              };
            }
          }
        }
      }

      // Method 3: direct foliate-paginator
      const paginators = document.querySelectorAll('foliate-paginator');
      for (const p of paginators) {
        if (p.shadowRoot) {
          const c = p.shadowRoot.querySelector('#container');
          if (c) {
            return {
              container: c,
              renderer: p,
              scroll: (delta) => {
                if (typeof p.scrollBy === 'function') {
                  p.scrollBy(0, delta);
                } else {
                  c.scrollTop += delta;
                }
              },
              getScrollTop: () => c.scrollTop,
            };
          }
        }
      }

      // Method 4: fallback to document scrollingElement
      if (document.scrollingElement && document.scrollingElement.scrollHeight > window.innerHeight) {
        const el = document.scrollingElement;
        return {
          container: el,
          renderer: null,
          scroll: (delta) => {
            el.scrollTop += delta;
          },
          getScrollTop: () => el.scrollTop,
        };
      }
    } catch (e) {
      console.warn('[AutoScroll] Error finding scroll container:', e);
    }
    return null;
  }

  function notifyFlutterState() {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('onAutoScrollStateChanged', {
          isScrolling: isScrolling,
          isPaused: isPaused || isTouching,
          speedLevel: speedLevel,
        });
      }
    } catch (e) {}
  }

  function triggerNextPage() {
    try {
      if (typeof window.nextPage === 'function') {
        window.nextPage();
      } else if (globalThis.reader?.view?.next) {
        globalThis.reader.view.next();
      } else {
        const paginator = document.querySelector('foliate-view')?.shadowRoot?.querySelector('foliate-paginator');
        if (paginator && typeof paginator.next === 'function') {
          paginator.next();
        }
      }
    } catch (e) {
      console.warn('[AutoScroll] Error calling next page:', e);
    }
  }

  function step(timestamp) {
    if (!isScrolling) return;

    if (!lastTimestamp) {
      lastTimestamp = timestamp;
    }
    const elapsedMs = Math.min(100, timestamp - lastTimestamp); // cap at 100ms to avoid huge jump
    lastTimestamp = timestamp;

    if (!isPaused && !isTouching) {
      const target = getScrollTarget();
      if (target) {
        const pxPerSec = getSpeedPxPerSec(speedLevel);
        accumulatedDelta += (pxPerSec * elapsedMs) / 1000.0;

        if (accumulatedDelta >= 1.0) {
          const pixelsToScroll = Math.floor(accumulatedDelta);
          accumulatedDelta -= pixelsToScroll;

          const oldTop = target.getScrollTop();
          target.scroll(pixelsToScroll);
          const newTop = target.getScrollTop();

          // If reached bottom of current container/section in continuous scroll, trigger next page
          if (newTop === oldTop && pixelsToScroll > 0) {
            triggerNextPage();
          }
        }
      } else {
        // Fallback: window.scrollBy
        const pxPerSec = getSpeedPxPerSec(speedLevel);
        window.scrollBy(0, (pxPerSec * elapsedMs) / 1000.0);
      }
    }

    animFrameId = requestAnimationFrame(step);
  }

  function setupTouchListeners() {
    const handleTouchStart = () => {
      if (!isScrolling) return;
      isTouching = true;
      if (resumeTimer) {
        clearTimeout(resumeTimer);
        resumeTimer = null;
      }
      notifyFlutterState();
    };

    const handleTouchEnd = () => {
      if (!isScrolling) return;
      if (resumeTimer) clearTimeout(resumeTimer);
      // Wait 2.5 seconds after user lifts finger, then resume auto-scrolling
      resumeTimer = setTimeout(() => {
        isTouching = false;
        lastTimestamp = null;
        accumulatedDelta = 0;
        notifyFlutterState();
      }, 2500);
    };

    window.addEventListener('touchstart', handleTouchStart, { passive: true, capture: true });
    window.addEventListener('touchend', handleTouchEnd, { passive: true, capture: true });
    window.addEventListener('touchcancel', handleTouchEnd, { passive: true, capture: true });
    window.addEventListener('pointerdown', handleTouchStart, { passive: true, capture: true });
    window.addEventListener('pointerup', handleTouchEnd, { passive: true, capture: true });
  }

  window.startAutoScroll = function (level) {
    if (typeof level === 'number') {
      speedLevel = Math.max(1, Math.min(10, level));
    }
    isScrolling = true;
    isPaused = false;
    isTouching = false;
    lastTimestamp = null;
    accumulatedDelta = 0;
    if (resumeTimer) clearTimeout(resumeTimer);

    if (animFrameId) cancelAnimationFrame(animFrameId);
    animFrameId = requestAnimationFrame(step);
    notifyFlutterState();
  };

  window.stopAutoScroll = function () {
    isScrolling = false;
    isPaused = false;
    isTouching = false;
    if (resumeTimer) clearTimeout(resumeTimer);
    if (animFrameId) cancelAnimationFrame(animFrameId);
    animFrameId = null;
    lastTimestamp = null;
    accumulatedDelta = 0;
    notifyFlutterState();
  };

  window.pauseAutoScroll = function () {
    if (!isScrolling) return;
    isPaused = true;
    notifyFlutterState();
  };

  window.resumeAutoScroll = function () {
    if (!isScrolling) return;
    isPaused = false;
    isTouching = false;
    lastTimestamp = null;
    accumulatedDelta = 0;
    if (resumeTimer) clearTimeout(resumeTimer);
    notifyFlutterState();
  };

  window.toggleAutoScrollPause = function () {
    if (!isScrolling) return;
    if (isPaused || isTouching) {
      window.resumeAutoScroll();
    } else {
      window.pauseAutoScroll();
    }
  };

  window.setAutoScrollSpeed = function (level) {
    speedLevel = Math.max(1, Math.min(10, level));
    notifyFlutterState();
  };

  window.getAutoScrollState = function () {
    return {
      isScrolling: isScrolling,
      isPaused: isPaused || isTouching,
      speedLevel: speedLevel,
    };
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupTouchListeners);
  } else {
    setupTouchListeners();
  }
})();
