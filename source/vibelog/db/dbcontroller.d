module vibelog.db.dbcontroller;

public import vibelog.config;
public import vibelog.post;
public import vibelog.user;
import vibelog.settings;
import vibe.core.stream;
import vibe.data.bson;


DBController createDBController(VibeLogSettings settings)
{
	import vibelog.db.mongo : MongoDBController;
	import std.exception : enforce;
	import std.string : startsWith;

	enforce(settings.databaseURL.startsWith("mongodb:"), "Only mongodb: database URLs supported.");
	return new MongoDBController(settings.databaseURL);
}

interface DBController {
	Config getConfig(string name, bool createdefault = false);
	void setConfig(Config cfg);
	void invokeOnConfigChange(void delegate() del);
	void deleteConfig(string name);
	Config[] getAllConfigs();

	User[string] getAllUsers();
	User getUser(BsonObjectID userid);
	User getUserByName(string name);
	User getUserByEmail(string email);
	BsonObjectID addUser(User user);
	void modifyUser(User user);
	void deleteUser(BsonObjectID id);

	int countPostsForCategory(string[] categories);
	void getPostsForCategory(string[] categories, int nskip, bool delegate(size_t idx, Post post) del);
	void getPublicPostsForCategory(string[] categories, int nskip, bool delegate(size_t idx, Post post) del);
	void getAllPosts(int nskip, bool delegate(size_t idx, Post post) del);
	Post getPost(BsonObjectID postid);
	Post getPost(string name);
	bool hasPost(string name);
	BsonObjectID addPost(Post post);
	void modifyPost(Post post);
	void deletePost(BsonObjectID id);
	void addFile(string post_name, string file_name, in ubyte[] contents);
	string[] getFiles(string post_name);
	InputStream getFile(string post_name, string file_name);
	void removeFile(string post_name, string file_name);
}
