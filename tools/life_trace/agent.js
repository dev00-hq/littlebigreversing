const config = (() => {
    const defaults = {
        moduleName: "LBA2.EXE",
        mode: "basic",
        logAll: false,
        maxHits: 1,
        targetObject: 0,
        targetOpcode: 0x76,
        targetOffset: 46,
        windowBefore: 8,
        windowAfter: 8,
        focusOffsetStart: null,
        focusOffsetEnd: null,
        fingerprintOffset: null,
        fingerprintHex: null,
        fingerprintBytes: [],
        comparisonObject: null,
        comparisonOpcode: null,
        comparisonOffset: null,
        helperCaptureEnabled: false,
        requiresCallsiteMap: false,
    };
    return Object.assign(defaults, __TRACE_CONFIG__);
})();

__TRACE_AGENT_SHARED__

__TRACE_AGENT_SCENES__

__TRACE_AGENT_BOOTSTRAP__
