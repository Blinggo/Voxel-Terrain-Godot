class_name GenerationModule
extends RefCounted

## One step of the generation pipeline.
##
## A module owns a single scalar field. It declares a stable [member id], the
## fields it reads, and writes exactly one field. The engine decides when it
## runs, based on those declarations.
##
## [b]Contract.[/b]
## - [method evaluate_node] is pure: same (x, z) and same configuration always
##   produce the same number, on any thread, in any order, in any chunk.
## - It must not allocate state that later samples depend on. Scalar caches of
##   configuration are fine; per-coordinate memoisation belongs in the engine.
## - It must only read the inputs it declared. The field layout is built from
##   those declarations, so an undeclared read would silently see a stale slot.
##
## [b]Why one field per module.[/b] It keeps ordering explicit and makes each
## module independently testable: a test can feed a module synthetic inputs and
## assert its output without building a world. Modules that need several outputs
## are not needed in M1 and are deliberately not supported yet.
##
## [b]Extending.[/b] To add a field: subclass, give it a new [member id], list
## its dependencies, register it in
## [method TerrainGenerationStack._register_modules]. No other module changes,
## and modules that do not depend on it keep producing identical values.

## Stable identifier. Part of the determinism contract: it seeds the module's
## random stream, so renaming a module changes its terrain.
var id: StringName

## Version of this module's algorithm. Bumping it reshuffles only this module's
## stream, which is how a local algorithm change is signalled without disturbing
## unrelated fields.
var version: int = 1

## Ids of the modules whose fields this module reads. Ordering follows from
## these declarations.
var dependencies: PackedStringArray = PackedStringArray()

## Name of the field this module writes. Unique across the registry.
var output_field: StringName

## True if this module also contributes a full-resolution per-column
## term. Most modules do not; see [method sample_column].
var contributes_columns := false

var _context: GenerationContext
var _registry: GenerationRegistry
## Field slot of this module's output, assigned by the registry.
var _output_index := -1


func _init(
		p_id: StringName,
		p_output_field: StringName,
		p_dependencies: PackedStringArray = PackedStringArray(),
		p_version: int = 1
) -> void:
	id = p_id
	output_field = p_output_field
	dependencies = p_dependencies
	version = p_version


## Set by the engine before [method configure], so a module can resolve the field
## slots of the modules it declared as dependencies.
func bind(registry_ref: GenerationRegistry) -> void:
	_registry = registry_ref


## Field slot of a dependency, for modules that need to read one.
##
## Returns -1 (and reports) if the dependency was not declared or not
## registered - which is a wiring bug, so it is deliberately loud.
func dependency_index(module_id: StringName) -> int:
	if _registry == null:
		push_error(
				"GenerationModule '%s': dependency_index('%s') used before bind()."
				% [id, module_id]
		)
		return -1
	var index := _registry.get_module_output_index(module_id)
	if index < 0:
		push_error(
				"GenerationModule '%s' reads undeclared or unknown dependency '%s'."
				% [id, module_id]
		)
	if not dependencies.has(String(module_id)):
		push_error(
				"GenerationModule '%s' reads '%s' without declaring it as a dependency."
				% [id, module_id]
		)
	return index


## Called once by the engine, on the main thread, before any sampling. Modules
## create their noise objects here and must not mutate them afterwards.
func configure(_context_ref: GenerationContext) -> void:
	push_error("GenerationModule.configure() is abstract and must be overridden.")


## Called once by the registry after resolution, to tell the module where its
## output lives in the per-node value array.
func assign_output_index(index: int) -> void:
	_output_index = index


func get_output_index() -> int:
	return _output_index


## Writes this module's field value for the node at world coordinate
## ([param x], [param z]).
##
## [param values] is the per-node value array: read declared dependencies from
## it and write [member output_field] at [method get_output_index].
func evaluate_node(_x: int, _z: int, _values: PackedFloat32Array) -> void:
	push_error("GenerationModule.evaluate_node() is abstract and must be overridden.")


## Bounds the engine should clamp the composed surface to, after every
## full-resolution term has been added. [code]Vector2.ZERO[/code] means unbounded.
##
## The composer owns the world-unit limits; the engine only applies them. Keeping
## the constant in one module is why a detail term can never silently push the
## surface outside the range the rest of the project - mesher, camera framing,
## tests - assumes.
func get_output_bounds() -> Vector2:
	return Vector2.ZERO


## Optional full-resolution contribution, applied by the engine after
## interpolation.
##
## Regional fields are computed on a coarse node grid and interpolated, which is
## cheap but cannot represent detail finer than the grid. A module that wants a
## full-resolution contribution sets [member contributes_columns] and overrides
## this; the default contributes nothing, so most modules never pay for it.
##
## [b]Bulk, not per column.[/b] The engine hands over the whole block's height
## array at once rather than asking column by column. A scripted call costs far
## more than the arithmetic inside it, so 256 calls per block would dominate the
## frame; one call per block does not.
##
## [param heights] is row-major, [param size].x values per row, and already holds
## the interpolated regional surface. Add to it, do not overwrite it.
func add_columns(_heights: PackedFloat32Array, _origin: Vector2i, _size: Vector2i) -> void:
	pass
