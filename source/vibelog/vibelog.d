module vibelog.vibelog;

import vibelog.dbcontroller;
import vibelog.rss;

import vibe.db.mongo.db;
import vibe.http.auth.basic_auth;
import vibe.http.router;
import vibe.templ.diet;
import vibe.core.log;

import std.conv;
import std.datetime;
import std.exception;
import std.string;

class VibeLogSettings {
	string databaseHost = "localhost";
	ushort databasePort = MongoConnection.defaultPort;
	string databaseName = "vibelog";
	string configName = "default";
	int postsPerPage = 4;
	string basePath = "/";
	string function(string)[] textFilters;
}

void registerVibeLog(VibeLogSettings settings, UrlRouter router)
{
	new VibeLog(settings, router);
}

class VibeLog {
	private {
		DBController m_db;
		string m_subPath;
		VibeLogSettings m_settings;
		Config m_config;
	}

	this(VibeLogSettings settings, UrlRouter router)
	{
		m_settings = settings;
		m_db = new DBController(settings.databaseHost, settings.databasePort, settings.databaseName);
		try m_config = m_db.getConfig(settings.configName, true);
		catch( Exception e ){
			logError("ERR: %s", e);
			throw e;
		}
		
		enforce(settings.basePath.startsWith("/"), "All local URLs must start with '/'.");
		if( !settings.basePath.endsWith("/") ) settings.basePath ~= "/";

		m_subPath = settings.basePath;

		//
		// public pages
		//
		if( m_subPath.length > 1 ) router.get(m_subPath[0 .. $-1], staticRedirect(m_subPath));
		router.get(m_subPath, &showPostList);
		router.get(m_subPath ~ "posts/:postname", &showPost);
		router.post(m_subPath ~ "posts/:postname/post_comment", &postComment);
		router.get(m_subPath ~ "feed/rss", &rssFeed);

		//
		// restricted pages
		//
		router.get(m_subPath ~ "manage",                      auth(&showAdminPanel));

		router.get(m_subPath ~ "configs/",                    auth(&showConfigList));
		router.get(m_subPath ~ "configs/:configname/edit",    auth(&showConfigEdit));
		router.post(m_subPath ~ "configs/:configname/put",    auth(&putConfig));
		router.post(m_subPath ~ "configs/:configname/delete", auth(&deleteConfig));

		router.get(m_subPath ~ "users/",                      auth(&showUserList));
		router.get(m_subPath ~ "users/:username/edit",        auth(&showUserEdit));
		router.post(m_subPath ~ "users/:username/put",        auth(&putUser));
		router.post(m_subPath ~ "users/:username/delete",     auth(&deleteUser));
		router.post(m_subPath ~ "add_user",                   auth(&addUser));

		router.get(m_subPath ~ "posts/",                      auth(&showEditPosts));
		router.get(m_subPath ~ "posts/:postname/edit",        auth(&showEditPost));
		router.post(m_subPath ~ "posts/:postname/put",        auth(&putPost));
		router.post(m_subPath ~ "posts/:postname/delete",     auth(&deletePost));
		router.get(m_subPath ~ "make_post",                   auth(&showMakePost));
		router.post(m_subPath ~ "make_post",                  auth(&putPost));
	}

	int getPageCount()
	{
		int cnt = m_db.countPostsForCategory(m_config.categories);
		return (cnt + m_settings.postsPerPage - 1) / m_settings.postsPerPage;
	}

	Post[] getPostsForPage(int n)
	{
		Post[] ret;
		try {
			size_t cnt = 0;
			m_db.getPublicPostsForCategory(m_config.categories, n*m_settings.postsPerPage, (size_t i, Post p){
				ret ~= p;
				if( ++cnt >= m_settings.postsPerPage )
					return false;
				return true;
			});
		} catch( Exception e ){
			auto p = new Post;
			p.header = "ERROR";
			p.subHeader = e.msg;
			ret ~= p;
		}
		return ret;
	}

	string getShowPagePath(int page)
	{
		return m_subPath ~ "?page=" ~ to!string(page+1);
	}

