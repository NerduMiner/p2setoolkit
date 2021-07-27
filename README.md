# p2setoolkit
A tool that dissassembles and reassembles sequenced music files from Pikmin 2, specializes in handling Pikmin 2's se.bms file.

The tool, at best, can accurately process around 760 bytes of instructions in se.bms before it finds an unimplemented opcode as of 7/27/2021
<br/>The tool also only has functionality for printing BMS Instructions, decompiling to a file and recompiling from it will come in the future once all instructions in se.bms are accurately printed.

# Building
p2setoolkit requires a D compiler(DMD is recommended), downloads can be found at https://dlang.org/.<br/>Once installed, run `dub build` in your CLI/Terminal in the root directory of the repository to compile the project.

# Usage
Run the executable in CLI/Terminal. The desired bms file you wish to handle with the tool needs to be put in the arguments like so:
<br/>`p2setoolkit --input [name of bms file]`

Thanks to XAYRGA, RenolY2, and arookas for their resources and guidance on BMS intricacies in the creation of this tool. 
<br/>Thanks to PikHacker for helping with reverse engineering Pikmin 2's sound system.
