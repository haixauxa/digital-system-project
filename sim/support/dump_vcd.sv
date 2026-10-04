`timescale 1ns/1ps

// Add this as a second top-level module to enable waveform dumping without
// modifying a self-checking testbench. Override the output path with
// +vcd=<path>; otherwise build/sim/wave.vcd is used.
module dump_vcd;
  string vcd_path;

  initial begin
    if (!$value$plusargs("vcd=%s", vcd_path))
      vcd_path = "build/sim/wave.vcd";

    $dumpfile(vcd_path);
    $dumpvars;
  end
endmodule
