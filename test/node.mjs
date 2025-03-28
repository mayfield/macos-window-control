import test from 'node:test';
import assert from 'node:assert';
import * as mwc from '../js/index.mjs';

test('hasAccessiblityPermission', () => {
    assert(mwc.hasAccessibilityPermission());
});

test('async-perf-bench', async () => {
    for (let j = 0; j < 10; j++) {
        const promises = [];
        for (let i = 0; i < 100; i++) {
            const p = mwc.getWindows({app: {name: 'Finder'}});
            promises.push(p);
        }
        await Promise.all(promises);
    }
});

test('getWindows', async () => {
    const apps = await mwc.getApps();
    const promises = [];
    let count = 0;
    for (const x of apps) {
        const p = mwc.getWindows({app: {pid: x.pid}});
        promises.push(p.then(x => count += x.length));
    }
    await Promise.all(promises);
});

test('getZoom', () => {
    const r = mwc.getZoom();
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(typeof r.scale, 'number');
    assert.strictEqual(typeof r.smooth, 'boolean');
    assert.strictEqual(typeof r.center, 'object');
    assert(Array.isArray(r.center));
    assert.strictEqual(typeof r.center[0], 'number');
    assert.strictEqual(typeof r.center[1], 'number');
});

test('getZoom-noop-args', () => {
    let r = mwc.getZoom('unused');
    assert.strictEqual(typeof r, 'object');
    r = mwc.getZoom({unused: 'unused'});
    assert.strictEqual(typeof r, 'object');
});

test('setWindowSize-invalid-window', () => {
    assert.throws(
        () => mwc.setWindowSize({app: {name: 'nope-nada def not 123'}, size: [1, 1], position: [1, 1]}),
        mwc.NotFoundError
    );
});

test('setWindowSize-bad-args', () => {
    assert.throws(() => mwc.setWindowSize(), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize('asdf'), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize([]), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: 'nope nope no'}}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: 1.234}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: null}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: {}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: undefined}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({window: {}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {}, window: {}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: 'foo'}, window: {}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.setWindowSize({app: {name: 'foo', pid: 111}, size: [0, 0]}), mwc.ValidationError);
});

test('setWindowSize-Terminal', () => {
    assert.strictEqual(mwc.setWindowSize({app: {name: 'Terminal'}, size: [1000, 1000], position: [10, 20]}), undefined);
});

test('setZoom', () => {
    const r = mwc.setZoom({scale: 1});
    assert.strictEqual(r, undefined);
    mwc.setZoom({scale: 1, center: [0, 0]});
    try {
        mwc.setZoom({scale: 2});
    } finally {
        mwc.setZoom({scale: 1});
    }
    try {
        mwc.setZoom({scale: 2, center: [1000, 1000]});
    } finally {
        mwc.setZoom({scale: 1});
    }
});

test('setZoom-bad-args', () => {
    try {
        assert.throws(() => mwc.setZoom(), mwc.ValidationError);
        assert.throws(() => mwc.setZoom('asdf'), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom([]), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: 'nope nope no'}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: undefined}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: null}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: 2, center: [false, 1.1]}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: 2, center: [1.1, true]}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({scale: 2, center: [1.1, 'asdf']}), mwc.ValidationError);
    } finally {
        mwc.setZoom({scale: 1})
    }
});

test('getMainScreenSize', () => {
    const r = mwc.getMainScreenSize();
    assert(Array.isArray(r.size));
    assert(Array.isArray(r.position));
    assert.strictEqual(r.size.length, 2);
    assert.strictEqual(r.position.length, 2);
    assert(r.size.every(x => typeof x === 'number'));
    assert(r.position.every(x => typeof x === 'number'));
});

test('getActiveScreenSize', () => {
    const r = mwc.getActiveScreenSize();
    assert(Array.isArray(r.size));
    assert(Array.isArray(r.position));
    assert.strictEqual(r.size.length, 2);
    assert.strictEqual(r.position.length, 2);
    assert(r.size.every(x => typeof x === 'number'));
    assert(r.position.every(x => typeof x === 'number'));
});

