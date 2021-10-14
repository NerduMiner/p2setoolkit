import bmsinterpret;
import std.path;
import std.stdio;
import std.string;
//import vibe.data.json;

int main(string[] args)
{
	//Setup Arguments
    if (args.length == 1) {
        writeln("No arguments given. Please provide BMS/Decomp TXT.");
        return 1;
    }
    string filename;
    string task = "bofadeez";
    string mode = "jv1pikmin2";
    int workSuccess;
    //auto const argInfo = getopt(args, "input", &filename, "task", &task, "mode", &mode);
    if (extension(args[1]) == ".bms") {
        writeln("Decompiling BMS...");
        if (args.length == 4) {
        	task = args[2];
        	mode = args[3];
        } else if (args.length == 3) {
        	task = args[2];
        }
        if (task != "print" && task != "decompile")
            throw new Exception("task argument must either be 'print' or 'decompile'");
        workSuccess = decompileBMS(args[1], task, mode);
        return workSuccess;
    } else if (extension(args[1]) == ".txt") {
        writeln("Recompiling BMS...");
        if (args.length == 3) {
        	mode = args[2];
        }
        workSuccess = recompileBMS(args[1], mode);
        return workSuccess;
    }
    return 1;
}