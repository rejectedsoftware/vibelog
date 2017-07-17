module vibelog.db.mongo;

import vibelog.db.dbcontroller;

import vibe.core.log;
import vibe.core.stream;
import vibe.crypto.passwordhash;
import vibe.data.bson;
import vibe.db.mongo.mongo;
import vibe.mail.smtp;
import vibe.stream.memory;
import vibe.templ.diet;

import std.exception;
import std.variant;


final class MongoDBController : DBController {
	private {
		MongoCollection m_configs;
		MongoCollection m_users;
		MongoCollection m_posts;
		MongoCollection m_postFiles;
		void delegate()[] m_onConfigChange;
	}

	this(string db_url)
	{
		string database = "vibelog";
		MongoClientSettings dbsettings;
		if (parseMongoDBUrl(dbsettings, db_url))
			database = dbsettings.database;

		auto db = connectMongoDB(db_url).getDatabase(database);
		m_configs = db["configs"];
		m_users = db["users"];
		m_posts = db["posts"];
		m_postFiles = db["postFiles"];

		upgradeComments(db);
	}

	Config getConfig(string name, bool createdefault = false)
	{
		auto configbson = m_configs.findOne(["name": Bson(name)]);
		if( !configbson.isNull() )
			return Config.fromBson(configbson);
		enforce(createdefault, "Configuration does not exist.");
		auto cfg = new Config;
		cfg.name = name;
		m_configs.insert(cfg.toBson());
		return cfg;
	}

	void setConfig(Config cfg)
	{
		Bson update = cfg.toBson();
		m_configs.update(["name": Bson(cfg.name)], update);
		foreach (d; m_onConfigChange) d();
	}

	void invokeOnConfigChange(void delegate() del)
	{
		m_onConfigChange ~= del;
	}

	void deleteConfig(string name)
	{
		m_configs.remove(["name": Bson(name)]);
	}

	Config[] getAllConfigs()
	{
		Bson[string] query;
		Config[] ret;
		foreach( config; m_configs.find(query) ){
			auto c = Config.fromBson(config);
			ret ~= c;
		}
		return ret;
	}

	User[string] getAllUsers()
	{
		Bson[string] query;
		User[string] ret;
		foreach( user; m_users.find(query) ){
			auto u = User.fromBson(user);
			ret[u.username] = u;
		}
		if( ret.length == 0 ){
			auto initial_admin = new User;
			initial_admin.username = "admin";
			initial_admin.password = generateSimplePasswordHash("admin");
			initial_admin.name = "Default Administrator";
			initial_admin.groups ~= "admin";
			m_users.insert(initial_admin);
			ret["admin"] = initial_admin;
		}
		return ret;
	}
	
	User getUser(BsonObjectID userid)
	{
		auto userbson = m_users.findOne(["_id": Bson(userid)]);
		return User.fromBson(userbson);
	}

	User getUserByName(string name)
	{
		auto userbson = m_users.findOne(["username": Bson(name)]);
		if (userbson.isNull()) {
			try {
				auto id = BsonObjectID.fromHexString(name);
				logDebug("%s <-> %s", name, id.toString());
				assert(id.toString() == name);
				userbson = m_users.findOne(["_id": Bson(id)]);
			} catch (Exception e) {
				return null;
			}
		}
		//auto userbson = m_users.findOne(Bson(["name" : Bson(name)]));
		return User.fromBson(userbson);
	}

	User getUserByEmail(string email)
	{
		auto userbson = m_users.findOne(["email": Bson(email)]);
		return User.fromBson(userbson);
	}

	BsonObjectID addUser(User user)
	{
		auto id = BsonObjectID.generate();
		Bson userbson = user.toBson();
		userbson["_id"] = Bson(id);
		m_users.insert(userbson);
		return id;
	}

	void modifyUser(User user)
	{
		assert(user._id.valid);
		Bson update = user.toBson();
		m_users.update(["_id": Bson(user._id)], update);
	}

	void deleteUser(BsonObjectID id)
	{
		assert(id.valid);
		m_users.remove(["_id": Bson(id)]);
	}

	int countPostsForCategory(string[] categories)
	{
		int cnt;
		getPostsForCategory(categories, 0, (size_t, Post p){ if( p.isPublic ) cnt++; return true; });
		return cnt;
	}

	void getPostsForCategory(string[] categories, int nskip, bool delegate(size_t idx, Post post) del)
	{
		auto cats = new Bson[categories.length];
		foreach( i; 0 .. categories.length ) cats[i] = Bson(categories[i]);
		Bson category = Bson(["$in" : Bson(cats)]);
		Bson[string] query = ["query" : Bson(["category" : category]), "orderby" : Bson(["date" : Bson(-1)])];
		foreach (idx, post; m_posts.find(query, null, QueryFlags.None, nskip).byPair) {
			if (!del(idx, Post.fromBson(post)))
				break;
		}
	}

	void getPublicPostsForCategory(string[] categories, int nskip, bool delegate(size_t idx, Post post) del)
	{
		auto cats = new Bson[categories.length];
		foreach( i; 0 .. categories.length ) cats[i] = Bson(categories[i]);
		Bson category = Bson(["$in" : Bson(cats)]);
		Bson[string] query = ["query" : Bson(["category" : category, "isPublic": Bson(true)]), "orderby" : Bson(["date" : Bson(-1)])];
		foreach (idx, post; m_posts.find(query, null, QueryFlags.None, nskip).byPair) {
			if (!del(idx, Post.fromBson(post)))
				break;
		}
	}

