import test from 'node:test';
import assert from 'node:assert';
import * as mwc from '../js/index.mjs';

test('hasAccessiblityPermission', () => {
    assert(mwc.hasAccessibilityPermission());
});

test('getWindows', async () => {
    const p = mwc.getWindows({app: {name: "Terminal"}});
    console.log("p", p);
    console.log("await p", await p);
});

test('getZoom', () => {
    const r = mwc.getZoom();
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(typeof r.scale, 'number');
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
    assert(Array.isArray(r));
    assert.strictEqual(r.length, 2);
    assert(r.every(x => typeof x === 'number'));
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

test('getApps', () => {
    const r = mwc.getApps();
    //console.dir(r, {depth: 1000});
    assert(Array.isArray(r));
    assert(r.every(x => typeof x === 'object'));
    assert(r.every(x => typeof x.name === 'string'));
    assert(r.every(x => typeof x.pid === 'number'));
});

test('activateWindow', () => {
    return; // Finish getWindows work
    const winApps = mwc.getApps().filter(x => x.windows.length && x.name !== 'Finder');
    for (const appProp of ['name', 'pid']) {
        for (const app of winApps) {
            for (const win of app.windows) {
                if (!win.title) {
                    continue;
                }
                console.debug(`Activating: ${appProp}:${app[appProp]}, ${win.title}`);
                mwc.activateWindow({
                    app: {[appProp]: app[appProp]},
                    window: {title: win.title}
                });
            }
        }
        for (const app of winApps) {
            for (const [index, win] of app.windows.entries()) {
                console.debug(`Activating: ${appProp}:${app[appProp]}, window[${index}]`);
                mwc.activateWindow({
                    app: {[appProp]: app[appProp]},
                    window: {index}
                });
            }
        }
        for (const app of winApps) {
            console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateWindow({
                app: {[appProp]: app[appProp]},
            });
        }
        for (const app of winApps) {
            console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateWindow({
                app: {[appProp]: app[appProp]},
                window: {main: true}
            });
            mwc.activateWindow({app: {pid: app.pid}, window: {main: true}});
        }
    }
});

test('spiral', async () => {
    return 'XXX';
    const [width, height] = mwc.getMainScreenSize();
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
