import binary.common; //Needed for some pack-d functions
import binary.pack; //For formatting data into specific types
import binary.reader; //For parsing data from raw byte arrays
import bmsinterpret;
import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format : format;
import std.getopt;
import std.path;
import std.stdio;
import std.string;

int main(string[] args)
{
	//Setup Arguments
    if (args.length == 1) {
        writeln("No arguments given. Please provide BMS/Decomp TXT.");
        return 1;
    }
    string filename = "filename.bms";
    int workSuccess;
    auto const argInfo = getopt(args, "input", &filename);
    if (extension(filename) == ".bms") {
        writeln("Decompiling BMS...");
        workSuccess = decompileBMS(filename);
        return workSuccess;
    } else if (extension(filename) == ".txt") {
        writeln("Recompiling BMS...");
        workSuccess = recompileBMS(filename);
        return workSuccess;
    }
    return 1;
}

///Decompiles a BMS file, creating an editable text based format in the process
int decompileBMS(string filename) {
    File bms = File(filename, "rb");
    //Prepare binaryReader
    ubyte[] data;
    data.length = 1;
    auto reader = binaryReader(data);
    while (!bms.eof()) {
        writeln("At ", format!"%X"(bms.tell), " in file.");
        bms.rawRead(data);
        const ubyte opcode = reader.read!ubyte();
        const ubyte bmsInstruction = parseOpcode(opcode);
        printBMSInstruction(bmsInstruction, bms);
        data = [];
        data.length = 1;
        reader.source(data);
    }
    writeln("Finished Decompiling!");
    return 0;
}

///Recompiles a BMS file from our editable text format
int recompileBMS(string filename) {
    return 0;
}