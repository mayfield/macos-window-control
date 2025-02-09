macos-window-control
--------
Abusing the Accessibility APIs to resize windows from the command line.


Building
========
```shell
make
```

Running
========
```shell
dist/macos-window-control.arm64 resize Safari 1000 500
dist/macos-window-control.arm64 zoom 2
```

```
:; ./dist/macos-window-control.arm64 
Usage: ./dist/macos-window-control.arm64 COMMAND [ARGS...]
  Command 'resize':
    Args: PROC_NAME WIDTH HEIGHT [X Y]
    Example: ./dist/macos-window-control.arm64 resize ZwiftAppSilicon 1920 1080

  Command 'zoom':
    Args: FACTOR [CENTER_X CENTER_Y]
    Example: ./dist/macos-window-control.arm64 zoom 1.2 960 640

  Command 'fullscreen':
    Args: APP
    Example: ./dist/macos-window-control.arm64 ZwiftAppSilicon
```
