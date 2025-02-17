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
        () => mwc.resizeAppWindow({appName: 'nope-nada def not 123', width: 1, height: 1, x: 1, y: 1}),
        {name: 'NotFoundError'}
    );
});

test('resizeAppWindow-bad-args', () => {
    assert.throws(() => mwc.resizeAppWindow(), {name: 'TypeError'});
    assert.throws(() => mwc.resizeAppWindow('asdf'), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow([]), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: 'nope nope no'}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: 1.234, width: 0, height: 0}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: null, width: 0, height: 0}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: {}, width: 0, height: 0}), {name: 'DecodingError'});
    assert.throws(() => mwc.resizeAppWindow({appName: undefined, width: 0, height: 0}), {name: 'DecodingError'});
});

test('resizeAppWindow-Terminal', () => {
    assert.strictEqual(mwc.resizeAppWindow({appName: 'Terminal', width: 1000, height: 1000, x: 10, y: 20}), undefined);
});

test('setZoom', () => {
    const r = mwc.setZoom({factor: 1, cx: 0, cy: 0});
    assert.strictEqual(r, undefined);
});

test('setZoom-bad-args', () => {
    assert.throws(() => mwc.setZoom(), {name: 'TypeError'});
    assert.throws(() => mwc.setZoom('asdf'), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom([]), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: 'nope nope no'}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: 1.234}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: undefined}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: null}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: 2, cx: false, cy: 1.1}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: 2, cx: 1.1, cy: true}), {name: 'DecodingError'});
    assert.throws(() => mwc.setZoom({factor: 2, cx: 1.1, cy: 'asdf'}), {name: 'DecodingError'});
});

test('getMainScreenSize', () => {
    const r = mwc.getMainScreenSize();
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(Object.keys(r).length, 2);
    assert.strictEqual(typeof r.width, 'number');
    assert.strictEqual(typeof r.height, 'number');
});

test('getAppWindowSize', () => {
    const r = mwc.getAppWindowSize({appName: 'Terminal'});
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(Object.keys(r).length, 4);
    assert.strictEqual(typeof r.width, 'number');
    assert.strictEqual(typeof r.height, 'number');
    assert.strictEqual(typeof r.x, 'number');
    assert.strictEqual(typeof r.y, 'number');
});

test('getWindowApps', () => {
    const r = mwc.getWindowApps();
    assert(Array.isArray(r));
});

test('spiral', async () => {
    return;
    mwc.setZoom({factor: 1, cx: 0, cy: 0});
    const {width, height} = mwc.getMainScreenSize();
    const centerX = width / 2;
    const centerY = height / 2;
    const circleSize = (Math.min(width, height) / 2) * 0.5;
    const targetInterval = (1000 / 60) - 1;
    try {
        for (let i = 0; i < 1000; i++) {
            const factor = 2 - Math.cos(i / 40);
            const radius = (circleSize / factor) * (factor - 1);
            const cx = centerX + Math.cos(i / 8) * radius;
            const cy = centerY + Math.sin(i / 8) * radius;
            mwc.setZoom({factor, cx, cy});
            await new Promise(r => setTimeout(r, targetInterval));
        }
    } finally {
        mwc.setZoom({factor: 1, cx: 0, cy: 0});
    }
});
