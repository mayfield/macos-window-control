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
