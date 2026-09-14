// Static analysis only: export recovered function pseudocode, never execute Canon code.
// @category CanonResearch
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;

public class ExportCanonFunctions extends GhidraScript {
    public void run() throws Exception {
        Path directory = Path.of(getScriptArgs()[0], currentProgram.getName());
        Files.createDirectories(directory);
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
        int count = 0, failed = 0;
        try {
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function function = functions.next();
                if (function.isExternal()) continue;
                DecompileResults result = decompiler.decompileFunction(function, 30, monitor);
                String text = "/* " + function.getEntryPoint() + " " + function.getName() + " */\n";
                if (result.decompileCompleted()) text += result.getDecompiledFunction().getC();
                else { text += "/* FAILED: " + result.getErrorMessage() + " */\n"; failed++; }
                Files.writeString(directory.resolve(function.getEntryPoint().toString() + ".c"), text, StandardCharsets.UTF_8);
                count++;
            }
        } finally { decompiler.dispose(); }
        println("Exported " + count + " functions; " + failed + " decompilation failures to " + directory);
    }
}
