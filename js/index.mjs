import * as bindings from 'bindings';
const mwc = bindings.default('mwc');


function wrap(fn, arg) {
    const rawResp = arg ? fn(JSON.stringify(arg)) : fn();
    if (!rawResp) {
        console.warn("returnless func, okay... remove after validation"); // XXX
        return;
    }
    const resp = JSON.parse(rawResp);
    if (resp.success) {
        return resp.value;
    } else if (!resp.success) {
        const {type, description, message} = resp.error;
        throw new Error(`${type} [${description}]: ${message}`);
    } else {
        throw new Error('Internal Swift Bridge Protocol Error');
    }
}


export function getMainScreenSize() {
    return wrap(mwc.getMainScreenSize);
}


export function getMenuBarHeight() {
    return wrap(mwc.getMenuBarHeight);
}


export function resizeAppWindow({appName, width, height, x=0, y=0, activate=false}) {
    return wrap(mwc.resizeAppWindow, {appName, width, height, x, y, activate});
}


export function getZoom() {
    return wrap(mwc.getZoom);
}
