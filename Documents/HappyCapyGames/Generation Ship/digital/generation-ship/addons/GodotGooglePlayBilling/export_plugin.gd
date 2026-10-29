@tool
extends EditorPlugin

# A class member to hold the editor export plugin during its lifecycle.
var export_plugin : BillingPluginExportPlugin

func _enter_tree():
	# Initialization of the plugin goes here.
	export_plugin = BillingPluginExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	# Clean-up of the plugin goes here.
	remove_export_plugin(export_plugin)
	export_plugin = null


class BillingPluginExportPlugin extends EditorExportPlugin:
	var _plugin_name = "GodotGooglePlayBilling"

	func _supports_platform(platform):
		if platform is EditorExportPlatformAndroid:
			return true
		return false

	func _get_android_libraries(platform, debug):
		if debug:
			return PackedStringArray([_plugin_name + "/bin/debug/" + _plugin_name + "-debug.aar"])
		else:
			return PackedStringArray([_plugin_name + "/bin/release/" + _plugin_name + "-release.aar"])

	# Generation Ship change: the plain "billing" library instead of "billing-ktx".
	# billing-ktx 9.1.0 is built with Kotlin 2.3 and Godot 4.7's Android build
	# template compiles with Kotlin 2.1 ("incompatible version of Kotlin"); the
	# plugin's own code only uses the base com.android.billingclient.api classes.
	func _get_android_dependencies(platform, debug):
		if debug:
			return PackedStringArray(["com.android.billingclient:billing:9.1.0"])
		else:
			return PackedStringArray(["com.android.billingclient:billing:9.1.0"])

	func _get_name():
		return _plugin_name
