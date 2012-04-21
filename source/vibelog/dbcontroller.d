module vibelog.dbcontroller;

public import vibelog.config;
public import vibelog.post;
public import vibelog.user;

import vibe.db.mongo.mongo;
import vibe.core.log;
import vibe.data.bson;

import std.exception;


class DBController {
	private {
		MongoDB m_db;
		string m_dbname;
		MongoCollection m_configs;
		MongoCollection m_users;
		MongoCollection m_posts;
	}

	this(string host, ushort port, string dbname)
	{
		m_db = connectMongoDB(host, port);
		m_dbname = dbname;
		m_configs = m_db[m_dbname~"."~"configs"];
		m_users = m_db[m_dbname~"."~"users"];
		m_posts = m_db[m_dbname~"."~"posts"];
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
			initial_admin.password = generatePasswordHash("admin");
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
		Bson[string] query = ["query" : Bson(["category" : category]), "orderby" : Bson(["_id" : Bson(-1)])];
		foreach( idx, post; m_posts.find(query, null, QueryFlags.None, nskip) ){
			if( !del(idx, Post.fromBson(post)) )
				break;
		}
	}

	void getAllPosts(int nskip, bool delegate(size_t idx, Post post) del)
	{
		Bson[string] query;
		Bson[string] extquery = ["query" : Bson(query), "orderby" : Bson(["_id" : Bson(-1)])];
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


	void addComment(BsonObjectID post, Comment comment)
	{
		Bson cmtbson = comment.toBson();
		m_posts.update(["_id": Bson(post)], Bson(["$push" : Bson(["comments" : cmtbson])]));
	}
}
