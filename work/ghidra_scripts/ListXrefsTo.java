import java.util.Set;
import java.util.TreeSet;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;

public class ListXrefsTo extends GhidraScript {
	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("Usage: ListXrefsTo <address> [address...]");
			return;
		}

		ReferenceManager refs = currentProgram.getReferenceManager();
		for (String arg : getScriptArgs()) {
			Address address = toAddr(arg);
			printf("Xrefs to %s\n", address);
			Set<String> lines = new TreeSet<>();
			ReferenceIterator it = refs.getReferencesTo(address);
			while (it.hasNext()) {
				Reference ref = it.next();
				Function function = getFunctionContaining(ref.getFromAddress());
				String owner = function == null
					? "<no function>"
					: function.getName() + "@" + function.getEntryPoint();
				lines.add(String.format("  %s in %s type=%s", ref.getFromAddress(), owner, ref.getReferenceType()));
			}

			if (lines.isEmpty()) {
				printf("  <none>\n");
			}
			else {
				for (String line : lines) {
					printf("%s\n", line);
				}
			}
		}
	}
}
