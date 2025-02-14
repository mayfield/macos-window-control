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
