import * as bindings from 'bindings';
const _mwc = bindings.default('mwc');


export class MWCError extends Error {
    get name() {
        return this.constructor.name;
    }
}
export class NotFoundError extends MWCError {}
export class PermError extends MWCError {}
export class DecodingError extends MWCError {}

const typedErrors = {
    NotFoundError,
    PermError,
    DecodingError,
};


function wrap(fn, arg) {
    const rawResp = arg ? fn(JSON.stringify(arg)) : fn();
    const resp = JSON.parse(rawResp);
    if (resp.success) {
        return resp.value;
    } else if (!resp.success) {
        const E = typedErrors[resp.error.type];
        if (E) {
            throw new E(resp.error.message);
        } else {
            throw new MWCError(`${resp.error.type}: ${resp.error.message}`);
        }
    } else {
        throw new Error('Internal Swift Bridge Protocol Error');
    }
}


export function getMainScreenSize() {
    return wrap(_mwc.getMainScreenSize);
}


export function getMenuBarHeight() {
    return wrap(_mwc.getMenuBarHeight);
}


export function resizeAppWindow({appName, width, height, x=0, y=0, activate=false}) {
    return wrap(_mwc.resizeAppWindow, {appName, width, height, x, y, activate});
}


export function getZoom() {
    return wrap(_mwc.getZoom);
}
