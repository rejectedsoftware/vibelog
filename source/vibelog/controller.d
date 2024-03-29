module vibelog.controller;

public import vibelog.settings;

import vibelog.db.dbcontroller;
import diskuto.commentstore : DiskutoCommentStore;
import diskuto.commentstores.mongodb;

import std.conv : to;
import vibe.data.bson : BsonObjectID;


class VibeLogController {
	private {
		DBController m_db;
		VibeLogSettings m_settings;
		Config m_config;
		DiskutoCommentStore m_diskuto;
	}

	this(VibeLogSettings settings)
	{
		m_settings = settings;
		m_diskuto = new MongoDBCommentStore(settings.databaseURL);
		m_db = createDBController(settings);

		try m_config = m_db.getConfig(settings.configName, true);
		catch( Exception e ){
			import vibe.core.log;
			logError("Error reading configuration '%s': %s", settings.configName, e.msg);
			throw e;
		}
		m_db.invokeOnConfigChange({ m_config = m_db.getConfig(settings.configName, true); });
	}

	@property inout(DBController) db() inout { return m_db; }
	@property inout(VibeLogSettings) settings() inout { return m_settings; }
	@property inout(Config) config() inout { return m_config; }
	@property inout(DiskutoCommentStore) diskuto() inout { return m_diskuto; }

	PostListInfo getPostListInfo(int page = 0, int page_size = 0)
	{
		auto info = PostListInfo(m_settings);
		info.users = m_db.getAllUsers();
		info.pageCount = getPageCount(page_size);
		info.pageNumber = page;
		info.posts = getPostsForPage(info.pageNumber, page_size);
		foreach (p; info.posts) info.commentCount ~= m_diskuto.getActiveCommentCount("vibelog-"~p.id.toString());
		info.recentPosts = getRecentPosts();
		return info;
	}

	int getPageCount(int page_size = 0)
	{
		if (page_size <= 0) page_size = m_settings.postsPerPage;
		int cnt = m_db.countPostsForCategory(m_config.categories);
		return (cnt + page_size - 1) / page_size;
	}

	int getPostPage(BsonObjectID post_id, int page_size = 0)
	{
		if (page_size <= 0) page_size = m_settings.postsPerPage;
		try {
			int cnt = 0;
			m_db.getPublicPostsForCategory(m_config.categories, 0, (size_t i, Post p){
				if (p.id == post_id)
					return false;
				cnt++;
				return true;
			});
			return cnt / page_size + 1;
		} catch (Exception e) return 1;
	}

	Post[] getPostsForPage(int n, int page_size = 0)
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

	Post[] getRecentPosts()
	{
		Post[] ret;
		m_db.getPublicPostsForCategory(m_config.categories, 0, (i, p){
			if (i >= m_settings.maxRecentPosts) return false;
			ret ~= p;
			return true;
		});
		return ret;
	}

	string getShowPagePath(int page)
	{
		return m_settings.rootDir ~ "?page=" ~ to!string(page+1);
	}
}

struct PostListInfo
{
	import vibelog.info : VibeLogInfo;
	VibeLogInfo vli;
	alias vli this;

	User[string] users;
	int pageNumber = 0;
	int pageCount;
	Post[] posts;
	long[] commentCount;
	Post[] recentPosts;

	import vibelog.settings : VibeLogSettings;
	this(VibeLogSettings settings)
	{
		vli = VibeLogInfo(settings);
	}
}

struct VibelogHeadlineListConfig
{
	bool showSummaries = true;
	size_t maxPosts = 10;
	size_t headerLevel = 2;
	bool headerLinks = true;
	bool footerLinks = false;
	bool dateFirst = true;
}
