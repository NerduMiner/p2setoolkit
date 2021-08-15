module bmsinterpret;
import binary.reader;
import binary.writer;
import binary.common;
import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.format;
import std.stdio;
import std.string;

///Needed to know what block of arbitrary data we are looking out for next
int dataInfoPosition = 0;

///Details what kind of arbitrary data is in the BMS file and at what point in the file it resides
struct BMSDataInfo
{
    int position;
    string dataType;
    int dataLength;
    int padlength = 0;
}

///Details the information needed to make a label, namely its name and its position in the file
struct BMSLabel
{
    string labelname;
    int position;
    int opCmp(BMSLabel)(const BMSLabel other) const
    {
        return (this.position < other.position) - (this.position > other.position);
    }
}

///A list of functions paired with their BMS Opcode, some opcodes come from https://github.com/XAYRGA/JaiSeqX/blob/sxlja/JaiSeqXLJA/libJAudio/Sequence/JAISeqEvent.cs
enum BMSFunction : ubyte
{
    INVALID = 0x00, //0x00-0x7F
    NOTE_ON = 0x01,
    CMD_WAIT8 = 0x80,
    NOTE_OFF = 0x81, //0x81-0x87, 0x89-0x8F
    CMD_WAIT16 = 0x88,
    SETPARAM_90 = 0x90, //0x90-0x9F cmdSetParam
    SETPARAM_91 = 0x91,
    SETPARAM_92 = 0x92,
    PERF_U8_NODUR = 0x94, //Come from Xayr's Documents
    PERF_U8_DUR_U8 = 0x96,
    PERF_U8_DUR_U16 = 0x97,
    PERF_S8_NODUR = 0x98,
    PERF_S8_DUR_U8 = 0x9A,
    PERF_S8_DUR_U16 = 0x9B,
    PERF_S16_NODUR = 0x9C,
    PERF_S16_DUR_U8 = 0x9D,
    PERF_S16_DUR_U8_9E = 0x9E,
    PERF_S16_DUR_U16 = 0x9F,
    PARAM_SET_R = 0xA0, //0xA0-0xAF cmdWriteRegParam
    PARAM_ADD_R = 0xA1, //Come from Xayr's Documents
    PARAM_MUL_R = 0xA2,
    PARAM_CMP_R = 0xA3,
    PARAM_SET_8 = 0xA4,
    PARAM_ADD_8 = 0xA5,
    PARAM_MUL_8 = 0xA6,
    PARAM_CMP_8 = 0xA7,
    PARAM_LOAD_UNK = 0xA8,
    PARAM_BITWISE = 0xA9,
    PARAM_LOADTBL = 0xAA,
    PARAM_SUBTRACT = 0xAB,
    PARAM_SET_16 = 0xAC,
    PARAM_ADD_16 = 0xAD,
    PARAM_MUL_16 = 0xAE,
    PARAM_CMP_16 = 0xAF,
    OPOVERRIDE_1 = 0xB0, //0xB0-0xBF are command overriders?
    OPOVERRIDE_2 = 0xB1,
    OPOVERRIDE_R = 0xB8,
    OPENTRACK = 0xC1,
    OPENTRACKBROS = 0xC2,
    CALL = 0xC4,
    RETURN_NOARG = 0xC5,
    RETURN = 0xC6,
    JMP = 0xC8,
    LOOP_S = 0xC9,
    LOOP_E = 0xCA,
    READPORT = 0xCB,
    WRITEPORT = 0xCC,
    CHECKPORTIMPORT = 0xCD,
    CHECKPORTEXPORT = 0xCE,
    CMD_WAITR = 0xCF,
    PARENTWRITEPORT = 0xD1,
    CHILDWRITEPORT = 0xD2,
    SETLASTNOTE = 0xD4,
    TIMERELATE = 0xD5,
    SIMPLEOSC = 0xD6,
    SIMPLEENV = 0xD7,
    SIMPLEADSR = 0xD8,
    TRANSPOSE = 0xD9,
    CLOSETRACK = 0xDA,
    OUTSWITCH = 0xDB,
    UPDATESYNC = 0xDC,
    BUSCONNECT = 0xDD,
    PAUSESTATUS = 0xDE,
    SETINTERRUPT = 0xDF,
    DISINTERRUPT = 0xE0,
    CLRI = 0xE1,
    SETI = 0xE2,
    RETI = 0xE3,
    INTTIMER = 0xE4,
    VIBDEPTH = 0xE5,
    VIBDEPTHMIDI = 0xE6,
    SYNCCPU = 0xE7,
    FLUSHALL = 0xE8,
    FLUSHRELEASE = 0xE9,
    WAIT_VLQ = 0xEA,
    PANPOWSET = 0xEB,
    IIRSET = 0xEC,
    FIRSET = 0xED,
    EXTSET = 0xEE,
    PANSWSET = 0xEF,
    OSCROUTE = 0xF0,
    IIRCUTOFF = 0xF1,
    OSCFULL = 0xF2,
    VOLUMEMODE = 0xF3,
    VIBPITCH = 0xF4,
    CHECKWAVE = 0xFA,
    PRINTF = 0xFB,
    NOP = 0xFC,
    TEMPO = 0xFD,
    TIMEBASE = 0xFE,
    FINISH = 0xFF
}

