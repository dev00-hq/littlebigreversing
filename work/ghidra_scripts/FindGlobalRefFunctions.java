import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;

public class FindGlobalRefFunctions extends GhidraScript {
	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("Usage: FindGlobalRefFunctions <addr> [<addr>...]");
			return;
		}

		List<Address> targets = new ArrayList<>();
		for (String arg : getScriptArgs()) {
			targets.add(toAddr(arg));
		}

		Listing listing = currentProgram.getListing();
		ReferenceManager refs = currentProgram.getReferenceManager();
		Map<String, List<String>> hits = new HashMap<>();

		for (Function function : listing.getFunctions(true)) {
			AddressSetView body = function.getBody();
			InstructionIterator it = listing.getInstructions(body, true);
			while (it.hasNext()) {
				Instruction instruction = it.next();
				for (Reference ref : refs.getReferencesFrom(instruction.getAddress())) {
					for (Address target : targets) {
						if (!ref.getToAddress().equals(target)) {
							continue;
						}
						String key = function.getName() + "@" + function.getEntryPoint();
						hits.computeIfAbsent(key, ignored -> new ArrayList<>())
							.add(target.toString() + " from " + instruction.getAddress());
					}
				}
			}
		}

		List<String> keys = new ArrayList<>(hits.keySet());
		Collections.sort(keys);
		for (String key : keys) {
			printf("%s\n", key);
			for (String hit : hits.get(key)) {
				printf("  %s\n", hit);
			}
		}
	}
}
