const config = (() => {
    const defaults = {
        moduleName: "LBA2.EXE",
        logAll: false,
        maxHits: 1,
        targetObject: 0,
        targetOpcode: 0x76,
        targetOffset: 46,
        windowBefore: 8,
        windowAfter: 8,
    };
    return Object.assign(defaults, __TRACE_CONFIG__);
})();

const offsets = {
    doLifeEntry: 0x00020574,
    doLifeLoop: 0x000205bc,
    ptrPrg: 0x000576d0,
    typeAnswer: 0x000576d4,
    value: 0x00057d44,
    objectBase: 0x0005a19c,
    objectStride: 0x21b,
    ptrLife: 0x1ee,
    offsetLife: 0x1f2,
    exeSwitchFunc: 0x20e,
    exeSwitchTypeAnswer: 0x20f,
    exeSwitchValue: 0x210,
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
let matchedHits = 0;

function absolute(offset) {
    return base.add(offset);
}

function sendEvent(kind, payload) {
    send({
        kind,
        timestamp_utc: new Date().toISOString(),
        payload,
    });
}

function pointerString(pointerValue) {
    return pointerValue.isNull() ? "0x0" : pointerValue.toString();
}

function readPointerSafe(pointerValue) {
    try {
        return Memory.readPointer(pointerValue);
    } catch (error) {
        return ptr(0);
    }
}

function readU8Safe(pointerValue) {
    try {
        return Memory.readU8(pointerValue);
    } catch (error) {
        return null;
    }
}

function readS16Safe(pointerValue) {
    try {
        return Memory.readS16(pointerValue);
    } catch (error) {
        return null;
    }
}

function readS32Safe(pointerValue) {
    try {
        return Memory.readS32(pointerValue);
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
        const raw = Memory.readByteArray(start, length);
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

function snapshotObjectState(objectIndex) {
    const currentObject = currentObjectAddress(objectIndex);
    const ptrLife = readPointerSafe(currentObject.add(offsets.ptrLife));
    const offsetLife = readS16Safe(currentObject.add(offsets.offsetLife));
    return {
        object_index: objectIndex,
        current_object: pointerString(currentObject),
        ptr_life: pointerString(ptrLife),
        offset_life: offsetLife,
        exe_switch: {
            func: readU8Safe(currentObject.add(offsets.exeSwitchFunc)),
            type_answer: readU8Safe(currentObject.add(offsets.exeSwitchTypeAnswer)),
            value: readS32Safe(currentObject.add(offsets.exeSwitchValue)),
        },
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

sendEvent("status", {
    message: "life trace agent loaded",
    module_name: mainModule.name,
    module_base: pointerString(base),
    config,
});

Interceptor.attach(absolute(offsets.doLifeEntry), {
    onEnter(args) {
        const objectIndex = args[0].toUInt32() & 0xff;
        pendingByThread[this.threadId] = snapshotObjectState(objectIndex);
    },
});

Interceptor.attach(absolute(offsets.doLifeLoop), {
    onEnter(args) {
        const state = pendingByThread[this.threadId];
        if (state === undefined) {
            return;
        }

        const ptrPrg = readPointerSafe(absolute(offsets.ptrPrg));
        if (ptrPrg.isNull()) {
            return;
        }

        const opcode = readU8Safe(ptrPrg);
        const trace = {
            object_index: state.object_index,
            owner_kind: state.object_index === 0 ? "hero" : "object",
            current_object: state.current_object,
            ptr_life: state.ptr_life,
            offset_life: state.offset_life,
            ptr_prg: pointerString(ptrPrg),
            ptr_prg_offset: pointerDelta(ptrPrg, ptr(state.ptr_life)),
            opcode,
            opcode_hex: opcode === null ? null : `0x${opcode.toString(16).padStart(2, "0")}`,
            ptr_window: readWindow(ptrPrg),
            working_type_answer: readU8Safe(absolute(offsets.typeAnswer)),
            working_value: readS32Safe(absolute(offsets.value)),
            exe_switch: snapshotObjectState(state.object_index).exe_switch,
        };

        trace.matches_target = matchesTarget(trace);
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
    },
});