	void getAllPosts(int nskip, bool delegate(size_t idx, Post post) del)
	{
		Bson[string] query;
		Bson[string] extquery = ["query" : Bson(query), "orderby" : Bson(["date" : Bson(-1)])];
		foreach (idx, post; m_posts.find(extquery, null, QueryFlags.None, nskip).byPair) {
			if (!del(idx, Post.fromBson(post)))
				break;
		}
	}


	Post getPost(BsonObjectID postid)
	{
		auto postbson = m_posts.findOne(["_id": Bson(postid)]);
		return Post.fromBson(postbson);
	}

	Post getPost(string name)
	{
		auto postbson = m_posts.findOne(["slug": Bson(name)]);
		if( postbson.isNull() )
			postbson = m_posts.findOne(["_id" : Bson(BsonObjectID.fromHexString(name))]);
		return Post.fromBson(postbson);
	}

	bool hasPost(string name)
	{
		return !m_posts.findOne(["slug": Bson(name)]).isNull();

	}

	BsonObjectID addPost(Post post)
	{
		auto id = BsonObjectID.generate();
		Bson postbson = post.toBson();
		postbson["_id"] = Bson(id);
		m_posts.insert(postbson);
		return id;
	}

	void modifyPost(Post post)
	{
		assert(post.id.valid);
		Bson update = post.toBson();
		m_posts.update(["_id": Bson(post.id)], update);
	}

	void deletePost(BsonObjectID id)
	{
		assert(id.valid);
		m_posts.remove(["_id": Bson(id)]);
	}

	void addFile(string post_name, string file_name, InputStream contents)
	{
		import vibe.stream.operations : readAll;
		struct I {
			string postName;
			string fileName;
		}
		m_postFiles.insert(PostFile(post_name, file_name, contents.readAll()));
	}

	string[] getFiles(string post_name)
	{
		import std.algorithm.iteration : map;
		import std.array : array;
		return m_postFiles.find(["postName": post_name], ["fileName": true]).map!(p => p["fileName"].get!string).array;
	}

	InputStream getFile(string post_name, string file_name)
	{
		auto f = m_postFiles.findOne!PostFile(["postName": post_name, "fileName": file_name]);
		if (f.isNull) return null;
		return new MemoryStream(f.contents);
	}

	void removeFile(string post_name, string file_name)
	{
		m_postFiles.remove(["postName": post_name, "fileName": file_name]);
	}

	private void upgradeComments(MongoDatabase db)
	{
		import diskuto.backend : StoredComment, CommentStatus;
		import diskuto.backends.mongodb : MongoStruct;

		auto comments = db["comments"];

		// Upgrade post contained comments to their collection
		foreach( p; m_posts.find(["comments": ["$exists": true]], ["comments": 1]) ){
			foreach( c; p["comments"] ){
				c["_id"] = BsonObjectID.generate();
				c["postId"] = p["_id"];
				comments.insert(c);
			}
			m_posts.update(["_id": p["_id"]], ["$unset": ["comments": 1]]);
		}

		// Upgrade old comments to Diskuto format
		foreach (c; comments.find(["postId": ["$exists": true]])) {
			auto oldc = OldComment.fromBson(c);
			StoredComment newc;
			newc.id = oldc.id.toString();
			newc.status = oldc.isPublic ? CommentStatus.active : CommentStatus.disabled;
			newc.topic = "vibelog-" ~ oldc.postId.toString();
			newc.author = "vibelog-...";
			newc.clientAddress = oldc.authorIP;
			newc.name = oldc.authorName;
			newc.email = oldc.authorMail;
			newc.website = oldc.authorHomepage;
			newc.text = oldc.content;
			newc.time = oldc.date;
			comments.update(["_id": c["_id"]], MongoStruct!StoredComment(newc));
		}
	}
}

struct PostFile {
	string postName;
	string fileName;
	ubyte[] contents;
}


final class OldComment {
	BsonObjectID id;
	BsonObjectID postId;
	bool isPublic;
	SysTime date;
	int answerTo;
	string authorName;
	string authorMail;
	string authorHomepage;
	string authorIP;
	string header;
	string content;

	static OldComment fromBson(Bson bson)
	{
		auto ret = new OldComment;
		ret.id = cast(BsonObjectID)bson["_id"];
		ret.postId = cast(BsonObjectID)bson["postId"];
		ret.isPublic = cast(bool)bson["isPublic"];
		ret.date = SysTime.fromISOExtString(cast(string)bson["date"]);
		ret.answerTo = cast(int)bson["answerTo"];
		ret.authorName = cast(string)bson["authorName"];
		ret.authorMail = cast(string)bson["authorMail"];
		ret.authorHomepage = cast(string)bson["authorHomepage"];
		ret.authorIP = bson["authorIP"].opt!string();
		ret.header = cast(string)bson["header"];
		ret.content = cast(string)bson["content"];
		return ret;
	}
}
