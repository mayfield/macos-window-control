import test from 'node:test';
import assert from 'node:assert';
import * as mwc from '../js/index.mjs';

test('hasAccessiblityPermission', () => {
    assert(mwc.hasAccessibilityPermission());
});

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
        () => mwc.resizeAppWindow({query: {app: {name: 'nope-nada def not 123'}}, size: [1, 1], position: [1, 1]}),
        mwc.NotFoundError
    );
});

test('resizeAppWindow-bad-args', () => {
    assert.throws(() => mwc.resizeAppWindow(), TypeError);
    assert.throws(() => mwc.resizeAppWindow('asdf'), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow([]), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: 'nope nope no'}}}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: 1.234}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: null}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: {}}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: undefined}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {window: {}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {}, window: {}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: 'foo'}, window: {}}, size: [0, 0]}), mwc.ValidationError);
    assert.throws(() => mwc.resizeAppWindow({query: {app: {name: 'foo', pid: 111}}, size: [0, 0]}), mwc.ValidationError);
});

test('resizeAppWindow-Terminal', () => {
    assert.strictEqual(mwc.resizeAppWindow({query: {app: {name: 'Terminal'}}, size: [1000, 1000], position: [10, 20]}), undefined);
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
        assert.throws(() => mwc.setZoom(), TypeError);
        assert.throws(() => mwc.setZoom('asdf'), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom([]), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: 'nope nope no'}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: undefined}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: null}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: 2, center: [false, 1.1]}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: 2, center: [1.1, true]}), mwc.ValidationError);
        assert.throws(() => mwc.setZoom({factor: 2, center: [1.1, 'asdf']}), mwc.ValidationError);
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
    const r = mwc.getAppWindowSize({app: {name: 'Terminal'}, window: {main: true}});
    assert.strictEqual(typeof r, 'object');
    assert.strictEqual(Object.keys(r).length, 2);
    assert(Array.isArray(r.size));
    assert(Array.isArray(r.position));
    assert.strictEqual(r.size.length, 2);
    assert.strictEqual(r.position.length, 2);
    assert(r.size.every(x => typeof x === 'number'));
    assert(r.position.every(x => typeof x === 'number'));
    const rSame = mwc.getAppWindowSize({app: {name: 'Terminal'}});
    assert.deepEqual(r, rSame)
});

test('getAppWindowSize-bad-args', () => {
    assert.throws(() => mwc.getAppWindowSize({app: {name: 'Terminal'}, window: {main: false}}),
                  mwc.ValidationError);
    assert.throws(() => mwc.getAppWindowSize({app: {}, window: {main: true}}), mwc.ValidationError);
    assert.throws(() => mwc.getAppWindowSize({app: false, window: {main: true}}), mwc.ValidationError);
    assert.throws(() => mwc.getAppWindowSize({window: {}}), mwc.ValidationError);
    assert.throws(() => mwc.getAppWindowSize({app: {pid: -100}, window: {}}), mwc.ValidationError);
});

test('getWindowApps', () => {
    const r = mwc.getWindowApps();
    //console.dir(r, {depth: 1000});
    assert(Array.isArray(r));
    assert(r.every(x => typeof x === 'object'));
    assert(r.every(x => typeof x.name === 'string'));
    assert(r.every(x => typeof x.pid === 'number'));
    assert(r.every(x => Array.isArray(x.windows)));
});

test('activateAppWindow', () => {
    const winApps = mwc.getWindowApps().filter(x => x.name !== 'Finder');
    for (const appProp of ['name', 'pid']) {
        for (const app of winApps) {
            for (const win of app.windows) {
                if (!win.title) {
                    continue;
                }
                console.debug(`Activating: ${appProp}:${app[appProp]}, ${win.title}`);
                mwc.activateAppWindow({
                    app: {[appProp]: app[appProp]},
                    window: {title: win.title}
                });
            }
        }
        for (const app of winApps) {
            for (const [index, win] of app.windows.entries()) {
                console.debug(`Activating: ${appProp}:${app[appProp]}, window[${index}]`);
                mwc.activateAppWindow({
                    app: {[appProp]: app[appProp]},
                    window: {index}
                });
            }
        }
        for (const app of winApps) {
            console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateAppWindow({
                app: {[appProp]: app[appProp]},
            });
        }
        for (const app of winApps) {
            console.debug(`Activating: ${appProp}:${app[appProp]} [MAIN Window]`);
            mwc.activateAppWindow({
                app: {[appProp]: app[appProp]},
                window: {main: true}
            });
            mwc.activateAppWindow({app: {pid: app.pid}, window: {main: true}});
        }
    }
});

test('spiral', async () => {
    const [width, height] = mwc.getMainScreenSize();
    const circleSize = (Math.min(width, height) / 2) * 0.5;
    const fps = 60;
    const zoomTime = 0.5;
    const cycles = 1;
    const targetInterval = (1000 / fps) - 1;
    const framesPerCycle = fps * zoomTime;
    mwc.setZoom({factor: 1});
    try {
        for (let i = 0; i < framesPerCycle * Math.PI * 2 * cycles; i++) {
            const factor = 2 - Math.cos(i / framesPerCycle);
            const radius = (circleSize / factor) * (factor - 1);
            const center = [
                (width / 2) + Math.cos(i / (framesPerCycle / 5)) * radius,
                (height / 2) + Math.sin(i / (framesPerCycle / 5)) * radius
            ];
            mwc.setZoom({factor, center});
            await new Promise(r => setTimeout(r, targetInterval));
        }
    } finally {
        mwc.setZoom({factor: 1});
    }
});
