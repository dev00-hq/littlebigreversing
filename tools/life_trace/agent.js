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
    };
    return Object.assign(defaults, __TRACE_CONFIG__);
})();

const isTavernTrace = config.mode === "tavern-trace";
const isScene11Pair = config.mode === "scene11-pair";

const offsets = {
    doLifeEntry: 0x00020574,
    doLifeLoop: 0x000205bc,
    doFuncLife: 0x0001f0a8,
    doTest: 0x0001fe30,
    ptrPrg: 0x000976d0,
    typeAnswer: 0x000976d4,
    value: 0x00097d44,
    objectBase: 0x0009a19c,
    objectStride: 0x21b,
    ptrLife: 0x1ee,
    offsetLife: 0x1f2,
    exeSwitchFunc: 0x20e,
    exeSwitchTypeAnswer: 0x20f,
    exeSwitchValue: 0x210,
    switchWriteEntry: 0x00021127,
    switchWritePost: 0x00021151,
    orCaseEntry: 0x00021164,
    orCasePostTest: 0x00021193,
    caseEvalEntry: 0x000211c2,
    caseEvalPostTest: 0x000211f1,
    breakJumpEntry: 0x000211f9,
};

const mainModule = (() => {
    const target = config.moduleName.toLowerCase();
    const exact = Process.enumerateModules().find((module) => module.name.toLowerCase() === target);
    if (exact) {
        return exact;
    }
    return Process.enumerateModules()[0];
})();

const base = mainModule.base;
const pendingByThread = Object.create(null);
const branchPendingByThread = Object.create(null);
const trackedRun = {
    matchedFingerprint: false,
    threadId: null,
    ptrLifePtr: ptr(0),
    saw076: false,
    post076ThreadId: null,
    post076OutcomeCaptured: false,
};
const scene11Run = {
    matchedFingerprint: false,
    fingerprintThreadId: null,
    fingerprintPtrLifePtr: ptr(0),
    pendingByThread: Object.create(null),
    resolvedRoles: Object.create(null),
};
let branchHooksAttached = false;
let matchedHits = 0;

function absolute(offset) {
    return base.add(offset);
}

function stateStackForThread(threadId) {
    if (pendingByThread[threadId] === undefined) {
        pendingByThread[threadId] = [];
    }
    return pendingByThread[threadId];
}

function currentStateForThread(threadId) {
    const stack = pendingByThread[threadId];
    if (stack === undefined || stack.length === 0) {
        return undefined;
    }
    return stack[stack.length - 1];
}

function sendEvent(kind, payload) {
    send({
        kind,
        payload,
    });
}

function pointerString(pointerValue) {
    return pointerValue.isNull() ? "0x0" : pointerValue.toString();
}

function readPointerSafe(pointerValue) {
    try {
        return pointerValue.readPointer();
    } catch (error) {
        return ptr(0);
    }
}

function readU8Safe(pointerValue) {
    try {
        return pointerValue.readU8();
    } catch (error) {
        return null;
    }
}

function readS16Safe(pointerValue) {
    try {
        return pointerValue.readS16();
    } catch (error) {
        return null;
    }
}

function readS32Safe(pointerValue) {
    try {
        return pointerValue.readS32();
    } catch (error) {
        return null;
    }
}

function readBytesHexSafe(pointerValue, count) {
    try {
        const raw = pointerValue.readByteArray(count);
        return Array.from(new Uint8Array(raw), (value) => value.toString(16).padStart(2, "0").toUpperCase()).join(" ");
    } catch (error) {
        return null;
    }
}

function readWindow(pointerValue) {
    const before = Math.max(0, config.windowBefore | 0);
    const after = Math.max(0, config.windowAfter | 0);
    const start = pointerValue.sub(before);
    const length = before + after + 1;

    try {
        const raw = start.readByteArray(length);
        const bytes = Array.from(new Uint8Array(raw), (value) => value.toString(16).padStart(2, "0"));
        return {
            start: pointerString(start),
            cursor_index: before,
            bytes_hex: bytes.join(" "),
        };
    } catch (error) {
        return {
            start: pointerString(start),
            cursor_index: before,
            bytes_hex: null,
            error: String(error),
        };
    }
}

