registerScene("scene11-live-pair", function createScene11LivePairScene() {
    return {
        usesDoLifeEntryState: false,

        installHooks() {
            const liveStateByThread = Object.create(null);

            function stackForThread(threadId) {
                if (liveStateByThread[threadId] === undefined) {
                    liveStateByThread[threadId] = [];
                }
                return liveStateByThread[threadId];
            }

            Interceptor.attach(absolute(offsets.doLifeEntry), {
                onEnter(args) {
                    const objectIndex = this.context.eax.toUInt32() & 0xff;
                    const currentObject = absolute(offsets.objectBase).add(objectIndex * offsets.objectStride);
                    const ptrLifePtr = readPointerSafe(currentObject.add(offsets.ptrLife));
                    const offsetLife = readS16Safe(currentObject.add(offsets.offsetLife));
                    stackForThread(this.threadId).push({
                        objectIndex,
                        currentObject: pointerString(currentObject),
                        ptrLifePtr,
                        ptrLife: pointerString(ptrLifePtr),
                        offsetLife,
                    });
                },
                onLeave(retval) {
                    const stack = stackForThread(this.threadId);
                    if (stack.length > 0) {
                        stack.pop();
                    }
                    if (stack.length === 0) {
                        delete liveStateByThread[this.threadId];
                    }
                },
            });

            Interceptor.attach(absolute(offsets.doLifeLoop), {
                onEnter(args) {
                    const stack = liveStateByThread[this.threadId];
                    if (stack === undefined || stack.length === 0) {
                        return;
                    }
                    const state = stack[stack.length - 1];
                    if (state.objectIndex !== config.targetObject || state.ptrLifePtr.isNull()) {
                        return;
                    }

                    const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
                    if (ptrPrg.isNull()) {
                        return;
                    }

                    const ptrPrgOffset = pointerDelta(ptrPrg, state.ptrLifePtr);
                    const opcode = readU8Safe(ptrPrg);
                    const isEndSwitch =
                        ptrPrgOffset === config.targetOffset && opcode === config.targetOpcode;
                    const isDefault =
                        ptrPrgOffset === config.comparisonOffset && opcode === config.comparisonOpcode;
                    if (!isEndSwitch && !isDefault) {
                        return;
                    }

                    sendEvent("window_trace", {
                        thread_id: this.threadId,
                        object_index: state.objectIndex,
                        owner_kind: "object",
                        current_object: state.currentObject,
                        ptr_life: state.ptrLife,
                        offset_life: state.offsetLife,
                        matches_target: isEndSwitch,
                        ptr_prg: pointerString(ptrPrg),
                        ptr_prg_offset: ptrPrgOffset,
                        opcode,
                        opcode_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
                        byte_at_ptr_prg: opcode,
                        byte_at_ptr_prg_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
                    });
                },
            });

            sendEvent("status", {
                message: "scene11 live pair hooks installed",
            });
        },
    };
});
