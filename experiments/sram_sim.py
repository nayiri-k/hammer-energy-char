import math
import matplotlib.pyplot as plt
import numpy as np
import os
import pandas as pd
import pathlib
import random
import struct
import subprocess
import sys
from typing import TypedDict

class SRAMConfig(TypedDict):
    SRAM: str
    DATA_WIDTH: int
    ADDR_WIDTH: int
    WMASK_WIDTH: int

class OpCode:
    """Operation codes for SRAM access."""
    READ = 0
    WRITE = 1

class DataValue:
    """32-bit data input values."""
    ZERO = 0
    MAX = (1 << 32) - 1

class Address:
    """6-bit address space."""
    ZERO = 0
    ONE = 1
    MAX = (1 << 6) - 1  # 6-bit max address

class WriteMask:
    """4-bit write mask for 32-bit word (8-bit granularity)."""
    ZERO = 0
    MAX = (1 << 4) - 1

def parse_sram_config(sram_config: str) -> SRAMConfig:
    """
    Parses an SRAM configuration string and extracts key parameters.
    """
    parts = sram_config.split("_")[1]
    num_words = int(parts.split("x")[0])
    data_width = int(parts.split("x")[1].split("m")[0])
    write_size = int(parts.split("w")[1])

    addr_width = int(math.ceil(math.log2(num_words)))
    wmask_width = data_width // write_size

    return {
        "SRAM"        : sram_config,
        "DATA_WIDTH"  : data_width,
        "ADDR_WIDTH"  : addr_width,
        "WMASK_WIDTH" : wmask_width
    }

def create_test_directories(tests: dict, base_dir: pathlib.Path, pdk: str) -> None:
    """
    Create necessary directories for the given tests and update the test configurations.
    """
    for test in tests:
        # input/output files directory
        test_dir = base_dir / test
        test_dir.mkdir(exist_ok=True, parents=True)
        print(f"Directory created at: {test_dir}")
        tests[test]['defines']['TESTROOT'] = test_dir
        tests[test]['root'] = test_dir

        # hammer build directory
        obj_dir = f"build-{pdk}-cm/{tests[test]['design']}"
        tests[test]['obj_dir'] = obj_dir
        tests[test]['obj_dpath'] = energy_char_dpath / obj_dir

def write_input_files(tests: dict) -> None:
    """
    Generate input files for a set of tests.
    """
    for test_name in tests:
        input_path = tests[test_name]['root'] / 'input.txt'
        with input_path.open('w') as input_file:
            for input_line in tests[test_name]['inputs']:
                binary_operands = ['{0:b}'.format(operand) for operand in input_line]
                input_file.write(" ".join(binary_operands) + '\n')
        print(f"Inputs for '{test_name}' test written at: {input_path}")

def generate_hammer_config(test: dict, clock_period: int) -> None:
    defines_str = '\n'.join( [ f"  - {key}={val}" for key,val in test['defines'].items() ] )
    delays = [f"""{{name: {input_port}, clock: {test['clock']}, delay: "1", direction: input}}""" for input_port in test['input_ports']]
    delays += [f"""{{name: {output_port}, clock: {test['clock']}, delay: "1", direction: output}}""" for output_port in test['output_ports']]
    delays = ',\n  '.join(delays)
    config = f"""\
vlsi.core.build_system: make
vlsi.inputs.power_spec_type: cpf
vlsi.inputs.power_spec_mode: auto

design.defines: &DEFINES
  - CLOCK_PERIOD={clock_period}
{defines_str}

vlsi.inputs.clocks: [{{name: "clock", period: "{clock_period}ns", uncertainty: "100ps"}}]

vlsi.inputs.delays: [
  {delays}
]

synthesis.inputs:
  top_module: {test['top_module']}
  input_files: {test['vsrcs']}
  defines: *DEFINES

sim.inputs:
  top_module: {test['top_module']}
  tb_name: {test['tb_name']}
  tb_dut: {test['tb_dut']}
  options: ["-timescale=1ns/10ps", "-sverilog"]
  options_meta: append
  defines: *DEFINES
  defines_meta: append
  level: rtl
  input_files: {test['vsrcs'] + test['vsrcs_tb']}

vlsi.core.power_tool: hammer.power.joules

power.inputs:
  level: rtl
  top_module: {test['top_module']}
  tb_name: {test['tb_name']}
  tb_dut: {test['tb_dut']}
  defines: *DEFINES
  input_files: {test['vsrcs']}
  report_configs:
    - waveform_path: {test['root']}/output.fsdb
      report_stem: {test['root']}/power
      toggle_signal: {test['clock']}
      num_toggles: 1
      levels: all
      output_formats:
      - report
      - plot_profile
      - ppa

vlsi.inputs.placement_constraints:
  - path: {test['top_module']}
    type: toplevel
    x: 0
    y: 0
    width: 100
    height: 100
    margins:
      left: 0
      right: 0
      top: 0
      bottom: 0

vlsi.inputs.sram_parameters: "../../../../../hammer/technology/sky130/sram-cache.json"
vlsi.inputs.sram_parameters_meta: ["prependlocal", "transclude", "json2list"]
"""
    config_path = test['root'] / 'config.yml'
    with config_path.open('w') as f:
        f.write(config)

