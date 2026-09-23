class_name Cmd
extends RefCounted
## One tick of player input (the web game's `cmd`). Plain data, so it could go over a network.

var forward := 0.0 # 1 forward, -1 back
var right := 0.0 # 1 right, -1 left
var jump := false # pressed since the last tick
var jump_held := false
var sprint := false
var crouch := false
var slide := false # held
var slide_pressed := false # pressed since the last tick
var fire := false
var fire_pressed := false
var reload := false
var ability := false
var slot := "" # "primary" / "secondary" when a weapon key was pressed
var cycle := 0 # mouse wheel
var yaw := 0.0
var pitch := 0.0
