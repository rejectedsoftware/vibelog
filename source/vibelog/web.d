module vibelog.web;

import vibelog.dbcontroller;
import vibelog.rss;
import vibelog.settings;

import vibe.core.log;
import vibe.crypto.passwordhash;
import vibe.db.mongo.connection;
import vibe.http.auth.basic_auth;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.inet.url;
import vibe.templ.diet;
import vibe.textfilter.markdown;
import vibe.web.web;

import std.conv;
import std.datetime;
import std.exception;
import std.string;


deprecated("Use registerVibeLogWeb instead.")
void registerVibeLog(VibeLogSettings settings, URLRouter router)
{
	auto db = new DBController(settings);
	registerVibeLogWeb(router, db, settings);
}

void registerVibeLogWeb(URLRouter router, DBController controller, VibeLogSettings settings)
{
	auto sub_path = settings.siteUrl.path.toString();
	assert(sub_path.endsWith("/"), "Blog site URL must end with '/'.");

	if (sub_path.length > 1) router.get(sub_path[0 .. $-1], staticRedirect(sub_path));

	auto websettings = new WebInterfaceSettings;
	websettings.urlPrefix = sub_path;
	router.registerWebInterface(new VibeLogWeb(controller, settings));

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = sub_path;
	router.get(sub_path ~ "*", serveStaticFiles("public", fsettings));
}


class VibeLogWeb {
	private {
		DBController m_db;
		string m_subPath;
		VibeLogSettings m_settings;
		Config m_config;
	}

	this(DBController controller, VibeLogSettings settings)
	{
		m_settings = settings;

		m_db = controller;
		try m_config = m_db.getConfig(settings.configName, true);
		catch( Exception e ){
			logError("ERR: %s", e);
			throw e;
		}

		m_subPath = settings.siteUrl.path.toString();

		enforce(m_subPath.startsWith("/") && m_subPath.endsWith("/"), "All local URLs must start with and end with '/'.");
	}

	//
	// public pages
	//

	void get(int page = 1)
	{
		auto info = getPostListInfo(page);
		render!("vibelog.postlist.dt", info);
	}

	@path("posts/:postname")
	void getPost(string _postname)
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
		try info.post = m_db.getPost(_postname);
		catch(Exception e){ return; } // -> gives 404 error
		info.comments = m_db.getComments(info.post.id);
		info.recentPosts = getRecentPosts();
		
