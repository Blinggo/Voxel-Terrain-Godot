class_name GenerationRegistry
extends RefCounted

## Ordered set of generation modules, with dependency resolution.
##
## Registration is explicit and happens in one place
## ([method TerrainGenerationStack._register_modules]); the registry then works
## out the execution order from the declared dependencies. A module added later
## only needs to declare what it reads - nothing else in the pipeline changes.
##
## [b]Failure modes are loud.[/b] A duplicate id, a dependency on a module that
## was never registered, or a dependency cycle makes [method resolve] fail with
## an error naming the module. Generation then refuses to start rather than
## producing terrain from a half-ordered pipeline.
##
## [b]Determinism.[/b] Resolution is deterministic: modules whose dependencies are
## already satisfied run in registration order, so the order - and therefore the
## terrain - does not depend on hash iteration order or on the platform.

var _modules: Array[GenerationModule] = []
var _ordered: Array[GenerationModule] = []
var _field_indices: Dictionary = {}
var _resolved := false


## Adds a module. Returns false (and reports) if the id is already taken.
func register(module: GenerationModule) -> bool:
	if module == null:
		push_error("GenerationRegistry.register(): module is null.")
		return false
	if find_module(module.id) != null:
		push_error("GenerationRegistry.register(): duplicate module id '%s'." % module.id)
		return false
	if _field_indices.has(module.output_field):
		push_error(
				"GenerationRegistry.register(): duplicate output field '%s' (module '%s')."
				% [module.output_field, module.id]
		)
		return false
	_modules.append(module)
	_field_indices[module.output_field] = _modules.size() - 1
	_resolved = false
	return true


## Sorts the modules so every dependency runs before its dependants, and assigns
## each module its field slot. Returns false if the graph is invalid.
func resolve() -> bool:
	_ordered.clear()

	var remaining: Array[GenerationModule] = _modules.duplicate()
	var satisfied: Dictionary = {}
	var ordered_ids: Array[StringName] = []

	while not remaining.is_empty():
		var progressed := false
		for i in range(remaining.size()):
			var module := remaining[i]
			var ready := true
			for dependency in module.dependencies:
				var dependency_id := StringName(dependency)
				if not satisfied.has(dependency_id):
					ready = false
					break
			if not ready:
				continue

			# Everything this module reads must exist; a missing dependency is
			# a wiring bug, not something to paper over.
			for dependency in module.dependencies:
				if find_module(StringName(dependency)) == null:
					push_error(
							"GenerationRegistry.resolve(): module '%s' depends on unknown module '%s'."
							% [module.id, dependency]
					)
					return false

			_ordered.append(module)
			satisfied[module.id] = true
			ordered_ids.append(module.id)
			remaining.remove_at(i)
			progressed = true
			break

		if not progressed:
			var stuck := PackedStringArray()
			for module in remaining:
				stuck.append(String(module.id))
			if remaining.size() == 1:
				push_error(
						"GenerationRegistry.resolve(): module '%s' depends on unknown module(s)."
						% remaining[0].id
				)
			else:
				push_error(
						"GenerationRegistry.resolve(): dependency cycle or unknown dependency among %s."
						% ", ".join(stuck)
				)
			_ordered.clear()
			return false

	# Field slots follow execution order, so a module's dependencies always have
	# lower indices than the module itself.
	_field_indices.clear()
	for i in range(_ordered.size()):
		var module := _ordered[i]
		_field_indices[module.output_field] = i
		module.assign_output_index(i)

	_resolved = true
	return true


func is_resolved() -> bool:
	return _resolved


## Modules in execution order. Empty until [method resolve] succeeds.
func get_ordered_modules() -> Array[GenerationModule]:
	return _ordered


## Number of scalar fields produced per node, which is also the size of the
## per-node value array.
func get_field_count() -> int:
	return _ordered.size()


## Slot of a field in the per-node value array, or -1 if no module produces it.
func get_field_index(field_name: StringName) -> int:
	var index: Variant = _field_indices.get(field_name)
	return -1 if index == null else int(index)


## Slot of a module's output field, or -1.
func get_module_output_index(module_id: StringName) -> int:
	var module := find_module(module_id)
	return -1 if module == null else module.get_output_index()


func find_module(module_id: StringName) -> GenerationModule:
	for module in _modules:
		if module.id == module_id:
			return module
	return null


func get_module_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for module in _ordered:
		ids.append(String(module.id))
	return ids


func get_module_count() -> int:
	return _ordered.size()
