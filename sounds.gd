extends Node
## Plays the original game's sounds by class name (GameSound.as): short effects on a small
## pool of players and one looping music track.
##
## The sounds are extracted assets (tools/extract_sounds.py). A missing one is reported once
## and then skipped: the game stays playable without them.

const SOUND_PATH := "res://assets/sounds/%s.mp3"
const EFFECT_PLAYERS := 6

var _effects: Array[AudioStreamPlayer] = []
var _music := AudioStreamPlayer.new()
var _music_name := ""
var _streams: Dictionary = {}
var _reported_missing: Dictionary = {}


func _ready() -> void:
	add_child(_music)
	for index in EFFECT_PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_effects.append(player)


## Plays a short effect. If every player is busy the sound is dropped, not queued.
func play(sound_name: String) -> void:
	var stream := _load(sound_name)
	if stream == null:
		return
	for player in _effects:
		if not player.playing:
			player.stream = stream
			player.play()
			return


## Switches the looping music. Asking for the track already playing does nothing.
func play_music(sound_name: String) -> void:
	if sound_name == _music_name and _music.playing:
		return
	_music_name = sound_name
	var stream := _load(sound_name)
	if stream == null:
		_music.stop()
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_name = ""
	_music.stop()


func has_sound(sound_name: String) -> bool:
	return ResourceLoader.exists(SOUND_PATH % sound_name)


func _load(sound_name: String) -> AudioStream:
	if _streams.has(sound_name):
		return _streams[sound_name]
	if not has_sound(sound_name):
		if not _reported_missing.has(sound_name):
			_reported_missing[sound_name] = true
			push_warning("Sounds: %s is missing. Run: python3 tools/extract_sounds.py" % sound_name)
		return null
	var stream: AudioStream = load(SOUND_PATH % sound_name)
	_streams[sound_name] = stream
	return stream
