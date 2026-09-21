class_name Sha256Util
extends RefCounted

const CHUNK_SIZE := 1024 * 1024


static func HashFile(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var total := file.get_length()
	var read := 0
	while read < total:
		var n: int = mini(CHUNK_SIZE, total - read)
		ctx.update(file.get_buffer(n))
		read += n
	return ctx.finish().hex_encode()


static func HashFileAsync(path: String, host: Node, progress: Callable = Callable()) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var total := file.get_length()
	var read := 0
	var frames := 0
	while read < total:
		var n: int = mini(CHUNK_SIZE, total - read)
		ctx.update(file.get_buffer(n))
		read += n
		frames += 1
		if progress.is_valid():
			progress.call(read, total)
		if frames % 8 == 0 and host != null and host.get_tree() != null:
			await host.get_tree().process_frame
	return ctx.finish().hex_encode()
