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
//import vibe.data.json;

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
    File bmsinfo = File(filename ~ ".info", "r");
    File decompiledBMS = File(filename ~ ".txt", "w");
    const int dataAmnt = to!int(bmsinfo.readln().strip());
    BMSDataInfo[] bmsInfo;
    bmsInfo.length = dataAmnt;
    writeln(dataAmnt, " override[s] found for this bms file.");
    for(int i = 0; i < dataAmnt; i++) {
        bmsInfo[i].position = to!int(bmsinfo.readln().strip());
        bmsInfo[i].dataType = bmsinfo.readln().strip();
        bmsInfo[i].dataLength = to!int(bmsinfo.readln().strip());
    }
    //Prepare binaryReader
    ubyte[] data;
    data.length = 1;
    auto reader = binaryReader(data);
    while (!bms.eof()) {
        writeln("At ", format!"%X"(bms.tell), " in file.");
        //We need to make sure that we aren't reading arbitrary data first, so do a check before parsing an instruction
        if (bms.tell() == bmsInfo[dataInfoPosition].position) {
            writeln("Detected special data block at ", bms.tell(), ".");
            writeln("Data Type: ", bmsInfo[dataInfoPosition].dataType);
            if (bmsInfo[dataInfoPosition].dataType == "data") {
                HandleBMSArbitraryData(bms, bmsInfo);
            }
            if (bmsInfo[dataInfoPosition].dataType == "jumptable") {
                //HandleBMSJumpTable(bms, bmsInfo);
                HandleBMSJumpTableFile(bms, decompiledBMS, bmsInfo);
            }
            if (bmsInfo[dataInfoPosition].dataType == "padding") {
                HandleBMSPadding(bms, bmsInfo);
            }
            if (bmsInfo[dataInfoPosition].dataType == "a5_3bytearg_override") {
                bms.rawRead(data);
                const ubyte opcode = reader.read!ubyte();
                //A53ByteArgOverride(bms, opcode);
                A53ByteArgOverrideFile(bms, decompiledBMS, opcode);
                data = [];
                data.length = 1;
                reader.source(data);
            }
            if (bmsInfo[dataInfoPosition].dataType == "a8_3bytearg_override") {
                bms.rawRead(data);
                const ubyte opcode = reader.read!ubyte();
                //A83ByteArgOverride(bms, opcode);
                A83ByteArgOverrideFile(bms, decompiledBMS, opcode);
                data = [];
                data.length = 1;
                reader.source(data);
            }
            dataInfoPosition += 1;
            continue;
        }
        bms.rawRead(data);
        const ubyte opcode = reader.read!ubyte();
        const ubyte bmsInstruction = parseOpcode(opcode);
        //printBMSInstruction(bmsInstruction, bms);
        decompileBMSInstruction(bmsInstruction, bms, decompiledBMS);
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