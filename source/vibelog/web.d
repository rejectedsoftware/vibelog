module vibelog.web;

public import vibelog.controller;

import vibelog.config;
import vibelog.post;
import vibelog.rss;
import vibelog.settings;
import vibelog.user;

import diskuto.web;
import vibe.core.log;
import vibe.db.mongo.connection;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.inet.url;
import vibe.textfilter.markdown;
import vibe.web.web;

import std.conv;
import std.datetime;
import std.exception;
import std.string;


void registerVibeLogWeb(URLRouter router, VibeLogController controller)
{
	import vibelog.internal.diskuto;

	string sub_path = controller.settings.rootDir;
	assert(sub_path.endsWith("/"), "Blog site URL must end with '/'.");

	if (sub_path.length > 1) router.get(sub_path[0 .. $-1], staticRedirect(sub_path));

	auto diskuto = router.registerDiskuto(controller);

	auto web = new VibeLogWeb(controller, diskuto);

	auto websettings = new WebInterfaceSettings;
	websettings.urlPrefix = sub_path;
	router.registerWebInterface(web, websettings);

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = sub_path;
	router.get(sub_path ~ "*", serveStaticFiles("public", fsettings));
}


/// private
/*private*/ final class VibeLogWeb {
	private {
		VibeLogController m_ctrl;
		VibeLogSettings m_settings;
		DiskutoWeb m_diskuto;
		SessionVar!(string, "vibelog.loggedInUser") m_loggedInUser;
	}

	this(VibeLogController controller, DiskutoWeb diskuto)
	{
		m_settings = controller.settings;
		m_ctrl = controller;
		m_diskuto = diskuto;

		enforce(m_settings.rootDir.startsWith("/") && m_settings.rootDir.endsWith("/"), "All local URLs must start with and end with '/'.");
	}

	//
	// public pages
	//

	void get(int page = 1, string _error = null)
	{
		auto info = PageInfo(m_settings, m_ctrl.getPostListInfo(page - 1));
		info.refPath = m_settings.rootDir;
		info.loginError = _error;
		render!("vibelog.postlist.dt", info);
	}

	@errorDisplay!getPost
	@path("posts/:postname")
	void getPost(string _postname, string _error)
	{
		m_diskuto.setupRequest();

		auto info = PostInfo(m_settings);
		info.users = m_ctrl.db.getAllUsers();
		try info.post = m_ctrl.db.getPost(_postname);
		catch(Exception e){ return; } // -> gives 404 error
		if (m_settings.enableBackButton)
			info.postPage = m_ctrl.getPostPage(info.post.id);
		info.recentPosts = m_ctrl.getRecentPosts();
		info.refPath = m_settings.rootDir~"posts/"~_postname;
		info.error = _error;
		info.diskuto = m_diskuto;

		render!("vibelog.post.dt", info);
	}

	@path("posts/:postname/:filename")
	void getPostFile(string _postname, string _filename, HTTPServerResponse res)
	{
		import vibe.core.stream : pipe;
		import vibe.inet.mimetypes : getMimeTypeForFile;

		auto f = m_ctrl.db.getFile(_postname, _filename);
		if (f) {
			res.contentType = getMimeTypeForFile(_filename);
			f.pipe(res.bodyWriter);
		}
	}

	@path("feed/rss")
	void getRSSFeed(HTTPServerResponse res)
	{
		auto cfg = m_ctrl.config;

		auto ch = new RssChannel;
		ch.title = cfg.feedTitle;
		ch.link = cfg.feedLink;
		ch.description = cfg.feedDescription;
		ch.copyright = cfg.copyrightString;
		ch.pubDate = Clock.currTime(UTC());
		ch.imageTitle = cfg.feedImageTitle;
		ch.imageUrl = cfg.feedImageUrl;
		ch.imageLink = cfg.feedLink;

		m_ctrl.db.getPostsForCategory(cfg.categories, 0, (size_t i, Post p){
				if( !p.isPublic ) return true;

				auto usr = m_ctrl.db.getUserByName(p.author);

				auto itm = new RssEntry;
				itm.title = p.header;
				itm.description = p.subHeader;
				itm.link = m_settings.siteURL.toString() ~ "posts/" ~ p.name;
				itm.author = usr ? usr.email : "unknown@unknown.unknown";
				itm.guid = p.id.toString;
				itm.pubDate = p.date;
				ch.entries ~= itm;
				return i < 10;
			});

		auto feed = new RssFeed;
		feed.channels ~= ch;

		res.headers["Content-Type"] = "application/rss+xml";
		feed.render(res.bodyWriter);
	}

	@path("/filter")
	void getFilter(string message, string filters, HTTPServerResponse res)
	{
		auto p = new Post;
		p.content = message;
		import std.array : split;
		p.filters = filters.split();
		res.writeBody(p.renderContentAsHtml(m_settings));
	}

	@path("/sitemap.xml")
	void getSitemap(HTTPServerResponse res)
	{
		res.contentType = "application/xml";
		res.bodyWriter.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
		res.bodyWriter.write("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
		void writeEntry(string[] parts...){
			res.bodyWriter.write("<url><loc>");
			res.bodyWriter.write(m_settings.siteURL.toString());
			foreach( p; parts )
				res.bodyWriter.write(p);
			res.bodyWriter.write("</loc></url>\n");
		}

		// home page
		writeEntry();

		m_ctrl.db.getPostsForCategory(m_ctrl.config.categories, 0, (size_t i, Post p){
				if( p.isPublic ) writeEntry("posts/", p.name);
				return true;
			});
		
		res.bodyWriter.write("</urlset>\n");
		res.bodyWriter.flush();
	}

	@errorDisplay!get
	void postLogin(string username, string password, string redirect = null)
	{
		import vibelog.internal.passwordhash : validatePasswordHash;

		auto usr = m_ctrl.db.getUserByName(username);
		enforce(usr && validatePasswordHash(usr.password, password),
			"Invalid user name or password.");
		m_loggedInUser = username;
		.redirect(redirect.length ? redirect : m_ctrl.settings.rootDir);
	}

	void getLogout()
	{
		m_loggedInUser = null;
		redirect(m_ctrl.settings.rootDir);
	}
}

import vibelog.info : VibeLogInfo;
struct PageInfo
{
	import vibelog.controller : PostListInfo;
	PostListInfo pli;
	alias pli this;
	string rootPath;
	string refPath;
	string loginError;

	import vibelog.settings : VibeLogSettings;
	this(VibeLogSettings settings, PostListInfo pli)
	{
		this.pli = pli;
		this.rootPath = settings.siteURL.path.toString();
	}
}

struct PostInfo
{
	string loginError;

	import vibelog.info : VibeLogInfo;
	VibeLogInfo vli;
	alias vli this;

	import vibelog.user : User;
	User[string] users;

	import vibelog.settings : VibeLogSettings;
	VibeLogSettings settings;

	import vibelog.post : Post;
	Post post;

	int postPage;

	DiskutoWeb diskuto;

	Post[] recentPosts;
	string rootPath;
	string refPath;
	string error;

	this(VibeLogSettings settings)
	{
		vli = VibeLogInfo(settings);
		this.settings = settings;
		this.rootPath = settings.siteURL.path.toString;
	}
}
