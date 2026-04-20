import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;

public class DescribeAddress extends GhidraScript {
	@Override
	protected void run() throws Exception {
		if (getScriptArgs().length == 0) {
			printerr("Usage: DescribeAddress <address> [before] [after]");
			return;
		}

		Address center = toAddr(getScriptArgs()[0]);
		int before = getScriptArgs().length > 1 ? Integer.parseInt(getScriptArgs()[1]) : 8;
		int after = getScriptArgs().length > 2 ? Integer.parseInt(getScriptArgs()[2]) : 12;
		Function function = getFunctionContaining(center);
		Listing listing = currentProgram.getListing();

		printf("Address %s\n", center);
		if (function != null) {
			printf("Containing function %s at %s\n", function.getName(), function.getEntryPoint());
		} else {
			printf("No containing function\n");
		}

		Instruction start = listing.getInstructionContaining(center);
		if (start == null) {
			printerr("No instruction at " + center);
			return;
		}

		Instruction cursor = start;
		for (int i = 0; i < before && cursor.getPrevious() != null; i++) {
			cursor = cursor.getPrevious();
		}

		int total = before + after + 1;
		for (int i = 0; i < total && cursor != null; i++) {
			String marker = cursor.getMinAddress().equals(start.getMinAddress()) ? ">>" : "  ";
			printf(
				"%s %s  %-10s %s\n",
				marker,
				cursor.getAddress(),
				cursor.getBytes().toString(),
				cursor
			);
			cursor = cursor.getNext();
		}
	}
}
