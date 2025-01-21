vlsi_dir=$(abspath .)
e2e_dir=$(vlsi_dir)/..


# minimal flow configuration variables
design              ?= pass
pdk                 ?= sky130
tools               ?= cm
env                 ?= bwrc

extra               ?=  # extra configs
args                ?=  # command-line args (including step flow control)


OBJ_DIR             ?= $(vlsi_dir)/build-$(pdk)-$(tools)/$(design)

# non-overlapping default configs
ENV_YML             ?= $(e2e_dir)/configs-env/$(env)-env.yml
PDK_CONF            ?= $(e2e_dir)/configs-pdk/$(pdk).yml
TOOLS_CONF          ?= $(e2e_dir)/configs-tool/$(tools).yml

# design-specific overrides of default configs
DESIGN_CONF         ?= # set by user
SRAM_CONF           ?= $(OBJ_DIR)/sram_generator-output.json

PROJ_YMLS           ?= $(PDK_CONF) $(TOOLS_CONF) $(DESIGN_CONF) $(extra)
HAMMER_EXTRA_ARGS   ?= $(foreach conf, $(PROJ_YMLS), -p $(conf)) -p $(SRAM_CONF) $(args)




HAMMER_D_MK = $(OBJ_DIR)/hammer.d

build: $(HAMMER_D_MK)

$(HAMMER_D_MK): $(SRAM_CONF)
	hammer-vlsi --obj_dir $(OBJ_DIR) -e $(ENV_YML) $(HAMMER_EXTRA_ARGS) build

-include $(HAMMER_D_MK)

$(SRAM_CONF) srams:
	hammer-vlsi --obj_dir $(OBJ_DIR) -e $(ENV_YML) $(foreach conf, $(PROJ_YMLS), -p $(conf)) sram_generator
	cp output.json $(SRAM_CONF)

clean:
	rm -rf $(OBJ_DIR) hammer-vlsi-*.log
