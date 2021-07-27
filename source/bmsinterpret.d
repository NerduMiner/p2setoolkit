module bmsinterpret;
import binary.reader;
import std.exception;
import std.file;
import std.format;
import std.stdio;

///A list of functions paired with their BMS Opcode, some opcodes come from https://github.com/XAYRGA/JaiSeqX/blob/sxlja/JaiSeqXLJA/libJAudio/Sequence/JAISeqEvent.cs
enum BMSFunction : ubyte 
{
    NOTE_ON = 0x00, //0x00-0x7F
    CMD_WAIT8 = 0x80,
    NOTE_OFF = 0x81, //0x81-0x87, 0x89-0x8F
    CMD_WAIT16 = 0x88,
    SETPARAM_UNK = 0x90, //0x90-0x9F cmdSetParam
    PERF_U8_NODUR = 0x94, //Come from Xayr's Documents
    PERF_U8_DUR_U8 = 0x96,
    PERF_U8_DUR_U16 = 0x97,
    PERF_S8_NODUR = 0x98,
    PERF_S8_DUR_U8 = 0x9A,
    PERF_S8_DUR_U16 = 0x9B,
    PERF_S16_NODUR = 0x9C,
    PERF_S16_DUR_U8 = 0x9D,
    PERF_S16_DUR_U16 = 0x9F,
    PARAM_SET_R = 0xA0, //0xA0-0xAF cmdWriteRegParam
    PARAM_ADD_R = 0xA1, //Come from Xayr's Documents
    PARAM_MUL_R = 0xA2,
    PARAM_CMP_R = 0xA3,
    PARAM_SET_8 = 0xA4,
    PARAM_ADD_8 = 0xA5,
    PARAM_MUL_8 = 0xA6,
    PARAM_CMP_8 = 0xA7,
    PARAM_UNKNOWN = 0xA8,
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
    if (opcode < 0x80) { //0x00-0x7F are cmdNoteOn commands
        return opcode; //We'll just have to do a similar check again
    }
    if ((opcode > 0x80 && opcode < 0x88) || (opcode > 0x88 && opcode < 0x90)) { //0x81-0x87, 0x89-0x8F are cmdNoteOff commands
        return opcode; //We'll just have to do a similar check again
    }
    if (opcode >= 0x90 && opcode < 0xA0) { //0x90-0x9F are cmdSetParam commands
        switch (opcode) {
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
            case BMSFunction.PERF_S16_DUR_U8:
                return BMSFunction.PERF_S16_DUR_U8;
            case BMSFunction.PERF_S16_DUR_U16:
                return BMSFunction.PERF_S16_DUR_U16;
            default:
                return BMSFunction.SETPARAM_UNK;
        }
    }
    if (opcode >= 0xA0 && opcode < 0xB0) { //0xA0-0xAF are cmdWriteRegParam commands
        switch (opcode) {
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
                return BMSFunction.PARAM_UNKNOWN;
        }
    }
    if (opcode >= 0xB0 && opcode < 0xC0) { //0xB0-0xBF are the very funny commands
        if (opcode >= 0xB8 && opcode < 0xC0)
            return BMSFunction.OPOVERRIDE_R;
        switch (opcode) {
            case BMSFunction.OPOVERRIDE_1:
                return BMSFunction.OPOVERRIDE_1;
            case BMSFunction.OPOVERRIDE_2:
                return BMSFunction.OPOVERRIDE_2;
            default:
                throw new Exception("UNIMPLEMENTED 0XBX OPCODE IN PARSER: " ~ format!"%02X"(opcode));
        }
    }
    switch (opcode) { //For opcodes 0x80, 0x88, 0xC0-0xFF
        case BMSFunction.CMD_WAIT8:
            return BMSFunction.CMD_WAIT8;
        case BMSFunction.CMD_WAIT16:
            return BMSFunction.CMD_WAIT16;
        case BMSFunction.OPENTRACK:
            return BMSFunction.OPENTRACK;
        case BMSFunction.CALL:
            return BMSFunction.CALL;
        case BMSFunction.RETURN:
            return BMSFunction.RETURN;
        case BMSFunction.JMP:
            return BMSFunction.JMP;
        case BMSFunction.READPORT:
            return BMSFunction.READPORT;
        case BMSFunction.WRITEPORT:
            return BMSFunction.WRITEPORT;
        case BMSFunction.OUTSWITCH:
            return BMSFunction.OUTSWITCH;
        case BMSFunction.BUSCONNECT:
            return BMSFunction.BUSCONNECT;
        case BMSFunction.SETINTERRUPT:
            return BMSFunction.SETINTERRUPT;
        case BMSFunction.RETI:
            return BMSFunction.RETI;
        case BMSFunction.INTTIMER:
            return BMSFunction.INTTIMER;
        case BMSFunction.SYNCCPU:
            return BMSFunction.SYNCCPU;
        case BMSFunction.WAIT_VLQ:
            return BMSFunction.WAIT_VLQ;
        case BMSFunction.PANSWSET:
            return BMSFunction.PANSWSET;
        case BMSFunction.OSCROUTE:
            return BMSFunction.OSCROUTE;
        case BMSFunction.IIRCUTOFF:
            return BMSFunction.IIRCUTOFF;
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
void printBMSInstruction (ubyte opcode, File bmsFile) {
    if (opcode < 0x80) { //0x00-0x7F are cmdNoteOn commands, so handle those first
        //Read voice[ubyte] and velocity[ubyte]
        ubyte[] data;
        data.length = 2;
        auto reader = binaryReader(data);
        bmsFile.rawRead(data);
        writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
        return;
    }
    if ((opcode > 0x80 && opcode < 0x88) || (opcode > 0x88 && opcode < 0x90)) { //0x81-0x87, 0x89-0x8F are cmdNoteOff commands {
        //Opcode contains which voice to stop, you can check this via AND-ing with 0x0F
        writeln("BMS Instruction: ", format!"%02X "(opcode));
        return;
    }
    switch (opcode) {
        case BMSFunction.CMD_WAIT8: //0x80
            //Read wait time[byte]
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.CMD_WAIT16: //0x88
            //Read wait time[short]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //shorts have to be read as 2 bytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PARAM_SET_R: //0xA0
            //Read source register[ubyte] and destination register[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PARAM_SET_8: //0xA4
            //Read target register[ubyte] and value[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PARAM_CMP_8: //0xA7
            //Read target register[ubyte] and value[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PARAM_BITWISE: //0xA9
            //Read something[ubyte] and something[ubyte](operation and register?)
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PARAM_LOADTBL: //0xAA
            //Read
            throw new Exception("0xAA CAUGHT BUT NOT HANDLED IN INSTRUCTION CREATOR");
        case BMSFunction.PARAM_SET_16: //0xAC
            //Read target register[ubyte] and value[short]
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //Shorts have to be read as 2 ubytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
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
            writeln("BMS Instruction[Funny 0xB0 opcode]: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.OPOVERRIDE_2: //0xB1?
            throw new Exception("CONFIRM BEHAVIOR OF THIS 0xBX OPCODE FIRST: " ~ format!"%02X"(opcode));
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
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.CALL: //0xC4
            //Read condition?[ubyte] and address[int24] and something?[ubyte]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //int24 have to be read as 3 ubytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.RETURN: //0xC6
            //Read condition[byte]
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.JMP: //0xC8
            //Read condition?[ubyte] and address[int24]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //int24 have to be read as 3 ubytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.READPORT: //0xCB
            //Read flags[ubyte] and target register[ubyte]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.WRITEPORT: //0xCC
            //Read port[ubyte] and value[ubyte](also known as source port and dest port)
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.OUTSWITCH: //0xDB
            //Read something[ubyte]
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.BUSCONNECT: //0xDD
            //Read something[short]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.SETINTERRUPT: //0xDF
            //Read interrupt level[byte] and address[int24]
            ubyte[] data;
            data.length = 4;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
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
            writeln("BMS Instruction(E4 Not Fully Accurate): ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.SYNCCPU: //0xE7
            //Read maximum wait[short]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.PANSWSET: //0xEF
            //Reads an int24? for something
            ubyte[] data;
            data.length = 3;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.OSCROUTE: //0xF0
            //Read something[byte]
            ubyte[] data;
            data.length = 1;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.IIRCUTOFF: //0xF1
            //Read something[short]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            writeln("BMS Instruction(F1 not fully accurate): ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.TEMPO: //0xFD
            //Read tempo value[short]
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //Shorts have to be read as 2 ubytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return; 
        case BMSFunction.TIMEBASE: //0xFE
            //Read timebase value
            ubyte[] data;
            data.length = 2;
            auto reader = binaryReader(data);
            bmsFile.rawRead(data);
            //Shorts have to be read as 2 ubytes
            writeln("BMS Instruction: ", format!"%02X "(opcode), format!"%02X "(reader.read!(ubyte)), format!"%02X"(reader.read!(ubyte)));
            return;
        case BMSFunction.FINISH:
            //cmdFinish has no arguments
            writeln("BMS Instruction: ", format!"%02X "(opcode));
            return;
        default:
            throw new Exception("UNIMPLEMENTED OPCODE IN INSTRUCTION PRINTER: " ~ format!"%02X"(opcode));
    }
}