import yaml, os, subprocess, struct, random, sys, math, re
from pathlib import Path
from typing import TypedDict
import pandas as pd
import numpy as np
import logging
import matplotlib.pyplot as plt

# --- Configurations ---
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%H:%M:%S'
)

# --- Test Functions ---
class SRAMConfig(TypedDict):
    SRAM: str
    DATA_WIDTH: int
    ADDR_WIDTH: int
    WMASK_WIDTH: int

class OpCode:
    READ = 0
    WRITE = 1

class DataValue:
    ZERO = 0
    MAX = (1 << 32) - 1

class Address:
    ZERO = 0
    MAX = (1 << 6) - 1

class WriteMask:
    ZERO = 0
    MAX = (1 << 4) - 1

def parse_sram_config(sram_config: str) -> SRAMConfig:
    parts = sram_config.split("_")[1]
    num_words = int(parts.split("x")[0])
    data_width = int(parts.split("x")[1].split("m")[0])
    write_size = int(parts.split("w")[1])
    addr_width = int(math.ceil(math.log2(num_words)))
    wmask_width = data_width // write_size
    return {
        "SRAM": sram_config,
        "DATA_WIDTH": data_width,
        "ADDR_WIDTH": addr_width,
        "WMASK_WIDTH": wmask_width
    }

# --- YAML Writer ---
def writeYaml(td):
    defines_str = '\n'.join([f"  - {key}={val}" for key, val in td['defines'].items()])
    delays = [
        f"""{{name: {i}, clock: {td['clock']}, delay: "1", direction: input}}""" for i in td['input_ports']
    ] + [
        f"""{{name: {i}, clock: {td['clock']}, delay: "1", direction: output}}""" for i in td['output_ports']
    ]
    delays = ',\n  '.join(delays)
    clock_period = td["clock_period"]
    cfg = f"""\
vlsi.core.build_system: make
vlsi.inputs.power_spec_type: cpf
vlsi.inputs.power_spec_mode: auto

design.defines: &DEFINES
  - CLOCK_PERIOD={clock_period}
{defines_str}

vlsi.inputs.clocks: [{{name: {td['clock']}, period: "{clock_period}ns", uncertainty: "100ps"}}]
vlsi.inputs.delays: [
  {delays}
]

synthesis.inputs:
  top_module: {td['top_module']}
  input_files: {td['vsrcs']}
  defines: *DEFINES

sim.inputs:
  top_module: {td['top_module']}
  tb_name: {td['tb_name']}
  tb_dut: {td['tb_dut']}
  options: ["-timescale=1ns/10ps", "-sverilog"]
  options_meta: append
  defines: *DEFINES
  defines_meta: append
  level: rtl
  input_files: {td['vsrcs'] + td['vsrcs_tb']}

vlsi.core.power_tool: hammer.power.joules
power.inputs:
  level: rtl
  top_module: {td['top_module']}
  tb_name: {td['tb_name']}
  tb_dut: {td['tb_dut']}
  defines: *DEFINES
  input_files: {td['vsrcs']}
  report_configs:
    - waveform_path: {td['root']}/output.fsdb
      report_stem: {td['root']}/power
      toggle_signal: {td['clock']}
      num_toggles: 1
      levels: 2
      output_formats: [report, plot_profile, ppa]

vlsi.inputs.placement_constraints:
  - path: {td['top_module']}
    type: toplevel
    x: 0
    y: 0
    width: 100
    height: 100
    margins: {{left: 0, right: 0, top: 0, bottom: 0}}

vlsi.inputs.sram_parameters: "../../../../../hammer/technology/sky130/sram-cache.json"
vlsi.inputs.sram_parameters_meta: ["prependlocal", "transclude", "json2list"]
"""
    with open(td['root']/'config.yml', 'w') as f:
        f.write(cfg)

# --- Test Generator ---
def createTest(test_name: str, test: dict, clock_period: int):
    design = test_name.split('-')[0]
    full_test_name = f"{test_name}-{clock_period}ns"
    test.update({
        'design': design,
        'inst': '/sram_sim/mem0',
        'clock': 'clock',
        'vsrcs': ['src/sram_sim.v'],
        'vsrcs_tb': ['src/sram_sim_tb.sv'],
        'top_module': 'sram_sim',
        'tb_name': 'sram_sim_tb',
        'tb_dut': 'sram_sim_dut',
        'input_ports': ['we', 'wmask', 'addr', 'din'],
        'output_ports': ['dout'],
        'clock_period': clock_period
    })
    root = tests_dpath / full_test_name
    root.mkdir(exist_ok=True, parents=True)
    test['defines']['TESTROOT'] = root
    test['root'] = root
    test['obj_dir'] = f"build-{PDK}-cm/{design}"
    test['obj_dpath'] = energy_char_dpath / test['obj_dir']
    cfg = root / 'config.yml'
    test['make'] = f"design={design} OBJ_DIR={test['obj_dir']} extra={cfg}"
    return full_test_name, test

