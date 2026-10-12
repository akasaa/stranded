extends Node2D
## Lapisan gambar tambahan (ambient, cahaya, UI).
## Isinya digambar oleh fungsi milik host (main.gd) supaya semua logika tetap di satu file.

var host: Node
var fn := ""


func _draw() -> void:
	if host != null and fn != "":
		host.call(fn, self)
