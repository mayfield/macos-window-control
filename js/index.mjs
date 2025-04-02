import * as bindings from 'bindings';
export const _mwc = bindings.default('mwc');


export class MWCError extends Error {
    get name() {
        return this.constructor.name;
    }
}
export class AXPermError extends MWCError {}
export class NotFoundError extends MWCError {}
export class ValidationError extends MWCError {}
export class DecodingError extends ValidationError {}

const typedErrors = {
    AXPermError,
    NotFoundError,
    DecodingError,
    ValidationError,
};


function _unwrapResp(rawResp) {
    const resp = JSON.parse(rawResp);
    if (resp.success) {
        return resp.value;
    } else if (!resp.success) {
        const E = typedErrors[resp.error.type];
        let e;
        if (E) {
            e = new E(resp.error.message);
        } else {
            e = new MWCError(`${resp.error.type}: ${resp.error.message}`);
        }
        if (resp.error.stack.length) {
            const relStack = resp.error.stack.filter(x => x.match(/ *[0-9]+ +mwc\.node /));
            e.stack += `\n\n---Swift Callstack---\n\n${relStack.join('\n')}`;
        }
        throw e;
    } else {
        throw new Error('Internal Swift Bridge Protocol Error');
    }
}


function wrap(fn) {
    const wrapped = function(arg) {
        const rawResp = fn(arg !== undefined ? JSON.stringify(arg) : '{}');
        if (rawResp instanceof Promise) {
            return rawResp.then(_unwrapResp);
        } else {
            return _unwrapResp(rawResp);
        }
    };
    Object.defineProperty(wrapped, 'name', {value: fn.name});
    return wrapped;
}


export const hasAccessibilityPermission = wrap(_mwc.hasAccessibilityPermission);
export const getMainDisplay = wrap(_mwc.getMainDisplay);
export const getActiveDisplay = wrap(_mwc.getActiveDisplay);
export const getDisplays = wrap(_mwc.getDisplays);
export const getZoom = wrap(_mwc.getZoom);
export const setZoom = wrap(_mwc.setZoom);
export const getApps = wrap(_mwc.getApps);
export const getWindows = wrap(_mwc.getWindows);
export const getWindowSize = wrap(_mwc.getWindowSize);
export const setWindowSize = wrap(_mwc.setWindowSize);
export const activateWindow = wrap(_mwc.activateWindow);
