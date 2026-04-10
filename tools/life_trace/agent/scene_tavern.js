registerScene("tavern-trace", function createTavernScene() {
    const tavernRun = {
        matchedFingerprint: false,
        threadId: null,
        objectIndex: null,
        ownerKind: null,
        currentObject: null,
        ptrLifePtr: ptr(0),
        offsetLife: null,
        saw076: false,
        post076ThreadId: null,
        post076OutcomeCaptured: false,
    };

    function buildTrackedTavernTrace(ptrPrg, ptrPrgOffset, opcode, threadId) {
        return {
            thread_id: threadId,
            object_index: tavernRun.objectIndex,
            owner_kind: tavernRun.ownerKind,
            current_object: tavernRun.currentObject,
            ptr_life: pointerString(tavernRun.ptrLifePtr),
            offset_life: tavernRun.offsetLife,
            ptr_prg: pointerString(ptrPrg),
            ptr_prg_offset: ptrPrgOffset,
            opcode,
            opcode_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
            byte_at_ptr_prg: opcode,
            byte_at_ptr_prg_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
        };
    }

    function isFocusOffset(offsetValue) {
        if (offsetValue === null || config.focusOffsetStart === null || config.focusOffsetEnd === null) {
            return false;
        }
        return offsetValue >= config.focusOffsetStart && offsetValue <= config.focusOffsetEnd;
    }

    function isTrackedThread(threadId) {
        if (!tavernRun.matchedFingerprint || tavernRun.threadId !== threadId) {
            return false;
        }
        return !tavernRun.ptrLifePtr.isNull();
    }

    function maybeEmitTargetValidation(threadId, state) {
        if (tavernRun.matchedFingerprint || state.object_index !== config.targetObject) {
            return;
        }
        if (state.ptrLifePtr.isNull() || config.fingerprintOffset === null || config.fingerprintBytes.length === 0) {
            return;
        }

        const fingerprintPtr = state.ptrLifePtr.add(config.fingerprintOffset);
        const actualHex = readBytesHexSafe(fingerprintPtr, config.fingerprintBytes.length);
        if (actualHex === null || actualHex.toUpperCase() !== config.fingerprintHex.toUpperCase()) {
            return;
        }

        tavernRun.matchedFingerprint = true;
        tavernRun.threadId = threadId;
        tavernRun.objectIndex = state.object_index;
        tavernRun.ownerKind = state.object_index === 0 ? "hero" : "object";
        tavernRun.currentObject = state.current_object;
        tavernRun.ptrLifePtr = state.ptrLifePtr;
        tavernRun.offsetLife = state.offset_life;

        sendEvent("target_validation", {
            thread_id: threadId,
            object_index: state.object_index,
            owner_kind: state.object_index === 0 ? "hero" : "object",
            ptr_life: state.ptr_life,
            fingerprint_start_offset: config.fingerprintOffset,
            fingerprint_hex_actual: actualHex,
            fingerprint_hex_expected: config.fingerprintHex,
            matches_fingerprint: true,
        });
    }

    return {
        usesDoLifeEntryState: false,

        installHooks() {
            Interceptor.attach(absolute(offsets.doLifeLoop), {
                onEnter(args) {
                    const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
                    if (ptrPrg.isNull()) {
                        return;
                    }

                    if (!tavernRun.matchedFingerprint) {
                        const state = snapshotObjectState(config.targetObject);
                        if (state.ptrLifePtr.isNull()) {
                            return;
                        }
                        maybeEmitTargetValidation(this.threadId, state);
                    }
                    if (!tavernRun.matchedFingerprint) {
                        return;
                    }
                    if (tavernRun.ptrLifePtr.isNull()) {
                        return;
                    }

                    if (tavernRun.threadId === null && isFocusOffset(pointerDelta(ptrPrg, tavernRun.ptrLifePtr))) {
                        tavernRun.threadId = this.threadId;
                    }

                    if (!isTrackedThread(this.threadId)) {
                        if (config.logAll) {
                            const ptrPrgOffset = pointerDelta(ptrPrg, tavernRun.ptrLifePtr);
                            const opcode = readU8Safe(ptrPrg);
                            const trace = buildTrackedTavernTrace(ptrPrg, ptrPrgOffset, opcode, this.threadId);
                            trace.matches_target = matchesTarget(trace);
                            sendEvent("trace", trace);
                        }
                        return;
                    }

                    const ptrPrgOffset = pointerDelta(ptrPrg, tavernRun.ptrLifePtr);
                    const post076ExpectedOffset =
                        config.targetOffset === null ? null : (config.targetOffset | 0) + 1;

                    if (!tavernRun.saw076 && !config.logAll && ptrPrgOffset !== config.targetOffset) {
                        return;
                    }

                    if (
                        tavernRun.saw076 &&
                        !config.logAll &&
                        tavernRun.post076ThreadId === this.threadId &&
                        !tavernRun.post076OutcomeCaptured &&
                        ptrPrgOffset !== post076ExpectedOffset
                    ) {
                        return;
                    }

                    const opcode = readU8Safe(ptrPrg);
                    const trace = buildTrackedTavernTrace(ptrPrg, ptrPrgOffset, opcode, this.threadId);
                    trace.matches_target = matchesTarget(trace);

                    const is076Trace =
                        trace.ptr_prg_offset === config.targetOffset && trace.opcode === config.targetOpcode;
                    const wantsLoopReentryProof =
                        tavernRun.saw076 &&
                        tavernRun.post076ThreadId === this.threadId &&
                        !tavernRun.post076OutcomeCaptured &&
                        trace.ptr_prg_offset === post076ExpectedOffset;

                    if (is076Trace && !tavernRun.saw076) {
                        tavernRun.saw076 = true;
                        tavernRun.post076ThreadId = this.threadId;
                    }

                    if (wantsLoopReentryProof) {
                        tavernRun.post076OutcomeCaptured = true;
                        trace.post_076_outcome = "loop_reentry";
                        sendEvent("window_trace", trace);
                        return;
                    }

                    if (is076Trace || wantsLoopReentryProof) {
                        sendEvent("window_trace", trace);
                        return;
                    }

                    if (config.logAll) {
                        sendEvent("trace", trace);
                    }
                },
            });
        },
    };
});
