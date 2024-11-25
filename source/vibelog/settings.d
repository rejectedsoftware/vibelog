module vibelog.settings;

public import vibe.inet.url;
import vibe.db.mongo.connection;
import vibe.textfilter.markdown;

final class VibeLogSettings {
	string databaseURL = "mongodb://127.0.0.1/vibelog";
	string configName = "global";
	string blogName = "VibeLog";
	string blogDescription = "Web publishing based on the vibe.d framework";
	int postsPerPage = 4;
	int maxRecentPosts = 20;
	bool showFullPostsInPostList = true;
	bool placePostHeaderImageFirst = false;
	bool enableBackButton = false;
	bool inlineReadMoreButton = false;
	URL siteURL = URL("http", "localhost", 8080, InetPath("/"));
	deprecated("Use siteURL instead.") alias siteUrl = siteURL;
	string adminPrefix = "manage/";
	string delegate(string) @safe [] textFilters;
	MarkdownSettings markdownSettings;

	this()
	{
		markdownSettings = new MarkdownSettings;
		markdownSettings.flags = MarkdownFlags.backtickCodeBlocks;
	}

	@property
	{
		string rootDir()
		{
			return siteURL.path.toString();
		}
	}
}