///Parses a BMS opcode, returning a relevant enum function value
ubyte parseOpcode(ubyte opcode)
{
    if (opcode == BMSFunction.INVALID)
    { //For the most part 00 always means a misalignment occured, BUT it could also mean a noteOn command
        writeln("0x00 CAUGHT, MISALIGNMENT POSSIBLY OCCURED.");
        return opcode;
    }
    if (opcode < 0x80)
    { //0x00-0x7F are cmdNoteOn commands
        return opcode; //We'll just have to do a similar check again
    }
    if ((opcode > 0x80 && opcode < 0x88) || (opcode > 0x88 && opcode < 0x90))
    { //0x81-0x87, 0x89-0x8F are cmdNoteOff commands
        return opcode; //We'll just have to do a similar check again
    }
    if (opcode >= 0x90 && opcode < 0xA0)
    { //0x90-0x9F are cmdSetParam commands
        switch (opcode)
        {
        case BMSFunction.SETPARAM_90:
            return BMSFunction.SETPARAM_90;
        case BMSFunction.SETPARAM_91:
            return BMSFunction.SETPARAM_91;
        case BMSFunction.SETPARAM_92:
            return BMSFunction.SETPARAM_92;
        case BMSFunction.PERF_U8_NODUR:
            return BMSFunction.PERF_U8_NODUR;
        case BMSFunction.PERF_U8_DUR_U8:
            return BMSFunction.PERF_U8_DUR_U8;
        case BMSFunction.PERF_U8_DUR_U16:
            return BMSFunction.PERF_U8_DUR_U16;
        case BMSFunction.PERF_S8_NODUR:
            return BMSFunction.PERF_S8_NODUR;
        case BMSFunction.PERF_S8_DUR_U8:
            return BMSFunction.PERF_S8_DUR_U8;
        case BMSFunction.PERF_S8_DUR_U16:
            return BMSFunction.PERF_S8_DUR_U16;
        case BMSFunction.PERF_S16_NODUR:
            return BMSFunction.PERF_S16_NODUR;
        case BMSFunction.PERF_S16_DUR_U8: //Where did 0x9D come from
            throw new Exception("Found 0x9D in parser.");
        case BMSFunction.PERF_S16_DUR_U8_9E: //0x9E is what 0x9D is defined as, did I make a mistake?
            return BMSFunction.PERF_S16_DUR_U8_9E;
        case BMSFunction.PERF_S16_DUR_U16:
            return BMSFunction.PERF_S16_DUR_U16;
        default:
            throw new Exception("UNIMPLEMENTED 0x9X OPCODE IN PARSER: " ~ format!"%02X"(opcode));
        }
    }
    if (opcode >= 0xA0 && opcode < 0xB0)
    { //0xA0-0xAF are cmdWriteRegParam commands
        switch (opcode)
        {
        case BMSFunction.PARAM_SET_R:
            return BMSFunction.PARAM_SET_R;
        case BMSFunction.PARAM_ADD_R:
            return BMSFunction.PARAM_ADD_R;
        case BMSFunction.PARAM_MUL_R:
            return BMSFunction.PARAM_MUL_R;
        case BMSFunction.PARAM_CMP_R:
            return BMSFunction.PARAM_CMP_R;
        case BMSFunction.PARAM_SET_8:
            return BMSFunction.PARAM_SET_8;
        case BMSFunction.PARAM_ADD_8:
            return BMSFunction.PARAM_ADD_8;
        case BMSFunction.PARAM_MUL_8:
            return BMSFunction.PARAM_MUL_8;
        case BMSFunction.PARAM_CMP_8:
            return BMSFunction.PARAM_CMP_8;
        case BMSFunction.PARAM_LOAD_UNK:
            return BMSFunction.PARAM_LOAD_UNK;
        case BMSFunction.PARAM_BITWISE:
            return BMSFunction.PARAM_BITWISE;
        case BMSFunction.PARAM_LOADTBL:
            return BMSFunction.PARAM_LOADTBL;
        case BMSFunction.PARAM_SUBTRACT:
            return BMSFunction.PARAM_SUBTRACT;
        case BMSFunction.PARAM_SET_16:
            return BMSFunction.PARAM_SET_16;
        case BMSFunction.PARAM_ADD_16:
            return BMSFunction.PARAM_ADD_16;
        case BMSFunction.PARAM_MUL_16:
            return BMSFunction.PARAM_MUL_16;
        case BMSFunction.PARAM_CMP_16:
            return BMSFunction.PARAM_CMP_16;
        default:
            throw new Exception("UNIMPLEMENTED 0xAX OPCODE IN PARSER: " ~ format!"%02X"(opcode));
        }
    }
    if (opcode >= 0xB0 && opcode < 0xC0)
    { //0xB0-0xBF are the very funny commands
        if (opcode >= 0xB8 && opcode < 0xC0)
            return BMSFunction.OPOVERRIDE_R;
        switch (opcode)
        {
        case BMSFunction.OPOVERRIDE_1:
            return BMSFunction.OPOVERRIDE_1;
        case BMSFunction.OPOVERRIDE_2:
            return BMSFunction.OPOVERRIDE_2;
        default:
            throw new Exception("UNIMPLEMENTED 0xBX OPCODE IN PARSER: " ~ format!"%02X"(opcode));
        }
    }
    switch (opcode)
    { //For opcodes 0x80, 0x88, 0xC0-0xFF
    case BMSFunction.CMD_WAIT8:
        return BMSFunction.CMD_WAIT8;
    case BMSFunction.CMD_WAIT16:
        return BMSFunction.CMD_WAIT16;
    case BMSFunction.OPENTRACK:
        return BMSFunction.OPENTRACK;
    case BMSFunction.CALL:
        return BMSFunction.CALL;
    case BMSFunction.RETURN_NOARG:
        return BMSFunction.RETURN_NOARG;
    case BMSFunction.RETURN:
        return BMSFunction.RETURN;
    case BMSFunction.JMP:
        return BMSFunction.JMP;
    case BMSFunction.LOOP_S:
        return BMSFunction.LOOP_S;
    case BMSFunction.LOOP_E:
        return BMSFunction.LOOP_E;
    case BMSFunction.READPORT:
        return BMSFunction.READPORT;
    case BMSFunction.WRITEPORT:
        return BMSFunction.WRITEPORT;
    case BMSFunction.CMD_WAITR:
        return BMSFunction.CMD_WAITR;
    case BMSFunction.CHILDWRITEPORT:
        return BMSFunction.CHILDWRITEPORT;
    case BMSFunction.SETLASTNOTE:
        return BMSFunction.SETLASTNOTE;
    case BMSFunction.SIMPLEOSC:
        return BMSFunction.SIMPLEOSC;
    case BMSFunction.SIMPLEENV:
        return BMSFunction.SIMPLEENV;
    case BMSFunction.SIMPLEADSR:
        return BMSFunction.SIMPLEADSR;
    case BMSFunction.TRANSPOSE:
        return BMSFunction.TRANSPOSE;
    case BMSFunction.CLOSETRACK:
        return BMSFunction.CLOSETRACK;
    case BMSFunction.OUTSWITCH:
        return BMSFunction.OUTSWITCH;
    case BMSFunction.BUSCONNECT:
        return BMSFunction.BUSCONNECT;
    case BMSFunction.SETINTERRUPT:
        return BMSFunction.SETINTERRUPT;
    case BMSFunction.CLRI:
        return BMSFunction.CLRI;
    case BMSFunction.RETI:
        return BMSFunction.RETI;
    case BMSFunction.INTTIMER:
        return BMSFunction.INTTIMER;
    case BMSFunction.VIBDEPTH:
        return BMSFunction.VIBDEPTH;
    case BMSFunction.VIBDEPTHMIDI:
        return BMSFunction.VIBDEPTHMIDI;
    case BMSFunction.SYNCCPU:
        return BMSFunction.SYNCCPU;
    case BMSFunction.FLUSHALL:
        return BMSFunction.FLUSHALL;
    case BMSFunction.WAIT_VLQ:
        return BMSFunction.WAIT_VLQ;
    case BMSFunction.PANPOWSET:
        return BMSFunction.PANPOWSET;
    case BMSFunction.IIRSET:
        return BMSFunction.IIRSET;
    case BMSFunction.EXTSET:
        return BMSFunction.EXTSET;
    case BMSFunction.PANSWSET:
        return BMSFunction.PANSWSET;
    case BMSFunction.OSCROUTE:
        return BMSFunction.OSCROUTE;
    case BMSFunction.IIRCUTOFF:
        return BMSFunction.IIRCUTOFF;
    case BMSFunction.VIBPITCH:
        return BMSFunction.VIBPITCH;
    case BMSFunction.PRINTF:
        return BMSFunction.PRINTF;
    case BMSFunction.TEMPO:
        return BMSFunction.TEMPO;
    case BMSFunction.TIMEBASE:
        return BMSFunction.TIMEBASE;
    case BMSFunction.FINISH:
        return BMSFunction.FINISH;
        //TODO: Finish expanding for at least 
    default:
        throw new Exception("UNIMPLEMENTED OPCODE IN PARSER: " ~ format!"%02X"(opcode));
    }
}

