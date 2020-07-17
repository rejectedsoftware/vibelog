module vibelog.internal.passwordhash;


string generatePasswordHash(string password)
@safe {
	import std.base64 : Base64;
	import std.random : uniform;

	// FIXME: use a more secure hash method
	ubyte[4] salt;
	foreach( i; 0 .. 4 ) salt[i] = cast(ubyte)uniform(0, 256);
	ubyte[16] hash = md5hash(salt, password);
	return Base64.encode(salt ~ hash).idup;
}

bool validatePasswordHash(string password_hash, string password)
@safe {
	import std.base64 : Base64;
	import std.exception : enforce;

	// FIXME: use a more secure hash method
	import std.string : format;
	ubyte[] upass = Base64.decode(password_hash);
	enforce(upass.length == 20, format("Invalid binary password hash length: %s", upass.length));
	auto salt = upass[0 .. 4];
	auto hashcmp = upass[4 .. 20];
	ubyte[16] hash = md5hash(salt, password);
	return hash == hashcmp;
}

unittest {
	auto h = generatePasswordHash("foobar");
	assert(!validatePasswordHash(h, "foo"));
	assert(validatePasswordHash(h, "foobar"));
}

private ubyte[16] md5hash(ubyte[] salt, string[] strs...)
@safe {
	import std.digest.md;
	MD5 ctx;
	ctx.start();
	ctx.put(salt);
	foreach( s; strs ) ctx.put(cast(const(ubyte)[])s);
	return ctx.finish();
}
