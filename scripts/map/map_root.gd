@tool
class_name MapRoot
extends Node3D
## The root of a map scene (maps/*.tscn): its name and the card it gets on the map screen.
## Everything under it is read by MapData.load_map(): MapBox (solid boxes, in tree order),
## MapPad, MapSpawn (the first one is where you start), MapTarget (bean dummies), MapPortal (hub
## portals to the time trial) and one optional MapTrial. Group them under plain Node3Ds however
## you like; moving a group moves everything in it.

@export var map_name := "New Map"
@export var tag := "Map" ## small line above the name on the map card
@export_multiline var desc := ""
@export var art := "MAP" ## big faded word on the card
@export var grad_from := Color("2f6bff")
@export var grad_to := Color("8a3dff")
## Big maps: pushes the distance haze (and the camera's far plane) out this many times.
@export_range(1.0, 3.0, 0.1) var view_scale := 1.0
## Bot arena layout for the future Bot Arena mode (kept as data for now).
@export var arena := {}