def generate_all_hammer_configs(tests: dict, clock_period: int) -> None:
    for test in tests:
        generate_hammer_config(test=tests[test], clock_period=clock_period)
        print(f"Generated Hammer config for '{test}' test.")


def run_experiments(tests: dict) -> None:
    # generate custom make str for each test
    for test in tests:
        cfg = str(tests[test]['root']/'config.yml')
        tests[test]['make'] = f"design={tests[test]['design']} OBJ_DIR={tests[test]['obj_dir']} extra={cfg}"

    # build
    build_dirs = {tests[test]['obj_dir']: test for test in tests} # run build once per build dir (not once per test)
    for bd, test in build_dirs.items():
        command = f"make build -B {tests[test]['make']} -B"
        print(f"Running: {command}")
        fpath = tests[test]['root']/'power.hier.power.rpt'
        if not fpath.exists():
            subprocess.run(command, shell=True, cwd=energy_char_dpath, check=True)
    print()

    # sim-rtl
    for test in tests:
        command = f"make redo-sim-rtl -B {tests[test]['make']}"
        print(f"Running: {command}")
        fpath = tests[test]['root']/'power.hier.power.rpt'
        if not fpath.exists():
            subprocess.run(command, shell=True, cwd=energy_char_dpath, check=True)
    print()

    # # power-rtl
    # for test in tests:
    #     # re-use pre_report_power database if it's already generated (i.e. skip synthesis)
    #     make_target = "redo-power-rtl args='--only_step report_power'" \
    #             if (tests[test]['obj_dpath']/'power-rtl-rundir/pre_report_power').exists() else 'power-rtl'
    #     command = f"make {make_target} -B {tests[test]['make']}"
    #     print(f"Running: {command}")
    #     fpath = tests[test]['root']/'power.hier.power.rpt'
    #     if not fpath.exists():
    #         subprocess.run(command, shell=True, cwd=energy_char_dpath, check=True)
    # print()
    
if __name__ == "__main__":
    # Global Parameters
    PDK = "sky130"
    CLOCK_PERIOD = 10 # ns

    # Paths
    e2e_dpath = pathlib.Path(os.getcwd()).parent
    energy_char_dpath = pathlib.Path(os.getcwd())
    tests_dpath = energy_char_dpath / "experiments" / f"tests-{PDK}"
    print(e2e_dpath)

    # Configure Tests
    INPUT_ITERS = 50

    tests = {
        'sram64x32-zero': {
            'inputs': [(OpCode.READ, DataValue.ZERO, Address.ZERO, WriteMask.ZERO) for _ in range(INPUT_ITERS)],
            'defines': parse_sram_config("sram22_64x32m4w8"),
        }
    }

    for test in tests:
        tests[test]['design'] = test.split('-')[0]
        tests[test]['inst'] = '/sram_sim/mem0'
        tests[test]['clock'] = 'clock'
        tests[test]['top_module'] = 'sram_sim'
        tests[test]['tb_name'] = 'sram_sim_tb'
        tests[test]['tb_dut'] = 'sram_sim_dut'
        tests[test]['vsrcs'] = ['src/sram_sim.v']
        tests[test]['vsrcs_tb'] = ['src/sram_sim_tb.sv']
        tests[test]['input_ports'] = ['we', 'wmask', 'addr', 'din']
        tests[test]['output_ports'] = ['dout']

    # Generate Files
    create_test_directories(tests=tests, base_dir=tests_dpath, pdk=PDK)
    write_input_files(tests=tests)
    generate_all_hammer_configs(tests=tests, clock_period=CLOCK_PERIOD)

    # Run Experiments
    run_experiments(tests=tests)