module vibelog.settings;

public import vibe.inet.url;
import vibe.db.mongo.connection;
import vibe.textfilter.markdown;

final class VibeLogSettings {
	string databaseURL = "mongodb://localhost/vibelog";
	string configName = "global";
	int postsPerPage = 4;
	int maxRecentPosts = 20;
	bool showFullPostsInPostList = true;
	URL siteURL = URL.parse("http://localhost:8080/");
	deprecated("Use siteURL instead.") alias siteUrl = siteURL;
	string adminPrefix = "manage/";
	string delegate(string) @safe [] textFilters;
	MarkdownSettings markdownSettings;

	this()
	{
		markdownSettings = new MarkdownSettings;
		markdownSettings.flags = MarkdownFlags.backtickCodeBlocks;
	}
}
