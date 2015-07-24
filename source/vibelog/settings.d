module vibelog.settings;

public import vibe.inet.url;
import vibe.db.mongo.connection;
import vibe.textfilter.markdown;

final class VibeLogSettings {
	string databaseURL = "mongodb://localhost/vibelog";
	string configName = "global";
	int postsPerPage = 4;
	URL siteURL = URL.parse("http://localhost:8080/");
	deprecated("Use siteURL instead.") alias siteUrl = siteURL;
	string adminPrefix = "manage/";
	string function(string)[] textFilters;
	MarkdownSettings markdownSettings;

	this()
	{
		markdownSettings = new MarkdownSettings;
		markdownSettings.flags = MarkdownFlags.backtickCodeBlocks;
	}
}
