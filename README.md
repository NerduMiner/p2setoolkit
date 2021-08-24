# p2setoolkit
A tool that dissassembles and reassembles sequenced music files from Pikmin 2, specializes in handling Pikmin 2's se.bms file, but other bms's from Pikmin 2 and flaaffy output might work as long as they use opcodes parsed by the tool.
The tool, with overrides for some 0xA5 and 0xA8 instructions, can parse the entirety of se.bms as of 8/10/2021
<br/>The tool, as of 8/15/2021, can recompile se.bms with an identical checksum.

# Building
p2setoolkit requires a D compiler(DMD is recommended), downloads can be found at https://dlang.org/.<br/>Once installed, run `dub build` in your CLI/Terminal in the root directory of the repository to compile the project.

# Usage
Run the executable in CLI/Terminal. The desired bms/dissassembled bms file you wish to handle with the tool and what task you would like to do needs to be put in the arguments like so:
<br/>`p2setoolkit --input [filename.bms/filename.bms.txt] --task [print/decompile]`
<br/>"print" makes the tool print out every BMS Instruction in the file, useful for debugging purposes and making sure the tool can successfully decompile the file.
<br/>"decompile" decompiles the byte code into a dissassembled text format, similar to flaafy's cotton format besides a few verbosities.
<br/>The task argument is not needed if you are reassembling a decompiled BMS file.

# .info file
YOU WILL NEED TO CREATE A [filename.bms].info FILE FOR THE PROGRAM TO RUN IN DECOMPILE MODE. This is due to the fact that there can be arbitrary data in a file that is hard for the tool to detect, or 0xA5 and 0xA8 instructions that only take 3 bytes of arguments instead of 4(for reasons yet unknown as of 8/11/2021).
<br/>A .info file only needs to contain the following for the program to handle your file:
```r
0 -> Amount of overrides in file
1234567890 -> Position of override
data -> Override type[data/padding/a5_3byte_override/a8_3byte_override/jumptable]
1234 -> Length of override[Only applicable for data/padding/jumptable]
0 -> Length of padding[Only applicable for jumptable, optional]
```

An example .info file for Pikmin 2's se.bms is provided in this repository. DATA AND PADDING ARE NOT AVAILABLE FOR USE IN THE DECOMPILE TASK.

# NOTICE
You will need to have a good understanding of BMS opcodes and how they work if you want to use this tool effectively, you can look at bmsinterpret.d to see how opcodes are defined but that can only take you so far, this is mainly due to a lack of info in the scene about BMS files and their intricacies.


Thanks to XAYRGA, RenolY2, and arookas for their resources and guidance on BMS intricacies in the creation of this tool. 
<br/>Thanks to PikHacker for helping with reverse engineering Pikmin 2's sound system.
<br/>Thanks to Robert Pasiński for the pack-d binary i/o library https://code.dlang.org/packages/pack-d
