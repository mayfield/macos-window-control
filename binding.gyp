{
    "targets": [{
        "target_name": "mwc",
        "sources": ["src/node-bridge.c"],
        "libraries": ["../obj/mwc.a"],
        "actions": [{
            "action_name": "prebuild_step",
            "inputs": ["src/*"],
            "outputs": ["./obj/mwc.a"],
            "action": ["sh", "-c", "make c-lib"]
        }]
    }]
}
