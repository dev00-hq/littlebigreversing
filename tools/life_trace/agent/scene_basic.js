registerScene("basic", function createBasicScene() {
    let matchedHits = 0;

    return {
        usesDoLifeEntryState: true,

        onDoLifeLoop(threadId, ptrPrg) {
            const state = currentStateForThread(threadId);
            if (state === undefined) {
                return;
            }

            const trace = buildTrace(state, ptrPrg, threadId);
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
    };
});
