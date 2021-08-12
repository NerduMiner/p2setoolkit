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
    string filename = "se.bms";
    string task = "decompile";
    int workSuccess;
    auto const argInfo = getopt(args, "input", &filename, "task", &task);
    if (extension(filename) == ".bms") {
        if (task != "print" && task != "decompile")
            throw new Exception("Task argument must either be 'print' or 'decompile'");
        writeln("Decompiling BMS...");
        workSuccess = decompileBMS(filename, task);
        return workSuccess;
    } else if (extension(filename) == ".txt") {
        writeln("Recompiling BMS...");
        workSuccess = recompileBMS(filename);
        return workSuccess;
    }
    return 1;
}

///Decompiles a BMS file, either creating an editable text based format or printing out instructions in the process
int decompileBMS(string filename, string task) {
    File bms = File(filename, "rb");
    File bmsinfo = File(filename ~ ".info", "r");
    File decompiledBMS = File(filename ~ ".txt", "w");
    const int dataAmnt = to!int(bmsinfo.readln().strip());
    BMSDataInfo[] bmsInfo;
    BMSLabel[] decompiledLabels;
    ulong[ulong] addressLookUptable;
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
        /*if(bms.tell() >= 15331) {
            readln();
            writeln("At ", format!"%X"(bms.tell), " in file.");
        }*/
        //writeln("At ", format!"%X"(bms.tell), " in file.");
        //We need to check if we're at a spot in the file where a label should be dropped
        //FIRST check if we are at a label position as long as we actually have some
        addressLookUptable[bms.tell()] = decompiledBMS.tell();
        //We need to make sure that we aren't reading arbitrary data first, so do a check before parsing an instruction
        if (bms.tell() == bmsInfo[dataInfoPosition].position) {
            writeln("Detected special data block at ", bms.tell(), ".");
            writeln("Data Type: ", bmsInfo[dataInfoPosition].dataType);
            if (bmsInfo[dataInfoPosition].dataType == "data") {
                HandleBMSArbitraryData(bms, bmsInfo);
            }
            if (bmsInfo[dataInfoPosition].dataType == "jumptable") {
                if (task == "print") {
                    HandleBMSJumpTable(bms, bmsInfo);
                } else if (task == "decompile") {
                    HandleBMSJumpTableFile(bms, decompiledBMS, bmsInfo, addressLookUptable);
                }
            }
            if (bmsInfo[dataInfoPosition].dataType == "padding") {
                HandleBMSPadding(bms, bmsInfo);
            }
            if (bmsInfo[dataInfoPosition].dataType == "a5_3bytearg_override") {
                bms.rawRead(data);
                const ubyte opcode = reader.read!ubyte();
                if (task == "print") {
                    A53ByteArgOverride(bms, opcode);
                } else if (task == "decompile") {
                    A53ByteArgOverrideFile(bms, decompiledBMS);
                }
                data = [];
                data.length = 1;
                reader.source(data);
            }
            if (bmsInfo[dataInfoPosition].dataType == "a8_3bytearg_override") {
                bms.rawRead(data);
                const ubyte opcode = reader.read!ubyte();
                if (task == "print") {
                    A83ByteArgOverride(bms, opcode);
                } else if (task == "decompile") {
                    A83ByteArgOverrideFile(bms, decompiledBMS, opcode);
                }
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
        if (task == "print") {
            printBMSInstruction(bmsInstruction, bms);
        } else if (task == "decompile") {
            decompileBMSInstruction(bmsInstruction, bms, decompiledBMS, &decompiledLabels);
        }
        data = [];
        data.length = 1;
        reader.source(data);
    }
    decompiledBMS.reopen(null, "r+");
    decompiledLabels.sort();
    writefln("Adding %s labels...THIS MAY TAKE TIME", decompiledLabels.length);
    foreach(label; decompiledLabels) {
        //writeln(label.position);
        if (bms.tell() > label.position) {
            //writefln("Appending label %s at %s", label.labelname, addressLookUptable[label.position]);
            decompiledBMS.seek(addressLookUptable[label.position]);
            string buffer;
            foreach(line; decompiledBMS.byLine) {
                buffer ~= line ~ "\n";
            }
            decompiledBMS.seek(addressLookUptable[label.position]);
            decompiledBMS.write(label.labelname ~ "\n" ~ buffer);
            buffer = "";
        }
    }
    writeln("Finished Decompiling!");
    return 0;
}

///Recompiles a BMS file from our editable text format
int recompileBMS(string filename) {
    return 0;
}