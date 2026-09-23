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

  // Map 1-10 levels to px/second: Level 1 ~ 20px/s, Level 10 ~ 200px/s
  function getSpeedPxPerSec(level) {
    const minSpeed = 20.0;
    const maxSpeed = 200.0;
    const clamped = Math.max(1, Math.min(10, level));
    return minSpeed + (maxSpeed - minSpeed) * ((clamped - 1) / 9.0);
  }

  function getScrollContainer() {
    try {
      if (typeof reader !== 'undefined' && reader && reader.view && reader.view.shadowRoot) {
        const paginator = reader.view.shadowRoot.querySelector('foliate-paginator');
        if (paginator && paginator.shadowRoot) {
          const container = paginator.shadowRoot.querySelector('#container');
          if (container) return container;
        }
      }
    } catch (e) {
      console.warn('Error getting scroll container:', e);
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

  function step(timestamp) {
    if (!isScrolling) return;

    if (!lastTimestamp) {
      lastTimestamp = timestamp;
    }
    const elapsedMs = timestamp - lastTimestamp;
    lastTimestamp = timestamp;

    if (!isPaused && !isTouching) {
      const container = getScrollContainer();
      if (container) {
        const pxPerSec = getSpeedPxPerSec(speedLevel);
        accumulatedDelta += (pxPerSec * elapsedMs) / 1000.0;

        if (accumulatedDelta >= 1.0) {
          const pixelsToScroll = Math.floor(accumulatedDelta);
          accumulatedDelta -= pixelsToScroll;
          container.scrollTop += pixelsToScroll;
        }
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