	//
	// public pages
	//

	protected void showPostList(HttpServerRequest req, HttpServerResponse res)
	{
		User[string] users = m_db.getAllUsers();
		int pageNumber = 0;
		auto pageCount = getPageCount();
		if( auto pp = "page" in req.query ) pageNumber = to!int(*pp)-1;
		else pageNumber = 0;
		auto posts = getPostsForPage(pageNumber);
		//parseJadeFile!("vibelog.postlist.dt", req, posts, pageNumber, pageCount)(res.bodyWriter);
		res.renderCompat!("vibelog.postlist.dt",
			HttpServerRequest, "req",
			User[string], "users",
			Post[], "posts",
			string function(string)[], "textFilters",
			int, "pageNumber",
			int, "pageCount")
			(Variant(req), Variant(users), Variant(posts), Variant(m_settings.textFilters), Variant(pageNumber), Variant(pageCount));
	}

	protected void showPost(HttpServerRequest req, HttpServerResponse res)
	{
		User[string] users = m_db.getAllUsers();
		Post post;
		try post = m_db.getPost(req.params["postname"]);
		catch(Exception e){ return; } // -> gives 404 error
		//res.render!("vibelog.post.dt", req, users, post, textFilters);
		res.renderCompat!("vibelog.post.dt",
			HttpServerRequest, "req",
			User[string], "users",
			Post, "post",
			string function(string)[], "textFilters")
			(Variant(req), Variant(users), Variant(post), Variant(m_settings.textFilters));
	}

	protected void postComment(HttpServerRequest req, HttpServerResponse res)
	{
		auto post = m_db.getPost(req.params["postname"]);
		enforce(post.commentsAllowed, "Posting comments is not allowed for this article.");

		auto c = new Comment;
		c.isPublic = true;
		c.date = Clock.currTime().toUTC();
		c.authorName = req.form["name"];
		c.authorMail = req.form["email"];
		c.authorHomepage = req.form["homepage"];
		if( c.authorHomepage == "http://" ) c.authorHomepage = "";
		c.content = req.form["message"];
		m_db.addComment(post.id, c);

		res.redirect(m_subPath ~ "posts/"~post.name);
	}

	protected void rssFeed(HttpServerRequest req, HttpServerResponse res)
	{
		auto ch = new RssChannel;
		ch.title = m_config.feedTitle;
		ch.link = m_config.feedLink;
		ch.description = m_config.feedDescription;
		ch.copyright = m_config.copyrightString;
		ch.pubDate = Clock.currTime(UTC());
		ch.imageTitle = m_config.feedImageTitle;
		ch.imageUrl = m_config.feedImageUrl;
		ch.imageLink = m_config.feedLink;

		m_db.getPostsForCategory(m_config.categories, 0, (size_t i, Post p){
				if( !p.isPublic ) return true;
				auto itm = new RssEntry;
				itm.title = p.header;
				itm.description = p.subHeader;
				itm.link = "http://vibed.org/blog/posts/"~p.name;
				itm.author = p.author;
				itm.guid = "xxyyzz";
				itm.pubDate = p.date;
				ch.entries ~= itm;
				return i < 10;
			});

		auto feed = new RssFeed;
		feed.channels ~= ch;

		res.headers["Content-Type"] = "application/rss+xml";
		feed.render(res.bodyWriter);
	}

	protected HttpServerRequestDelegate auth(void delegate(HttpServerRequest, HttpServerResponse, User[string], User) del)
	{
		return (HttpServerRequest req, HttpServerResponse res)
		{
			User[string] users = m_db.getAllUsers();
			bool testauth(string user, string password)
			{
				auto pu = user in users;
				if( pu is null ) return false;
				return testPassword(password, pu.password);
			}
			string username = performBasicAuth(req, res, "VibeLog admin area", &testauth);
			auto pusr = username in users;
			assert(pusr, "Authorized with unknown username !?");
			del(req, res, users, *pusr);
		};
	}

