import binary.common; //Needed for some pack-d functions
import binary.pack; //For formatting data into specific types
import binary.reader; //For parsing data from raw byte arrays
import binary.writer; //For assisting in writing raw byte arrays
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
    string filename;
    string task = "bofadeez";
    string mode = "jv1pikmin2";
    int workSuccess;
    auto const argInfo = getopt(args, "input", &filename, "task", &task, "mode", &mode);
    if (extension(filename) == ".bms") {
        if (task != "print" && task != "decompile")
            throw new Exception("--task argument must either be 'print' or 'decompile', did you add --task to your arguments?");
        writeln("Decompiling BMS...");
        workSuccess = decompileBMS(filename, task, mode);
        return workSuccess;
    } else if (extension(filename) == ".txt") {
        writeln("Recompiling BMS...");
        workSuccess = recompileBMS(filename, mode);
        return workSuccess;
    }
    return 1;
}

///Decompiles a BMS file, either creating an editable text based format or printing out instructions in the process
int decompileBMS(string filename, string task, string mode) {
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
        if (bmsInfo[i].dataType == "jumptable") {
            bmsInfo[i].padlength = to!int(bmsinfo.readln().strip());
        }
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
        //writeln("At ", format!"%s"(bms.tell), " in file.");
        //readln();
        //We need to check if we're at a spot in the file where a label should be dropped
        //FIRST check if we are at a label position as long as we actually have some
        addressLookUptable[bms.tell()] = decompiledBMS.tell();
        //We need to make sure that we aren't reading arbitrary data first, so do a check before parsing an instruction
        if (bms.tell() == bmsInfo[dataInfoPosition].position) {
            //writeln("Detected special data block at ", bms.tell(), ".");
            //writeln("Data Type: ", bmsInfo[dataInfoPosition].dataType);
            if (bmsInfo[dataInfoPosition].dataType == "data") {
                if (task == "print") {
                    HandleBMSArbitraryData(bms, bmsInfo);
                } else if (task == "decompile") {
                    HandleBMSArbitraryDataFile(bms, decompiledBMS, bmsInfo);
                }
            }
            if (bmsInfo[dataInfoPosition].dataType == "jumptable") {
                if (task == "print") {
                    HandleBMSJumpTable(bms, bmsInfo);
                } else if (task == "decompile") {
                    HandleBMSJumpTableFile(bms, decompiledBMS, bmsInfo, addressLookUptable, &decompiledLabels);
                }
            }
            if (bmsInfo[dataInfoPosition].dataType == "envelope") {
                if (task == "print") {
                    HandleBMSEnvelope(bms, bmsInfo);
                } else if (task == "decompile") {
                    HandleBMSEnvelopeFile(bms, decompiledBMS, bmsInfo);
                }
            }
            if (bmsInfo[dataInfoPosition].dataType == "padding") {
                if (task == "print") {
                    HandleBMSPadding(bms, bmsInfo);
                } else if (task == "decompile") {
                    HandleBMSPaddingFile(bms, decompiledBMS, bmsInfo);
                }
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
            printBMSInstruction(bmsInstruction, bms, mode);
        } else if (task == "decompile") {
            decompileBMSInstruction(bmsInstruction, bms, decompiledBMS, &decompiledLabels, mode);
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
int recompileBMS(string filename, string mode) {
    File bms = File(filename, "r");
    File bmsOutput = File(filename ~ ".bms", "wb");
    writeln("Doing first pass of assembling...");
    ulong[string] compiledLabels; //Ulong = address in bmsOutput, string = label name
    uint outputPos;
    //Assembling needs to be done in two passes, 
    //first we need to mark all label positions
    //for every other command we will simply count how many bytes that
    //instruction would be at in the output
    string linebuf;
    string label;
    foreach (line; bms.byLine) {
        linebuf = cast(string)line;
        //writeln(linebuf);
        if (canFind(linebuf, ":")) { //Check if the current line is a label
            label = chop(linebuf);
            compiledLabels[label.idup] = outputPos;
            writefln("Label %s marked at %sh", chop(linebuf), outputPos);
            //if (outputPos > 1860)
            //    readln();
        } else if (canFind(linebuf, "@JUMPTABLE")) { //Check if the current line is a jumptable address
            //writeln("Found jumptable address");
            outputPos += 3; //Each address is 3 bytes long
            //writefln("Current positon: %s", outputPos);
        } else if (canFind(linebuf, ".pad")) { //Check if we found a manual pad
            string[] pad = split(linebuf, " ");
            const uint padAmount = to!uint(pad[1]);
            //writefln("Found %s padding bytes", padAmount);
            for (int i = 0; i < padAmount; i++) {
                outputPos += 1;
            }
        } else if (canFind(linebuf, ".envelope")) {
            const string[] envelope = split(linebuf, " ");
            for (int i = 0; i < envelope.length - 2; i++) {
                outputPos += 2;
                //writefln("Current positon: %s", outputPos);
            }
        } else {
            //writeln("Found instruction");
            outputPos += findBMSInstByteLength(linebuf, mode);
            //writefln("Current positon: %s", outputPos);
        }
    }
    writeln("Done! Doing second pass of assembling...");
    //Second Pass is where we actually assemble the file
    bms.seek(0);
    foreach (line; bms.byLine) {
        linebuf = cast(string)line;
        //writeln(linebuf);
        if (canFind(linebuf, ":")) //Now we skip parsing lable lines
            continue;
        if (canFind(linebuf, "@JUMPTABLE")) //But we have to convert our jumptables back
        {
            BinaryWriter writer = BinaryWriter(ByteOrder.BigEndian);
            writeInt24(&writer, to!int(compiledLabels[strip(linebuf, "@")]));
            bmsOutput.rawWrite(writer.buffer);
            writer.clear();
            continue;
        }
        if (canFind(linebuf, ".pad")) 
        {
            string[] pad = split(linebuf, " ");
            const uint padAmount = to!uint(pad[1]);
            ubyte[1] padding = [0];
            writefln("Writing %s padding bytes", padAmount);
            for (int i = 0; i < padAmount; i++) {
                bmsOutput.rawWrite(padding);
            }
            continue;
        }
        if (canFind(linebuf, ".envelope"))
        {
            string[] args = split(linebuf, " ");
            BinaryWriter writer = BinaryWriter(ByteOrder.LittleEndian);
            for (int i = 1; i < args.length - 1; i++) {
                writeln(args[i], " ", i);
                writer.write(to!ushort(strip(args[i], "h")));
            }
            bmsOutput.rawWrite(writer.buffer);
            writer.clear();
            continue;
        }
        else 
        {
            compileBMSInstruction(bmsOutput, linebuf, compiledLabels, mode);
        }
    }
    ubyte[1] padding = [0];
    while (bmsOutput.tell() % 32 != 0) {
        writeln("Padding file.");
        bmsOutput.rawWrite(padding);
    }
    writeln("Finished Assembling!");
    return 0;
}