		render!("vibelog.post.dt", info);
	}

	@path("/posts/:postname/post_comment")
	void postComment(string name, string email, string homepage, string message, string _postname, HTTPServerRequest req)
	{
		auto post = m_db.getPost(_postname);
		enforce(post.commentsAllowed, "Posting comments is not allowed for this article.");

		auto c = new Comment;
		c.isPublic = true;
		c.date = Clock.currTime().toUTC();
		c.authorName = name;
		c.authorMail = email;
		c.authorHomepage = homepage;
		c.authorIP = req.peer;
		if (auto fip = "X-Forwarded-For" in req.headers) c.authorIP = *fip;
		if (c.authorHomepage == "http://") c.authorHomepage = "";
		c.content = message;
		m_db.addComment(post.id, c);

		redirect(m_subPath ~ "posts/" ~ post.name);
	}

	@path("feed/rss")
	protected void getRSSFeed(HTTPServerResponse res)
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

	void postMarkup(string message, HTTPServerResponse res)
	{
		auto post = new Post;
		post.content = message;
		res.writeBody(post.renderContentAsHtml(m_settings), "text/html");
	}

	@path("/sitemap.xml")
	void getSitemap(HTTPServerResponse res)
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

	@auth
	void getManage(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		render!("vibelog.admin.home.dt", users, loginUser);
	}

	//
	// Configs
	//

	@auth
	void getConfigs(AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		enforce(loginUser.isConfigAdmin());
		Config[] configs = m_db.getAllConfigs();
		render!("vibelog.admin.editconfiglist.dt", loginUser, configs);
	}

	@auth @path("configs/:configname/edit")
	void getConfigEdit(string _configname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_db.getConfig("global", true);
		enforce(loginUser.isConfigAdmin());
		Config config = m_db.getConfig(_configname);
		render!("vibelog.admin.editconfig.dt", loginUser, globalConfig, config);
	}

	@auth @path("configs/:configname/put")
	void postPutConfig(HTTPServerRequest req, string categories, string language, string copyrightString, string feedTitle, string feedLink, string feedDescription, string feedImageTitle, string feedImageUrl, string _configname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		enforce(loginUser.isConfigAdmin());
		Config cfg = m_db.getConfig(_configname);
		if( cfg.name == "global" )
			cfg.categories = categories.splitLines();
		else {
			cfg.categories = null;
			foreach( k, v; req.form ){
				if( k.startsWith("category_") )
					cfg.categories ~= k[9 .. $];
			}
		}
		cfg.language = language;
		cfg.copyrightString = copyrightString;
		cfg.feedTitle = feedTitle;
		cfg.feedLink = feedLink;
		cfg.feedDescription = feedDescription;
		cfg.feedImageTitle = feedImageTitle;
		cfg.feedImageUrl = feedImageUrl;
	
		m_db.setConfig(cfg);

		m_config = cfg;
		redirect(m_subPath ~ "configs/");
	}

	@auth @path("configs/:configname/delete")
	void postDeleteConfig(string _configname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		enforce(loginUser.isConfigAdmin());
		m_db.deleteConfig(_configname);
		redirect(m_subPath ~ "configs/");
	}


	//
	// Users
	//

	@auth
	void getUsers(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		render!("vibelog.admin.edituserlist.dt", loginUser, users);
	}

	@auth @path("users/:username/edit")
	void getUserEdit(string _username, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_db.getConfig("global", true);
		User user = m_db.getUser(_username);
		render!("vibelog.admin.edituser.dt", loginUser, globalConfig, user);
	}

	@auth @path("users/:username/put")
	void postPutUser(string id, string username, string password, string name, string email, string passwordConfirmation, string oldPassword, string _username, HTTPServerRequest req, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		User usr;
		if( id.length > 0 ){
			enforce(loginUser.isUserAdmin() || username == loginUser.username,
				"You can only change your own account.");
			usr = m_db.getUser(BsonObjectID.fromHexString(id));
			enforce(usr.username == username, "Cannot change the user name!");
		} else {
			enforce(loginUser.isUserAdmin(), "You are not allowed to add users.");
			usr = new User;
			usr.username = username;
			foreach( u; users )
				enforce(u.username != usr.username, "A user with the specified user name already exists!");
		}
		enforce(password == passwordConfirmation, "Passwords do not match!");

		usr.name = name;
		usr.email = email;

		if (password.length) {
			enforce(loginUser.isUserAdmin() || testSimplePasswordHash(oldPassword, usr.password), "Old password does not match.");
			usr.password = generateSimplePasswordHash(password);
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

		if( loginUser.isUserAdmin() ) redirect(m_subPath~"users/");
		else redirect(m_subPath~"manage");
	}

	@auth @path("users/:username/delete")
	void postDeleteUser(string _username, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		enforce(loginUser.isUserAdmin(), "You are not authorized to delete users!");
		enforce(loginUser.username != _username, "Cannot delete the own user account!");
		foreach( usr; users )
			if (usr.username == _username) {
				m_db.deleteUser(usr._id);
				redirect(m_subPath ~ "users/");
				return;
			}
		
		// fall-through (404)
	}

	@auth
	void postAddUser(string username, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		enforce(loginUser.isUserAdmin(), "You are not authorized to add users!");
		if (username !in users) {
			auto u = new User;
			u.username = username;
			m_db.addUser(u);
		}
		redirect(m_subPath ~ "users/" ~ username ~ "/edit");
	}

	//
	// Posts
	//

	@auth
	void getPosts(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
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
		render!("vibelog.admin.editpostslist.dt", users, loginUser, posts);
	}

	@auth
	void getMakePost(AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_db.getConfig("global", true);
		Post post;
		Comment[] comments;
		render!("vibelog.admin.editpost.dt", users, loginUser, globalConfig, post, comments);
	}

	alias postMakePost = postPutPost;
	/*@auth
	void postMakePost(AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		postPutPost(_users, loginUser);
	}*/

	@auth @path("posts/:postname/edit")
	void getEditPost(string _postname, AuthInfo _auth)
	{
		auto users = _auth.users;
		auto loginUser = _auth.loginUser;
		auto globalConfig = m_db.getConfig("global", true);
		auto post = m_db.getPost(_postname);
		auto comments = m_db.getComments(post.id, true);
		render!("vibelog.admin.editpost.dt", users, loginUser, globalConfig, post, comments);
	}

	@auth @path("posts/:postname/delete")
	void postDeletePost(string id, string _postname, AuthInfo _auth)
	{
		// FIXME: check permissons!
		auto bid = BsonObjectID.fromHexString(id);
		m_db.deletePost(bid);
		redirect(m_subPath ~ "posts/");
	}

	@auth @path("posts/:postname/set_comment_public")
	void postSetCommentPublic(string id, string _postname, bool public_, AuthInfo _auth)
	{
		// FIXME: check permissons!
		auto bid = BsonObjectID.fromHexString(id);
		m_db.setCommentPublic(bid, public_);
		redirect(m_subPath ~ "posts/"~_postname~"/edit");
	}

	@auth @path("posts/:postname/put")
	void postPutPost(string id, bool isPublic, bool commentsAllowed, string author,
		string date, string category, string slug, string headerImage, string header, string subHeader,
		string content, string _postname, AuthInfo _auth)
	{
		auto loginUser = _auth.loginUser;
		Post p;
		if( id.length > 0 ){
			p = m_db.getPost(BsonObjectID.fromHexString(id));
			enforce(_postname == p.name, "URL does not match the edited post!");
		} else {
			p = new Post;
			p.category = "default";
			p.date = Clock.currTime().toUTC();
		}
		enforce(loginUser.mayPostInCategory(category), "You are now allowed to post in the '"~category~"' category.");

		p.isPublic = isPublic;
		p.commentsAllowed = commentsAllowed;
		p.author = author;
		p.date = SysTime.fromSimpleString(date);
		p.category = category;
		p.slug = slug.length ? slug : makeSlugFromHeader(header);
		p.headerImage = headerImage;
		p.header = header;
		p.subHeader = subHeader;
		p.content = content;

		enforce(!m_db.hasPost(p.slug) || m_db.getPost(p.slug).id == p.id, "Post slug is already used for another article.");

		if( id.length > 0 ){
			m_db.modifyPost(p);
			_postname = p.name;
		} else {
			p.id = m_db.addPost(p);
		}
		redirect(m_subPath~"posts/");
	}

	protected PostListInfo getPostListInfo(int page = 0, int page_size = 0)
	{
		PostListInfo info;
		info.rootDir = m_subPath; // TODO: use relative path
		info.users = m_db.getAllUsers();
		info.settings = m_settings;
		info.pageCount = getPageCount(page_size);
		info.pageNumber = page;
		info.posts = getPostsForPage(info.pageNumber, page_size);
		foreach( p; info.posts ) info.commentCount ~= m_db.getCommentCount(p.id);
		info.recentPosts = getRecentPosts();
		return info;
	}	

	protected int getPageCount(int page_size = 0)
	{
		if (page_size <= 0) page_size = m_settings.postsPerPage;
		int cnt = m_db.countPostsForCategory(m_config.categories);
		return (cnt + page_size - 1) / page_size;
	}

	protected Post[] getPostsForPage(int n, int page_size = 0)
	{
		if (page_size <= 0) page_size = m_settings.postsPerPage;
		Post[] ret;
		try {
			size_t cnt = 0;
			m_db.getPublicPostsForCategory(m_config.categories, n*page_size, (size_t i, Post p){
				ret ~= p;
				if( ++cnt >= page_size )
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

	protected Post[] getRecentPosts()
	{
		Post[] ret;
		m_db.getPublicPostsForCategory(m_config.categories, 0, (i, p){
			if( i > 20 ) return false;
			ret ~= p;
			return true;
		});
		return ret;
	}

	protected string getShowPagePath(int page)
	{
		return m_subPath ~ "?page=" ~ to!string(page+1);
	}

	protected enum auth = before!performAuth("_auth");

	protected AuthInfo performAuth(HTTPServerRequest req, HTTPServerResponse res)
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
		return AuthInfo(*pusr, users);
	}

	mixin PrivateAccessProxy;
}

private struct AuthInfo {
	User loginUser;
	User[string] users;
}

private struct PostListInfo {
	string rootDir;
	User[string] users;
	VibeLogSettings settings;
	int pageNumber = 0;
	int pageCount;
	Post[] posts;
	long[] commentCount;
	Post[] recentPosts;
}

private struct VibelogHeadlineListConfig {
	bool showSummaries = true;
	size_t maxPosts = 10;
	size_t headerLevel = 2;
	bool headerLinks = true;
	bool footerLinks = false;
	bool dateFirst = true;
}
