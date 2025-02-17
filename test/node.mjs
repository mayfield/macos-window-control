import test from 'node:test';
import assert from 'node:assert';
import * as mwc from '../js/index.mjs';


test('getZoom', () => {
    const r = mwc.getZoom();
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(typeof r.factor, 'number');
    assert.strictEqual(typeof r.smooth, 'boolean');
    assert.strictEqual(typeof r.center, 'object');
    assert.strictEqual(typeof r.center.x, 'number');
    assert.strictEqual(typeof r.center.y, 'number');
});

test('getZoom-noop-args', () => {
    let r = mwc.getZoom('unused');
    assert.strictEqual(typeof r, 'object');
    r = mwc.getZoom({unused: 'unused'});
    assert.strictEqual(typeof r, 'object');
});

test('resizeAppWindow-invalid-window', () => {
    assert.throws(
        () => mwc.resizeAppWindow({appName: 'nope-nada def not 123', size: [1, 1], position: [1, 1]}),
        {name: 'NotFoundError'}
    );
});

test('resizeAppWindow-bad-args', () => {
    assert.throws(() => mwc.resizeAppWindow(), {name: 'TypeError'});
    assert.throws(() => mwc.resizeAppWindow('asdf'), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow([]), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: 'nope nope no'}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: 1.234, size: [0, 0]}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: null, size: [0, 0]}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: {}, size: [0, 0]}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: undefined, size: [0, 0]}), {name: 'DecodingError'});
});

test('resizeAppWindow-Terminal', () => {
    assert.strictEqual(mwc.resizeAppWindow({appName: 'Terminal', size: [1000, 1000], position: [10, 20]}), undefined);
});

test('setZoom', () => {
    const r = mwc.setZoom({factor: 1});
    assert.strictEqual(r, undefined);
    mwc.setZoom({factor: 1, center: [0, 0]});
    try {
        mwc.setZoom({factor: 2});
    } finally {
        mwc.setZoom({factor: 1});
    }
    try {
        mwc.setZoom({factor: 2, center: [1000, 1000]});
    } finally {
        mwc.setZoom({factor: 1});
    }
});

test('setZoom-bad-args', () => {
    try {
        assert.throws(() => mwc.setZoom(), {name: 'TypeError'});
        assert.throws(() => mwc.setZoom('asdf'), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom([]), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: 'nope nope no'}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: undefined}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: null}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: 2, center: [false, 1.1]}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: 2, center: [1.1, true]}), {name: 'DecodingError'});
        assert.throws(() => mwc.setZoom({factor: 2, center: [1.1, 'asdf']}), {name: 'DecodingError'});
    } finally {
        mwc.setZoom({factor: 1})
    }
});

test('getMainScreenSize', () => {
    const r = mwc.getMainScreenSize();
    assert(Array.isArray(r));
    assert.strictEqual(r.length, 2);
    assert(r.every(x => typeof x === 'number'));
});

test('getMenuBarHeight', () => {
    const r = mwc.getMenuBarHeight();
    assert.strictEqual(typeof r, 'number');
});

test('getAppWindowSize', () => {
    const r = mwc.getAppWindowSize({appName: 'Terminal'});
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(Object.keys(r).length, 2);
    assert(Array.isArray(r.size));
    assert(Array.isArray(r.position));
    assert.strictEqual(r.size.length, 2);
    assert.strictEqual(r.position.length, 2);
    assert(r.size.every(x => typeof x === 'number'));
    assert(r.position.every(x => typeof x === 'number'));
});

test('getWindowApps', () => {
    const r = mwc.getWindowApps();
    assert(Array.isArray(r));
    assert(r.every(x => typeof x === 'object'));
    assert(r.every(x => typeof x.name === 'string'));
    assert(r.every(x => typeof x.pid === 'number'));
    assert(r.every(x => Array.isArray(x.windows)));
});

test('spiral', async () => {
    mwc.setZoom({factor: 1});
    const [width, height] = mwc.getMainScreenSize();
    const centerX = width / 2;
    const centerY = height / 2;
    const circleSize = (Math.min(width, height) / 2) * 0.5;
    const targetInterval = (1000 / 60) - 1;
    try {
        for (let i = 0; i < 1000; i++) {
            const factor = 2 - Math.cos(i / 40);
            const radius = (circleSize / factor) * (factor - 1);
            const center = [
                centerX + Math.cos(i / 8) * radius,
                centerY + Math.sin(i / 8) * radius
            ];
            mwc.setZoom({factor, center});
            await new Promise(r => setTimeout(r, targetInterval));
        }
    } finally {
        mwc.setZoom({factor: 1});
    }
});
