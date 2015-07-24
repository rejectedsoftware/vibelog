module vibelog.web;

import vibelog.dbcontroller;
import vibelog.rss;
import vibelog.settings;

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
	router.registerWebInterface(new VibeLogWeb(controller, settings), websettings);

	auto fsettings = new HTTPFileServerSettings;
	fsettings.serverPathPrefix = sub_path;
	router.get(sub_path ~ "*", serveStaticFiles("public", fsettings));
}


private final class VibeLogWeb {
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

		m_db.invokeOnConfigChange({ m_db.getConfig(settings.configName, true); });

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