	protected void showAdminPanel(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		res.renderCompat!("vibelog.admin.dt",
			HttpServerRequest, "req",
			User[string], "users",
			User, "loginUser")
			(Variant(req), Variant(users), Variant(loginUser));
	}

	//
	// Configs
	//

	protected void showConfigList(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isConfigAdmin());
		Config[] configs = m_db.getAllConfigs();
		res.renderCompat!("vibelog.editconfiglist.dt",
			HttpServerRequest, "req",
			User, "loginUser",
			Config[], "configs")
			(Variant(req), Variant(loginUser), Variant(configs));
	}

	protected void showConfigEdit(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		enforce(loginUser.isConfigAdmin());
		Config config = m_db.getConfig(req.params["configname"]);
		res.renderCompat!("vibelog.editconfig.dt",
			HttpServerRequest, "req",
			User, "loginUser",
			Config, "globalConfig",
			Config, "config")
			(Variant(req), Variant(loginUser), Variant(globalConfig), Variant(config));
	}

	protected void putConfig(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isConfigAdmin());
		Config cfg = m_db.getConfig(req.params["configname"]);
		if( cfg.name == "global" )
			cfg.categories = req.form["categories"].splitLines();
		else {
			cfg.categories = null;
			foreach( k, v; req.form ){
				if( k.startsWith("category_") )
					cfg.categories ~= k[9 .. $];
			}
		}
		cfg.language = req.form["language"];
		cfg.copyrightString = req.form["copyrightString"];
		cfg.feedTitle = req.form["feedTitle"];
		cfg.feedLink = req.form["feedLink"];
		cfg.feedDescription = req.form["feedDescription"];
		cfg.feedImageTitle = req.form["feedImageTitle"];
		cfg.feedImageUrl = req.form["feedImageUrl"];
	
		m_db.setConfig(cfg);

		m_config = cfg;
		res.redirect(m_subPath ~ "configs/");
	}

	protected void deleteConfig(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isConfigAdmin());
		m_db.deleteConfig(req.params["configname"]);
		res.redirect(m_subPath ~ "configs/");
	}


	//
	// Users
	//

	protected void showUserList(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		res.renderCompat!("vibelog.edituserlist.dt",
			HttpServerRequest, "req",
			User, "loginUser",
			User[string], "users")
			(Variant(req), Variant(loginUser), Variant(users));
	}

	protected void showUserEdit(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		User user = m_db.getUser(req.params["username"]);
		res.renderCompat!("vibelog.edituser.dt",
			HttpServerRequest, "req",
			User, "loginUser",
			Config, "globalConfig",
			User, "user")
			(Variant(req), Variant(loginUser), Variant(globalConfig), Variant(user));
	}

	protected void putUser(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto id = req.form["id"];
		User usr;
		if( id.length > 0 ){
			enforce(loginUser.isUserAdmin() || req.form["username"] == loginUser.username,
				"You can only change your own account.");
			usr = m_db.getUser(BsonObjectID.fromHexString(id));
			enforce(usr.username == req.form["username"], "Cannot change the user name!");
		} else {
			enforce(loginUser.isUserAdmin(), "You are not allowed to add users.");
			usr = new User;
			usr.username = req.form["username"];
			foreach( u; users )
				enforce(u.username != usr.username, "A user with the specified user name already exists!");
		}
		enforce(req.form["password"] == req.form["passwordConfirmation"], "Passwords do not match!");

		usr.name = req.form["name"];
		usr.email = req.form["email"];

		if( req.form["password"].length || req.form["passwordConfirmation"].length ){
			enforce(loginUser.isUserAdmin() || testPassword(req.form["oldPassword"], usr.password), "Old password does not match.");
			usr.password = generatePasswordHash(req.form["password"]);
		}

		if( loginUser.isUserAdmin() ){
			usr.groups = null;
			foreach( k, v; req.form ){
				if( k.startsWith("group_") )
					usr.groups ~= k[6 .. $];
			}

			usr.allowedCategories = null;
			foreach( k, v; req.form ){
				if( k.startsWith("category_") )
					usr.allowedCategories ~= k[9 .. $];
			}
		}

		if( id.length > 0 ){
			m_db.modifyUser(usr);
		} else {
			usr._id = m_db.addUser(usr);
		}

		if( loginUser.isUserAdmin() ) res.redirect(m_subPath~"users/");
		else res.redirect(m_subPath~"manage");
	}

	protected void deleteUser(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isUserAdmin(), "You are not authorized to delete users!");
		enforce(loginUser.username != req.form["username"], "Cannot delete the own user account!");
		foreach( usr; users )
			if( usr.username == req.form["username"] ){
				m_db.deleteUser(usr._id);
				res.redirect(m_subPath ~ "edit_posts");
				return;
			}
		enforce(false, "Unknown user name.");
	}

	protected void addUser(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isUserAdmin(), "You are not authorized to add users!");
		string uname = req.form["username"];
		if( uname !in users ){
			auto u = new User;
			u.username = uname;
			m_db.addUser(u);
		}
		res.redirect(m_subPath ~ "users/" ~ uname ~ "/edit");
	}

	//
	// Posts
	//

	protected void showEditPosts(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		Post[] posts;
		m_db.getAllPosts(0, (size_t idx, Post post){
			if( loginUser.isPostAdmin() || post.author == loginUser.username
				|| loginUser.mayPostInCategory(post.category) )
			{
				posts ~= post;
			}
			return true;
		});
		logInfo("Showing %d posts.", posts.length);
		//parseJadeFile!("vibelog.postlist.dt", req, posts, pageNumber, pageCount)(res.bodyWriter);
		res.renderCompat!("vibelog.editpostslist.dt",
			HttpServerRequest, "req",
			User[string], "users",
			User, "loginUser",
			Post[], "posts")
			(Variant(req), Variant(users), Variant(loginUser), Variant(posts));
	}

	protected void showMakePost(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		Post post;
		res.renderCompat!("vibelog.editpost.dt",
			HttpServerRequest, "req",
			User[string], "users",
			User, "loginUser",
			Config, "globalConfig",
			Post, "post")
			(Variant(req), Variant(users), Variant(loginUser), Variant(globalConfig), Variant(post));
	}

	protected void showEditPost(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		auto post = m_db.getPost(req.params["postname"]);
		res.renderCompat!("vibelog.editpost.dt",
			HttpServerRequest, "req",
			User[string], "users",
			User, "loginUser",
			Config, "globalConfig",
			Post, "post")
			(Variant(req), Variant(users), Variant(loginUser), Variant(globalConfig), Variant(post));
	}

	protected void deletePost(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto id = BsonObjectID.fromHexString(req.form["id"]);
		m_db.deletePost(id);
		res.redirect(m_subPath ~ "posts/");
	}

	protected void putPost(HttpServerRequest req, HttpServerResponse res, User[string] users, User loginUser)
	{
		auto id = req.form["id"];
		Post p;
		if( id.length > 0 ){
			p = m_db.getPost(BsonObjectID.fromHexString(id));
			enforce(req.params["postname"] == p.name, "URL does not match the edited post!");
		} else {
			p = new Post;
			p.category = "default";
			p.date = Clock.currTime().toUTC();
		}
		enforce(loginUser.mayPostInCategory(req.form["category"]), "You are now allowed to post in the '"~req.form["category"]~"' category.");

		p.isPublic = ("isPublic" in req.form) !is null;
		p.commentsAllowed = ("commentsAllowed" in req.form) !is null;
		p.author = req.form["author"];
		p.category = req.form["category"];
		p.slug = req.form["slug"].length ? req.form["slug"] : makeSlugFromHeader(req.form["header"]);
		p.headerImage = req.form["headerImage"];
		p.header = req.form["header"];
		p.subHeader = req.form["subHeader"];
		p.content = req.form["content"];

		enforce(!m_db.hasPost(p.slug) || m_db.getPost(p.slug).id == p.id);

		if( id.length > 0 ){
			m_db.modifyPost(p);
			req.params["postname"] = p.name;
		} else {
			p.id = m_db.addPost(p);
		}
		res.redirect(m_subPath~"posts/");
	}
}
