{
    "targets": [{
        "target_name": "mwc",
        "sources": ["src/node-bridge.c"],
        "libraries": ["../obj/mwc.a", "-lpthread"],
        "actions": [{
            "action_name": "prebuild_step",
            "inputs": ["src/*"],
            "outputs": ["./obj/mwc.a"],
            "action": ["make", "c-lib", "ARCH=<(target_arch)"]
        }]
    }]
}
