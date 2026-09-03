/* Shared behaviour for comparison pages (/vs/*).
   External file (no inline handlers) so the pages work under CSP script-src 'self'. */

(function () {
  'use strict';

  var root = document.documentElement;

  function store(key, value) {
    try { localStorage.setItem(key, value); } catch (e) { /* private mode */ }
  }

  function restore(key) {
    try { return localStorage.getItem(key); } catch (e) { return null; }
  }

  /* ===== Theme: saved > browser preference > page default ===== */
  var savedTheme = restore('fara-theme');
  if (savedTheme) {
    root.setAttribute('data-theme', savedTheme);
  } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
    root.setAttribute('data-theme', 'light');
  }

  function toggleTheme() {
    var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    store('fara-theme', next);
  }

  /* ===== Language: saved > browser locale > ru ===== */
  function applyLang(lang) {
    root.setAttribute('data-lang', lang);
    var buttons = document.querySelectorAll('[data-lang-set]');
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].classList.toggle('active', buttons[i].getAttribute('data-lang-set') === lang);
    }
    var marketplace = document.querySelector('.topnav__link--mp');
    if (marketplace) {
      marketplace.setAttribute('data-soon', lang === 'ru' ? 'скоро' : 'soon');
    }
  }

  function setLang(lang) {
    applyLang(lang);
    store('fara-lang', lang);
  }

  var savedLang = restore('fara-lang');
  if (!savedLang) {
    var browserLang = (navigator.language || 'ru').slice(0, 2).toLowerCase();
    savedLang = browserLang === 'ru' ? 'ru' : 'en';
  }
  root.setAttribute('data-lang', savedLang);

  /* ===== Bindings (DOM is ready by now — script runs in <head>) ===== */
  document.addEventListener('DOMContentLoaded', function () {
    applyLang(root.getAttribute('data-lang') || 'ru');

    var toggle = document.querySelector('.theme-toggle');
    if (toggle) {
      toggle.addEventListener('click', toggleTheme);
      toggle.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          toggleTheme();
        }
      });
    }

    document.querySelectorAll('[data-lang-set]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        setLang(btn.getAttribute('data-lang-set'));
      });
    });

    var burger = document.querySelector('.topnav__burger');
    var links = document.querySelector('.topnav__links');
    if (burger && links) {
      burger.addEventListener('click', function () {
        links.classList.toggle('open');
      });
      links.addEventListener('click', function () {
        links.classList.remove('open');
      });
    }

    var reveals = document.querySelectorAll('.reveal');
    if (!('IntersectionObserver' in window)) {
      reveals.forEach(function (el) { el.classList.add('visible'); });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.05, rootMargin: '0px 0px -40px 0px' });
    reveals.forEach(function (el) { observer.observe(el); });
  });
})();