function pointerDelta(pointerValue, basePointer) {
    if (pointerValue.isNull() || basePointer.isNull()) {
        return null;
    }
    return (pointerValue.toUInt32() - basePointer.toUInt32()) | 0;
}

function currentObjectAddress(objectIndex) {
    return absolute(offsets.objectBase).add(objectIndex * offsets.objectStride);
}

function readExeSwitchStateForObject(objectIndex) {
    const currentObject = currentObjectAddress(objectIndex);
    return {
        func: readU8Safe(currentObject.add(offsets.exeSwitchFunc)),
        type_answer: readU8Safe(currentObject.add(offsets.exeSwitchTypeAnswer)),
        value: readS32Safe(currentObject.add(offsets.exeSwitchValue)),
    };
}

function readWorkingState() {
    return {
        type_answer: readU8Safe(absolute(offsets.typeAnswer)),
        value: readS32Safe(absolute(offsets.value)),
    };
}

function snapshotObjectState(objectIndex) {
    const currentObject = currentObjectAddress(objectIndex);
    const ptrLifePtr = readPointerSafe(currentObject.add(offsets.ptrLife));
    return {
        object_index: objectIndex,
        currentObjectPtr: currentObject,
        current_object: pointerString(currentObject),
        ptrLifePtr,
        ptr_life: pointerString(ptrLifePtr),
        offset_life: readS16Safe(currentObject.add(offsets.offsetLife)),
        lastSeenOffset: null,
        lastSeenOpcode: null,
        recent: [],
    };
}

function matchesTarget(trace) {
    if (config.targetObject !== null && trace.object_index !== config.targetObject) {
        return false;
    }
    if (config.targetOpcode !== null && trace.opcode !== config.targetOpcode) {
        return false;
    }
    if (config.targetOffset !== null && trace.ptr_prg_offset !== config.targetOffset) {
        return false;
    }
    return true;
}

function isFocusOffset(offsetValue) {
    if (offsetValue === null || config.focusOffsetStart === null || config.focusOffsetEnd === null) {
        return false;
    }
    return offsetValue >= config.focusOffsetStart && offsetValue <= config.focusOffsetEnd;
}

function isTrackedThread(threadId) {
    if (!isTavernTrace || !trackedRun.matchedFingerprint || trackedRun.threadId !== threadId) {
        return false;
    }
    return !trackedRun.ptrLifePtr.isNull();
}

function buildTrace(state, ptrPrg, threadId) {
    const opcode = readU8Safe(ptrPrg);
    const workingState = readWorkingState();
    return {
        thread_id: threadId,
        object_index: state.object_index,
        owner_kind: state.object_index === 0 ? "hero" : "object",
        current_object: state.current_object,
        ptr_life: state.ptr_life,
        offset_life: state.offset_life,
        ptr_prg: pointerString(ptrPrg),
        ptr_prg_offset: pointerDelta(ptrPrg, state.ptrLifePtr),
        opcode,
        opcode_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
        byte_at_ptr_prg: opcode,
        byte_at_ptr_prg_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
        ptr_window: readWindow(ptrPrg),
        working_type_answer: workingState.type_answer,
        working_value: workingState.value,
        exe_switch: readExeSwitchStateForObject(state.object_index),
    };
}

function recordRecent(state, trace) {
    state.lastSeenOffset = trace.ptr_prg_offset;
    state.lastSeenOpcode = trace.opcode;
    state.recent.push({
        ptr_prg_offset: trace.ptr_prg_offset,
        opcode: trace.opcode,
    });
    if (state.recent.length > 16) {
        state.recent.shift();
    }
}

