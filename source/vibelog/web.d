module vibelog.web;

public import vibelog.controller;

import vibelog.config;
import vibelog.post;
import vibelog.rss;
import vibelog.settings;
import vibelog.user;

import vibe.core.log;
import vibe.db.mongo.connection;
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


void registerVibeLogWeb(URLRouter router, VibeLogController controller)
{
	string sub_path = controller.settings.rootDir;
	assert(sub_path.endsWith("/"), "Blog site URL must end with '/'.");

	if (sub_path.length > 1) router.get(sub_path[0 .. $-1], staticRedirect(sub_path));

	auto web = new VibeLogWeb(controller);

	auto websettings = new WebInterfaceSettings;
	websettings.urlPrefix = sub_path;
	router.registerWebInterface(web, websettings);

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = sub_path;
	router.get(sub_path ~ "*", serveStaticFiles("public", fsettings));
}


private final class VibeLogWeb {
	private {
		VibeLogController m_ctrl;
		VibeLogSettings m_settings;
	}

	this(VibeLogController controller)
	{
		m_settings = controller.settings;
		m_ctrl = controller;

		enforce(m_settings.rootDir.startsWith("/") && m_settings.rootDir.endsWith("/"), "All local URLs must start with and end with '/'.");
	}

	//
	// public pages
	//

	void get(int page = 1)
	{
		auto info = PageInfo(m_settings, m_ctrl.getPostListInfo(page - 1));
		info.refPath = m_settings.rootDir;
		render!("vibelog.postlist.dt", info);
	}

	@errorDisplay!getPost
	@path("posts/:postname")
	void getPost(string _postname, string _error)
	{
		auto info = PostInfo(m_settings);
		info.users = m_ctrl.db.getAllUsers();
		try info.post = m_ctrl.db.getPost(_postname);
		catch(Exception e){ return; } // -> gives 404 error
		info.comments = m_ctrl.db.getComments(info.post.id);
		info.recentPosts = m_ctrl.getRecentPosts();
		info.refPath = m_settings.rootDir~"posts/"~_postname;
		info.error = _error;

		render!("vibelog.post.dt", info);
	}

	@path("posts/:postname/:filename")
	void getPostFile(string _postname, string _filename, HTTPServerResponse res)
	{
		import vibe.inet.mimetypes;
		auto f = m_ctrl.db.getFile(_postname, _filename);
		if (f) {
			res.contentType = getMimeTypeForFile(_filename);
			res.bodyWriter.write(f);
		}
	}

	@errorDisplay!getPost
	@path("posts/:postname/post_comment")
	void postComment(string name, string email, string homepage, string message, string _postname, HTTPServerRequest req)
	{
		auto post = m_ctrl.db.getPost(_postname);
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
		m_ctrl.db.addComment(post.id, c);

		redirect(m_settings.rootDir ~ "posts/" ~ post.name);
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
				auto itm = new RssEntry;
				itm.title = p.header;
				itm.description = p.subHeader;
				itm.link = m_settings.siteURL.toString() ~ "posts/" ~ p.name;
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

	void postMarkup(string message, HTTPServerRequest req, HTTPServerResponse res)
	{
		auto post = new Post;
		post.content = message;
		res.writeBody(post.renderContentAsHtml(m_settings, req.path), "text/html");
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
}

import vibelog.info : VibeLogInfo;
struct PageInfo
{
	import vibelog.controller : PostListInfo;
	PostListInfo pli;
	alias pli this;
	string refPath;

	import vibelog.settings : VibeLogSettings;
	this(VibeLogSettings settings, PostListInfo pli)
	{
		this.pli = pli;
	}
}

struct PostInfo
{
	import vibelog.info : VibeLogInfo;
	VibeLogInfo vli;
	alias vli this;

	import vibelog.user : User;
	User[string] users;

	import vibelog.settings : VibeLogSettings;
	VibeLogSettings settings;

	import vibelog.post : Post;
	Post post;

	import vibelog.post : Comment;
	Comment[] comments;

	Post[] recentPosts;
	string refPath;
	string error;

	this(VibeLogSettings settings)
	{
		vli = VibeLogInfo(settings);
		this.settings = settings;
	}
}
