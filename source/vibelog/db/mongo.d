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
		MongoCollection m_comments;
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
		m_comments = db["comments"];

		// Upgrade post contained comments to their collection
		foreach( p; m_posts.find(["comments": ["$exists": true]], ["comments": 1]) ){
			foreach( c; p.comments ){
				c["_id"] = BsonObjectID.generate();
				c["postId"] = p._id;
				m_comments.insert(c);
			}
			m_posts.update(["_id": p._id], ["$unset": ["comments": 1]]);
		}
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

	User getUser(string name)
	{
		auto userbson = m_users.findOne(["username": Bson(name)]);
		if( userbson.isNull() ){
			auto id = BsonObjectID.fromHexString(name);
			logDebug("%s <-> %s", name, id.toString());
			assert(id.toString() == name);
			userbson = m_users.findOne(["_id": Bson(id)]);
		}
		//auto userbson = m_users.findOne(Bson(["name" : Bson(name)]));
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
		foreach( idx, post; m_posts.find(query, null, QueryFlags.None, nskip) ){
			if( !del(idx, Post.fromBson(post)) )
				break;
		}
	}

	void getPublicPostsForCategory(string[] categories, int nskip, bool delegate(size_t idx, Post post) del)
	{
		auto cats = new Bson[categories.length];
		foreach( i; 0 .. categories.length ) cats[i] = Bson(categories[i]);
		Bson category = Bson(["$in" : Bson(cats)]);
		Bson[string] query = ["query" : Bson(["category" : category, "isPublic": Bson(true)]), "orderby" : Bson(["date" : Bson(-1)])];
		foreach( idx, post; m_posts.find(query, null, QueryFlags.None, nskip) ){
			if( !del(idx, Post.fromBson(post)) )
				break;
		}
	}

	void getAllPosts(int nskip, bool delegate(size_t idx, Post post) del)
	{
		Bson[string] query;
		Bson[string] extquery = ["query" : Bson(query), "orderby" : Bson(["date" : Bson(-1)])];
		foreach( idx, post; m_posts.find(extquery, null, QueryFlags.None, nskip) ){
			if( !del(idx, Post.fromBson(post)) )
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
		return m_postFiles.find(["postName": post_name], ["fileName": true]).map!(p => p.fileName.get!string).array;
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

	Comment[] getComments(BsonObjectID post_id, bool allow_inactive = false)
	{
		Comment[] ret;
		foreach( c; m_comments.find(["postId": post_id]) )
			if( allow_inactive || c.isPublic.get!bool )
				ret ~= Comment.fromBson(c);
		return ret;
	}

	long getCommentCount(BsonObjectID post_id)
	{
		return m_comments.count(["postId": Bson(post_id), "isPublic": Bson(true)]);
	}


	void addComment(BsonObjectID post_id, Comment comment)
	{
		Bson cmtbson = comment.toBson();
		comment.id = BsonObjectID.generate();
		comment.postId = post_id;
		m_comments.insert(comment.toBson());

		try {
			auto p = m_posts.findOne(["_id": post_id]);
			auto u = m_users.findOne(["username": p.author]);
			auto msg = new MemoryOutputStream;

			auto post = Post.fromBson(p);

			msg.compileDietFile!("mail.new_comment.dt", comment, post);

			auto mail = new Mail;
			mail.headers["From"] = comment.authorName ~ " <" ~ comment.authorMail ~ ">";
			mail.headers["To"] = u.email.get!string;
			mail.headers["Subject"] = "[VibeLog] New comment";
			mail.headers["Content-Type"] = "text/html";
			mail.bodyText = cast(string)msg.data();

			auto settings = new SMTPClientSettings;
			//settings.host = m_settings.mailServer;
			sendMail(settings, mail);
		} catch(Exception e){
			logWarn("Failed to send comment mail: %s", e.msg);
		}
	}

	void setCommentPublic(BsonObjectID comment_id, bool is_public)
	{
		m_comments.update(["_id": comment_id], ["$set": ["isPublic": is_public]]);
	}

	void deleteNonPublicComments(BsonObjectID post_id)
	{
		m_posts.remove(["postId": Bson(post_id), "isPublic": Bson(false)]);
	}
}

struct PostFile {
	string postName;
	string fileName;
	ubyte[] contents;
}
