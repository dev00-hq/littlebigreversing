import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;

public class ListTopFunctions extends GhidraScript {
	private static class FunctionInfo {
		Function function;
		long bodySize;
		int instructionCount;
		int callCount;
		Map<String, Integer> callees = new HashMap<>();
	}

	@Override
	protected void run() throws Exception {
		List<FunctionInfo> infos = new ArrayList<>();
		Listing listing = currentProgram.getListing();
		ReferenceManager refs = currentProgram.getReferenceManager();

		for (Function function : listing.getFunctions(true)) {
			if (function.isThunk()) {
				continue;
			}

			FunctionInfo info = new FunctionInfo();
			info.function = function;
			AddressSetView body = function.getBody();
			info.bodySize = body.getNumAddresses();

			InstructionIterator it = listing.getInstructions(body, true);
			while (it.hasNext()) {
				Instruction instruction = it.next();
				info.instructionCount++;
				FlowType flowType = instruction.getFlowType();
				if (!flowType.isCall()) {
					continue;
				}

				info.callCount++;
				for (Reference ref : refs.getReferencesFrom(instruction.getAddress())) {
					if (!ref.getReferenceType().isCall()) {
						continue;
					}
					Function callee = getFunctionAt(ref.getToAddress());
					if (callee != null) {
						String key = callee.getName() + "@" + callee.getEntryPoint();
						info.callees.merge(key, 1, Integer::sum);
					}
				}
			}
			infos.add(info);
		}

		Collections.sort(infos, Comparator
			.comparingLong((FunctionInfo info) -> info.bodySize)
			.reversed()
			.thenComparing(Comparator.comparingInt((FunctionInfo info) -> info.instructionCount).reversed()));

		int limit = Math.min(40, infos.size());
		printf("Top %d functions by body size:\n", limit);
		for (int i = 0; i < limit; i++) {
			FunctionInfo info = infos.get(i);
			printf(
				"%2d. %s %s body=%d insns=%d calls=%d\n",
				i + 1,
				info.function.getName(),
				info.function.getEntryPoint(),
				info.bodySize,
				info.instructionCount,
				info.callCount
			);

			List<Map.Entry<String, Integer>> calleeEntries = new ArrayList<>(info.callees.entrySet());
			Collections.sort(calleeEntries, Comparator
				.comparingInt((Map.Entry<String, Integer> entry) -> entry.getValue())
				.reversed()
				.thenComparing(Map.Entry::getKey));

			int calleeLimit = Math.min(8, calleeEntries.size());
			for (int j = 0; j < calleeLimit; j++) {
				Map.Entry<String, Integer> entry = calleeEntries.get(j);
				printf("    %s x%d\n", entry.getKey(), entry.getValue());
			}
		}
	}
}
