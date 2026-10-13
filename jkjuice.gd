@tool
extends EditorPlugin

const EXPORT_TOOL_NAME := "Export Yalk Map..."
const MAP_PATH := "res://map.tscn"
const TEXTURES_DIR := "res://textures"

func _enter_tree() -> void:
	add_tool_menu_item(EXPORT_TOOL_NAME, _show_export_dialog)

func _exit_tree() -> void:
	remove_tool_menu_item(EXPORT_TOOL_NAME)

func _show_export_dialog() -> void:
	var file_dialog := EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	file_dialog.add_filter("*.pck", "Godot Pack File")
	file_dialog.title = "Choose where to save the Yalk map (.pck)"

	get_editor_interface().get_base_control().add_child(file_dialog)
	file_dialog.file_selected.connect(_on_file_selected)
	file_dialog.popup_file_dialog()

func _on_file_selected(output_pck_path: String) -> void:
	print("[Yalk Map Export] Starting map export...")

	if not FileAccess.file_exists(MAP_PATH):
		printerr("[Yalk Map Export] Map scene not found: ", MAP_PATH)
		return

	var map_name := output_pck_path.get_file().get_basename().validate_filename()
	if map_name.is_empty():
		printerr("[Yalk Map Export] Invalid map name.")
		return

	var map_root := "res://maps/%s/" % map_name
	var packer := PCKPacker.new()
	var error: Error = packer.pck_start(output_pck_path)

	if error != OK:
		printerr("[Yalk Map Export] Failed to initialize PCKPacker. Error: ", error)
		return

	var scene_text := FileAccess.get_file_as_string(MAP_PATH)
	scene_text = scene_text.replace("res://textures/", map_root + "textures/")
	scene_text = _remove_uids(scene_text)

	var scene_target := map_root + MAP_PATH.get_file()
	error = _pack_text_file(packer, scene_target, scene_text, ".tscn")

	if error != OK:
		printerr("[Yalk Map Export] Failed to pack the map scene. Error: ", error)
		return

	var packed_count := 1
	print("[Yalk Map Export] Packed: ", scene_target)

	packed_count += _scan_directory_for_textures(TEXTURES_DIR, map_root, packer)

	error = packer.flush()

	if error == OK:
		print("[Yalk Map Export] Export completed successfully.")
		print("[Yalk Map Export] Internal map path: ", map_root)
		print("[Yalk Map Export] Files packed: ", packed_count)
	else:
		printerr("[Yalk Map Export] Failed to save the PCK file. Error: ", error)

func _scan_directory_for_textures(path: String, map_root: String, packer: PCKPacker) -> int:
	var dir := DirAccess.open(path)

	if dir == null:
		printerr("[Yalk Map Export] Texture directory not found: ", path)
		return 0

	var packed_count := 0
	dir.list_dir_begin()

	var file_name := dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				packed_count += _scan_directory_for_textures(path.path_join(file_name), map_root, packer)
		else:
			var extension := file_name.get_extension().to_lower()

			if extension in ["png", "jpg", "jpeg"]:
				var source_path := path.path_join(file_name)
				var target_path := map_root + source_path.trim_prefix("res://")
				packed_count += _pack_texture(packer, source_path, target_path, map_root)

		file_name = dir.get_next()

	dir.list_dir_end()
	return packed_count

func _pack_texture(packer: PCKPacker, source_path: String, target_path: String, map_root: String) -> int:
	var source_absolute_path := ProjectSettings.globalize_path(source_path)
	var error: Error = packer.add_file(target_path, source_absolute_path)

	if error != OK:
		printerr("[Yalk Map Export] Failed to pack: ", source_path, " Error: ", error)
		return 0

	var packed_count := 1
	print("[Yalk Map Export] Packed: ", target_path)

	var import_path := source_path + ".import"
	if not FileAccess.file_exists(import_path):
		return packed_count

	var import_text := FileAccess.get_file_as_string(import_path)
	var import_regex := RegEx.new()
	import_regex.compile('path="(res://[^"]+)"')

	var import_match := import_regex.search(import_text)
	if import_match == null:
		printerr("[Yalk Map Export] Could not find the imported resource path in: ", import_path)
		return packed_count

	var imported_source_path := import_match.get_string(1)
	var imported_absolute_path := ProjectSettings.globalize_path(imported_source_path)

	if not FileAccess.file_exists(imported_absolute_path):
		printerr("[Yalk Map Export] Imported texture cache not found: ", imported_source_path)
		return packed_count

	var imported_target_path := map_root + imported_source_path.trim_prefix("res://")
	error = packer.add_file(imported_target_path, imported_absolute_path)

	if error != OK:
		printerr("[Yalk Map Export] Failed to pack imported texture: ", imported_source_path, " Error: ", error)
		return packed_count

	packed_count += 1

	import_text = import_text.replace(source_path, target_path)
	import_text = import_text.replace("res://.godot/imported/", map_root + ".godot/imported/")
	import_text = _remove_uids(import_text)

	error = _pack_text_file(packer, target_path + ".import", import_text, ".import")

	if error == OK:
		packed_count += 1
	else:
		printerr("[Yalk Map Export] Failed to pack import metadata for: ", source_path)

	var remap_text := import_text.split("[deps]", false, 1)[0]
	error = _pack_text_file(packer, target_path + ".remap", remap_text, ".remap")

	if error == OK:
		packed_count += 1
	else:
		printerr("[Yalk Map Export] Failed to pack remap metadata for: ", source_path)

	return packed_count

func _pack_text_file(packer: PCKPacker, target_path: String, content: String, suffix: String) -> Error:
	var temp_path := "user://yalk_export_%d%s" % [Time.get_ticks_usec(), suffix]
	var temp_file := FileAccess.open(temp_path, FileAccess.WRITE)

	if temp_file == null:
		return FileAccess.get_open_error()

	temp_file.store_string(content)
	temp_file.close()

	var temp_absolute_path := ProjectSettings.globalize_path(temp_path)
	var error: Error = packer.add_file(target_path, temp_absolute_path)

	DirAccess.remove_absolute(temp_absolute_path)
	return error

func _remove_uids(content: String) -> String:
	var uid_regex := RegEx.new()
	uid_regex.compile('uid="uid://[^"]+"')
	return uid_regex.sub(content, "", true)
