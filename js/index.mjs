import * as bindings from 'bindings';
const mwc = bindings.default('mwc');


export function resizeAppWindow({appName, width, height, x=0, y=0, activate=false}) {
    mwc.resizeAppWindow(JSON.stringify({appName, width, height, x, y, activate}));
}

export function getMainScreenSize() {
    return JSON.parse(mwc.getMainScreenSize());
}

export function getMenuBarHeight() {
    return JSON.parse(mwc.getMenuBarHeight());
}

/*
try {
    console.log(mwc.getMainScreenSize());
    console.log(mwc.getMenuBarHeight());
    let sign = 1;
    let x = 500;
    let y = 300;
    let i = 1;
    while(true) {
        sign = sign > 0 ? -1 : 1;
        for (;;) {
            i++;
            x += 0.5 * sign;
            mwc.resizeAppWindow(JSON.stringify({
                appName: "Google Chrome",
                width: 200,
                height: 200,
                x,
                y: 300 + Math.sin(i / 30) * 200,
                activate: true,
            }));
            mwc.resizeAppWindow(JSON.stringify({
                appName: "Safari",
                width: 200,
                height: 200,
                x: 1300 - x,
                y: 600 + Math.cos(i / 30) * 200,
            }));

            if (i % 1000 === 0) {
                break;
            }
        }
    }
} catch(e) {
    console.warn("cauth it", e);
}
*/