function maybeEmitTargetValidation(threadId, state) {
    if (!isTavernTrace || trackedRun.matchedFingerprint || state.object_index !== config.targetObject) {
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

    trackedRun.matchedFingerprint = true;
    trackedRun.threadId = threadId;
    trackedRun.ptrLifePtr = state.ptrLifePtr;
    attachBranchHooks();

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

function maybeEmitScene11Validation(threadId, state) {
    if (!isScene11Pair || scene11Run.matchedFingerprint || state.object_index !== config.targetObject) {
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

    scene11Run.matchedFingerprint = true;
    scene11Run.fingerprintThreadId = threadId;
    scene11Run.fingerprintPtrLifePtr = state.ptrLifePtr;

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

function scene11RoleForTrace(trace) {
    if (
        trace.object_index === config.targetObject &&
        trace.opcode === config.targetOpcode &&
        trace.ptr_prg_offset === config.targetOffset
    ) {
        return "primary";
    }

    if (
        config.comparisonObject !== null &&
        trace.object_index === config.comparisonObject &&
        trace.opcode === config.comparisonOpcode &&
        trace.ptr_prg_offset === config.comparisonOffset
    ) {
        return "comparison";
    }

    return null;
}

function scene11HasPendingRole(role) {
    return Object.keys(scene11Run.pendingByThread).some((threadId) => {
        const pending = scene11Run.pendingByThread[threadId];
        return pending !== undefined && pending.role === role;
    });
}

function queueScene11Match(threadId, trace, role) {
    if (!isScene11Pair || role === null || scene11Run.resolvedRoles[role] || scene11HasPendingRole(role)) {
        return false;
    }

    scene11Run.pendingByThread[threadId] = {
        role,
        trace,
        enteredDoFuncLife: false,
        enteredDoTest: false,
    };
    return true;
}

function buildScene11ResolutionPayload(pending, afterTrace, postHitOutcome) {
    return {
        trace_role: pending.role,
        thread_id: pending.trace.thread_id,
        object_index: pending.trace.object_index,
        owner_kind: pending.trace.owner_kind,
        current_object: pending.trace.current_object,
        ptr_life: pending.trace.ptr_life,
        offset_life: pending.trace.offset_life,
        fetched_in_do_life_loop: true,
        ptr_prg_before: pending.trace.ptr_prg,
        ptr_prg_before_offset: pending.trace.ptr_prg_offset,
        byte_at_ptr_prg: pending.trace.byte_at_ptr_prg,
        byte_at_ptr_prg_hex: pending.trace.byte_at_ptr_prg_hex,
        ptr_window_before: pending.trace.ptr_window,
        working_type_answer_before: pending.trace.working_type_answer,
        working_value_before: pending.trace.working_value,
        exe_switch_before: pending.trace.exe_switch,
        ptr_prg_after: afterTrace.ptr_prg,
        ptr_prg_after_offset: afterTrace.ptr_prg_offset,
        next_opcode: afterTrace.opcode,
        next_opcode_hex: afterTrace.opcode_hex,
        ptr_window_after: afterTrace.ptr_window,
        working_type_answer_after: afterTrace.working_type_answer,
        working_value_after: afterTrace.working_value,
        exe_switch_after: afterTrace.exe_switch,
        entered_do_func_life: pending.enteredDoFuncLife,
        entered_do_test: pending.enteredDoTest,
        post_hit_outcome: postHitOutcome,
    };
}

function resolveScene11Pending(threadId, afterTrace, postHitOutcome) {
    const pending = scene11Run.pendingByThread[threadId];
    if (pending === undefined) {
        return false;
    }

    const payload = buildScene11ResolutionPayload(pending, afterTrace, postHitOutcome);
    sendEvent(postHitOutcome === "do_life_return" ? "do_life_return" : "window_trace", payload);
    scene11Run.resolvedRoles[pending.role] = true;
    delete scene11Run.pendingByThread[threadId];
    return true;
}

function markScene11Helper(threadId, helperName) {
    if (!isScene11Pair) {
        return;
    }

    const pending = scene11Run.pendingByThread[threadId];
    if (pending === undefined) {
        return;
    }

    if (helperName === "do_func_life") {
        pending.enteredDoFuncLife = true;
    } else if (helperName === "do_test") {
        pending.enteredDoTest = true;
    }
}

function prepareBranchTrace(threadId, branchKind, operandPtr, hasTargetOperand) {
    if (!isTrackedThread(threadId)) {
        return;
    }
    const operandOffset = hasTargetOperand ? readS16Safe(operandPtr) : null;
    const ptrPrgOffsetBefore = pointerDelta(operandPtr.sub(1), trackedRun.ptrLifePtr);
    if (!isFocusOffset(ptrPrgOffsetBefore)) {
        return;
    }
    branchPendingByThread[threadId] = {
        thread_id: threadId,
        branch_kind: branchKind,
        object_index: config.targetObject,
        ptr_prg_offset_before: ptrPrgOffsetBefore,
        operand_offset: operandOffset,
        computed_target_offset: operandOffset,
        exe_switch_before: readExeSwitchStateForObject(config.targetObject),
    };
}

function emitPreparedBranchTrace(threadId, comparisonResult) {
    const prepared = branchPendingByThread[threadId];
    if (prepared === undefined) {
        return;
    }
    const payload = Object.assign({}, prepared, {
        exe_switch_after: readExeSwitchStateForObject(prepared.object_index),
    });
    if (comparisonResult !== undefined) {
        payload.comparison_result = comparisonResult;
    }
    sendEvent("branch_trace", payload);
    delete branchPendingByThread[threadId];
    if (trackedRun.saw076 && trackedRun.post076ThreadId === threadId) {
        trackedRun.post076OutcomeCaptured = true;
    }
}

function emitBreakJumpTrace(threadId, operandPtr) {
    if (!isTrackedThread(threadId)) {
        return;
    }
    const ptrPrgOffsetBefore = pointerDelta(operandPtr.sub(1), trackedRun.ptrLifePtr);
    if (!isFocusOffset(ptrPrgOffsetBefore)) {
        return;
    }
    const operandOffset = readS16Safe(operandPtr);
    sendEvent("branch_trace", {
        thread_id: threadId,
        branch_kind: "break_jump",
        object_index: config.targetObject,
        ptr_prg_offset_before: ptrPrgOffsetBefore,
        operand_offset: operandOffset,
        computed_target_offset: operandOffset,
        exe_switch_before: readExeSwitchStateForObject(config.targetObject),
        exe_switch_after: readExeSwitchStateForObject(config.targetObject),
    });
    if (trackedRun.saw076 && trackedRun.post076ThreadId === threadId) {
        trackedRun.post076OutcomeCaptured = true;
    }
}

function registerToBool(value) {
    return ptr(value).toUInt32() !== 0;
}

function attachBranchHooks() {
    if (branchHooksAttached) {
        return;
    }
    branchHooksAttached = true;

    Interceptor.attach(absolute(offsets.switchWriteEntry), {
        onEnter(args) {
            prepareBranchTrace(this.threadId, "switch_write", ptr(this.context.ebx), false);
        },
    });

    Interceptor.attach(absolute(offsets.switchWritePost), {
        onEnter(args) {
            emitPreparedBranchTrace(this.threadId, undefined);
        },
    });

    Interceptor.attach(absolute(offsets.orCaseEntry), {
        onEnter(args) {
            prepareBranchTrace(this.threadId, "or_case_eval", ptr(this.context.ebx), true);
        },
    });

    Interceptor.attach(absolute(offsets.orCasePostTest), {
        onEnter(args) {
            emitPreparedBranchTrace(this.threadId, registerToBool(this.context.eax));
        },
    });

    Interceptor.attach(absolute(offsets.caseEvalEntry), {
        onEnter(args) {
            prepareBranchTrace(this.threadId, "case_eval", ptr(this.context.ebx), true);
        },
    });

    Interceptor.attach(absolute(offsets.caseEvalPostTest), {
        onEnter(args) {
            emitPreparedBranchTrace(this.threadId, registerToBool(this.context.eax));
        },
    });

    Interceptor.attach(absolute(offsets.breakJumpEntry), {
        onEnter(args) {
            emitBreakJumpTrace(this.threadId, ptr(this.context.ebx));
        },
    });
}

sendEvent("status", {
    message: "life trace agent loaded",
    module_name: mainModule.name,
    module_base: pointerString(base),
    config,
});

if (isScene11Pair) {
    Interceptor.attach(absolute(offsets.doFuncLife), {
        onEnter(args) {
            markScene11Helper(this.threadId, "do_func_life");
        },
    });

    Interceptor.attach(absolute(offsets.doTest), {
        onEnter(args) {
            markScene11Helper(this.threadId, "do_test");
        },
    });
}

if (!isTavernTrace) {
    const doLifeEntryHooks = {
        onEnter(args) {
            const objectIndex = this.context.eax.toUInt32() & 0xff;
            const state = snapshotObjectState(objectIndex);
            stateStackForThread(this.threadId).push(state);
        },
    };

    doLifeEntryHooks.onLeave = function onLeave(retval) {
        const stack = stateStackForThread(this.threadId);
        const state = stack.length === 0 ? undefined : stack[stack.length - 1];
        if (state !== undefined && isScene11Pair) {
            const finalPtrPrg = readPointerSafe(absolute(offsets.ptrPrg));
            if (!finalPtrPrg.isNull()) {
                const afterTrace = buildTrace(state, finalPtrPrg, this.threadId);
                resolveScene11Pending(this.threadId, afterTrace, "do_life_return");
            }
        }
        if (stack.length > 0) {
            stack.pop();
        }
        if (stack.length === 0) {
            delete pendingByThread[this.threadId];
        }
        delete branchPendingByThread[this.threadId];
    };
    Interceptor.attach(absolute(offsets.doLifeEntry), doLifeEntryHooks);
}

Interceptor.attach(absolute(offsets.doLifeLoop), {
    onEnter(args) {
        const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
        if (ptrPrg.isNull()) {
            return;
        }

        if (!isTavernTrace) {
            const state = currentStateForThread(this.threadId);
            if (state === undefined) {
                return;
            }
            const trace = buildTrace(state, ptrPrg, this.threadId);
            trace.matches_target = matchesTarget(trace);
            if (!isScene11Pair) {
                if (!config.logAll && !trace.matches_target) {
                    return;
                }
                sendEvent("trace", trace);
                if (trace.matches_target) {
                    matchedHits += 1;
                    if (matchedHits >= config.maxHits) {
                        sendEvent("status", {
                            message: "requested max matched hits reached",
                            matched_hits: matchedHits,
                        });
                    }
                }
                return;
            }

            if (!scene11Run.matchedFingerprint) {
                maybeEmitScene11Validation(this.threadId, state);
            }
            if (!scene11Run.matchedFingerprint) {
                if (config.logAll) {
                    sendEvent("trace", trace);
                }
                return;
            }

            resolveScene11Pending(this.threadId, trace, "loop_reentry");

            const role = scene11RoleForTrace(trace);
            if (role !== null) {
                queueScene11Match(this.threadId, trace, role);
            }

            if (config.logAll || role !== null) {
                trace.trace_role = role;
                sendEvent("trace", trace);
            }
            return;
        }

        const state = snapshotObjectState(config.targetObject);
        if (state.ptrLifePtr.isNull()) {
            return;
        }

        if (!trackedRun.matchedFingerprint) {
            maybeEmitTargetValidation(this.threadId, state);
        }
        if (!trackedRun.matchedFingerprint) {
            return;
        }

        if (trackedRun.threadId === null && isFocusOffset(pointerDelta(ptrPrg, trackedRun.ptrLifePtr))) {
            trackedRun.threadId = this.threadId;
        }

        if (!isTrackedThread(this.threadId)) {
            if (config.logAll) {
                const trace = buildTrace(state, ptrPrg, this.threadId);
                trace.matches_target = matchesTarget(trace);
                sendEvent("trace", trace);
            }
            return;
        }

        const trace = buildTrace(state, ptrPrg, this.threadId);
        trace.matches_target = matchesTarget(trace);
        recordRecent(state, trace);

        const is076Trace = trace.ptr_prg_offset === config.targetOffset && trace.opcode === config.targetOpcode;
        const wantsLoopReentryProof =
            trackedRun.saw076 &&
            trackedRun.post076ThreadId === this.threadId &&
            !trackedRun.post076OutcomeCaptured &&
            !is076Trace;

        if (is076Trace && !trackedRun.saw076) {
            trackedRun.saw076 = true;
            trackedRun.post076ThreadId = this.threadId;
        }

        if (wantsLoopReentryProof) {
            trackedRun.post076OutcomeCaptured = true;
            trace.post_076_outcome = "loop_reentry";
            sendEvent("window_trace", trace);
            return;
        }

        if (isFocusOffset(trace.ptr_prg_offset)) {
            sendEvent("window_trace", trace);
            return;
        }

        if (config.logAll) {
            sendEvent("trace", trace);
        }
    },
});
