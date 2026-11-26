extends Node

## Owns the ENet peer and exposes a small, stable API to the menu/game world.
## Gameplay RPCs live on GameWorld so every peer uses the same node path.

signal connected_to_server
signal connection_failed(message: String)
signal server_disconnected
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal status_changed(message: String)

enum SessionMode {
	OFFLINE,
	HOST,
	CLIENT,
	DEDICATED
}

const DEFAULT_PORT := 7000
const MAX_CLIENTS := 6
const NETWORK_CHANNELS := 3

var public_host_address := ""
var upnp := UPNP.new()
var mapped_port := 0
var mode: int = SessionMode.OFFLINE
var enet_peer: ENetMultiplayerPeer
var active_port := DEFAULT_PORT


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func start_offline() -> void:
	close_session()
	mode = SessionMode.OFFLINE
	status_changed.emit("Training mode")

func _open_upnp_port(port: int) -> String:
	var result := upnp.discover()

	if result != UPNP.UPNP_RESULT_SUCCESS:
		return ""

	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		return ""

	result = upnp.add_port_mapping(
		port,
		port,
		"Online Soccer Beta",
		"UDP"
	)

	if result != UPNP.UPNP_RESULT_SUCCESS:
		return ""

	mapped_port = port
	return upnp.query_external_address()

func start_dedicated_server(port: int = DEFAULT_PORT) -> Error:
	close_session()

	enet_peer = ENetMultiplayerPeer.new()
	var error := enet_peer.create_server(
		port,
		MAX_CLIENTS,
		NETWORK_CHANNELS
	)

	if error != OK:
		enet_peer = null
		return error

	multiplayer.multiplayer_peer = enet_peer
	mode = SessionMode.DEDICATED
	active_port = port

	print("Dedicated server listening on UDP port %d" % port)
	return OK

func host_game(port: int = DEFAULT_PORT) -> Error:
	close_session()
	enet_peer = ENetMultiplayerPeer.new()
	var error := enet_peer.create_server(
		port,
		MAX_CLIENTS,
		NETWORK_CHANNELS
	)
	if error != OK:
		enet_peer = null
		connection_failed.emit("Could not host on UDP port %d (error %d)." % [port, error])
		return error

	multiplayer.multiplayer_peer = enet_peer
	mode = SessionMode.HOST
	active_port = port
	var public_ip := _open_upnp_port(port)
	public_host_address = public_ip
	if public_ip.is_empty():
		status_changed.emit("Hosting locally. UPnP failed—forward UDP 7000 manually.")
	else:
		status_changed.emit("Hosting at %s:%d" % [public_ip, port])
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	close_session()
	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		clean_address = "127.0.0.1"

	enet_peer = ENetMultiplayerPeer.new()
	var error := enet_peer.create_client(
		clean_address,
		port,
		NETWORK_CHANNELS
	)
	if error != OK:
		enet_peer = null
		connection_failed.emit("Could not connect to %s:%d (error %d)." % [clean_address, port, error])
		return error

	multiplayer.multiplayer_peer = enet_peer
	mode = SessionMode.CLIENT
	active_port = port
	status_changed.emit("Connecting to %s:%d..." % [clean_address, port])
	return OK


func close_session() -> void:
	if mapped_port > 0:
		upnp.delete_port_mapping(mapped_port, "UDP")
		mapped_port = 0
	if enet_peer != null:
		enet_peer.close()
		enet_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = SessionMode.OFFLINE
	active_port = DEFAULT_PORT


func is_server_authority() -> bool:
	return mode != SessionMode.CLIENT


func is_online() -> bool:
	return mode != SessionMode.OFFLINE


func local_peer_id() -> int:
	if mode == SessionMode.OFFLINE:
		return 1
	return multiplayer.get_unique_id()


func one_way_latency_seconds(peer_id: int = 1) -> float:
	if mode == SessionMode.OFFLINE or enet_peer == null:
		return 0.0

	var packet_peer: ENetPacketPeer = enet_peer.get_peer(peer_id)

	if packet_peer == null or not packet_peer.is_active():
		return 0.0

	var round_trip_msec: float = packet_peer.get_statistic(
		ENetPacketPeer.PEER_ROUND_TRIP_TIME
	)

	return clampf(round_trip_msec * 0.0005, 0.0, 0.10)


func mode_label() -> String:
	match mode:
		SessionMode.HOST:
			return "HOST"
		SessionMode.CLIENT:
			return "CLIENT"
		_:
			return "TRAINING"


func _on_connected_to_server() -> void:
	status_changed.emit("Connected")
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit("The connection failed. Check the IP address, firewall, and UDP port.")


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	status_changed.emit("Server disconnected")


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