test('getScreenSizes', () => {
    const rArr = mwc.getScreenSizes();
    assert(Array.isArray(rArr));
    for (const r of rArr) {
        assert(Array.isArray(r.size));
        assert(Array.isArray(r.position));
        assert.strictEqual(r.size.length, 2);
        assert.strictEqual(r.position.length, 2);
        assert(r.size.every(x => typeof x === 'number'));
        assert(r.position.every(x => typeof x === 'number'));
    }
});

test('getMenuBarHeight', () => {
    const r = mwc.getMenuBarHeight();
    assert.strictEqual(typeof r, 'number');
});

test('getWindowSize', () => {
    const r = mwc.getWindowSize({app: {name: 'Terminal'}, window: {main: true}});
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(Object.keys(r).length, 2);
    assert(Array.isArray(r.size));
    assert(Array.isArray(r.position));
    assert.strictEqual(r.size.length, 2);
    assert.strictEqual(r.position.length, 2);
    assert(r.size.every(x => typeof x === 'number'));
    assert(r.position.every(x => typeof x === 'number'));
    const rSame = mwc.getWindowSize({app: {name: 'Terminal'}});
    assert.deepEqual(r, rSame)
});

test('getWindowSize-bad-args', () => {
    assert.throws(() => mwc.getWindowSize({app: {name: 'Terminal'}, window: {main: false}}),
                  mwc.ValidationError);
    assert.throws(() => mwc.getWindowSize({app: {}, window: {main: true}}), mwc.ValidationError);
    assert.throws(() => mwc.getWindowSize({app: false, window: {main: true}}), mwc.ValidationError);
    assert.throws(() => mwc.getWindowSize({window: {}}), mwc.ValidationError);
    assert.throws(() => mwc.getWindowSize({app: {pid: -100}, window: {}}), mwc.ValidationError);
});

test('getApps', async () => {
    const r = await mwc.getApps();
    //console.dir(r, {depth: 1000});
    assert(Array.isArray(r));
    assert(r.every(x => typeof x === 'object'));
    assert(r.every(x => typeof x.name === 'string'));
    assert(r.every(x => typeof x.pid === 'number'));
});

test('activateWindow', async () => {
    let winApps = (await mwc.getApps()).filter(x => x.name !== 'Finder');
    await Promise.all(winApps.map(async app => {
        app.windows = await mwc.getWindows({app: {pid: app.pid}});
    }));
    winApps = winApps.filter(x => x.windows.length);
    for (const appProp of ['name', 'pid']) {
        for (const app of winApps) {
            for (const win of app.windows) {
                if (!win.title) {
                    continue;
                }
                //console.debug(`Activating: ${appProp}:${app[appProp]}, ${win.title}`);
                mwc.activateWindow({
                    app: {[appProp]: app[appProp]},
                    window: {title: win.title}
                });
            }
        }
        for (const app of winApps) {
            for (const [index, win] of app.windows.entries()) {
                //console.debug(`Activating: ${appProp}:${app[appProp]}, window[${index}]`);
                mwc.activateWindow({
                    app: {[appProp]: app[appProp]},
                    window: {index}
                });
            }
        }
        for (const app of winApps) {
            //console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateWindow({
                app: {[appProp]: app[appProp]},
            });
        }
        for (const app of winApps) {
            //console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateWindow({
                app: {[appProp]: app[appProp]},
                window: {main: true}
            });
            mwc.activateWindow({app: {pid: app.pid}, window: {main: true}});
        }
    }
});

test('spiral', async () => {
    //console.warn("SKIP"); return;
    const {size: [width, height]} = mwc.getMainScreenSize();
    const circleSize = (Math.min(width, height) / 2) * 0.5;
    const fps = 60;
    const zoomTime = 0.5;
    const cycles = 1;
    const targetInterval = (1000 / fps) - 1;
    const framesPerCycle = fps * zoomTime;
    mwc.setZoom({scale: 1});
    try {
        for (let i = 0; i < framesPerCycle * Math.PI * 2 * cycles; i++) {
            const scale = 2 - Math.cos(i / framesPerCycle);
            const radius = (circleSize / scale) * (scale - 1);
            const center = [
                (width / 2) + Math.cos(i / (framesPerCycle / 5)) * radius,
                (height / 2) + Math.sin(i / (framesPerCycle / 5)) * radius
            ];
            mwc.setZoom({scale, center});
            await new Promise(r => setTimeout(r, targetInterval));
        }
    } finally {
        mwc.setZoom({scale: 1});
    }
});