///Takes a BMS opcode and prints out its full instruction in hex bytes
void printBMSInstruction(ubyte opcode, File bmsFile)
{
    if (opcode == 0x00)
    {
        //First check if we are near end of file
        if ((bmsFile.size - bmsFile.tell()) < 32)
        {
            //Get out of the function because we are in padding, but we still have to read one byte
            ubyte[1] data;
            bmsFile.rawRead(data);
            return;
        }
        //Print out 00 instruction to user
        //Read flags[ubyte] and velocity[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        const ubyte flags = reader.read!(ubyte);
        const ubyte velocity = reader.read!(ubyte);
        write("BMS 0x00 Parsed Instruction: ", format!"%02X "(opcode),
                format!"%02X "(flags), format!"%02X "(velocity)); //Put down what we have, as there may be more in the future
        if ((flags & 7) == 0)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte header = reader.read!(ubyte);
            write(format!"%02X "(header));
            //InstructionDecompiler: check header & 0x80 != 0
            for (int i = 0; i < (flags >> 3 & 3); i++)
            { //upper nybble of opcode contains how many extra bytes we have to read
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                write(format!"%02X "(reader.read!(ubyte)));
            }
        }
        else
        {
            const ubyte topnybble = flags >> 3 & 3;
            if (topnybble - 1 > 7)
                throw new Exception("Invalid parameters in flag byte for cmdNoteOn command.");
            if ((flags >> 5 & 1) != 0)
            {
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                write(format!"%02X "(reader.read!(ubyte)));
            }
        }
        write("\n"); //Add a newline after we're done
        writeln("Do you want to continue? Press Enter to Continue or Close Program");
        readln();
        return;
    }
    if (opcode < 0x80)
    { //0x00-0x7F are cmdNoteOn commands, so handle those first
        //Read flags[ubyte] and velocity[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        const ubyte flags = reader.read!(ubyte);
        const ubyte velocity = reader.read!(ubyte);
        write("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(flags), format!"%02X "(velocity)); //Put down what we have, as there may be more in the future
        if ((flags & 7) == 0)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte header = reader.read!(ubyte);
            write(format!"%02X "(header));
            //InstructionDecompiler: check header & 0x80 != 0
            for (int i = 0; i < (flags >> 3 & 3); i++)
            { //upper nybble of opcode contains how many extra bytes we have to read
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                write(format!"%02X "(reader.read!(ubyte)));
            }
        }
        else
        {
            const ubyte topnybble = flags >> 3 & 3;
            if (topnybble - 1 > 7)
                throw new Exception("Invalid parameters in flag byte for cmdNoteOn command.");
            if ((flags >> 5 & 1) != 0)
            {
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                write(format!"%02X "(reader.read!(ubyte)));
            }
        }
        write("\n"); //Add a newline after we're done
        return;
    }
    if ((opcode > 0x80 && opcode < 0x88) || (opcode > 0x88 && opcode < 0x90))
    { //0x81-0x87, 0x89-0x8F are cmdNoteOff commands
        //Opcode contains which voice to stop, you can check this via AND-ing with 0x0F
        //If bit 4 is set in the argument, read an extra byte
        if ((opcode & 0x8) > 0)
        {
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        }
        else
        {
            writeln("BMS Instruction: ", format!"%02X "(opcode));
        }
        return;
    }
    if (opcode >= 0x90 && opcode < 0xA0)
    { //Opcodes 0x90-0x9F are a part of the perf family
        switch (opcode)
        {
        case BMSFunction.SETPARAM_90: //0x90
            //Read something[ubyte] and something[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.SETPARAM_91: //0x91
            //Read something[ubyte] and something[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.SETPARAM_92: //0x92
            //Read something[ubyte], something[ubyte], and something[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_U8_NODUR: //0x94
            //Read param[ubyte] and value[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_U8_DUR_U8: //0x96
            //Read param[ubyte], value[ubyte] and duration_ticks[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S8_NODUR: //0x98
            //Read param[ubyte] and value[byte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S8_DUR_U8: //0x9A
            //Read param[ubyte] value[byte] and duration ticks[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S8_DUR_U16: //0x9B
            //Read param[ubyte], value[byte], and duration_ticks[short]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S16_NODUR: //0x9C
            //Read param[ubyte] and value[short]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S16_DUR_U8_9E: //0x9E
            //Read param[ubyte], value[short], and duration_ticks[ubyte]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S16_DUR_U16: //0x9F
            //Read param[ubyte], value[short], and duration_ticks[short]
            ubyte[] data;
            data.length = 5;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
            return;
        default:
            throw new Exception(
                    "UNIMPLEMENTED PERF OPCODE IN INSRTUCTION PARSER: " ~ format!"%02X"(opcode));
        }
    }
    switch (opcode)
    {
    case BMSFunction.CMD_WAIT8: //0x80
        //Read wait time[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CMD_WAIT16: //0x88
        //Read wait time[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //shorts have to be read as 2 bytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_SET_R: //0xA0
        //Read source register[ubyte] and destination register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_CMP_R: //0xA3
        //Read target register[ubyte] and source register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_SET_8: //0xA4
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_ADD_8: //0xA5
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_CMP_8: //0xA7
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_LOAD_UNK: //0xA8
        //Read something[ubyte] and something[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_BITWISE: //0xA9
        //Read operation[ubyte] and something[short](operation and register?), if operation & 0x0F == 0xC then read another short, if operation & 0x0F == 0x8, then stop, otherwise read another byte
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        ubyte operation = reader.read!(ubyte);
        if ((operation & 0xF) == 0xC)
        {
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(operation), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        }
        else if ((operation & 0xF) == 0x8)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(operation), format!"%02X"(reader.read!(ubyte)));
        }
        else
        {
            data = [];
            data.length = 2;
            reader.source(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode),
                    format!"%02X "(operation), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
        }
        return;
    case BMSFunction.PARAM_LOADTBL: //0xAA
        throw new Exception("0xAA CAUGHT BUT NOT HANDLED IN INSTRUCTION CREATOR");
    case BMSFunction.PARAM_SUBTRACT: //0xAB
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_SET_16: //0xAC
        //Read target register[ubyte] and value[short]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //Shorts have to be read as 2 ubytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_ADD_16: //0xAD
        //Read target register[ubyte] and value[short]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //Shorts have to be read as 2 ubytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.OPOVERRIDE_1: //0xB0
        /*//0xBX commands have an instruction inside them, so we recursively call this function to find that and return to read arguments
            writeln("BMS Instruction[Next instruction is inside 0xBX instruction]: ", format!"%02X "(opcode));
            //Read opcode
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            printBMSInstruction(reader.read!(ubyte), bmsFile);
            //Read argument[ubyte]
            data = [];
            data.length = 1;
            bmsFile.rawRead(data);
            reader.source(data);
            writeln("0xB0 Arguments: ", format!"%02X "(reader.read!(ubyte)));
            return;*/
        //ACTUALLY 0xBX commands have an overrided opcode[ubyte], an argument mask[ubyte], then an argument for the 0xBX opcode[ubyte]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction[Funny 0xB0 opcode]: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.OPOVERRIDE_2: //0xB1?
        throw new Exception(
                "CONFIRM BEHAVIOR OF THIS 0xBX OPCODE FIRST: " ~ format!"%02X"(opcode));
        /*//0xBX commands have an instruction inside them, so we recursively call this function to find that and return to read arguments
            writeln("BMS Instruction[Next instruction is inside 0xBX instruction]: ", format!"%02X "(opcode));
            //Read opcode
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            printBMSInstruction(reader.read!(ubyte), bmsFile);
            //Read arguments[ubyte x2]
            data = [];
            data.length = 2;
            bmsFile.rawRead(data);
            reader.source(data);
            writeln("0xB0 Arguments: ", format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;*/
    case BMSFunction.OPENTRACK: //0xC1
        //Read track id[ubyte] and address[int24]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //int24 has to be read as 3 ubytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CALL: //0xC4
        //Read condition?[ubyte] and address[int24] and something?[ubyte]
        //C4 C0 is Call Register Table, so we also have to check for that
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        const ubyte arg = reader.read!(ubyte);
        write("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(arg));
        if (arg == 0xC0)
        {
            //Read register[ubyte] and address[int24]
            data = [];
            data.length = 4;
            reader.source(data);
            bmsFile.rawRead(data);
            write(format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
        }
        else
        {
            //read address[int24]
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            write(format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        }
        //int24 have to be read as 3 ubytes
        write("\n");
        return;
    case BMSFunction.RETURN_NOARG: //0xC5
        //Has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    case BMSFunction.RETURN: //0xC6
        //Read condition[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.JMP: //0xC8
        //Read condition?[ubyte] and address[int24]
        //Like C4, we also have to check for C0 in the first argument
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        const ubyte arg = reader.read!ubyte;
        writef("BMS Instruction: %s %s", format!"%02X"(opcode), format!"%02X"(arg));
        if (arg == 0xC0)
        {
            data = [];
            data.length = 4;
            reader.source(data);
            bmsFile.rawRead(data);
            //int24 have to be read as 3 ubytes
            writeln(format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                    format!"%02X"(reader.read!(ubyte)));
        }
        else
        {
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            writeln(format!"%02X "(reader.read!(ubyte)),
                    format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        }
        return;
    case BMSFunction.LOOP_S: //0xC9
        //Read something?[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.LOOP_E: //0xCA
        //Apparently has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    case BMSFunction.READPORT: //0xCB
        //Read flags[ubyte] and target register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.WRITEPORT: //0xCC
        //Read port[ubyte] and value[ubyte](also known as source port and dest port)
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CMD_WAITR: //0xCF
        //Read register[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CHILDWRITEPORT: //0xD2
        //Read port[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SETLASTNOTE: //0xD4
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEOSC: //0xD6
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEENV: //0xD7
        //Read Something?[int24] and something?[ubyte]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction[0xD7 not yet accurate]: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEADSR: //0xD8
        //Read A[ubyte] D[ubyte] S[ubyte] and R[ubyte]: Xayrs version
        //Read 5 shorts: debugging Pikmin 2, Yoshi2's version
        ubyte[] data;
        data.length = 10;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //idk why but here it clashes with std.file.write
        std.stdio.write("BMS Instruction: ", format!"%02X "(opcode));
        for (int i = 0; i < data.length; i++)
        {
            write(format!"%02X "(reader.read!(ubyte)));
        }
        write("\n");
        return;
    case BMSFunction.TRANSPOSE: //0xD9
        //Read transpose[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CLOSETRACK: //0xDA
        //Read track-id[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.OUTSWITCH: //0xDB
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.BUSCONNECT: //0xDD
        //Read something[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SETINTERRUPT: //0xDF
        //Read interrupt level[byte] and address[int24]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.CLRI: //0xE1
        //Apparently has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    case BMSFunction.RETI: //0xE3
        //Apparently has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    case BMSFunction.INTTIMER: //0xE4
        //Read something[byte] and extra short?
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction(E4 Not Fully Accurate): ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.VIBDEPTH: //0xE5
        //Read something?[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.VIBDEPTHMIDI: //0xE6
        //Read something[ubyte] and something[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.SYNCCPU: //0xE7
        //Read maximum wait[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.FLUSHALL: //0xE8
        //cmdFlushAll has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    case BMSFunction.WAIT_VLQ: //0xEA
        /*Variable length Quantity means we have to do funky stuff
            int vlq;
            int temp;
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            temp = reader.read!(ubyte);
            write("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(temp));
            do {
                vlq = (vlq << 7) | (temp & 0x7F);
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                temp = reader.read!(ubyte);
                write(format!"%02X "(temp));
            } while ((temp & 0x80) > 0);
            write("\n"); //Add a newline after we're done*/
        //Read wait time[int24]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PANPOWSET: //0xEB
        //Read 5 ubytes
        ubyte[] data;
        data.length = 5;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.IIRSET: //0xEC
        //Read 8 ubytes
        ubyte[] data;
        data.length = 8;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //idk why but here it clashes with std.file.write
        std.stdio.write("BMS Instruction: ", format!"%02X "(opcode));
        for (int i = 0; i < data.length; i++)
        {
            write(format!"%02X "(reader.read!(ubyte)));
        }
        write("\n");
        return;
    case BMSFunction.EXTSET: //0xEE
        //Reads an address?[int16]
        ubyte[] data;
        data.length = 2; //Could also be 3
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)));
        return;
    case BMSFunction.PANSWSET: //0xEF
        //Reads an int24? for something
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.OSCROUTE: //0xF0
        //Read something[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.IIRCUTOFF: //0xF1
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction(F1 not fully accurate): ",
                format!"%02X "(opcode), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.VIBPITCH: //0xF4
        //Read something?[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.PRINTF: //0xFB
        //Read until read byte is 00, then read one more byte
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        ubyte nxtByte = reader.read!(ubyte);
        std.stdio.write("BMS Instruction: ", format!"%02X "(opcode));
        while (nxtByte != 0x00)
        {
            write(format!"%02X "(nxtByte));
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            nxtByte = reader.read!(ubyte);
        }
        data = [];
        data.length = 1;
        reader.source(data);
        bmsFile.rawRead(data);
        ubyte finalByte = reader.read!(ubyte);
        if (finalByte == 0x00)
        {
            writeln(format!"%02X "(nxtByte), format!"%02X"(finalByte));
        }
        else
        {
            //Go back one byte because sometimes there isnt an extra 00
            bmsFile.seek(bmsFile.tell() - 1);
            writeln(format!"%02X"(nxtByte));
        }
        return;
    case BMSFunction.TEMPO: //0xFD
        //Read tempo value[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //Shorts have to be read as 2 ubytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.TIMEBASE: //0xFE
        //Read timebase value
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        //Shorts have to be read as 2 ubytes
        writeln("BMS Instruction: ", format!"%02X "(opcode),
                format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    case BMSFunction.FINISH:
        //cmdFinish has no arguments
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    default:
        throw new Exception("UNIMPLEMENTED OPCODE IN INSTRUCTION PRINTER: " ~ format!"%02X"(opcode));
    }
}

