registerScene("scene11-pair", function createScene11PairScene() {
    const scene11Run = {
        matchedFingerprint: false,
        fingerprintThreadId: null,
        fingerprintPtrLifePtr: ptr(0),
        helperHooksInstalled: false,
        pendingByThread: Object.create(null),
        resolvedRoles: Object.create(null),
    };

    function maybeInstallScene11HelperHooks() {
        if (!config.helperCaptureEnabled || scene11Run.helperHooksInstalled) {
            return;
        }

        Interceptor.attach(absolute(offsets.doFuncLife), {
            onEnter(args) {
                markScene11Helper.call(this, this.threadId, "do_func_life");
            },
        });

        Interceptor.attach(absolute(offsets.doTest), {
            onEnter(args) {
                markScene11Helper.call(this, this.threadId, "do_test");
            },
        });

        scene11Run.helperHooksInstalled = true;
    }

    function maybeEmitScene11Validation(threadId, state) {
        if (scene11Run.matchedFingerprint || state.object_index !== config.targetObject) {
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
        maybeInstallScene11HelperHooks();

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
        if (role === null || scene11Run.resolvedRoles[role] || scene11HasPendingRole(role)) {
            return false;
        }

        scene11Run.pendingByThread[threadId] = {
            role,
            trace,
            state: {
                object_index: trace.object_index,
                current_object: trace.current_object,
                ptrLifePtr: ptr(trace.ptr_life),
                ptr_life: trace.ptr_life,
                offset_life: trace.offset_life,
            },
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

    function resolveScene11PendingAtLoop(threadId, ptrPrg) {
        const pending = scene11Run.pendingByThread[threadId];
        if (pending === undefined) {
            return false;
        }

        const afterTrace = buildTrace(pending.state, ptrPrg, threadId);
        return resolveScene11Pending(threadId, afterTrace, "loop_reentry");
    }

    function markScene11Helper(threadId, helperName) {
        const pending = scene11Run.pendingByThread[threadId];
        if (pending === undefined) {
            return;
        }

        const calleeName = helperName === "do_func_life" ? "DoFuncLife" : "DoTest";
        sendEvent("helper_callsite", {
            callee_name: calleeName,
            caller_static_live: pointerString(this.returnAddress),
            caller_static_rel: pointerRelativeHex(this.returnAddress, base),
            thread_id: pending.trace.thread_id,
            object_index: pending.trace.object_index,
            owner_kind: pending.trace.owner_kind,
            ptr_life: pending.trace.ptr_life,
            ptr_prg: pending.trace.ptr_prg,
            ptr_prg_offset: pending.trace.ptr_prg_offset,
            opcode: pending.trace.opcode,
            opcode_hex: pending.trace.opcode_hex,
            trace_role: pending.role,
        });

        if (helperName === "do_func_life") {
            pending.enteredDoFuncLife = true;
        } else if (helperName === "do_test") {
            pending.enteredDoTest = true;
        }
    }

    return {
        installHooks() {
            Interceptor.attach(absolute(offsets.doLifeLoop), {
                onEnter(args) {
                    const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
                    if (ptrPrg.isNull()) {
                        return;
                    }

                    const targetState = snapshotObjectState(config.targetObject);
                    if (!scene11Run.matchedFingerprint) {
                        if (!targetState.ptrLifePtr.isNull()) {
                            maybeEmitScene11Validation(this.threadId, targetState);
                        }
                        if (!scene11Run.matchedFingerprint) {
                            return;
                        }
                    }

                    resolveScene11PendingAtLoop(this.threadId, ptrPrg);

                    let matchedTrace = null;
                    let matchedRole = null;

                    if (!targetState.ptrLifePtr.isNull()) {
                        const primaryTrace = buildTrace(targetState, ptrPrg, this.threadId);
                        primaryTrace.matches_target = matchesTarget(primaryTrace);
                        if (scene11RoleForTrace(primaryTrace) === "primary") {
                            matchedTrace = primaryTrace;
                            matchedRole = "primary";
                        }
                    }

                    if (matchedRole === null && config.comparisonObject !== null) {
                        const comparisonState = snapshotObjectState(config.comparisonObject);
                        if (!comparisonState.ptrLifePtr.isNull()) {
                            const comparisonTrace = buildTrace(comparisonState, ptrPrg, this.threadId);
                            comparisonTrace.matches_target = matchesTarget(comparisonTrace);
                            if (scene11RoleForTrace(comparisonTrace) === "comparison") {
                                matchedTrace = comparisonTrace;
                                matchedRole = "comparison";
                            }
                        }
                    }

                    if (matchedTrace === null) {
                        return;
                    }

                    matchedTrace.trace_role = matchedRole;
                    queueScene11Match(this.threadId, matchedTrace, matchedRole);
                    sendEvent("trace", matchedTrace);
                },
            });
        },
    };
});
