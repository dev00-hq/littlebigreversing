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
const sceneFactories = Object.create(null);
const pendingByThread = Object.create(null);

function registerScene(name, factory) {
    if (sceneFactories[name] !== undefined) {
        throw new Error(`duplicate life_trace scene registration: ${name}`);
    }
    sceneFactories[name] = factory;
}

function createScene(mode) {
    const factory = sceneFactories[mode];
    if (factory === undefined) {
        throw new Error(`unsupported life_trace mode: ${mode}`);
    }
    return factory();
}

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

function clearStateStackForThread(threadId) {
    delete pendingByThread[threadId];
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

function pointerRelativeHex(pointerValue, basePointer) {
    if (pointerValue.isNull() || basePointer.isNull()) {
        return null;
    }
    const relative = (pointerValue.toUInt32() - basePointer.toUInt32()) >>> 0;
    return `0x${relative.toString(16).toUpperCase().padStart(8, "0")}`;
}

function currentObjectAddress(objectIndex) {
    return absolute(offsets.objectBase).add(objectIndex * offsets.objectStride);
}

function readExeSwitchStateForObject(objectIndex) {
    const currentObject = currentObjectAddress(objectIndex);
    return {
        func: readU8Safe(currentObject.add(0x20e)),
        type_answer: readU8Safe(currentObject.add(0x20f)),
        value: readS32Safe(currentObject.add(0x210)),
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

function installDoLifeEntryHooks(scene) {
    if (!scene.usesDoLifeEntryState) {
        return;
    }

    const doLifeEntryHooks = {
        onEnter(args) {
            const objectIndex = this.context.eax.toUInt32() & 0xff;
            const state = snapshotObjectState(objectIndex);
            stateStackForThread(this.threadId).push(state);
            if (scene.onDoLifeEntry !== undefined) {
                scene.onDoLifeEntry(this.threadId, state);
            }
        },
    };

    doLifeEntryHooks.onLeave = function onLeave(retval) {
        const stack = stateStackForThread(this.threadId);
        const state = stack.length === 0 ? undefined : stack[stack.length - 1];
        if (state !== undefined && scene.onDoLifeLeave !== undefined) {
            scene.onDoLifeLeave(this.threadId, state);
        }
        if (stack.length > 0) {
            stack.pop();
        }
        if (stack.length === 0) {
            clearStateStackForThread(this.threadId);
        }
    };

    Interceptor.attach(absolute(offsets.doLifeEntry), doLifeEntryHooks);
}

function installDoLifeLoopHook(scene) {
    Interceptor.attach(absolute(offsets.doLifeLoop), {
        onEnter(args) {
            const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
            if (ptrPrg.isNull()) {
                return;
            }
            scene.onDoLifeLoop(this.threadId, ptrPrg);
        },
    });
}
