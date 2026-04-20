import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSetView;
import ghidra.program.model.listing.CodeUnit;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;
import ghidra.program.model.symbol.ReferenceManager;

public class FindStringRefs extends GhidraScript {
	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length != 1) {
			printerr("Usage: FindStringRefs <substring>");
			return;
		}

		String needle = getScriptArgs()[0];
		Listing listing = currentProgram.getListing();
		ReferenceManager refs = currentProgram.getReferenceManager();
		List<Address> matches = new ArrayList<>();
		byte[] pattern = needle.getBytes(StandardCharsets.US_ASCII);
		AddressSetView loadedAndInitialized = currentProgram.getMemory().getLoadedAndInitializedAddressSet();
		Address cursor = loadedAndInitialized.getMinAddress();
		while (cursor != null) {
			Address found = currentProgram.getMemory().findBytes(cursor, pattern, null, true, monitor);
			if (found == null || !loadedAndInitialized.contains(found)) {
				break;
			}
			matches.add(found);
			printf("Raw string match at %s\n", found);
			cursor = found.add(1);
		}

		if (matches.isEmpty()) {
			printerr("No raw strings contain: " + needle);
			return;
		}

		Collections.sort(matches);
		for (Address address : matches) {
			printf("Xrefs to %s:\n", address);
			ReferenceIterator iter = refs.getReferencesTo(address);
			while (iter.hasNext()) {
				Reference ref = iter.next();
				Function fn = getFunctionContaining(ref.getFromAddress());
				Data fromData = listing.getDefinedDataContaining(ref.getFromAddress());
				CodeUnit cu = listing.getCodeUnitContaining(ref.getFromAddress());
				String owner;
				if (fn != null) {
					owner = fn.getName() + "@" + fn.getEntryPoint();
				}
				else if (fromData != null) {
					owner = "DATA@" + fromData.getAddress();
				}
				else if (cu != null) {
					owner = cu.getAddressString(false, true);
				}
				else {
					owner = ref.getFromAddress().toString();
				}
				printf("  %s via %s\n", owner, ref.getFromAddress());
			}
		}
	}
}
