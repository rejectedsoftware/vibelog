module vibelog.settings;

public import vibe.inet.url;
import vibe.db.mongo.connection;
import vibe.textfilter.markdown;

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