///Takes an opcode and decompiles it, writing the instruction to an output file
void decompileBMSInstruction(ubyte opcode, File bmsFile, File decompiledBMS,
        BMSLabel[]* decompiledLabels)
{
    if (opcode == 0x00)
    {
        //First check if we are near end of file
        if ((bmsFile.size - bmsFile.tell()) < 32)
        {
            //Get out of the function because we are in padding, but we still have to read one byte
            ubyte[1] data;
            bmsFile.rawRead(data);
            return;
        }
        //Print out 00 instruction to user
        //Read flags[ubyte] and velocity[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const ubyte flags = reader.read!(ubyte);
        const ubyte velocity = reader.read!(ubyte);
        decompiledBMS.write("noteon ", opcode, "b ", flags, "b ", velocity, "b "); //Put down what we have, as there may be more in the future
        if ((flags & 7) == 0)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte header = reader.read!(ubyte);
            decompiledBMS.write(header, "b ");
            //InstructionDecompiler: check header & 0x80 != 0
            for (int i = 0; i < (flags >> 3 & 3); i++)
            { //upper nybble of opcode contains how many extra bytes we have to read
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                decompiledBMS.write(reader.read!(ubyte), "b ");
            }
        }
        else
        {
            const ubyte topnybble = flags >> 3 & 3;
            if (topnybble - 1 > 7)
                throw new Exception("Invalid parameters in flag byte for cmdNoteOn command.");
            if ((flags >> 5 & 1) != 0)
            {
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                decompiledBMS.write(reader.read!(ubyte), "b ");
            }
        }
        decompiledBMS.write("\n"); //Add a newline after we're done
        return;
    }
    if (opcode < 0x80)
    { //0x00-0x7F are cmdNoteOn commands, so handle those first
        //Read flags[ubyte] and velocity[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const ubyte flags = reader.read!(ubyte);
        const ubyte velocity = reader.read!(ubyte);
        decompiledBMS.write("noteon ", opcode, "b ", flags, "b ", velocity, "b "); //Put down what we have, as there may be more in the future
        if ((flags & 7) == 0)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte header = reader.read!(ubyte);
            decompiledBMS.write(header, "b ");
            //InstructionDecompiler: check header & 0x80 != 0
            for (int i = 0; i < (flags >> 3 & 3); i++)
            { //upper nybble of opcode contains how many extra bytes we have to read
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                decompiledBMS.write(reader.read!(ubyte), "b ");
            }
        }
        else
        {
            const ubyte topnybble = flags >> 3 & 3;
            if (topnybble - 1 > 7)
                throw new Exception("Invalid parameters in flag byte for cmdNoteOn command.");
            if ((flags >> 5 & 1) != 0)
            {
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                decompiledBMS.write(reader.read!(ubyte), "b ");
            }
        }
        decompiledBMS.write("\n"); //Add a newline after we're done
        return;
    }
    if ((opcode > 0x80 && opcode < 0x88) || (opcode > 0x88 && opcode < 0x90))
    { //0x81-0x87, 0x89-0x8F are cmdNoteOff commands
        //Opcode contains which voice to stop, you can check this via AND-ing with 0x0F
        //If bit 4 is set in the argument, read an extra byte
        if ((opcode & 0x8) > 0)
        {
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("noteoff ", (opcode & 0xF), "b ", reader.read!(ubyte));
            return;
        }
        else
        {
            decompiledBMS.writeln("noteoff ", (opcode & 0xF), "b");
        }
        return;
    }
    if (opcode >= 0x90 && opcode < 0xA0)
    { //Opcodes 0x90-0x9F are a part of the perf family
        switch (opcode)
        {
        case BMSFunction.SETPARAM_90: //0x90
            //Read something[ubyte] and something[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("setparam_90 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.SETPARAM_91: //0x91
            //Read something[ubyte] and something[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("setparam_91 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.SETPARAM_92: //0x92
            //Read something[ubyte], something[ubyte], and something[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("setparam_92 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_U8_NODUR: //0x94
            //Read param[ubyte] and value[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_u8_nodur ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_U8_DUR_U8: //0x96
            //Read param[ubyte], value[ubyte] and duration_ticks[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_u8_dur_u8 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S8_NODUR: //0x98
            //Read param[ubyte] and value[byte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s8_nodur ",
                    format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(byte)));
            return;
        case BMSFunction.PERF_S8_DUR_U8: //0x9A
            //Read param[ubyte] value[byte] and duration ticks[ubyte]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s8_dur_u8 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb "(reader.read!(byte)), format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S8_DUR_U16: //0x9B
            //Read param[ubyte], value[byte], and duration_ticks[ushort]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s8_dur_u16 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sb "(reader.read!(byte)), format!"%sh"(reader.read!(ushort)));
            return;
        case BMSFunction.PERF_S16_NODUR: //0x9C
            //Read param[ubyte] and value[short]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s16_nodur ",
                    format!"%sb "(reader.read!(ubyte)), format!"%sh"(reader.read!(short)));
            return;
        case BMSFunction.PERF_S16_DUR_U8_9E: //0x9E
            //Read param[ubyte], value[short], and duration_ticks[ubyte]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s16_dur_u8 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sh "(reader.read!(short)), format!"%sb"(reader.read!(ubyte)));
            return;
        case BMSFunction.PERF_S16_DUR_U16: //0x9F
            //Read param[ubyte], value[short], and duration_ticks[ushort]
            ubyte[] data;
            data.length = 5;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("perf_s16_dur_u16 ", format!"%sb "(reader.read!(ubyte)),
                    format!"%sh "(reader.read!(short)), format!"%sh "(reader.read!(ushort)));
            return;
        default:
            throw new Exception(
                    "UNIMPLEMENTED PERF OPCODE IN INSRTUCTION PARSER: " ~ format!"%02X"(opcode));
        }
    }
    switch (opcode)
    {
    case BMSFunction.CMD_WAIT8: //0x80
        //Read wait time[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("wait8 ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.CMD_WAIT16: //0x88
        //Read wait time[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("wait16 ", format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.PARAM_SET_R: //0xA0
        //Read source register[ubyte] and destination register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_set_r ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_CMP_R: //0xA3
        //Read target register[ubyte] and source register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_cmp_r ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_SET_8: //0xA4
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_set_8 ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_ADD_8: //0xA5
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_add_8 ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_CMP_8: //0xA7
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_cmp_8 ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_LOAD_UNK: //0xA8
        //Read something[ubyte] and something[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_load ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_BITWISE: //0xA9
        //Read operation[ubyte] and something[ubyte?](operation and register?), if operation & 0x0F == 0xC then read another short, if operation & 0x0F == 0x8, then stop, otherwise read another byte
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        ubyte operation = reader.read!(ubyte);
        if ((operation & 0xF) == 0xC)
        {
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("param_bitwise ", format!"%sb "(operation),
                    format!"%sb "(reader.read!(ubyte)), format!"%sh"(reader.read!(ushort)));
        }
        else if ((operation & 0xF) == 0x8)
        {
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("param_bitwise ", format!"%sb "(operation),
                    format!"%sb"(reader.read!(ubyte)));
        }
        else
        {
            data = [];
            data.length = 2;
            reader.source(data);
            bmsFile.rawRead(data);
            decompiledBMS.writeln("param_bitwise ", format!"%sb "(operation),
                    format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
        }
        return;
    case BMSFunction.PARAM_LOADTBL: //0xAA
        throw new Exception("0xAA CAUGHT BUT NOT HANDLED IN INSTRUCTION DECOMPILER");
    case BMSFunction.PARAM_SUBTRACT: //0xAB
        //Read target register[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_subtract ",
                format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PARAM_SET_16: //0xAC
        //Read target register[ubyte] and value[short]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_set_16 ", format!"%sb "(reader.read!(ubyte)),
                format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.PARAM_ADD_16: //0xAD
        //Read target register[ubyte] and value[short]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("param_add_16 ", format!"%sb "(reader.read!(ubyte)),
                format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.OPOVERRIDE_1: //0xB0
        /*//0xBX commands have an instruction inside them, so we recursively call this function to find that and return to read arguments
            writeln("BMS Instruction[Next instruction is inside 0xBX instruction]: ", format!"%02X "(opcode));
            //Read opcode
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            printBMSInstruction(reader.read!(ubyte), bmsFile);
            //Read argument[ubyte]
            data = [];
            data.length = 1;
            bmsFile.rawRead(data);
            reader.source(data);
            writeln("0xB0 Arguments: ", format!"%02X "(reader.read!(ubyte)));
            return;*/
        //ACTUALLY 0xBX commands have an overrided opcode[ubyte], an argument mask[ubyte], then an argument for the 0xBX opcode[ubyte]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("op_override_1 ", format!"%02X "(reader.read!(ubyte)),
                format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.OPOVERRIDE_2: //0xB1?
        throw new Exception(
                "CONFIRM BEHAVIOR OF THIS 0xBX OPCODE FIRST: " ~ format!"%02X"(opcode));
        /*//0xBX commands have an instruction inside them, so we recursively call this function to find that and return to read arguments
            writeln("BMS Instruction[Next instruction is inside 0xBX instruction]: ", format!"%02X "(opcode));
            //Read opcode
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            printBMSInstruction(reader.read!(ubyte), bmsFile);
            //Read arguments[ubyte x2]
            data = [];
            data.length = 2;
            bmsFile.rawRead(data);
            reader.source(data);
            writeln("0xB0 Arguments: ", format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;*/
    case BMSFunction.OPENTRACK: //0xC1
        //Read track id[ubyte] and address[int24]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const ubyte trackid = reader.read!(ubyte);
        //int24 has to be read as a ubyte bitshifted left by 16 and OR'd with a ushort
        const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
        *decompiledLabels ~= BMSLabel(("TRACK_" ~ format!"%s"(trackid) ~ "_START_" ~ format!"%s"(address) ~ "h:"), address);
        decompiledBMS.writeln("opentrack ", format!"%sb "(trackid),
                "@TRACK_" ~ format!"%s"(trackid) ~ "_START_" ~ format!"%s"(address) ~ "h");
        return;
    case BMSFunction.CALL: //0xC4
        //Read condition?[ubyte] and address[int24] and something?[ubyte]
        //C4 C0 is Call Register Table, so we also have to check for that
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const ubyte arg = reader.read!(ubyte);
        decompiledBMS.write("call ", format!"%sb "(arg));
        if (arg == 0xC0)
        {
            //Read register[ubyte] and address[int24]
            data = [];
            data.length = 4;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte register = reader.read!ubyte;
            const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
            *decompiledLabels ~= BMSLabel(("CALL_" ~ format!"%s"(decompiledLabels.length) ~ "_" ~ format!"%s"(address) ~ "h:"),
                    address);
            decompiledBMS.write(format!"%sb "(register),
                    "@CALL_" ~ format!"%s"(decompiledLabels.length - 1) ~ "_" ~ format!"%s"(address) ~ "h");
        }
        else
        {
            //read address[int24]
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
            *decompiledLabels ~= BMSLabel(("CALL_" ~ format!"%s"(decompiledLabels.length) ~ "_" ~ format!"%s"(address) ~ "h:"),
                    address);
            decompiledBMS.write("@CALL_" ~ format!"%s"(decompiledLabels.length - 1) ~ "_" ~ format!"%s"(address) ~ "h");
        }
        decompiledBMS.write("\n");
        return;
    case BMSFunction.RETURN_NOARG: //0xC5
        //Has no arguments
        decompiledBMS.writeln("return_noarg");
        return;
    case BMSFunction.RETURN: //0xC6
        //Read condition[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("return ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.JMP: //0xC8
        //Read condition?[ubyte] and address[int24]
        //Like 0xC4, we have to check for C0 as the first argument
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const ubyte arg = reader.read!(ubyte);
        decompiledBMS.write("jmp ", format!"%sb "(arg));
        if (arg == 0xC0)
        {
            //Read something[ubyte] and address[int24]
            data = [];
            data.length = 4;
            reader.source(data);
            bmsFile.rawRead(data);
            const ubyte condition = reader.read!ubyte;
            const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
            *decompiledLabels ~= BMSLabel(("JMP_" ~ format!"%s"(address) ~ "h:"), address);
            decompiledBMS.writeln(format!"%sb "(condition), "@JMP_" ~ format!"%s"(address) ~ "h");
        }
        else
        {
            //Read address[int24]
            data = [];
            data.length = 3;
            reader.source(data);
            bmsFile.rawRead(data);
            const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
            *decompiledLabels ~= BMSLabel(("JMP_" ~ format!"%s"(address) ~ "h:"), address);
            decompiledBMS.writeln("@JMP_" ~ format!"%s"(address) ~ "h");
        }
        return;
    case BMSFunction.LOOP_S: //0xC9
        //Read something?[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("loop_s ", format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.LOOP_E: //0xCA
        //Apparently has no arguments
        decompiledBMS.writeln("loop_e");
        return;
    case BMSFunction.READPORT: //0xCB
        //Read flags[ubyte] and target register[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("readport ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.WRITEPORT: //0xCC
        //Read port[ubyte] and value[ubyte](also known as source port and dest port)
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("writeport ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.CMD_WAITR: //0xCF
        //Read register[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("wait_r ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.CHILDWRITEPORT: //0xD2
        //Read port[ubyte] and value[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("childwriteport ",
                format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.SETLASTNOTE: //0xD4
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("setlastnote ", format!"%s"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEOSC: //0xD6
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("simpleosc ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEENV: //0xD7
        //Read Something?[int24] and something?[ubyte]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("simpleenv ",
                format!"%sq "((reader.read!(ubyte) << 16) | reader.read!(ushort)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.SIMPLEADSR: //0xD8
        //Read A[ubyte] D[ubyte] S[ubyte] and R[ubyte]: Xayrs version
        //Read 5 shorts: debugging Pikmin 2, Yoshi2's version
        ubyte[] data;
        data.length = 10;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.write("simpleadsr ");
        for (int i = 0; i < (data.length / 2); i++)
        {
            decompiledBMS.write(format!"%sh "(reader.read!(ushort)));
        }
        decompiledBMS.write("\n");
        return;
    case BMSFunction.TRANSPOSE: //0xD9
        //Read transpose[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("transpose ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.CLOSETRACK: //0xDA
        //Read track-id[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("closetrack ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.OUTSWITCH: //0xDB
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("outswitch ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.BUSCONNECT: //0xDD
        //Read something[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("busconnect ", format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.SETINTERRUPT: //0xDF
        //Read interrupt level[byte] and address[int24]
        ubyte[] data;
        data.length = 4;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("setinterrupt ", format!"%sb "(reader.read!(ubyte)),
                format!"%sq"((reader.read!(ubyte) << 16) | reader.read!(ushort)));
        return;
    case BMSFunction.CLRI: //0xE1
        //Apparently has no arguments
        decompiledBMS.writeln("clri");
        return;
    case BMSFunction.RETI: //0xE3
        //Apparently has no arguments
        decompiledBMS.writeln("reti");
        return;
    case BMSFunction.INTTIMER: //0xE4
        //Read something[byte] and extra short?
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("inttimer ", format!"%sb "(reader.read!(ubyte)),
                format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.VIBDEPTH: //0xE5
        //Read something?[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("vibdepth ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.VIBDEPTHMIDI: //0xE6
        //Read something[ubyte] and something[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("vibdepthmidi ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.SYNCCPU: //0xE7
        //Read maximum wait[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("synccpu ", format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.FLUSHALL: //0xE8
        //cmdFlushAll has no arguments
        decompiledBMS.writeln("flushall");
        return;
    case BMSFunction.WAIT_VLQ: //0xEA
        /*Variable length Quantity means we have to do funky stuff
            int vlq;
            ubyte temp;
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data, ByteOrder.BigEndian);
            bmsFile.rawRead(data);
            temp = reader.read!(ubyte);
            decompiledBMS.write("wait_vlq ");
            do {
                vlq = (vlq << 7) | (temp & 0x7F);
                data = [];
                data.length = 1;
                reader.source(data);
                bmsFile.rawRead(data);
                temp = reader.read!(ubyte);
            } while ((temp & 0x80) > 0);
            decompiledBMS.writeln(format!"%svlq"(vlq));*/
        //Read wait time[int24]
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("wait_EA ",
                format!"%sq"((reader.read!(ubyte) << 16) | reader.read!(ushort)));
        return;
    case BMSFunction.PANPOWSET: //0xEB
        //Read 5 ubytes
        ubyte[] data;
        data.length = 5;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("panpowset ", format!"%sb "(reader.read!(ubyte)),
                format!"%sb "(reader.read!(ubyte)), format!"%sb "(reader.read!(ubyte)),
                format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.IIRSET: //0xEC
        //Read 8 ubytes
        ubyte[] data;
        data.length = 8;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.write("iirset ");
        for (int i = 0; i < data.length; i++)
        {
            decompiledBMS.write(format!"%sb "(reader.read!(ubyte)));
        }
        decompiledBMS.write("\n");
        return;
    case BMSFunction.EXTSET: //0xEE
        //Reads an address?[int16]
        ubyte[] data;
        data.length = 2; //Could also be 3
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("extset ", format!"%sb"(reader.read!(ushort)));
        return;
    case BMSFunction.PANSWSET: //0xEF
        //Reads an int24? for something
        ubyte[] data;
        data.length = 3;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("panswset ",
                format!"%sq"((reader.read!(ubyte) << 16) | reader.read!(ushort)));
        return;
    case BMSFunction.OSCROUTE: //0xF0
        //Read something[byte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("oscroute ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.IIRCUTOFF: //0xF1
        //Read something[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("iircutoff ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.VIBPITCH: //0xF4
        //Read something?[ubyte]
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("vibpitch ", format!"%sb"(reader.read!(ubyte)));
        return;
    case BMSFunction.PRINTF: //0xFB
        //Read until read byte is 00, then read one more byte
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        ubyte nxtByte = reader.read!(ubyte);
        decompiledBMS.write("printf ");
        while (nxtByte != 0x00)
        {
            decompiledBMS.write(format!"%c"(cast(char) nxtByte));
            data = [];
            data.length = 1;
            reader.source(data);
            bmsFile.rawRead(data);
            nxtByte = reader.read!(ubyte);
        }
        data = [];
        data.length = 1;
        reader.source(data);
        bmsFile.rawRead(data);
        ubyte finalByte = reader.read!(ubyte);
        if (finalByte == 0x00)
        {
            decompiledBMS.writeln(format!"%c"(cast(char) nxtByte),
                    format!"%c"(cast(char) finalByte));
        }
        else
        {
            //Go back one byte because sometimes there isnt an extra 00
            bmsFile.seek(bmsFile.tell() - 1);
            decompiledBMS.writeln(format!"%c"(cast(char) nxtByte));
        }
        return;
    case BMSFunction.TEMPO: //0xFD
        //Read tempo value[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("tempo ", format!"%sh"(reader.read!(ushort)));
        return;
    case BMSFunction.TIMEBASE: //0xFE
        //Read timebase value[short]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        decompiledBMS.writeln("timebase ", format!"%sh "(reader.read!(ushort)));
        return;
    case BMSFunction.FINISH:
        //cmdFinish has no arguments
        decompiledBMS.writeln("finish");
        return;
    default:
        throw new Exception("UNIMPLEMENTED OPCODE IN INSTRUCTION PRINTER: " ~ format!"%02X"(opcode));
    }
}

///A function that assists in the first part of the BMS assembly process by returning amount of bytes processed for a certain instruction
uint findBMSInstByteLength(string line)
{
    string[] instruction = line.split(" ");
    switch (instruction[0])
    { //Includes opcode instruction
    case "opentrack":
        return 5;
    case "timebase":
        return 3;
    case "param_set_8":
        return 3;
    case "wait16":
        return 3;
    case "tempo":
        return 3;
    case "wait_EA":
        return 4;
    case "jmp":
        const ubyte operation = to!ubyte(strip(instruction[1], "b"));
        if (operation == 0xC0)
        {
            return 6;
        }
        else
        {
            return 5;
        }
    case "synccpu":
        return 3;
    case "perf_s8_nodur":
        return 3;
    case "noteon":
        uint length = cast(uint) instruction.length - 2;
        writefln("Noteon argument no.: %s",length);
        return length;
    case "wait8":
        return 2;
    case "noteoff":
        uint length = cast(uint) instruction.length -1;
        return length;
    case "param_set_16":
        return 4;
    case "call":
        const ubyte operation = to!ubyte(strip(instruction[1], "b"));
        if(operation == 0xC0)
        {
            return 6;
        }
        else
        {
            return 5;
        }
    case "finish":
        return 1;
    case "return":
        return 2;
    case "panswset":
        return 4;
    case "busconnect":
        return 3;
    case "outswitch":
        return 2;
    case "oscroute":
        return 2;
    case "setinterrupt":
        return 5;
    case "inttimer":
        return 4;
    case "op_override_1":
        return 4;
    case "param_cmp_8":
        return 3;
    case "reti":
        return 1;
    case "writeport":
        return 3;
    case "readport":
        return 3;
    case "childwriteport":
        return 3;
    case "param_bitwise":
        const ubyte operation = to!ubyte(strip(instruction[1], "b"));
        if ((operation & 0xF) == 0xC)
        {
            return 5;
        }
        else if ((operation & 0xF) == 0x8)
        {
            return 3;
        }
        else
        {
            return 4;
        }
    case "wait_r":
        return 2;
    case "closetrack":
        return 2;
    case "param_add_16":
        return 4;
    case "clri":
        return 1;
    case "transpose":
        return 2;
    case "simpleadsr":
        return 11;
    case "iircutoff":
        return 2;
    case "perf_s8_dur_u8":
        return 4;
    case "perf_s16_nodur":
        return 4;
    case "vibdepth":
        return 2;
    case "vibpitch":
        return 2;
    case "simpleenv":
        return 5;
    case "param_add_8": //The funny 0xA5 and 0xA8 instructions
        uint length = cast(uint) instruction.length;
        return length;
    case "param_load":
        uint length = cast(uint) instruction.length;
        return length;
    case "flushall":
        return 1;
    case "loop_e":
        return 1;
    case "perf_s16_dur_u8":
        return 5;
    case "perf_s8_dur_u16":
        return 5;
    case "loop_s":
        return 3;
    case "perf_s16_dur_u16":
        return 6;
    case "simpleosc":
        return 2;
    case "panpowset":
        return 6;
    case "vibdepthmidi":
        return 3;
    case "setlastnote":
        return 2;
    case "setparam_90":
        return 3;
    case "perf_u8_dur_u8":
        return 4;
    case "setparam_92":
        return 4;
    case "iirset":
        return 9;
    case "perf_u8_nodur":
        return 3;
    case "printf":
        return to!uint(line.length - 7) + 1;
    default:
        throw new Exception("UNIMPLEMENTED INSTRUCTION " ~ instruction[0] ~ " IN LENGTH PARSER");
    }
}

///A function that takes a decompiled instruction and converts it to bytecode
void compileBMSInstruction(File outputBMS, string instruction, ulong[string] labels)
{
    string[] instructionargs = instruction.split(" ");
    BinaryWriter writer = BinaryWriter(ByteOrder.BigEndian);
    if (canFind(instruction, "@JUMPTABLE"))
    {
        writeInt24(&writer, to!int(labels[strip(instruction, "@")]));
    }
    switch (instructionargs[0])
    { //Includes opcode instruction
    case "opentrack":
        writer.write(BMSFunction.OPENTRACK); //Opcode
        writer.write(to!byte(strip(instructionargs[1], "b"))); //Track id
        writeInt24(&writer, to!int(labels[strip(instructionargs[2], "@")])); //Address
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "timebase":
        writer.write(BMSFunction.TIMEBASE); //Opcode
        writer.write(to!short(strip(instructionargs[1], "h"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_set_8":
        writer.write(BMSFunction.PARAM_SET_8); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "wait16":
        writer.write(BMSFunction.CMD_WAIT16); //Opcode
        writer.write(to!ushort(strip(instructionargs[1], "h"))); //Wait period
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "tempo":
        writer.write(BMSFunction.TEMPO); //Opcode
        writer.write(to!short(strip(instructionargs[1], "h"))); //Tempo
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "wait_EA":
        writer.write(BMSFunction.WAIT_VLQ); //Opcode
        writeInt24(&writer, to!int(strip(instructionargs[1], "q")));
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "jmp":
        writer.write(BMSFunction.JMP); //Opcode
        const ubyte condition = to!ubyte(strip(instructionargs[1], "b"));
        writer.write(condition); //Condition
        if (condition == 0xC0)
        {
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Somethingidk
            writeInt24(&writer, to!int(labels[strip(instructionargs[3], "@")])); //Address
        }
        else
        {
            writeInt24(&writer, to!int(labels[strip(instructionargs[2], "@")])); //Address
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "synccpu":
        writer.write(BMSFunction.SYNCCPU); //Opcode
        writer.write(to!short(strip(instructionargs[1], "h"))); //Maximum wait
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s8_nodur":
        writer.write(BMSFunction.PERF_S8_NODUR); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //param
        writer.write(to!byte(strip(instructionargs[2], "b"))); //value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "noteon":
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Opcode
        for (int i = 2; i < instructionargs.length - 1; i++)
        {
            writer.write(to!ubyte(strip(instructionargs[i], "b")));
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "wait8":
        writer.write(BMSFunction.CMD_WAIT8); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //wait time
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "noteoff":
        const ubyte voicestop = (to!ubyte(strip(instructionargs[1], "b")) | 0x80);
        writer.write(voicestop);
        if ((voicestop & 0x8) > 0)
        {
            writer.write(to!ubyte(strip(instructionargs[2], "b")));
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_set_16":
        writer.write(BMSFunction.PARAM_SET_16); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
        writer.write(to!ushort(strip(instructionargs[2], "h"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "call":
        writer.write(BMSFunction.CALL); //Opcode
        const ubyte condition = to!ubyte(strip(instructionargs[1], "b"));
        writer.write(condition); //Condition
        if (condition == 0xC0)
        {
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Somethingidk
            writeInt24(&writer, to!int(labels[strip(instructionargs[3], "@")])); //Address
        }
        else
        {
            writeInt24(&writer, to!int(labels[strip(instructionargs[2], "@")])); //Address
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "finish":
        writer.write(BMSFunction.FINISH); //Opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "return":
        writer.write(BMSFunction.RETURN); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Condition
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "panswset":
        writer.write(BMSFunction.PANSWSET); //Opcode
        writeInt24(&writer, to!uint(strip(instructionargs[1], "q"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "busconnect":
        writer.write(BMSFunction.BUSCONNECT); //Opcode
        writer.write(to!short(strip(instructionargs[1], "h"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "outswitch":
        writer.write(BMSFunction.OUTSWITCH); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "oscroute":
        writer.write(BMSFunction.OSCROUTE); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "setinterrupt":
        writer.write(BMSFunction.SETINTERRUPT); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Interrupt Level
        writeInt24(&writer, to!uint(strip(instructionargs[2], "q"))); //Address
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "inttimer":
        writer.write(BMSFunction.INTTIMER); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        writer.write(to!short(strip(instructionargs[2], "h"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "op_override_1":
        writer.write(BMSFunction.OPOVERRIDE_1); //Opcode
        writer.write(to!ubyte(instructionargs[1], 16)); //Overridden opcode
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Argument Mask
        writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Argument for first opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_cmp_8":
        writer.write(BMSFunction.PARAM_CMP_8); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "reti":
        writer.write(BMSFunction.RETI); //Opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "writeport":
        writer.write(BMSFunction.WRITEPORT); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Port
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "readport":
        writer.write(BMSFunction.READPORT); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Flags
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Target Register
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "childwriteport":
        writer.write(BMSFunction.CHILDWRITEPORT); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Port
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_bitwise":
        writer.write(BMSFunction.PARAM_BITWISE); //Opcode
        const ubyte operation = to!ubyte(strip(instructionargs[1], "b"));
        //If operation & 0x0F == 0xC then write another short after a byte, if operation & 0x0F == 0x8, then only write 1 byte, otherwise write 2 bytes
        if ((operation & 0x0F) == 0xC)
        {
            writer.write(operation);
            writer.write(to!ubyte(strip(instructionargs[2], "b")));
            writer.write(to!short(strip(instructionargs[3], "h")));
            outputBMS.rawWrite(writer.buffer);
            writer.clear();
            return;
        }
        else if ((operation & 0xF) == 0x8)
        {
            writer.write(operation);
            writer.write(to!ubyte(strip(instructionargs[2], "b")));
            outputBMS.rawWrite(writer.buffer);
            writer.clear();
            return;
        }
        else
        {
            writer.write(operation);
            writer.write(to!ubyte(strip(instructionargs[2], "b")));
            writer.write(to!ubyte(strip(instructionargs[3], "b")));
            outputBMS.rawWrite(writer.buffer);
            writer.clear();
            return;
        }
    case "wait_r":
        writer.write(BMSFunction.CMD_WAITR); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "closetrack":
        writer.write(BMSFunction.CLOSETRACK); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Track-ID
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_add_16":
        writer.write(BMSFunction.PARAM_ADD_16); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
        writer.write(to!ushort(strip(instructionargs[2], "h"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "clri":
        writer.write(BMSFunction.CLRI); //Opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "transpose":
        writer.write(BMSFunction.TRANSPOSE); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Transpose
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "simpleadsr":
        writer.write(BMSFunction.SIMPLEADSR); //Opcode
        writer.write(to!ushort(strip(instructionargs[1], "h"))); //Write 5 shorts
        writer.write(to!ushort(strip(instructionargs[2], "h")));
        writer.write(to!ushort(strip(instructionargs[3], "h")));
        writer.write(to!ushort(strip(instructionargs[4], "h")));
        writer.write(to!ushort(strip(instructionargs[5], "h")));
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "iircutoff":
        writer.write(BMSFunction.IIRCUTOFF); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s8_dur_u8":
        writer.write(BMSFunction.PERF_S8_DUR_U8); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!byte(strip(instructionargs[2], "b"))); //Value
        writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Duration Ticks
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s16_nodur":
        writer.write(BMSFunction.PERF_S16_NODUR); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!short(strip(instructionargs[2], "h"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "vibdepth":
        writer.write(BMSFunction.VIBDEPTH); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "vibpitch":
        writer.write(BMSFunction.VIBPITCH); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "simpleenv":
        writer.write(BMSFunction.SIMPLEENV); //Opcode
        writeInt24(&writer, to!uint(strip(instructionargs[1], "q"))); //Something
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_add_8":
        writer.write(BMSFunction.PARAM_ADD_8); //Opcode
        if ((instructionargs.length - 1) == 2)
        {
            writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        }
        else
        {
            writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
            writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Something
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "param_load":
        writer.write(BMSFunction.PARAM_LOAD_UNK); //Opcode
        if ((instructionargs.length - 1) == 2)
        {
            writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        }
        else
        {
            writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Register
            writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
            writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Something
        }
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "flushall":
        writer.write(BMSFunction.FLUSHALL); //Opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "loop_e":
        writer.write(BMSFunction.LOOP_E); //Opcode
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s16_dur_u8":
        writer.write(BMSFunction.PERF_S16_DUR_U8_9E); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!short(strip(instructionargs[2], "h"))); //Value
        writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Duration Ticks
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s8_dur_u16":
        writer.write(BMSFunction.PERF_S8_DUR_U16); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!byte(strip(instructionargs[2], "b"))); //Value
        writer.write(to!ushort(strip(instructionargs[3], "h"))); //Duration Ticks
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "loop_s":
        writer.write(BMSFunction.LOOP_S); //Opcode
        writer.write(to!ushort(strip(instructionargs[1], "h"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_s16_dur_u16":
        writer.write(BMSFunction.PERF_S16_DUR_U16); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!short(strip(instructionargs[2], "h"))); //Value
        writer.write(to!ushort(strip(instructionargs[3], "h"))); //Duration Ticks
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "simpleosc":
        writer.write(BMSFunction.SIMPLEOSC); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "panpowset":
        writer.write(BMSFunction.PANPOWSET); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Write 5 ubytes
        writer.write(to!ubyte(strip(instructionargs[2], "b")));
        writer.write(to!ubyte(strip(instructionargs[3], "b")));
        writer.write(to!ubyte(strip(instructionargs[4], "b")));
        writer.write(to!ubyte(strip(instructionargs[5], "b")));
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "vibdepthmidi":
        writer.write(BMSFunction.VIBDEPTHMIDI); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "setlastnote":
        writer.write(BMSFunction.SETLASTNOTE); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "setparam_90":
        writer.write(BMSFunction.SETPARAM_90); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_u8_dur_u8":
        writer.write(BMSFunction.PERF_U8_DUR_U8); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Duration Ticks
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "setparam_92":
        writer.write(BMSFunction.SETPARAM_92); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Something
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Something
        writer.write(to!ubyte(strip(instructionargs[3], "b"))); //Something
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "iirset":
        writer.write(BMSFunction.IIRSET); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Write 8 ubytes
        writer.write(to!ubyte(strip(instructionargs[2], "b")));
        writer.write(to!ubyte(strip(instructionargs[3], "b")));
        writer.write(to!ubyte(strip(instructionargs[4], "b")));
        writer.write(to!ubyte(strip(instructionargs[5], "b")));
        writer.write(to!ubyte(strip(instructionargs[6], "b")));
        writer.write(to!ubyte(strip(instructionargs[7], "b")));
        writer.write(to!ubyte(strip(instructionargs[8], "b")));
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "perf_u8_nodur":
        writer.write(BMSFunction.PERF_U8_NODUR); //Opcode
        writer.write(to!ubyte(strip(instructionargs[1], "b"))); //Param
        writer.write(to!ubyte(strip(instructionargs[2], "b"))); //Value
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    case "printf":
        writer.write(BMSFunction.PRINTF); //Opcode
        writer.write(instruction[6 .. $]); //Text
        outputBMS.rawWrite(writer.buffer);
        writer.clear();
        return;
    default:
        throw new Exception("UNIMPLEMENTED INSTRUCTION " ~ instructionargs[0] ~ " IN COMPILER");
    }
}

///A function that writes an int24 to a binarywriter's buffer, function ported from Flaaffy https://github.com/arookas/flaaffy/blob/5925f5db92394e12368d67c32785f57c9ceaf095/mareep/binary.cs#L35
void writeInt24(BinaryWriter* writer, uint value)
{
    byte byte1 = cast(byte)((value >> 16) & 0xFF);
    byte byte2 = cast(byte)((value >> 8) & 0xFF);
    byte byte3 = cast(byte)(value & 0xFF);

    writer.write(byte1);
    writer.write(byte2);
    writer.write(byte3);
}

///A function that handles jump tables in a BMS file
void HandleBMSJumpTable(File bmsFile, BMSDataInfo[] bmsinfo)
{
    writeln("BMS JUMPTABLE DETECTED: OUTPUTTING JUMPTABLE");
    //Jumptables are incremental, when you find that the next value is lower
    //than the one you have, you reached the end of the current jumptable
    write("Jumptable: ");
    for (int i = 0; i < bmsinfo[dataInfoPosition].dataLength; i++)
    {
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        write(format!"%02X "(reader.read!(ubyte)));
    }
    write("\n");
}

///A function that handles jump tables in a BMS file and outputs it to a decompiled BMS file
void HandleBMSJumpTableFile(File bmsFile, File decompiledBMS, BMSDataInfo[] bmsinfo,
        ulong[ulong] addressLookUptable, BMSLabel[]* decompiledLabels)
{
    writeln("BMS JUMPTABLE DETECTED: OUTPUTTING JUMPTABLE");
    //Jumptables are incremental, when you find that the next value is lower
    //than the one you have, you reached the end of the current jumptable
    //decompiledBMS.write("Jumptable: ");
    if (bmsinfo[dataInfoPosition].padlength > 0)
        decompiledBMS.writef(".pad %s", bmsinfo[dataInfoPosition].padlength);
    for (int i = 0; i < bmsinfo[dataInfoPosition].padlength; i++)
    {
        //writeln("Padding file");
        addressLookUptable[bmsFile.tell()] = decompiledBMS.tell();
        ubyte[1] data;
        bmsFile.rawRead(data);
    }
    for (int i = 0; i < bmsinfo[dataInfoPosition].dataLength / 3; i++)
    {
        addressLookUptable[bmsFile.tell()] = decompiledBMS.tell();
        ubyte[] data;
        data.length = 3; //1
        auto reader = binaryReader(data, ByteOrder.BigEndian);
        bmsFile.rawRead(data);
        const int address = ((reader.read!(ubyte) << 16) | reader.read!(ushort)); //Label time
        *decompiledLabels ~= BMSLabel(("JUMPTABLE_" ~ format!"%s"(address) ~ "h:"), address);
        decompiledBMS.writeln("@JUMPTABLE_" ~ format!"%s"(address) ~ "h");
        //decompiledBMS.write(format!"%02X "(reader.read!(ubyte)));
    }
}

///A function that handles uncategorized data in a BMS file that should still be outputted
void HandleBMSArbitraryData(File bmsFile, BMSDataInfo[] bmsinfo)
{
    writeln("UNKNOWN DATA DETECTED: OUTPUTTING DATA");
    write("Data: ");
    for (int i = 0; i < bmsinfo[dataInfoPosition].dataLength; i++)
    {
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        write(format!"%02X "(reader.read!(ubyte)));
    }
    write("\n");
}
///A function that handles padding in a BMS file
void HandleBMSPadding(File bmsFile, BMSDataInfo[] bmsinfo)
{
    writeln("BMS PADDING DTECTED: SKIPPING PADDING");
    for (int i = 0; i < bmsinfo[dataInfoPosition].dataLength; i++)
    {
        ubyte[] data;
        data.length = 1;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
    }
}

///A command parser override for 0xA5 that reads 3 bytes of arguments instead of 2 TODO: remove the need for this function
void A53ByteArgOverride(File bmsFile, ubyte opcode)
{
    writeln(
            "0xA5 3 BYTE ARGUMENT OVERRIDE. PLEASE IMPLEMENT ACCURATE PARSING FOR 0xA5 IN THE FUTURE");
    //Read target register[ubyte] and value[ubyte] and something?[ubyte]
    ubyte[] data;
    data.length = 3;
    auto reader = binaryReader(data);
    bmsFile.rawRead(data);
    writeln("BMS Instruction: ", format!"%02X "(opcode),
            format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
            format!"%02X"(reader.read!(ubyte)));
    return;
}

///A command parser override for 0xA5 that reads 3 bytes of arguments instead of 2, outputting a decompiled form to a decompiled BMS file TODO: remove the need for this function
void A53ByteArgOverrideFile(File bmsFile, File decompiledBMS)
{
    writeln(
            "0xA5 3 BYTE ARGUMENT OVERRIDE. PLEASE IMPLEMENT ACCURATE PARSING FOR 0xA5 IN THE FUTURE");
    //Read target register[ubyte] and value[ubyte] and something?[ubyte]
    ubyte[] data;
    data.length = 3;
    auto reader = binaryReader(data);
    bmsFile.rawRead(data);
    decompiledBMS.writeln("param_add_8 ", format!"%sb "(reader.read!(ubyte)),
            format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
    return;
}

///A command parser override for 0xA8 that reads 3 bytes of arguments instead of 2 TODO: remove the need for this function
void A83ByteArgOverride(File bmsFile, ubyte opcode)
{
    writeln(
            "0xA8 3 BYTE ARGUMENT OVERRIDE. PLEASE IMPLEMENT ACCURATE PARSING FOR 0xA8 IN THE FUTURE");
    //Read target register[ubyte] and value[ubyte] and something?[ubyte]
    ubyte[] data;
    data.length = 3;
    auto reader = binaryReader(data);
    bmsFile.rawRead(data);
    writeln("BMS Instruction: ", format!"%02X "(opcode),
            format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)),
            format!"%02X"(reader.read!(ubyte)));
    return;
}

///A command parser override for 0xA8 that reads 3 bytes of arguments instead of 2, outputting the decompiled form to a decompiled BMS file TODO: remove the need for this function
void A83ByteArgOverrideFile(File bmsFile, File decompiledBMS, ubyte opcode)
{
    writeln(
            "0xA8 3 BYTE ARGUMENT OVERRIDE. PLEASE IMPLEMENT ACCURATE PARSING FOR 0xA8 IN THE FUTURE");
    //Read target register[ubyte] and value[ubyte] and something?[ubyte]
    ubyte[] data;
    data.length = 3;
    auto reader = binaryReader(data);
    bmsFile.rawRead(data);
    decompiledBMS.writeln("param_load ", format!"%sb "(reader.read!(ubyte)),
            format!"%sb "(reader.read!(ubyte)), format!"%sb"(reader.read!(ubyte)));
    return;
}
