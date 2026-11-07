class_name TerrainGenerationStack
extends RefCounted

## Builds the generation pipeline for one configuration.
##
## This is the single place where modules are registered. Adding a field means
## writing a module and adding one line in [method _register_modules]; nothing
## else in the project changes, and the modules that do not depend on it keep
## producing exactly the same values.
##
## [b]Registration order does not have to be execution order.[/b] The registry
## sorts by declared dependencies, so the list below is grouped for readability:
## signals first, the composer last.
##
## [b]One stack per world build.[/b] A stack owns its context (seed plus frozen
## configuration) and its engine, so a new seed gets a new stack and nothing is
## shared between two configurations.

var context: GenerationContext
var registry: GenerationRegistry
var engine: GenerationEngine


func _init(world_config: WorldConfig) -> void:
	var snapshot := world_config.duplicate_config() if world_config != null else WorldConfig.new()

	context = GenerationContext.new(
			snapshot.world_seed, snapshot.generation_version, snapshot
	)
	registry = GenerationRegistry.new()

	if not _register_modules():
		push_error("TerrainGenerationStack: module registration failed.")
		return

	if not registry.resolve():
		push_error("TerrainGenerationStack: module graph could not be resolved.")
		return

	engine = GenerationEngine.new(context, registry)


func is_valid() -> bool:
	return engine != null


## Registers the M1 pipeline.
##
## Order here is presentational. What matters is each module's declared
## dependencies:
## [codeblock]
## detail          (independent, per-column)
## continentalness (independent)
## elevation       <- continentalness
## mountainness    <- continentalness
## hills           <- continentalness, mountainness
## surface         <- continentalness, elevation, mountainness, hills
## [/codeblock]
func _register_modules() -> bool:
	var modules: Array[GenerationModule] = [
		DetailModule.new(),
		ContinentalnessModule.new(),
		ElevationModule.new(),
		MountainModule.new(),
		HillsModule.new(),
		SurfaceModule.new(),
	]

	var ok := true
	for module in modules:
		if not registry.register(module):
			ok = false
	return ok


## Module ids in execution order, for diagnostics and documentation.
func get_execution_order() -> PackedStringArray:
	return registry.get_module_ids()