# --- Build/Run Helpers ---
def runMakeCmd(make_target, td, fp, overwrite=False, verbose=False):
    if overwrite or not fp.exists():
        cmd = f"make {make_target} {td['make']}"
        logging.info(f"Running: {cmd}")
        try:
            subprocess.run(cmd, cwd=energy_char_dpath, shell=True, check=True,
                           capture_output=(not verbose), text=True)
        except subprocess.CalledProcessError as e:
            logging.error(f"Make failed [{cmd}]: {e.returncode}")
            if not verbose:
                logging.error("STDOUT:\n" + e.stdout)
                logging.error("STDERR:\n" + e.stderr)
            raise

def runBuild(td, overwrite=False, verbose=False): runMakeCmd("build -B", td, td['obj_dpath'], overwrite, verbose)
def runSim(td, overwrite=False, verbose=False): runMakeCmd("redo-sim-rtl", td, td['root']/'output.fsdb', overwrite, verbose)
def runPowerSyn(td, overwrite=False, verbose=False): runMakeCmd("power-rtl", td, td['obj_dpath']/'power-rtl-rundir/pre_report_power', overwrite, verbose)
def runPowerReport(td, overwrite=False, verbose=False): runMakeCmd("redo-power-rtl args='--only_step report_power'", td, td['root']/'power.power.rpt', overwrite, verbose)

# --- Power Report Parsers ---
def parse_hier_power_rpt(td) -> list:
    fpath = td['root']/'power.hier.power.rpt'
    with fpath.open('r') as f:
        for l in f:
            words = l.split()
            if td['inst'] == words[-1]:
                return [float(p) for p in words[2:6]]
    return []

def parse_power_profile(td) -> float:
    fpath = td['root']/'power.profile.png.data'
    with fpath.open('r') as f:
        lines = f.readlines()
    header = lines[0]
    match = re.search(r'simulation time \((\w+)\)', header)
    unit = match.group(1) if match else None
    scaling = {'ns': 1, 'ps': 1e-3, 'fs': 1e-6}[unit]
    time_power = [l.split() for l in lines[1:] if len(l.split()) == 2]
    times = [float(t)*scaling for t,p in time_power]
    powers = [float(p) for t,p in time_power][1:-1]
    avgpow = sum(powers)/len(powers)
    return times[-1] - times[0], avgpow

if __name__ == "__main__":
    # --- Setup ---
    PDK = 'sky130'
    CLOCK_PERIOD = 10

    energy_char_dpath = Path(os.getcwd())
    tests_dpath = energy_char_dpath / f'experiments/tests-{PDK}'
    tests_dpath.mkdir(parents=True, exist_ok=True)
    PDKs = ["sky130"]
    test_paths = {pdk: energy_char_dpath/f'experiments/tests-{pdk}' for pdk in PDKs}
    num_inputs = 50
    clock_periods = [CLOCK_PERIOD]

    # --- Generate Tests ---
    tests_dict = {
        'sram64x32-zero': {
            'inputs': [(OpCode.READ, DataValue.ZERO, Address.ZERO, WriteMask.ZERO) for _ in range(num_inputs)],
            'defines': parse_sram_config("sram22_64x32m4w8"),
        }
    }
    for clock in clock_periods:
        for test_name, test_info in list(tests_dict.items()):
            new_name, new_info = createTest(test_name, test_info, clock)
            writeYaml(new_info)
            tests_dict[new_name] = new_info

    python_exec_fpath = Path(sys.executable)
    env_dpath = str(python_exec_fpath.parent)
    if not os.environ['PATH'].startswith(env_dpath):
        os.environ['PATH'] = env_dpath + ':' + os.environ['PATH']

    # --- Build & Simulate ---
    overwrite = True
    build_dpaths = {td['obj_dpath']: t for t, td in tests_dict.items()}
    for bd, t in build_dpaths.items(): runBuild(tests_dict[t], overwrite)
    for bd, t in build_dpaths.items():
        runSim(tests_dict[t], overwrite)
        runPowerSyn(tests_dict[t], overwrite)
        runPowerReport(tests_dict[t], overwrite)

    # --- Generate Database ---
    # power = [parse_hier_power_rpt(td) for td in tests_dict.values()]
    # power = pd.DataFrame(power, columns=['Leakage','Internal','Switching','Total'], index=tests_dict.keys())
    # database = pd.DataFrame(index=tests_dict.keys())
    # database['design'] = [t.split('-')[0] for t in tests_dict]
    # database['clock']  = [t.split('-')[1] for t in tests_dict]
    # database['output_af']  = [0.5 for _ in tests_dict]  # Placeholder for AF

    # time_ns = [parse_power_profile(td)[0] for td in tests_dict.values()]
    # energy = power.mul(time_ns, axis=0) / num_inputs
    # energy.columns = [c + ' Energy (pJ)' for c in energy.columns]
    # database['time_ns'] = time_ns
    # database = pd.concat([database, energy, power], axis=1)
    # database.to_hdf(PDK + '.h5', key='df', mode='w')
    # print(database)