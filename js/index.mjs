import * as bindings from 'bindings';
export const _mwc = bindings.default('mwc');


export class MWCError extends Error {
    get name() {
        return this.constructor.name;
    }
}
export class AXPermError extends MWCError {}
export class NotFoundError extends MWCError {}
export class DecodingError extends MWCError {}

const typedErrors = {
    AXPermError,
    NotFoundError,
    DecodingError,
};


function wrap(fn) {
    const wrapped = function(arg) {
        const rawResp = arg ? fn(JSON.stringify(arg)) : fn();
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
                e.stack += `\n\n---Swift Callstack---\n\n${resp.error.stack.join('\n')}`;
            }
            throw e;
        } else {
            throw new Error('Internal Swift Bridge Protocol Error');
        }
    };
    Object.defineProperty(wrapped, 'name', {value: fn.name});
    return wrapped;
}


export const hasAccessibilityPermission = wrap(_mwc.hasAccessibilityPermission);
export const getMainScreenSize = wrap(_mwc.getMainScreenSize);
export const getMenuBarHeight = wrap(_mwc.getMenuBarHeight);
export const getZoom = wrap(_mwc.getZoom);
export const setZoom = wrap(_mwc.setZoom);
export const getWindowApps = wrap(_mwc.getWindowApps);
export const getAppWindowSize = wrap(_mwc.getAppWindowSize);
export const resizeAppWindow = wrap(_mwc.resizeAppWindow);
