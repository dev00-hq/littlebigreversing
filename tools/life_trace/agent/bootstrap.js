const scene = createScene(config.mode);

sendEvent("status", {
    message: "life trace agent loaded",
    module_name: mainModule.name,
    module_base: pointerString(base),
    config,
});

if (scene.installHooks !== undefined) {
    scene.installHooks();
} else {
    if (scene.installAuxiliaryHooks !== undefined) {
        scene.installAuxiliaryHooks();
    }

    installDoLifeEntryHooks(scene);
    installDoLifeLoopHook(scene);
}
