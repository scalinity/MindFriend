const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const html = fs.readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1])
  .find(source => source.includes('const motionPreference'));

function page(reduced, libraries = true) {
  class Element extends EventTarget {
    constructor() { super(); this.style = {}; this.dataset = { target: '50' }; this.textContent = '0'; }
    querySelector() { return this.span; }
    getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 40 }; }
    getAttribute() { return '#section'; }
    scrollIntoView(options) { this.scroll = options; }
  }
  const counter = new Element(), bar = new Element(), button = new Element(), orb = new Element();
  const tilt = new Element(), anchor = new Element(), destination = new Element();
  button.span = new Element();
  const document = new Element();
  document.readyState = 'complete';
  document.documentElement = { scrollTop: 0, scrollHeight: 1000, clientHeight: 500 };
  document.getElementById = () => new Element();
  const selectors = { '.counter, .level-counter': [counter], '.counter': [counter], '.xp-bar': [bar],
    '.magnetic-btn': [button], '.orb': [orb], '[data-tilt]': [tilt], 'a[href^="#"]': [anchor] };
  document.querySelectorAll = selector => selectors[selector] || [];
  document.querySelector = selector => selector === '#section' ? destination : null;
  let motions = 0, destroyed = 0, callback, cleanup;
  const preference = { matches: reduced };
  const gsap = {
    registerPlugin() {},
    matchMedia: () => ({ add(conditions, handler) { callback = handler; cleanup = handler({ conditions: { reduced: preference.matches } }); } }),
    timeline: () => ({ fromTo() { motions++; return this; } }),
    to() { motions++; }, fromTo() { motions++; }, set() {}, killTweensOf() {}, utils: { toArray: () => [] }
  };
  const ScrollTrigger = { create(config) { config.onEnter?.(); } };
  const VanillaTilt = { init(elements) { for (const element of elements) element.vanillaTilt = { destroy() { destroyed++; delete element.vanillaTilt; } }; } };
  const window = new Element();
  Object.assign(window, { matchMedia: () => preference, innerWidth: 1000, innerHeight: 800 });
  if (libraries) Object.assign(window, { gsap, ScrollTrigger, VanillaTilt });
  vm.runInNewContext(script, { window, document, gsap, ScrollTrigger, VanillaTilt, AbortController });
  function move() {
    for (const element of [document, button]) {
      const event = new Event('mousemove'); event.clientX = 50; event.clientY = 20;
      element.dispatchEvent(event);
    }
  }
  function setReduced(value) {
    cleanup?.(); preference.matches = value;
    cleanup = callback({ conditions: { reduced: value } });
  }
  function clickAnchor() { anchor.dispatchEvent(new Event('click', { cancelable: true })); }
  return { get motions() { return motions; }, get destroyed() { return destroyed; }, counter, bar, move, setReduced, clickAnchor, destination };
}

test('initial reduced motion creates no animation or pointer effects and shows final values', () => {
  const view = page(true);
  view.move(); assert.equal(view.motions, 0);
  assert.equal(view.counter.textContent, '50'); assert.equal(view.bar.style.width, '78%');
  view.clickAnchor(); assert.equal(view.destination.scroll.behavior, 'instant');
});

test('preference changes remove pointer listeners and destroy tilt, then reenable once', () => {
  const view = page(false);
  assert.ok(view.motions > 0);
  const beforeMove = view.motions; view.move(); assert.ok(view.motions > beforeMove);
  view.setReduced(true); assert.equal(view.destroyed, 1);
  const stopped = view.motions; view.move(); assert.equal(view.motions, stopped);
  view.setReduced(false);
  const restarted = view.motions; view.move(); assert.ok(view.motions > restarted);
  view.setReduced(true); assert.equal(view.destroyed, 2);
  const stoppedAgain = view.motions; view.move(); assert.equal(view.motions, stoppedAgain);
});

test('anchor navigation remains available without optional libraries', () => {
  const view = page(true, false); view.clickAnchor();
  assert.equal(view.destination.scroll.behavior, 'instant');
});
