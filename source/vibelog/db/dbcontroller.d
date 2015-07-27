module vibelog.db.dbcontroller;

public import vibelog.config;
public import vibelog.post;
public import vibelog.user;
import vibelog.settings;
import vibe.data.bson;


DBController createDBController(VibeLogSettings settings)
{
	import vibelog.db.mongo;
	import std.string;
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
	User getUser(string name);
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

	Comment[] getComments(BsonObjectID post_id, bool allow_inactive = false);
	long getCommentCount(BsonObjectID post_id);
	void addComment(BsonObjectID post_id, Comment comment);
	void setCommentPublic(BsonObjectID comment_id, bool is_public);
	void deleteNonPublicComments(BsonObjectID post_id);
}
