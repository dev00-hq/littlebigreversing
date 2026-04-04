import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;

public class DescribeFunction extends GhidraScript {
	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("Usage: DescribeFunction <address> [line_limit]");
			return;
		}

		Address address = toAddr(getScriptArgs()[0]);
		Function function = getFunctionContaining(address);
		if (function == null) {
			printerr("No function contains " + address);
			return;
		}

		printf("Function %s at %s\n", function.getName(), function.getEntryPoint());
		printf("Signature: %s\n", function.getSignature(true));

		Listing listing = currentProgram.getListing();
		ReferenceManager refs = currentProgram.getReferenceManager();
		AddressSetView body = function.getBody();

		Map<String, Integer> calleeCounts = new HashMap<>();
		Set<String> globalRefs = new HashSet<>();

		InstructionIterator it = listing.getInstructions(body, true);
		while (it.hasNext()) {
			Instruction instruction = it.next();
			for (Reference ref : refs.getReferencesFrom(instruction.getAddress())) {
				if (ref.getReferenceType().isCall()) {
					Function callee = getFunctionAt(ref.getToAddress());
					if (callee != null) {
						String key = callee.getName() + "@" + callee.getEntryPoint();
						calleeCounts.merge(key, 1, Integer::sum);
					}
					continue;
				}

				Data data = listing.getDefinedDataAt(ref.getToAddress());
				if (data != null) {
					String label = ref.getToAddress() + " " + data.getDataType().getName() + " " + data;
					globalRefs.add(label);
				}
				else if (!body.contains(ref.getToAddress())) {
					globalRefs.add(ref.getToAddress().toString());
				}
			}
		}

		List<Map.Entry<String, Integer>> calleeList = new ArrayList<>(calleeCounts.entrySet());
		Collections.sort(calleeList, Comparator
			.comparingInt((Map.Entry<String, Integer> entry) -> entry.getValue())
			.reversed()
			.thenComparing(Map.Entry::getKey));

		printf("Callees:\n");
		for (Map.Entry<String, Integer> entry : calleeList) {
			printf("  %s x%d\n", entry.getKey(), entry.getValue());
		}

		List<String> globals = new ArrayList<>(globalRefs);
		Collections.sort(globals);
		printf("External/data refs:\n");
		for (String global : globals) {
			printf("  %s\n", global);
		}

		DecompInterface ifc = new DecompInterface();
		ifc.openProgram(currentProgram);
		DecompileResults results = ifc.decompileFunction(function, 60, monitor);
		if (!results.decompileCompleted()) {
			printerr("Decompilation failed: " + results.getErrorMessage());
			return;
		}

		int limit = 220;
		if (getScriptArgs().length > 1) {
			limit = Integer.parseInt(getScriptArgs()[1]);
		}

		printf("Decompiled C:\n");
		String[] lines = results.getDecompiledFunction().getC().split("\\R");
		int actualLimit = Math.min(lines.length, limit);
		for (int i = 0; i < actualLimit; i++) {
			printf("%4d  %s\n", i + 1, lines[i]);
		}
		if (lines.length > actualLimit) {
			printf("... (%d total lines)\n", lines.length);
		}
	}
}
