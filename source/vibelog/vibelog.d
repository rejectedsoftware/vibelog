module vibelog.vibelog;

import vibelog.dbcontroller;
import vibelog.rss;

import vibe.core.log;
import vibe.crypto.passwordhash;
import vibe.db.mongo.connection;
import vibe.http.auth.basic_auth;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.inet.url;
import vibe.templ.diet;
import vibe.textfilter.markdown;

import std.conv;
import std.datetime;
import std.exception;
import std.string;

enum RECENT_COMMENT_LIMIT = 3;

class VibeLogSettings {
	string databaseHost = "localhost";
	ushort databasePort = MongoConnection.defaultPort;
	string databaseName = "vibelog";
	string configName = "global";
	int postsPerPage = 4;
	URL siteUrl = URL.parse("http://localhost:8080/");
	string function(string)[] textFilters;
	MarkdownSettings markdownSettings;

	this()
	{
		markdownSettings = new MarkdownSettings;
		markdownSettings.flags = MarkdownFlags.backtickCodeBlocks;
	}
}

void registerVibeLog(VibeLogSettings settings, URLRouter router)
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

	this(VibeLogSettings settings)
	{
		m_settings = settings;
		m_db = new DBController(settings.databaseHost, settings.databasePort, settings.databaseName);
		try m_config = m_db.getConfig(settings.configName, true);
		catch( Exception e ){
			logError("ERR: %s", e);
			throw e;
		}

		m_subPath = settings.siteUrl.path.toString();

		enforce(m_subPath.startsWith("/") && m_subPath.endsWith("/"), "All local URLs must start with and end with '/'.");
	}

	this(VibeLogSettings settings, URLRouter router)
	{
		this(settings);
		register(router);
	}

	void register(URLRouter router)
	{
		//
		// public pages
		//
		if( m_subPath.length > 1 ) router.get(m_subPath[0 .. $-1], staticRedirect(m_subPath));
		router.get(m_subPath, &showPostList);
		router.get(m_subPath ~ "posts/:postname", &showPost);
		router.post(m_subPath ~ "posts/:postname/post_comment", &postComment);
		router.get(m_subPath ~ "feed/rss", &rssFeed);
		router.post(m_subPath ~ "markup", &markup);

		router.get(m_subPath ~ "sitemap.xml", &sitemap);

		auto fsettings = new HTTPFileServerSettings;
		fsettings.serverPathPrefix = m_subPath;
		router.get(m_subPath ~ "*", serveStaticFiles("public", fsettings));

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
		router.post(m_subPath ~ "posts/:postname/set_comment_public", auth(&setCommentPublic));
		router.get(m_subPath ~ "make_post",                   auth(&showMakePost));
		router.post(m_subPath ~ "make_post",                  auth(&putPost));
	}


	PostListInfo getPostListInfo(HTTPServerRequest req)
	{
		PostListInfo info;
		info.rootDir = m_subPath; // TODO: use relative path
		info.users = m_db.getAllUsers();
		info.settings = m_settings;
		info.pageCount = getPageCount();
		if (auto pp = "page" in req.query) info.pageNumber = to!int(*pp)-1;
		info.posts = getPostsForPage(info.pageNumber);
		foreach( p; info.posts ) info.commentCount ~= m_db.getCommentCount(p.id);
		info.recentPosts = getRecentPosts();
		return info;
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

	Post[] getRecentPosts()
	{
		Post[] ret;
		m_db.getPublicPostsForCategory(m_config.categories, 0, (i, p){
			if( i > 20 ) return false;
			ret ~= p;
			return true;
		});
		return ret;
	}

	string getShowPagePath(int page)
	{
		return m_subPath ~ "?page=" ~ to!string(page+1);
	}

	//
	// public pages
	//

	protected void showPostList(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto info = getPostListInfo(req);

		res.render!("vibelog.postlist.dt", req, info);
	}

	protected void showPost(HTTPServerRequest req, HTTPServerResponse res)
	{
		struct ShowPostInfo {
			string rootDir;
			User[string] users;
			VibeLogSettings settings;
			Post post;
			Comment[] comments;
			Post[] recentPosts;
		}

		ShowPostInfo info;
		info.rootDir = m_subPath; // TODO: use relative path
		info.users = m_db.getAllUsers();
		info.settings = m_settings;
		try info.post = m_db.getPost(req.params["postname"]);
		catch(Exception e){ return; } // -> gives 404 error
		info.comments = m_db.getComments(info.post.id);
		info.recentPosts = getRecentPosts();
		
		res.render!("vibelog.post.dt", req, info);
	}

	protected void postComment(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto post = m_db.getPost(req.params["postname"]);
		enforce(post.commentsAllowed, "Posting comments is not allowed for this article.");

		auto c = new Comment;
		c.isPublic = true;
		c.date = Clock.currTime().toUTC();
		c.authorName = req.form["name"];
		c.authorMail = req.form["email"];
		c.authorHomepage = req.form["homepage"];
		c.authorIP = req.peer;
		if( auto fip = "X-Forwarded-For" in req.headers ) c.authorIP = *fip;
		if( c.authorHomepage == "http://" ) c.authorHomepage = "";
		c.content = req.form["message"];
		m_db.addComment(post.id, c);

		res.redirect(m_subPath ~ "posts/"~post.name);
	}

	protected void rssFeed(HTTPServerRequest req, HTTPServerResponse res)
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
				itm.link = m_settings.siteUrl.toString() ~ "posts/" ~ p.name;
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

	protected void markup(HTTPServerRequest req, HTTPServerResponse res)
	{
		auto post = new Post;
		post.content = req.form["message"];
		res.writeBody(post.renderContentAsHtml(m_settings), "text/html");
	}

	protected void sitemap(HTTPServerRequest req, HTTPServerResponse res)
	{
		res.contentType = "application/xml";
		res.bodyWriter.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		res.bodyWriter.write("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
		void writeEntry(string[] parts...){
			res.bodyWriter.write("<url><loc>");
			res.bodyWriter.write(m_settings.siteUrl.toString());
			foreach( p; parts )
				res.bodyWriter.write(p);
			res.bodyWriter.write("</loc></url>\n");
		}

		// home page
		writeEntry();

		m_db.getPostsForCategory(m_config.categories, 0, (size_t i, Post p){
				if( p.isPublic ) writeEntry("posts/", p.name);
				return true;
			});
		
		res.bodyWriter.write("</urlset>\n");
		res.bodyWriter.flush();
	}

	protected HTTPServerRequestDelegate auth(void delegate(HTTPServerRequest, HTTPServerResponse, User[string], User) del)
	{
		return (HTTPServerRequest req, HTTPServerResponse res)
		{
			User[string] users = m_db.getAllUsers();
			bool testauth(string user, string password)
			{
				auto pu = user in users;
				if( pu is null ) return false;
				return testSimplePasswordHash(pu.password, password);
			}
			string username = performBasicAuth(req, res, "VibeLog admin area", &testauth);
			auto pusr = username in users;
			assert(pusr, "Authorized with unknown username !?");
			del(req, res, users, *pusr);
		};
	}

	protected void showAdminPanel(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
        struct DashboardInfo {
            int posts;
            int comments;
            int users;
            Comment[] recentComments;
        }

        DashboardInfo info;
        info.posts = m_db.getPostCount();
        info.comments = m_db.getCommentCount();
        info.users = m_db.getUserCount();
        info.recentComments = m_db.getRecentComments(RECENT_COMMENT_LIMIT); 

		res.render!("vibelog.admin.home.dt", req, users, loginUser, info);
	}

	//
	// Configs
	//

	protected void showConfigList(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isConfigAdmin());
		Config[] configs = m_db.getAllConfigs();
		res.render!("vibelog.admin.editconfiglist.dt", req, loginUser, configs);
	}

	protected void showConfigEdit(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		enforce(loginUser.isConfigAdmin());
		Config config = m_db.getConfig(req.params["configname"]);
		res.render!("vibelog.admin.editconfig.dt", req, loginUser, globalConfig, config);
	}

	protected void putConfig(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
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

	protected void deleteConfig(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isConfigAdmin());
		m_db.deleteConfig(req.params["configname"]);
		res.redirect(m_subPath ~ "configs/");
	}


	//
	// Users
	//

	protected void showUserList(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		res.render!("vibelog.admin.edituserlist.dt", req, loginUser, users);
	}

	protected void showUserEdit(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		User user = m_db.getUser(req.params["username"]);
		res.render!("vibelog.admin.edituser.dt", req, loginUser, globalConfig, user);
	}

	protected void putUser(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
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
			enforce(loginUser.isUserAdmin() || testSimplePasswordHash(req.form["oldPassword"], usr.password), "Old password does not match.");
			usr.password = generateSimplePasswordHash(req.form["password"]);
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

	protected void deleteUser(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		enforce(loginUser.isUserAdmin(), "You are not authorized to delete users!");
		enforce(loginUser.username != req.params["username"], "Cannot delete the own user account!");
		foreach( usr; users )
			if( usr.username == req.params["username"] ){
				m_db.deleteUser(usr._id);
				res.redirect(m_subPath ~ "users/");
				return;
			}
		enforce(false, "Unknown user name.");
	}

	protected void addUser(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
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

	protected void showEditPosts(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
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
		res.render!("vibelog.admin.editpostslist.dt", req, users, loginUser, posts);
	}

	protected void showMakePost(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		Post post;
		Comment[] comments;
		res.render!("vibelog.admin.editpost.dt", req, users, loginUser, globalConfig, post, comments);
	}

	protected void showEditPost(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto globalConfig = m_db.getConfig("global", true);
		auto post = m_db.getPost(req.params["postname"]);
		auto comments = m_db.getComments(post.id, true);
		res.render!("vibelog.admin.editpost.dt", req, users, loginUser, globalConfig, post, comments);
	}

	protected void deletePost(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto id = BsonObjectID.fromHexString(req.form["id"]);
		m_db.deletePost(id);
		res.redirect(m_subPath ~ "posts/");
	}

	protected void setCommentPublic(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
	{
		auto id = BsonObjectID.fromHexString(req.form["id"]);
		m_db.setCommentPublic(id, to!int(req.form["public"]) != 0);
		res.redirect(m_subPath ~ "posts/"~req.params["postname"]~"/edit");
	}

	protected void putPost(HTTPServerRequest req, HTTPServerResponse res, User[string] users, User loginUser)
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
		p.date = SysTime.fromSimpleString(req.form["date"]);
		p.category = req.form["category"];
		p.slug = req.form["slug"].length ? req.form["slug"] : makeSlugFromHeader(req.form["header"]);
		p.headerImage = req.form["headerImage"];
		p.header = req.form["header"];
		p.subHeader = req.form["subHeader"];
		p.content = req.form["content"];

		enforce(!m_db.hasPost(p.slug) || m_db.getPost(p.slug).id == p.id, "Post slug is already used for another article.");

		if( id.length > 0 ){
			m_db.modifyPost(p);
			req.params["postname"] = p.name;
		} else {
			p.id = m_db.addPost(p);
		}
		res.redirect(m_subPath~"posts/");
	}
}

struct PostListInfo {
	string rootDir;
	User[string] users;
	VibeLogSettings settings;
	int pageNumber = 0;
	int pageCount;
	Post[] posts;
	long[] commentCount;
	Post[] recentPosts;
}

struct VibelogHeadlineListConfig {
	bool showSummaries = true;
	size_t maxPosts = 10;
	size_t headerLevel = 2;
	bool headerLinks = true;
	bool footerLinks = false;
	bool dateFirst = true;
}
